import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/scale_service.dart';
import '../providers/entry_saver_provider.dart';
import '../widgets/app_messenger.dart';

final NumberFormat _oneDecimal = NumberFormat('0.0');

enum _Phase { permissions, denied, scanning, measuring, error }

/// BLE scale flow: permissions -> scan -> connect & measure -> confirm.
class ScaleScreen extends ConsumerStatefulWidget {
  const ScaleScreen({super.key});

  @override
  ConsumerState<ScaleScreen> createState() => _ScaleScreenState();
}

class _ScaleScreenState extends ConsumerState<ScaleScreen> {
  late final ScaleService _scaleService;

  final List<DiscoveredScale> _scales = [];
  StreamSubscription<DiscoveredScale>? _scanSub;
  StreamSubscription<WeightEntry>? _measureSub;

  _Phase _phase = _Phase.permissions;
  String? _errorMessage;
  DiscoveredScale? _connectedScale;
  double? _liveWeightKg;
  bool _confirmShowing = false;

  @override
  void initState() {
    super.initState();
    _scaleService = ref.read(scaleServiceProvider);
    _start();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _measureSub?.cancel();
    unawaited(_scaleService.stopScan().catchError((_) {}));
    unawaited(_scaleService.disconnect().catchError((_) {}));
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.permissions);
    final granted = await _requestPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() => _phase = _Phase.denied);
      return;
    }
    _startScan();
  }

  Future<bool> _requestPermissions() async {
    try {
      final permissions = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ];
      final statuses = await permissions.request();
      final bluetoothGranted = statuses.values
          .every((status) => status.isGranted || status.isLimited);
      if (!bluetoothGranted) return false;
      // Android 11 and below additionally need location for BLE scan
      // results. The manifest declares ACCESS_FINE_LOCATION with
      // maxSdkVersion=30, so on Android 12+ the OS auto-denies this
      // request — ask best-effort but never gate scanning on it.
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await Permission.locationWhenInUse.request();
        } catch (_) {
          // Ignore: scanning proceeds with the Bluetooth permissions.
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startScan() {
    setState(() {
      _phase = _Phase.scanning;
      _scales.clear();
      _errorMessage = null;
    });
    _scanSub?.cancel();
    _scanSub = _scaleService
        .scan(timeout: const Duration(seconds: 30))
        .listen(
      (scale) {
        if (!mounted) return;
        setState(() {
          final index =
              _scales.indexWhere((s) => s.deviceId == scale.deviceId);
          if (index >= 0) {
            _scales[index] = scale;
          } else {
            _scales.add(scale);
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _errorMessage = _messageFor(error);
        });
      },
    );
  }

  Future<void> _connect(DiscoveredScale scale) async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _scaleService.stopScan();
    } catch (_) {
      // Best effort; scanning may already have stopped.
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.measuring;
      _connectedScale = scale;
      _liveWeightKg = null;
    });
    _measureSub?.cancel();
    _measureSub = _scaleService.connectAndMeasure(scale.deviceId).listen(
      _onMeasurement,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _errorMessage = _messageFor(error);
        });
      },
    );
  }

  Future<void> _onMeasurement(WeightEntry entry) async {
    if (!mounted) return;
    setState(() => _liveWeightKg = entry.weightKg);
    if (_confirmShowing) return;
    _confirmShowing = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmMeasurementDialog(entry: entry),
    );
    _confirmShowing = false;
    if (!mounted || confirmed != true) return;

    try {
      final warnings = await ref.read(entrySaverProvider).save(entry);
      showAppSnackBar(
        warnings.isEmpty
            ? 'Measurement saved.'
            : 'Measurement saved. ${warnings.join(' ')}',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  static String _messageFor(Object error) {
    if (error is BlePermissionFailure) {
      return 'Bluetooth permission problem: ${error.message}';
    }
    if (error is Failure) return error.message;
    return 'Bluetooth error: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth scale')),
      body: switch (_phase) {
        _Phase.permissions => const _CenteredStatus(
            message: 'Requesting Bluetooth permissions...',
            showProgress: true,
          ),
        _Phase.denied => _PermissionDenied(onRetry: _start),
        _Phase.scanning => _ScanList(
            scales: _scales,
            onTap: _connect,
            onRescan: _startScan,
          ),
        _Phase.measuring => _MeasuringView(
            scale: _connectedScale,
            liveWeightKg: _liveWeightKg,
            onCancel: () => Navigator.of(context).pop(),
          ),
        _Phase.error => _ErrorView(
            message: _errorMessage ?? 'Something went wrong.',
            onRetry: _start,
          ),
      },
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.message, this.showProgress = false});

  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showProgress) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
          ],
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Bluetooth permission required',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Hakari needs Bluetooth (and location on Android) '
              'permissions to find your scale.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: openAppSettings,
                  child: const Text('Open settings'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanList extends StatelessWidget {
  const _ScanList({
    required this.scales,
    required this.onTap,
    required this.onRescan,
  });

  final List<DiscoveredScale> scales;
  final ValueChanged<DiscoveredScale> onTap;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scanning for scales...',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(onPressed: onRescan, child: const Text('Rescan')),
          ],
        ),
        const SizedBox(height: 8),
        if (scales.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  Icons.monitor_weight_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'Step on your scale to wake it up.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (final scale in scales)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  onTap: () => onTap(scale),
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: Text(
                    scale.name.isEmpty ? 'Unknown scale' : scale.name,
                  ),
                  subtitle: Text('Signal ${scale.rssi} dBm'),
                  trailing: _CapabilityBadge(
                    bodyComposition: scale.isBodyCompositionCapable,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _CapabilityBadge extends StatelessWidget {
  const _CapabilityBadge({required this.bodyComposition});

  final bool bodyComposition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bodyComposition
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        bodyComposition ? 'Body composition' : 'Weight only',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: bodyComposition
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _MeasuringView extends StatelessWidget {
  const _MeasuringView({
    required this.scale,
    required this.liveWeightKg,
    required this.onCancel,
  });

  final DiscoveredScale? scale;
  final double? liveWeightKg;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final weight = liveWeightKg;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              scale?.name.isNotEmpty ?? false
                  ? scale!.name
                  : 'Connected scale',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            if (weight == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Step on the scale...',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                _oneDecimal.format(weight),
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              Text('kg', style: theme.textTheme.titleLarge),
            ],
            const SizedBox(height: 48),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _ConfirmMeasurementDialog extends StatelessWidget {
  const _ConfirmMeasurementDialog({required this.entry});

  final WeightEntry entry;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      '${_oneDecimal.format(entry.weightKg)} kg',
      if (entry.bodyFatPercent != null)
        'Body fat ${_oneDecimal.format(entry.bodyFatPercent)}%',
      if (entry.bodyWaterPercent != null)
        'Body water ${_oneDecimal.format(entry.bodyWaterPercent)}%',
      if (entry.muscleMassKg != null)
        'Muscle ${_oneDecimal.format(entry.muscleMassKg)} kg',
      if (entry.visceralFatRating != null)
        'Visceral fat ${entry.visceralFatRating}',
      if (entry.boneMassKg != null)
        'Bone ${_oneDecimal.format(entry.boneMassKg)} kg',
      if (entry.basalMetabolicRateKcal != null)
        'BMR ${entry.basalMetabolicRateKcal} kcal',
      if (entry.metabolicAge != null)
        'Metabolic age ${entry.metabolicAge}',
    ];
    return AlertDialog(
      title: const Text('Save measurement?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final line in details) Text(line)],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
