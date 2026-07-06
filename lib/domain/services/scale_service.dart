import '../entities/weight_entry.dart';

/// A BLE body-composition scale discovered during scan.
class DiscoveredScale {
  final String deviceId;
  final String name;
  final int rssi;

  /// True when the advertisement includes the standard Weight Scale
  /// (0x181D) or Body Composition (0x181B) service, which TANITA
  /// consumer scales (BC/RD series) expose.
  final bool isBodyCompositionCapable;

  const DiscoveredScale({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.isBodyCompositionCapable,
  });
}

enum ScaleConnectionState { idle, scanning, connecting, connected, error }

/// BLE scale integration (TANITA-compatible).
/// Implementations throw [BleFailure] / [BlePermissionFailure].
abstract interface class ScaleService {
  Stream<ScaleConnectionState> get connectionState;

  /// Scan for scales advertising WSS/BCS services.
  Stream<DiscoveredScale> scan({Duration timeout});

  Future<void> stopScan();

  /// Connect and subscribe to measurement indications. Emits a
  /// [WeightEntry] (source = bleScale) for each stabilized reading.
  Stream<WeightEntry> connectAndMeasure(String deviceId);

  Future<void> disconnect();
}
