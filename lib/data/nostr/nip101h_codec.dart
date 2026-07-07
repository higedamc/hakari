import 'dart:convert';

import '../../domain/entities/weight_entry.dart';

/// Pure NIP-101h (de)serialization helpers, kept free of FFI so they are
/// unit-testable without loading the native library.
///
/// Wire contract (shared with rust/src/api.rs — do not rename fields):
/// - kind 1351: content = weight string ("72.5"), tags unit/t/timestamp/...
/// - kind 30078: content = NIP-44 self-encrypted JSON of the full entry.

const int weightEventKind = 1351;
const int backupEventKind = 30078;
const String backupDTagPrefix = 'hakari:entry:';
const String backupHashtag = 'hakari-health';

/// Content string of a plain (unencrypted) kind-1351 weight event.
/// Matches the Rust formatter: integral weights keep one decimal ("72.0").
String weightContent(double weightKg) => weightKg.toString();

/// First value of the first tag whose name is [key], or null.
String? tagValue(List<List<String>> tags, String key) {
  for (final tag in tags) {
    if (tag.length >= 2 && tag.first == key) return tag[1];
  }
  return null;
}

/// Whether a kind-1351 event declares NIP-44 encrypted content.
bool isEncryptedWeightEvent(List<List<String>> tags) =>
    tagValue(tags, 'encrypted') == 'true' ||
    tagValue(tags, 'encryption_algo') == 'nip44';

/// Plaintext JSON for the kind-30078 backup content (before NIP-44
/// encryption). [weightEventId] is the id of the companion 1351 event.
String backupPlaintext(WeightEntry entry, {String? weightEventId}) {
  final map = <String, dynamic>{
    'id': entry.id,
    'recorded_at': entry.recordedAt.millisecondsSinceEpoch ~/ 1000,
    'weight_kg': entry.weightKg,
    if (entry.bodyFatPercent != null) 'body_fat_percent': entry.bodyFatPercent,
    if (entry.bodyWaterPercent != null)
      'body_water_percent': entry.bodyWaterPercent,
    if (entry.muscleMassKg != null) 'muscle_mass_kg': entry.muscleMassKg,
    if (entry.visceralFatRating != null)
      'visceral_fat_rating': entry.visceralFatRating,
    if (entry.boneMassKg != null) 'bone_mass_kg': entry.boneMassKg,
    if (entry.basalMetabolicRateKcal != null)
      'basal_metabolic_rate_kcal': entry.basalMetabolicRateKcal,
    if (entry.metabolicAge != null) 'metabolic_age': entry.metabolicAge,
    'source': entry.source.name,
    'weight_event_id': ?weightEventId,
  };
  return jsonEncode(map);
}

/// The 1351 event id referenced by a decrypted backup map, if any.
String? weightEventIdOfBackup(Map<String, dynamic> map) =>
    map['weight_event_id'] as String?;

/// Map a decrypted kind-30078 backup JSON to a [WeightEntry].
/// [backupEventId] is the 30078 event id (fallback for [nostrEventId]
/// when the backup does not reference a 1351 event).
WeightEntry entryFromBackupMap(
  Map<String, dynamic> map, {
  required String backupEventId,
}) {
  return WeightEntry(
    id: map['id'] as String,
    recordedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['recorded_at'] as num).toInt() * 1000,
    ),
    weightKg: (map['weight_kg'] as num).toDouble(),
    bodyFatPercent: (map['body_fat_percent'] as num?)?.toDouble(),
    bodyWaterPercent: (map['body_water_percent'] as num?)?.toDouble(),
    muscleMassKg: (map['muscle_mass_kg'] as num?)?.toDouble(),
    visceralFatRating: (map['visceral_fat_rating'] as num?)?.toInt(),
    boneMassKg: (map['bone_mass_kg'] as num?)?.toDouble(),
    basalMetabolicRateKcal: (map['basal_metabolic_rate_kcal'] as num?)?.toInt(),
    metabolicAge: (map['metabolic_age'] as num?)?.toInt(),
    source: MeasurementSource.imported,
    nostrEventId: weightEventIdOfBackup(map) ?? backupEventId,
  );
}

/// Map a stand-alone (not backed-up) kind-1351 weight event to a
/// weight-only [WeightEntry]. [content] must already be decrypted.
/// Returns null when the content is not a parseable number.
WeightEntry? entryFromWeightEvent({
  required String eventId,
  required int createdAtUnix,
  required String content,
  required List<List<String>> tags,
}) {
  final weightKg = double.tryParse(content.trim());
  if (weightKg == null) return null;

  DateTime recordedAt = DateTime.fromMillisecondsSinceEpoch(
    createdAtUnix * 1000,
  );
  final timestamp = tagValue(tags, 'timestamp');
  if (timestamp != null) {
    recordedAt = DateTime.tryParse(timestamp) ?? recordedAt;
  }

  return WeightEntry(
    id: eventId,
    recordedAt: recordedAt,
    weightKg: weightKg,
    source: MeasurementSource.imported,
    nostrEventId: eventId,
  );
}
