import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/nostr_service.dart';
import '../providers/nostr_sync_provider.dart';
import '../providers/relay_status_provider.dart';
import '../providers/settings_provider.dart';
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
  bool _exporting = false;

  SettingsController get _settings => ref.read(settingsProvider.notifier);

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
                  final valid = (text.startsWith('wss://') ||
                          text.startsWith('ws://')) &&
                      uri != null &&
                      uri.host.isNotEmpty;
                  if (!valid) {
                    setDialogState(() {
                      errorText = 'Enter a wss:// or ws:// URL';
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

  Future<void> _connectHealth() async {
    try {
      final health = ref.read(healthServiceProvider);
      if (!await health.isAvailable()) {
        showAppSnackBar(
          'Health Connect / Health is not available on this device.',
        );
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
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is Failure
                  ? error.message
                  : 'Failed to load settings: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ..._identitySection(settings),
            ..._relaySection(settings),
            ..._torSection(settings),
            ..._publishingSection(settings),
            ..._healthSection(settings),
            ..._exportSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _identitySection(AppSettings settings) {
    final pubkey = settings.pubkeyHex;
    return [
      const SectionHeader('Identity'),
      if (pubkey != null)
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(_truncateMiddle(pubkey)),
          subtitle: Text(
            switch (settings.signerMode) {
              SignerMode.amber => 'Signing with Amber',
              SignerMode.localKey => 'Signing with local key',
              SignerMode.none => 'No signer configured',
            },
          ),
          trailing: TextButton(
            onPressed: _logout,
            child: const Text('Log out'),
          ),
        )
      else
        ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('Not logged in'),
          subtitle: const Text('Log in to publish your data to Nostr.'),
          trailing: FilledButton.tonal(
            onPressed: _loginWithAmber,
            child: const Text('Login with Amber'),
          ),
        ),
    ];
  }

  List<Widget> _relaySection(AppSettings settings) {
    return [
      const SectionHeader('Relays'),
      for (final relay in settings.relays)
        ListTile(
          dense: true,
          leading: const Icon(Icons.dns_outlined),
          title: Text(relay),
          trailing: IconButton(
            tooltip: 'Remove relay',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _updateAndApply((c) => c.removeRelay(relay)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _showAddRelayDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add relay'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () =>
                  _updateAndApply((c) => c.resetRelaysToDefaults()),
              child: const Text('Reset to defaults'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _torSection(AppSettings settings) {
    final orbotEnabled = settings.torMode == TorMode.orbot;
    return [
      const SectionHeader('Privacy'),
      SwitchListTile(
        title: const Text('Route through Orbot (SOCKS5)'),
        subtitle: const Text(
          'Requires Orbot running with SOCKS on port 9050',
        ),
        value: orbotEnabled,
        onChanged: (enabled) => _updateAndApply(
          (c) => c.setTorMode(enabled ? TorMode.orbot : TorMode.disabled),
        ),
      ),
      if (orbotEnabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextFormField(
            initialValue: settings.proxyUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'SOCKS5 proxy URL',
              helperText: 'Press done to apply '
                  '(default socks5://127.0.0.1:9050)',
            ),
            onFieldSubmitted: (value) =>
                _updateAndApply((c) => c.setProxyUrl(value.trim())),
          ),
        ),
    ];
  }

  List<Widget> _publishingSection(AppSettings settings) {
    final syncStatus = ref.watch(nostrSyncProvider);
    return [
      const SectionHeader('Publishing'),
      SwitchListTile(
        title: const Text('Encrypt health data (NIP-44)'),
        subtitle: const Text('Self-encrypt events before publishing'),
        value: settings.encryptHealthEvents,
        onChanged: (v) => _updateOnly((c) => c.setEncryptHealthEvents(v)),
      ),
      SwitchListTile(
        title: const Text('Auto-publish to Nostr'),
        subtitle: const Text('Publish each new entry to your relays'),
        value: settings.autoPublishToNostr,
        onChanged: (v) => _updateOnly((c) => c.setAutoPublishToNostr(v)),
      ),
      SwitchListTile(
        title: const Text('Auto-sync to Health'),
        subtitle: const Text(
          'Write each new entry to Health Connect / Health',
        ),
        value: settings.autoSyncToHealth,
        onChanged: (v) => _updateOnly((c) => c.setAutoSyncToHealth(v)),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('Fetch my data from relays'),
        subtitle: const Text('Import your published entries'),
        trailing: syncStatus.isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: syncStatus.isSyncing
            ? null
            : () => ref.read(nostrSyncProvider.notifier).fetchFromNostr(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _RelayStatusList(),
      ),
    ];
  }

  List<Widget> _healthSection(AppSettings settings) {
    return [
      const SectionHeader('Health'),
      ListTile(
        leading: const Icon(Icons.favorite_outline),
        title: const Text('Connect Health Connect / Health'),
        subtitle: const Text('Request read & write permissions'),
        onTap: _connectHealth,
      ),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('Import from Health (90 days)'),
        subtitle: const Text('Skips entries you already have'),
        trailing: _importingHealth
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: _importingHealth ? null : _importFromHealth,
      ),
    ];
  }

  List<Widget> _exportSection() {
    return [
      const SectionHeader('Export'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export(asCsv: true),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export CSV'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export(asCsv: false),
                icon: const Icon(Icons.data_object_outlined),
                label: const Text('Export JSON'),
              ),
            ),
          ],
        ),
      ),
    ];
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
            padding: EdgeInsets.symmetric(vertical: 8),
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
                  spacing: 8,
                  runSpacing: 8,
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
