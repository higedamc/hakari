import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/body_metrics.dart';
import '../../domain/services/nostr_service.dart';
import '../providers/nostr_sync_provider.dart';
import '../providers/relay_status_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/hakari_tokens.dart';
import '../widgets/app_messenger.dart';
import '../widgets/section_header.dart';

/// Settings: identity, relays, Tor, publishing, health and export.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _importingHealth = false;
  bool _checkingWellness = false;
  bool _exporting = false;
  bool _healthPlanetLinked = false;
  bool _healthPlanetBusy = false;

  SettingsController get _settings => ref.read(settingsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _loadHealthPlanetStatus();
  }

  Future<void> _loadHealthPlanetStatus() async {
    try {
      final linked = await ref.read(healthPlanetServiceProvider).isLinked();
      if (mounted) setState(() => _healthPlanetLinked = linked);
    } catch (_) {
      // Provider not wired (tests) or storage unavailable: stay unlinked.
    }
  }

  // ------------------------------------------------------------------
  // Helpers

  /// Re-initializes the Nostr client after relay / Tor / signer changes.
  Future<void> _applyNostrSettings(AppSettings settings) async {
    try {
      await ref.read(nostrServiceProvider).initialize(settings);
      ref.invalidate(relayStatusProvider);
    } on Failure catch (f) {
      showAppSnackBar('Nostr settings not applied: ${f.message}');
    } catch (e) {
      showAppSnackBar('Nostr settings not applied: $e');
    }
  }

  Future<void> _updateAndApply(
    Future<AppSettings> Function(SettingsController controller) action,
  ) async {
    try {
      final next = await action(_settings);
      await _applyNostrSettings(next);
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  Future<void> _updateOnly(
    Future<AppSettings> Function(SettingsController controller) action,
  ) async {
    try {
      await action(_settings);
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  static String _truncateMiddle(String value) {
    if (value.length <= 21) return value;
    return '${value.substring(0, 10)}...'
        '${value.substring(value.length - 10)}';
  }

  // ------------------------------------------------------------------
  // Identity / signer

  Future<void> _loginWithAmber() async {
    try {
      final pubkey = await ref.read(signerServiceProvider).getPublicKey();
      if (pubkey == null || pubkey.isEmpty) {
        showAppSnackBar('The signer returned no public key.');
        return;
      }
      await _updateAndApply(
        (c) => c.setSignerMode(SignerMode.amber, pubkeyHex: pubkey),
      );
      showAppSnackBar('Logged in with Amber.');
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  Future<void> _logout() => _updateAndApply((c) => c.logout());

  // ------------------------------------------------------------------
  // Relays

  Future<void> _showAddRelayDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Add relay'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'wss://relay.example.com',
                errorText: errorText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  final uri = Uri.tryParse(text);
                  // Plaintext ws:// would hand health events to any
                  // on-path attacker, so it is only accepted where TLS
                  // is unavailable but the transport is safe anyway:
                  // loopback (local relay) and .onion (Tor encrypts).
                  final host = uri?.host ?? '';
                  final cleartextOk =
                      host == '127.0.0.1' ||
                      host == 'localhost' ||
                      host.endsWith('.onion');
                  final valid =
                      uri != null &&
                      host.isNotEmpty &&
                      (text.startsWith('wss://') ||
                          (text.startsWith('ws://') && cleartextOk));
                  if (!valid) {
                    setDialogState(() {
                      errorText =
                          'Use wss:// (ws:// only for localhost or .onion)';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(text);
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (url == null) return;
    await _updateAndApply((c) => c.addRelay(url));
  }

  // ------------------------------------------------------------------
  // Health

  /// Android reads/writes Google Health Connect; iOS uses Apple
  /// HealthKit ("Health"). They are different APIs behind one seam.
  static final String _healthStoreName = Platform.isIOS
      ? 'Health'
      : 'Health Connect';

  Future<void> _connectHealth() async {
    try {
      final health = ref.read(healthServiceProvider);
      if (!await health.isAvailable()) {
        showAppSnackBar('$_healthStoreName is not available on this device.');
        return;
      }
      final granted = await health.requestPermissions();
      showAppSnackBar(
        granted
            ? 'Health permissions granted.'
            : 'Health permissions were denied.',
      );
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  Future<void> _importFromHealth() async {
    setState(() => _importingHealth = true);
    try {
      final now = DateTime.now();
      final fetched = await ref
          .read(healthServiceProvider)
          .readEntries(now.subtract(const Duration(days: 90)), now);
      final repo = ref.read(weightRepositoryProvider);
      final existing = List<WeightEntry>.of(await repo.getAll());
      var imported = 0;
      for (final entry in fetched) {
        final isDuplicate = existing.any(
          (e) =>
              e.recordedAt.difference(entry.recordedAt).abs() <=
              const Duration(seconds: 60),
        );
        if (isDuplicate) continue;
        await repo.upsert(entry);
        existing.add(entry);
        imported++;
      }
      showAppSnackBar(
        imported == 0
            ? 'No new entries to import.'
            : 'Imported $imported ${imported == 1 ? 'entry' : 'entries'} '
                  'from Health.',
      );
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    } finally {
      if (mounted) setState(() => _importingHealth = false);
    }
  }

  /// Diagnoses why the readiness card may be missing: permission state,
  /// and how many of the last 8 days actually have sleep / energy data.
  Future<void> _checkWellnessData() async {
    setState(() => _checkingWellness = true);
    String message;
    try {
      final health = ref.read(healthServiceProvider);
      if (!await health.isAvailable()) {
        message = '$_healthStoreName is not available on this device.';
      } else {
        final days = await health.readWellness(8);
        final sleepDays = days.where((d) => d.sleepHours != null).length;
        final energyDays = days.where((d) => d.activeEnergyKcal != null).length;
        final buffer = StringBuffer(
          'Last 8 days in $_healthStoreName:\n'
          '• Sleep: $sleepDays ${sleepDays == 1 ? 'day' : 'days'} with data\n'
          '• Active energy: $energyDays '
          '${energyDays == 1 ? 'day' : 'days'} with data\n\n',
        );
        if (sleepDays == 0) {
          buffer.write(
            'No sleep records found, so the readiness card stays '
            'hidden. Hakari only reads what other apps write into '
            '$_healthStoreName — two things to check:\n\n'
            '1. Permissions: tap "Connect $_healthStoreName" and make '
            'sure Sleep and Active energy are allowed (also visible in '
            'the $_healthStoreName app under App permissions → Hakari).\n'
            '2. A sleep source: your watch\'s companion app must sync '
            'sleep into $_healthStoreName (check its settings for a '
            '"$_healthStoreName" toggle; the $_healthStoreName app → '
            'Data and access → Sleep shows which apps write it). '
            'Fitbit, Pixel Watch, Samsung Health and Sleep as Android '
            'do; many vendor apps do not.',
          );
        } else {
          buffer.write(
            'Data is flowing — the readiness card should appear on the '
            'home screen (pull to refresh or reopen the app).',
          );
        }
        message = buffer.toString();
      }
    } on Failure catch (f) {
      message =
          'Reading wellness data failed: ${f.message}\n\n'
          'Tap "Connect $_healthStoreName" to (re)grant the sleep and '
          'active-energy permissions.';
    } finally {
      if (mounted) setState(() => _checkingWellness = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wellness data check'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Health Planet (TANITA cloud)

  Future<void> _linkHealthPlanet() async {
    final service = ref.read(healthPlanetServiceProvider);
    // First link: collect the user's own Health Planet developer
    // credentials (client id feeds the consent URL, so this must happen
    // before the browser opens). Later links go straight to the browser.
    try {
      if (!await service.hasClientSecret()) {
        final creds = await _showHealthPlanetCredentialsDialog(
          initialClientId: await service.clientId(),
        );
        if (creds == null) return;
        if (creds.clientId.trim().isEmpty || creds.secret.trim().isEmpty) {
          showAppSnackBar('Both the client ID and secret are required.');
          return;
        }
        await service.setClientId(creds.clientId);
        await service.setClientSecret(creds.secret);
      }
    } on Failure catch (f) {
      showAppSnackBar(f.message);
      return;
    }
    if (!mounted) return;
    try {
      await launchUrl(
        await service.authorizationUrl(),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      showAppSnackBar('Could not open the browser: $e');
      return;
    }
    if (!mounted) return;
    final code = await _showHealthPlanetCodeDialog();
    if (code == null || code.trim().isEmpty) return;
    setState(() => _healthPlanetBusy = true);
    try {
      await service.linkWithCode(code);
      if (mounted) setState(() => _healthPlanetLinked = true);
      showAppSnackBar('Health Planet linked.');
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    } finally {
      if (mounted) setState(() => _healthPlanetBusy = false);
    }
  }

  Future<({String clientId, String secret})?>
  _showHealthPlanetCredentialsDialog({required String initialClientId}) {
    final idCtrl = TextEditingController(text: initialClientId);
    final secretCtrl = TextEditingController();
    return showDialog<({String clientId, String secret})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Health Planet credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Register an application on the Health Planet developer '
              'page (healthplanet.jp) and enter its credentials. They '
              'are stored only on this device (Keystore) — entered '
              'once.',
            ),
            const SizedBox(height: HakariSpacing.md),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                helperText: 'xxxx.yyyy.apps.healthplanet.jp',
              ),
            ),
            const SizedBox(height: HakariSpacing.md),
            TextField(
              controller: secretCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Client secret'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop((clientId: idCtrl.text, secret: secretCtrl.text)),
            child: const Text('Continue'),
          ),
        ],
      ),
    ).whenComplete(() {
      idCtrl.dispose();
      secretCtrl.dispose();
    });
  }

  Future<String?> _showHealthPlanetCodeDialog() {
    final codeCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Link Health Planet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Approve access in the browser; Health Planet then shows '
              'an authorization code on the page. Copy it and paste it '
              'here within 10 minutes.',
            ),
            const SizedBox(height: HakariSpacing.md),
            TextField(
              controller: codeCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Authorization code',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(codeCtrl.text),
            child: const Text('Link'),
          ),
        ],
      ),
    ).whenComplete(codeCtrl.dispose);
  }

  Future<void> _importFromHealthPlanet({required bool fullHistory}) async {
    setState(() => _healthPlanetBusy = true);
    // Read the controller before the first await: ref must not be touched
    // after a dispose that may happen while the fetch is in flight.
    final settings = _settings;
    try {
      final service = ref.read(healthPlanetServiceProvider);
      final now = DateTime.now();
      final fetched = fullHistory
          ? await service.fetchAllEntries()
          : await service.fetchEntries(
              now.subtract(const Duration(days: 90)),
              now,
            );
      final repo = ref.read(weightRepositoryProvider);
      final existing = List<WeightEntry>.of(await repo.getAll());
      var imported = 0;
      var updated = 0;
      for (final entry in fetched) {
        final matchIndex = existing.indexWhere(
          (e) =>
              e.recordedAt.difference(entry.recordedAt).abs() <=
              const Duration(seconds: 60),
        );
        if (matchIndex == -1) {
          await repo.upsert(entry);
          existing.add(entry);
          imported++;
          continue;
        }
        // Duplicate timestamp: backfill metrics the stored entry lacks
        // (e.g. entries imported before muscle score / visceral level 2
        // were captured) without touching values already present.
        final current = existing[matchIndex];
        final merged = current.copyWith(
          bodyFatPercent: current.bodyFatPercent ?? entry.bodyFatPercent,
          bodyWaterPercent: current.bodyWaterPercent ?? entry.bodyWaterPercent,
          muscleMassKg: current.muscleMassKg ?? entry.muscleMassKg,
          muscleScore: current.muscleScore ?? entry.muscleScore,
          visceralFatRating:
              current.visceralFatRating ?? entry.visceralFatRating,
          visceralFatLevel2:
              current.visceralFatLevel2 ?? entry.visceralFatLevel2,
          boneMassKg: current.boneMassKg ?? entry.boneMassKg,
          basalMetabolicRateKcal:
              current.basalMetabolicRateKcal ?? entry.basalMetabolicRateKcal,
          metabolicAge: current.metabolicAge ?? entry.metabolicAge,
        );
        final gainedData =
            merged.toMap().toString() != current.toMap().toString();
        if (!gainedData) continue;
        await repo.upsert(merged);
        existing[matchIndex] = merged;
        updated++;
      }
      showAppSnackBar(switch ((imported, updated)) {
        (0, 0) => 'No new entries to import.',
        (final i, 0) =>
          'Imported $i ${i == 1 ? 'entry' : 'entries'} from Health Planet.',
        (0, final u) =>
          'Updated $u existing ${u == 1 ? 'entry' : 'entries'} with new '
              'metrics.',
        (final i, final u) =>
          'Imported $i new, updated $u existing entries from Health Planet.',
      });
      // The profile height rides along with the innerscan response. The
      // controller adopts it only while no height is stored, so a value
      // the user typed is never overwritten by an import.
      await settings.adoptFetchedHeightCm(service.lastFetchedHeightCm);
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    } finally {
      if (mounted) setState(() => _healthPlanetBusy = false);
    }
  }

  Future<void> _unlinkHealthPlanet() async {
    try {
      await ref.read(healthPlanetServiceProvider).unlink();
      if (mounted) setState(() => _healthPlanetLinked = false);
      showAppSnackBar('Health Planet unlinked.');
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    }
  }

  // ------------------------------------------------------------------
  // Export

  Future<void> _export({required bool asCsv}) async {
    setState(() => _exporting = true);
    try {
      final entries = await ref.read(weightRepositoryProvider).getAll();
      if (entries.isEmpty) {
        showAppSnackBar('Nothing to export yet.');
        return;
      }
      final exporter = ref.read(exportServiceProvider);
      final path = asCsv
          ? await exporter.exportCsv(entries)
          : await exporter.exportJson(entries);
      await exporter.shareFile(path);
    } on Failure catch (f) {
      showAppSnackBar(f.message);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _EmptyState(
          icon: Icons.error_outline,
          message: error is Failure
              ? error.message
              : 'Failed to load settings: $error',
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(
            HakariSpacing.page,
            0,
            HakariSpacing.page,
            HakariSpacing.xl,
          ),
          children: [
            _SettingsGroup(
              title: 'Identity',
              children: _identityRows(settings),
            ),
            _SettingsGroup(
              title: 'Body profile',
              children: _bodyProfileRows(settings),
            ),
            _SettingsGroup(title: 'Relays', children: _relayRows(settings)),
            _SettingsGroup(title: 'Privacy', children: _torRows(settings)),
            _SettingsGroup(
              title: 'Publishing',
              children: _publishingRows(settings),
            ),
            _SettingsGroup(title: _healthStoreName, children: _healthRows()),
            _SettingsGroup(
              title: 'TANITA Health Planet',
              children: _healthPlanetRows(),
            ),
            _SettingsGroup(title: 'Export', children: _exportRows()),
          ],
        ),
      ),
    );
  }

  List<Widget> _identityRows(AppSettings settings) {
    final pubkey = settings.pubkeyHex;
    if (pubkey != null) {
      return [
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(_truncateMiddle(pubkey)),
          subtitle: Text(switch (settings.signerMode) {
            SignerMode.amber => 'Signing with Amber',
            SignerMode.localKey => 'Signing with local key',
            SignerMode.none => 'No signer configured',
          }),
          trailing: TextButton(
            onPressed: _logout,
            child: const Text('Log out'),
          ),
        ),
      ];
    }
    return [
      const ListTile(
        leading: Icon(Icons.person_off_outlined),
        title: Text('Not logged in'),
        subtitle: Text('Log in to publish your data to Nostr.'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          HakariSpacing.lg,
          0,
          HakariSpacing.lg,
          HakariSpacing.lg,
        ),
        child: FilledButton.tonalIcon(
          onPressed: _loginWithAmber,
          icon: const Icon(Icons.login),
          label: const Text('Login with Amber'),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------
  // Body profile

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  /// Numeric entry for one body-profile value. Validation happens in the
  /// dialog, not the controller: the controller silently ignores
  /// implausible values without saving, so without this check a user
  /// typing `30` would see the value simply not stick.
  Future<void> _editBodyValue({
    required String title,
    required String unit,
    required double? initial,
    required double min,
    required double max,
    required Future<AppSettings> Function(SettingsController c, double value)
    save,
  }) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _BodyValueDialog(
        title: title,
        unit: unit,
        initial: initial,
        min: min,
        max: max,
      ),
    );
    if (value == null) return;
    await _updateOnly((c) => save(c, value));
  }

  List<Widget> _bodyProfileRows(AppSettings settings) {
    final height = settings.heightCm;
    final goal = settings.goalWeightKg;
    return [
      ListTile(
        leading: const Icon(Icons.height),
        title: const Text('Height'),
        // The stored value does not remember whether it was typed or
        // imported, so the row states the rule instead of guessing a
        // source: imports only fill an empty slot, and clearing is how a
        // corrected Health Planet height gets picked up.
        subtitle: Text(
          height == null
              ? 'Not set. Enter it here, or the next Health Planet import '
                    'fills it in.'
              : '${_formatNumber(height)} cm. Entered here or filled in by '
                    'a Health Planet import; imports never overwrite it. '
                    'Clear it to let the next import refill it.',
        ),
        isThreeLine: height != null,
        trailing: height == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Clear height',
                icon: const Icon(Icons.close),
                onPressed: () => _updateOnly((c) => c.setHeightCm(null)),
              ),
        onTap: () => _editBodyValue(
          title: 'Height',
          unit: 'cm',
          initial: height,
          min: BodyProfileLimits.minHeightCm,
          max: BodyProfileLimits.maxHeightCm,
          save: (c, v) => c.setHeightCm(v),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.flag_outlined),
        title: const Text('Goal weight'),
        subtitle: Text(
          goal == null
              ? 'Not set. Health Planet does not provide it; enter it here '
                    'to see progress on the Stats tab.'
              : '${_formatNumber(goal)} kg. Progress toward it shows on the '
                    'Stats tab.',
        ),
        trailing: goal == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Clear goal weight',
                icon: const Icon(Icons.close),
                onPressed: () => _updateOnly((c) => c.setGoalWeightKg(null)),
              ),
        onTap: () => _editBodyValue(
          title: 'Goal weight',
          unit: 'kg',
          initial: goal,
          min: BodyProfileLimits.minWeightKg,
          max: BodyProfileLimits.maxWeightKg,
          save: (c, v) => c.setGoalWeightKg(v),
        ),
      ),
    ];
  }

  List<Widget> _relayRows(AppSettings settings) {
    return [
      if (settings.relays.isEmpty)
        const _EmptyState(
          icon: Icons.dns_outlined,
          message: 'No relays configured',
          compact: true,
        ),
      for (final relay in settings.relays)
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(relay),
          trailing: IconButton(
            tooltip: 'Remove relay',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _updateAndApply((c) => c.removeRelay(relay)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          HakariSpacing.lg,
          HakariSpacing.sm,
          HakariSpacing.lg,
          HakariSpacing.lg,
        ),
        child: Wrap(
          spacing: HakariSpacing.sm,
          runSpacing: HakariSpacing.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: _showAddRelayDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add relay'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateAndApply((c) => c.resetRelaysToDefaults()),
              child: const Text('Reset to defaults'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _torRows(AppSettings settings) {
    final orbotEnabled = settings.torMode == TorMode.orbot;
    return [
      SwitchListTile(
        secondary: const Icon(Icons.shield_outlined),
        title: const Text('Route through Orbot (SOCKS5)'),
        subtitle: const Text('Requires Orbot running with SOCKS on port 9050'),
        value: orbotEnabled,
        onChanged: (enabled) => _updateAndApply(
          (c) => c.setTorMode(enabled ? TorMode.orbot : TorMode.disabled),
        ),
      ),
      if (orbotEnabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HakariSpacing.lg,
            HakariSpacing.sm,
            HakariSpacing.lg,
            HakariSpacing.lg,
          ),
          child: TextFormField(
            initialValue: settings.proxyUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'SOCKS5 proxy URL',
              helperText:
                  'Press done to apply '
                  '(default socks5://127.0.0.1:9050)',
            ),
            onFieldSubmitted: (value) =>
                _updateAndApply((c) => c.setProxyUrl(value.trim())),
          ),
        ),
    ];
  }

  List<Widget> _publishingRows(AppSettings settings) {
    final syncStatus = ref.watch(nostrSyncProvider);
    return [
      SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: const Text('Encrypt health data (NIP-44)'),
        subtitle: const Text('Self-encrypt events before publishing'),
        value: settings.encryptHealthEvents,
        onChanged: (v) => _updateOnly((c) => c.setEncryptHealthEvents(v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.cloud_upload_outlined),
        title: const Text('Auto-publish to Nostr'),
        subtitle: const Text('Publish each new entry to your relays'),
        value: settings.autoPublishToNostr,
        onChanged: (v) => _updateOnly((c) => c.setAutoPublishToNostr(v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.sync_outlined),
        title: Text('Auto-sync to $_healthStoreName'),
        subtitle: Text('Write each new entry to $_healthStoreName'),
        value: settings.autoSyncToHealth,
        onChanged: (v) => _updateOnly((c) => c.setAutoSyncToHealth(v)),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('Fetch my data from relays'),
        subtitle: const Text('Import your published entries'),
        trailing: syncStatus.isSyncing
            ? const _BusyIndicator()
            : const Icon(Icons.chevron_right),
        onTap: syncStatus.isSyncing
            ? null
            : () => ref.read(nostrSyncProvider.notifier).fetchFromNostr(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          HakariSpacing.lg,
          HakariSpacing.sm,
          HakariSpacing.lg,
          HakariSpacing.lg,
        ),
        child: _RelayStatusList(),
      ),
    ];
  }

  List<Widget> _healthRows() {
    return [
      ListTile(
        leading: const Icon(Icons.favorite_outline),
        title: Text('Connect $_healthStoreName'),
        subtitle: const Text(
          'Weight & body fat (read/write), sleep & active energy '
          '(read-only)',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _connectHealth,
      ),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: Text('Import from $_healthStoreName (90 days)'),
        subtitle: const Text('Skips entries you already have'),
        trailing: _importingHealth ? const _BusyIndicator() : null,
        onTap: _importingHealth ? null : _importFromHealth,
      ),
      ListTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Check wellness data'),
        subtitle: const Text(
          'See whether sleep & energy reach the readiness card',
        ),
        trailing: _checkingWellness
            ? const _BusyIndicator()
            : const Icon(Icons.chevron_right),
        onTap: _checkingWellness ? null : _checkWellnessData,
      ),
    ];
  }

  List<Widget> _healthPlanetRows() {
    final busyIndicator = _healthPlanetBusy ? const _BusyIndicator() : null;
    if (!_healthPlanetLinked) {
      return [
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Link Health Planet'),
          subtitle: const Text(
            'Import TANITA scale measurements via the official cloud API',
          ),
          trailing: busyIndicator ?? const Icon(Icons.chevron_right),
          onTap: _healthPlanetBusy ? null : _linkHealthPlanet,
        ),
      ];
    }
    return [
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('Import from Health Planet (90 days)'),
        subtitle: const Text('Skips entries you already have'),
        trailing: busyIndicator,
        onTap: _healthPlanetBusy
            ? null
            : () => _importFromHealthPlanet(fullHistory: false),
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Import full history'),
        subtitle: const Text(
          'Pages back through your entire Health Planet record',
        ),
        trailing: busyIndicator,
        onTap: _healthPlanetBusy
            ? null
            : () => _importFromHealthPlanet(fullHistory: true),
      ),
      ListTile(
        leading: const Icon(Icons.link_off),
        title: const Text('Unlink Health Planet'),
        trailing: busyIndicator,
        onTap: _healthPlanetBusy ? null : _unlinkHealthPlanet,
      ),
    ];
  }

  List<Widget> _exportRows() {
    final busyIndicator = _exporting ? const _BusyIndicator() : null;
    return [
      ListTile(
        leading: const Icon(Icons.table_chart_outlined),
        title: const Text('Export CSV'),
        trailing: busyIndicator ?? const Icon(Icons.chevron_right),
        onTap: _exporting ? null : () => _export(asCsv: true),
      ),
      ListTile(
        leading: const Icon(Icons.data_object_outlined),
        title: const Text('Export JSON'),
        trailing: busyIndicator ?? const Icon(Icons.chevron_right),
        onTap: _exporting ? null : () => _export(asCsv: false),
      ),
    ];
  }
}

/// Numeric entry dialog for a body-profile value. Owns its text controller
/// so it is disposed with the route, after the exit animation, and pops
/// with the parsed value only when it lies within `[min, max]`.
class _BodyValueDialog extends StatefulWidget {
  const _BodyValueDialog({
    required this.title,
    required this.unit,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final String unit;
  final double? initial;
  final double min;
  final double max;

  @override
  State<_BodyValueDialog> createState() => _BodyValueDialogState();
}

class _BodyValueDialogState extends State<_BodyValueDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null
          ? ''
          : _SettingsScreenState._formatNumber(widget.initial!),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    final valid =
        parsed != null &&
        parsed.isFinite &&
        parsed >= widget.min &&
        parsed <= widget.max;
    if (!valid) {
      setState(() {
        _errorText =
            'Enter a value between '
            '${_SettingsScreenState._formatNumber(widget.min)} and '
            '${_SettingsScreenState._formatNumber(widget.max)} ${widget.unit}';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: '${widget.title} (${widget.unit})',
          suffixText: widget.unit,
          errorText: _errorText,
          // The range message does not fit one line at dialog width and
          // the decoration truncates errors to a single line by default.
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// One settings group: a [SectionHeader] over a tonal card holding the rows.
///
/// The card is the theme's [Card] (surface ladder "card" level, token
/// radius), so every group reads as one rounded block on the page, the way
/// trale groups its settings.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Centred icon + message: the whole body when settings fail to load, or a
/// compact block inside a group card when it has nothing to list.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.compact = false,
  });

  final IconData icon;
  final String message;

  /// Tighter vertical padding and a smaller icon for use inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: HakariSpacing.xl,
          vertical: compact ? HakariSpacing.xl : HakariSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? HakariSpacing.xxl : HakariSpacing.xxxl,
              color: scheme.outline,
            ),
            const SizedBox(height: HakariSpacing.md),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small spinner shown in a row's trailing slot while its action runs.
class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _size,
      height: _size,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _RelayStatusList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusesAsync = ref.watch(relayStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Relay status', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh relay status',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => ref.invalidate(relayStatusProvider),
            ),
          ],
        ),
        statusesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HakariSpacing.sm),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => Text(
            error is Failure
                ? error.message
                : 'Could not read relay status: $error',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (statuses) => statuses.isEmpty
              ? Text(
                  'No relays connected yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: HakariSpacing.sm,
                  runSpacing: HakariSpacing.sm,
                  children: [
                    for (final status in statuses)
                      _RelayStatusChip(status: status),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RelayStatusChip extends StatelessWidget {
  const _RelayStatusChip({required this.status});

  final RelayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status.state) {
      RelayState.connected => Colors.green,
      RelayState.connecting => Colors.orange,
      RelayState.disconnected => Colors.grey,
    };
    final label = status.url
        .replaceFirst('wss://', '')
        .replaceFirst('ws://', '');
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelSmall,
      visualDensity: VisualDensity.compact,
    );
  }
}
