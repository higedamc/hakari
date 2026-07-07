import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/export_service.dart';

/// [ExportService] writing CSV / JSON files into
/// `<application documents>/exports/` and sharing them via share_plus.
///
/// The CSV column set matches WeightLogger's export format.
class FileExportService implements ExportService {
  static const String csvHeader =
      'recorded_at,weight_kg,body_fat_percent,'
      'body_water_percent,muscle_mass_kg,visceral_fat_rating,bone_mass_kg,'
      'basal_metabolic_rate_kcal,metabolic_age,source';

  /// Builds the full CSV document (header + one row per entry).
  /// Pure — safe to call without any platform channels.
  static String buildCsv(List<WeightEntry> entries) {
    final buffer = StringBuffer(csvHeader);
    for (final entry in entries) {
      buffer
        ..write('\n')
        ..write(buildCsvRow(entry));
    }
    return buffer.toString();
  }

  /// Builds a single CSV row for [entry] (no trailing newline).
  static String buildCsvRow(WeightEntry entry) {
    final fields = <String>[
      entry.recordedAt.toIso8601String(),
      entry.weightKg.toString(),
      entry.bodyFatPercent?.toString() ?? '',
      entry.bodyWaterPercent?.toString() ?? '',
      entry.muscleMassKg?.toString() ?? '',
      entry.visceralFatRating?.toString() ?? '',
      entry.boneMassKg?.toString() ?? '',
      entry.basalMetabolicRateKcal?.toString() ?? '',
      entry.metabolicAge?.toString() ?? '',
      entry.source.name,
    ];
    return fields.map(escapeCsvField).join(',');
  }

  /// RFC 4180 style escaping: fields containing a comma, double quote,
  /// or newline are wrapped in double quotes with inner quotes doubled.
  ///
  /// Also guards against spreadsheet formula injection: a non-numeric
  /// field starting with `=`, `+`, `-`, `@`, tab or CR would be executed
  /// as a formula by Excel/LibreOffice, so it gets a leading `'`. Today
  /// every column is a number, ISO timestamp or enum name — this matters
  /// the moment an attacker-controlled string (e.g. a BLE device name)
  /// is ever added as a column.
  static String escapeCsvField(String field) {
    var value = field;
    const formulaTriggers = ['=', '+', '-', '@', '\t', '\r'];
    final startsRisky = value.isNotEmpty && formulaTriggers.contains(value[0]);
    if (startsRisky && num.tryParse(value) == null) {
      value = "'$value";
    }
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Builds the versioned JSON backup document. Pure.
  static String buildJson(List<WeightEntry> entries) {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'hakari',
      'version': 1,
      'entries': entries.map((e) => e.toMap()).toList(),
    });
  }

  @override
  Future<String> exportCsv(List<WeightEntry> entries) {
    return _writeExportFile(extension: 'csv', content: buildCsv(entries));
  }

  @override
  Future<String> exportJson(List<WeightEntry> entries) {
    return _writeExportFile(extension: 'json', content: buildJson(entries));
  }

  @override
  Future<void> shareFile(String filePath) async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(filePath)]));
    } catch (e) {
      throw ExportFailure('Failed to share "$filePath"', e);
    }
  }

  Future<String> _writeExportFile({
    required String extension,
    required String content,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${docs.path}/exports');
      await exportDir.create(recursive: true);
      // Exports are unencrypted health data; don't let old ones pile up
      // on disk forever — only the file being shared right now is needed.
      await for (final old in exportDir.list()) {
        if (old is File && old.path.contains('hakari_export_')) {
          try {
            await old.delete();
          } catch (_) {
            // Best effort; a locked file must not break the new export.
          }
        }
      }
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(
        '${exportDir.path}/hakari_export_$timestamp.$extension',
      );
      await file.writeAsString(content, flush: true);
      return file.path;
    } catch (e) {
      throw ExportFailure('Failed to write $extension export', e);
    }
  }
}
