import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/scale_service.dart';
import 'gatt_parser.dart';

/// [ScaleService] backed by flutter_blue_plus.
///
/// Fully supports scales exposing the standard Bluetooth SIG Weight Scale
/// Service (0x181D) and/or Body Composition Service (0x181B) — e.g. HMM
/// smartLAB "WS..." devices. TANITA consumer scales (BC-401 / BC-768 /
/// RD-91x, advertising "TNT_..." names) use a proprietary account-bound
/// protocol; they are still surfaced by [scan] (with
/// `isBodyCompositionCapable = false`) so the UI can explain why they cannot
/// be read.
///
/// Runtime BLE permissions are expected to be requested by the presentation
/// layer (permission_handler) before calling [scan] / [connectAndMeasure];
/// this class only translates adapter / permission problems into
/// [BleFailure] / [BlePermissionFailure].
class BluePlusScaleService implements ScaleService {
  BluePlusScaleService({
    Uuid? uuid,
    this.stabilizationDelay = const Duration(seconds: 2),
    this.connectTimeout = const Duration(seconds: 15),
  }) : _uuid = uuid ?? const Uuid();

  static final Guid _weightScaleService = Guid('181d');
  static final Guid _bodyCompositionService = Guid('181b');
  static final Guid _weightMeasurementChar = Guid('2a9d');
  static final Guid _bodyCompositionChar = Guid('2a9c');

  /// Advertised-name prefixes of known scales (TANITA consumer devices and
  /// HMM smartLAB weight scales).
  static const List<String> _scaleNamePrefixes = ['TNT_', 'TANITA', 'WS'];

  final Uuid _uuid;

  /// Quiet period after the last measurement packet before a stabilized
  /// [WeightEntry] is emitted.
  final Duration stabilizationDelay;

  final Duration connectTimeout;

  final StreamController<ScaleConnectionState> _stateController =
      StreamController<ScaleConnectionState>.broadcast();
  ScaleConnectionState _state = ScaleConnectionState.idle;

  BluetoothDevice? _device;
  final List<StreamSubscription<dynamic>> _deviceSubscriptions = [];
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  Timer? _debounce;
  _PendingReading _pending = _PendingReading();

  @override
  Stream<ScaleConnectionState> get connectionState => _stateController.stream;

  /// Last state pushed to [connectionState] (initially idle).
  ScaleConnectionState get currentState => _state;

  @override
  Stream<DiscoveredScale> scan({
    Duration timeout = const Duration(seconds: 15),
  }) {
    final controller = StreamController<DiscoveredScale>();
    final seenIds = <String>{};

    Future<void> run() async {
      try {
        await _ensureAdapterOn();
        _setState(ScaleConnectionState.scanning);

        // Single unfiltered scan; classification below keeps only devices
        // that advertise the standard scale services or a known scale name.
        _scanResultsSub = FlutterBluePlus.onScanResults.listen(
          (results) {
            for (final result in results) {
              final scale = _classify(result);
              if (scale == null || !seenIds.add(scale.deviceId)) continue;
              if (!controller.isClosed) controller.add(scale);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(_translate(error, 'Scan failed'), stackTrace);
            }
          },
        );

        await FlutterBluePlus.startScan(timeout: timeout);
        // isScanning re-emits its latest value on listen, so this completes
        // when the scan (already running here) ends or is stopped.
        await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;

        if (_state == ScaleConnectionState.scanning) {
          _setState(ScaleConnectionState.idle);
        }
        if (!controller.isClosed) await controller.close();
      } catch (error, stackTrace) {
        _setState(ScaleConnectionState.error);
        if (!controller.isClosed) {
          controller.addError(_translate(error, 'Scan failed'), stackTrace);
          await controller.close();
        }
      }
    }

    controller.onListen = run;
    controller.onCancel = stopScan;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (error) {
      throw _translate(error, 'Failed to stop scan');
    } finally {
      if (_state == ScaleConnectionState.scanning) {
        _setState(ScaleConnectionState.idle);
      }
    }
  }

  @override
  Stream<WeightEntry> connectAndMeasure(String deviceId) {
    final controller = StreamController<WeightEntry>();

    Future<void> run() async {
      try {
        await _ensureAdapterOn();
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }

        _setState(ScaleConnectionState.connecting);
        final device = BluetoothDevice.fromId(deviceId);
        _device = device;

        // License.nonprofit: Hakari is a personal, free, non-commercial
        // app — the FlutterBluePlus License grants BSD-like terms for
        // this use (see the package LICENSE).
        await device.connect(
          timeout: connectTimeout,
          license: License.nonprofit,
        );

        // Close the measurement stream when the scale disconnects on its own
        // (typical: scales power down shortly after a measurement).
        final connectionSub = device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected &&
              _state == ScaleConnectionState.connected) {
            _debounce?.cancel();
            _debounce = null;
            _setState(ScaleConnectionState.idle);
            if (!controller.isClosed) controller.close();
          }
        });
        _deviceSubscriptions.add(connectionSub);

        final services = await device.discoverServices();
        final measurementChars = <BluetoothCharacteristic>[
          for (final service in services)
            for (final characteristic in service.characteristics)
              if (characteristic.characteristicUuid == _bodyCompositionChar ||
                  characteristic.characteristicUuid == _weightMeasurementChar)
                characteristic,
        ];

        if (measurementChars.isEmpty) {
          throw const BleFailure(
            'Device does not expose the standard Weight Measurement '
            '(0x2A9D) or Body Composition Measurement (0x2A9C) '
            'characteristics. TANITA consumer scales (TNT_...) use a '
            'proprietary protocol that cannot be read.',
          );
        }

        _pending = _PendingReading();
        for (final characteristic in measurementChars) {
          final isBodyComposition =
              characteristic.characteristicUuid == _bodyCompositionChar;
          final valueSub = characteristic.onValueReceived.listen((data) {
            _onMeasurementPacket(data, isBodyComposition, controller);
          });
          _deviceSubscriptions.add(valueSub);
          // flutter_blue_plus writes the CCC descriptor and picks
          // indications when that is what the characteristic supports.
          await characteristic.setNotifyValue(true);
        }

        _setState(ScaleConnectionState.connected);
        // Stream stays open for repeat measurements until disconnect() is
        // called or the device disconnects.
      } catch (error, stackTrace) {
        _setState(ScaleConnectionState.error);
        if (!controller.isClosed) {
          controller.addError(
            _translate(error, 'Connection failed'),
            stackTrace,
          );
          await controller.close();
        }
        await _teardownDevice();
      }
    }

    controller.onListen = run;
    controller.onCancel = disconnect;
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    _debounce?.cancel();
    _debounce = null;
    _pending = _PendingReading();
    await _teardownDevice();
    if (_state != ScaleConnectionState.idle) {
      _setState(ScaleConnectionState.idle);
    }
  }

  /// Releases every resource held by this service. Call from DI teardown.
  Future<void> dispose() async {
    try {
      await stopScan();
    } on Failure {
      // Best-effort teardown.
    }
    await disconnect();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _onMeasurementPacket(
    List<int> data,
    bool isBodyComposition,
    StreamController<WeightEntry> controller,
  ) {
    try {
      if (isBodyComposition) {
        _pending.applyBodyComposition(parseBodyComposition(data));
      } else {
        _pending.applyWeight(parseWeightMeasurement(data));
      }
    } on FormatException {
      // Malformed / truncated packet: ignore it and keep listening.
      return;
    }

    // Scales stream intermediate values while the reading stabilizes;
    // (re)start the debounce and emit once packets stop arriving.
    _debounce?.cancel();
    _debounce = Timer(stabilizationDelay, () {
      final entry = _pending.toEntry(id: _uuid.v4());
      _pending = _PendingReading();
      if (entry != null && !controller.isClosed) {
        controller.add(entry);
      }
    });
  }

  DiscoveredScale? _classify(ScanResult result) {
    final adv = result.advertisementData;
    final advertisesStandardService = adv.serviceUuids.any(
      (uuid) => uuid == _weightScaleService || uuid == _bodyCompositionService,
    );

    final name = adv.advName.isNotEmpty
        ? adv.advName
        : result.device.platformName;
    final upperName = name.toUpperCase();
    final nameMatches = _scaleNamePrefixes.any(upperName.startsWith);

    if (!advertisesStandardService && !nameMatches) return null;

    return DiscoveredScale(
      deviceId: result.device.remoteId.str,
      name: name,
      rssi: result.rssi,
      isBodyCompositionCapable: advertisesStandardService,
    );
  }

  Future<void> _ensureAdapterOn() async {
    BluetoothAdapterState state;
    try {
      state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw const BleFailure(
        'Bluetooth adapter state could not be determined.',
      );
    } catch (error) {
      throw _translate(error, 'Bluetooth adapter check failed');
    }

    switch (state) {
      case BluetoothAdapterState.on:
        return;
      case BluetoothAdapterState.unauthorized:
        throw const BlePermissionFailure(
          'Bluetooth permission was denied. Grant the Bluetooth / Nearby '
          'devices permission in system settings and try again.',
        );
      case BluetoothAdapterState.unavailable:
        throw const BleFailure('Bluetooth is not available on this device.');
      default:
        throw BleFailure(
          'Bluetooth is turned off (state: ${state.name}). Turn on '
          'Bluetooth and try again.',
        );
    }
  }

  Failure _translate(Object error, String context) {
    if (error is Failure) return error;
    final description = error.toString();
    final lower = description.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('unauthorized') ||
        lower.contains('denied')) {
      return BlePermissionFailure('$context: $description', error);
    }
    return BleFailure('$context: $description', error);
  }

  Future<void> _teardownDevice() async {
    for (final subscription in _deviceSubscriptions) {
      await subscription.cancel();
    }
    _deviceSubscriptions.clear();

    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
        // Best-effort: the device may already be gone.
      }
    }
  }

  void _setState(ScaleConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}

/// Aggregates 0x2A9D / 0x2A9C packets belonging to one physical measurement
/// until the debounce fires.
class _PendingReading {
  double? _weightFrom2a9d;
  double? _weightFrom2a9c;
  DateTime? _timestamp2a9d;
  DateTime? _timestamp2a9c;
  double? _bodyFatPercent;
  double? _bodyWaterMassKg;
  double? _muscleMassKg;
  int? _basalMetabolicRateKcal;

  void applyWeight(WeightMeasurement measurement) {
    _weightFrom2a9d = measurement.weightKg;
    if (measurement.timestamp != null) {
      _timestamp2a9d = measurement.timestamp;
    }
  }

  void applyBodyComposition(BodyCompositionMeasurement measurement) {
    if (measurement.weightKg != null) {
      _weightFrom2a9c = measurement.weightKg;
    }
    if (measurement.bodyFatPercent != null) {
      _bodyFatPercent = measurement.bodyFatPercent;
    }
    if (measurement.bodyWaterMassKg != null) {
      _bodyWaterMassKg = measurement.bodyWaterMassKg;
    }
    if (measurement.muscleMassKg != null) {
      _muscleMassKg = measurement.muscleMassKg;
    }
    if (measurement.basalMetabolismKcal != null) {
      _basalMetabolicRateKcal = measurement.basalMetabolismKcal;
    }
    if (measurement.timestamp != null) {
      _timestamp2a9c = measurement.timestamp;
    }
  }

  /// Builds the stabilized entry; null when no weight was received (e.g.
  /// only an unsuccessful body-composition packet arrived).
  WeightEntry? toEntry({required String id}) {
    // Prefer the 0x2A9C weight when present, else fall back to 0x2A9D.
    final weightKg = _weightFrom2a9c ?? _weightFrom2a9d;
    if (weightKg == null) return null;

    double? bodyWaterPercent;
    final waterMass = _bodyWaterMassKg;
    if (waterMass != null && weightKg > 0) {
      bodyWaterPercent = waterMass / weightKg * 100;
    }

    return WeightEntry(
      id: id,
      recordedAt: _timestamp2a9c ?? _timestamp2a9d ?? DateTime.now(),
      weightKg: weightKg,
      bodyFatPercent: _bodyFatPercent,
      bodyWaterPercent: bodyWaterPercent,
      muscleMassKg: _muscleMassKg,
      basalMetabolicRateKcal: _basalMetabolicRateKcal,
      source: MeasurementSource.bleScale,
    );
  }
}
