import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../providers/entry_saver_provider.dart';
import '../widgets/app_messenger.dart';

final DateFormat _dateFormat = DateFormat('EEE, MMM d, y');
final DateFormat _timeFormat = DateFormat('HH:mm');

/// Modal bottom sheet for adding a manual measurement.
class AddEntrySheet extends ConsumerStatefulWidget {
  const AddEntrySheet({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const AddEntrySheet(),
      );

  @override
  ConsumerState<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _bodyWaterCtrl = TextEditingController();
  final _muscleCtrl = TextEditingController();
  final _visceralCtrl = TextEditingController();
  final _boneCtrl = TextEditingController();
  final _bmrCtrl = TextEditingController();
  final _metabolicAgeCtrl = TextEditingController();

  DateTime _recordedAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    _bodyWaterCtrl.dispose();
    _muscleCtrl.dispose();
    _visceralCtrl.dispose();
    _boneCtrl.dispose();
    _bmrCtrl.dispose();
    _metabolicAgeCtrl.dispose();
    super.dispose();
  }

  static double? _parseDouble(TextEditingController ctrl) {
    final text = ctrl.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static int? _parseInt(TextEditingController ctrl) {
    final text = ctrl.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  String? _validateWeight(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      return 'Enter a weight in kg';
    }
    return null;
  }

  String? _validateOptionalDouble(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || parsed < 0) return 'Invalid number';
    return null;
  }

  String? _validateOptionalInt(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return 'Invalid number';
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _recordedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _recordedAt.hour,
        _recordedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordedAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _recordedAt = DateTime(
        _recordedAt.year,
        _recordedAt.month,
        _recordedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final entry = WeightEntry(
      id: const Uuid().v4(),
      recordedAt: _recordedAt,
      weightKg: _parseDouble(_weightCtrl)!,
      bodyFatPercent: _parseDouble(_bodyFatCtrl),
      bodyWaterPercent: _parseDouble(_bodyWaterCtrl),
      muscleMassKg: _parseDouble(_muscleCtrl),
      visceralFatRating: _parseInt(_visceralCtrl),
      boneMassKg: _parseDouble(_boneCtrl),
      basalMetabolicRateKcal: _parseInt(_bmrCtrl),
      metabolicAge: _parseInt(_metabolicAgeCtrl),
    );

    try {
      final warnings = await ref.read(entrySaverProvider).save(entry);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (warnings.isNotEmpty) {
        showAppSnackBar(warnings.join('\n'));
      }
    } on Failure catch (f) {
      if (mounted) setState(() => _saving = false);
      showAppSnackBar(f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New measurement', style: theme.textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                controller: _weightCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateWeight,
                decoration: const InputDecoration(
                  labelText: 'Weight',
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(_dateFormat.format(_recordedAt)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(_timeFormat.format(_recordedAt)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('Body composition'),
                subtitle: const Text('Optional'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  _fieldRow(
                    _numberField(_bodyFatCtrl, 'Body fat', suffix: '%'),
                    _numberField(_bodyWaterCtrl, 'Body water', suffix: '%'),
                  ),
                  const SizedBox(height: 12),
                  _fieldRow(
                    _numberField(_muscleCtrl, 'Muscle mass', suffix: 'kg'),
                    _numberField(
                      _visceralCtrl,
                      'Visceral fat',
                      integer: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fieldRow(
                    _numberField(_boneCtrl, 'Bone mass', suffix: 'kg'),
                    _numberField(
                      _bmrCtrl,
                      'BMR',
                      suffix: 'kcal',
                      integer: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fieldRow(
                    _numberField(
                      _metabolicAgeCtrl,
                      'Metabolic age',
                      integer: true,
                    ),
                    const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? suffix,
    bool integer = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      validator: integer ? _validateOptionalInt : _validateOptionalDouble,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}
