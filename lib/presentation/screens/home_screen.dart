import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../providers/entries_provider.dart';
import '../providers/nostr_sync_provider.dart';
import '../widgets/app_messenger.dart';
import '../widgets/entry_tile.dart';
import '../widgets/weight_chart.dart';
import 'add_entry_sheet.dart';
import 'scale_screen.dart';
import 'settings_screen.dart';

/// Main screen: trend chart, entry list, add / scale FABs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesProvider);
    final syncStatus = ref.watch(nostrSyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hakari'),
        actions: [
          IconButton(
            tooltip: 'Publish unpublished entries to Nostr',
            onPressed: syncStatus.isSyncing
                ? null
                : () => ref
                      .read(nostrSyncProvider.notifier)
                      .publishAllUnpublished(),
            icon: syncStatus.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is Failure
                  ? error.message
                  : 'Failed to load entries: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (entries) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            WeightChartCard(entries: entries),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const _EmptyList()
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DismissibleEntry(entry: entry),
                ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab-scale',
            tooltip: 'Measure with a Bluetooth scale',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScaleScreen()),
            ),
            child: const Icon(Icons.bluetooth),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'fab-add',
            tooltip: 'Add measurement',
            onPressed: () => AddEntrySheet.show(context),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _DismissibleEntry extends ConsumerWidget {
  const _DismissibleEntry({required this.entry});

  final WeightEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _deleteWithUndo(ref),
      child: EntryTile(entry: entry),
    );
  }

  Future<void> _deleteWithUndo(WidgetRef ref) async {
    final repo = ref.read(weightRepositoryProvider);
    try {
      await repo.delete(entry.id);
    } on Failure catch (f) {
      showAppSnackBar(f.message);
      return;
    }
    showAppSnackBar(
      'Entry deleted.',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await repo.upsert(entry);
          } on Failure catch (f) {
            showAppSnackBar(f.message);
          }
        },
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.monitor_weight_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('No measurements yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Tap + to add one, or connect your scale.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
