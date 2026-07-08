import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/weight_entry.dart';

final NumberFormat _oneDecimal = NumberFormat('0.0');
final DateFormat _dateFormat = DateFormat('EEE, MMM d, y');
final DateFormat _timeFormat = DateFormat('HH:mm');

IconData _sourceIcon(MeasurementSource source) => switch (source) {
  MeasurementSource.manual => Icons.edit_outlined,
  MeasurementSource.bleScale => Icons.bluetooth,
  MeasurementSource.healthSync => Icons.favorite_outline,
  MeasurementSource.imported => Icons.download_outlined,
};

String _sourceLabel(MeasurementSource source) => switch (source) {
  MeasurementSource.manual => 'Entered manually',
  MeasurementSource.bleScale => 'Bluetooth scale',
  MeasurementSource.healthSync => 'Health sync',
  MeasurementSource.imported => 'Imported',
};

/// Card row for a single measurement: bold weight, composition chips,
/// date, a source icon and a "published to Nostr" indicator.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.onTap});

  final WeightEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chips = _compositionChips();

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: _sourceLabel(entry.source),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(
                    _sourceIcon(entry.source),
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_oneDecimal.format(entry.weightKg)} kg',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (entry.nostrEventId != null)
                          Tooltip(
                            message: 'Published to Nostr',
                            child: Icon(
                              Icons.cloud_done_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_dateFormat.format(entry.recordedAt)} at '
                      '${_timeFormat.format(entry.recordedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in chips)
                            _CompositionChip(label: label),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _compositionChips() {
    final chips = <String>[];
    final fat = entry.bodyFatPercent;
    if (fat != null) chips.add('${_oneDecimal.format(fat)}% fat');
    final water = entry.bodyWaterPercent;
    if (water != null) chips.add('${_oneDecimal.format(water)}% water');
    final muscle = entry.muscleMassKg;
    if (muscle != null) chips.add('${_oneDecimal.format(muscle)} kg muscle');
    final muscleScore = entry.muscleScore;
    if (muscleScore != null) chips.add('Muscle score $muscleScore');
    // Prefer the one-decimal visceral level when present; the integer
    // rating is the same metric, coarser.
    final visceral2 = entry.visceralFatLevel2;
    final visceral = entry.visceralFatRating;
    if (visceral2 != null) {
      chips.add('Visceral ${_oneDecimal.format(visceral2)}');
    } else if (visceral != null) {
      chips.add('Visceral $visceral');
    }
    final bone = entry.boneMassKg;
    if (bone != null) chips.add('${_oneDecimal.format(bone)} kg bone');
    final bmr = entry.basalMetabolicRateKcal;
    if (bmr != null) chips.add('$bmr kcal BMR');
    final metAge = entry.metabolicAge;
    if (metAge != null) chips.add('Met. age $metAge');
    return chips;
  }
}

class _CompositionChip extends StatelessWidget {
  const _CompositionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
