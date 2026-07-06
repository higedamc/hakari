import '../entities/weight_entry.dart';

/// Export measurements to a shareable file.
/// Implementations throw [ExportFailure].
abstract interface class ExportService {
  /// Write [entries] as CSV (WeightLogger-compatible column set)
  /// and return the file path.
  Future<String> exportCsv(List<WeightEntry> entries);

  /// Write [entries] as JSON backup and return the file path.
  Future<String> exportJson(List<WeightEntry> entries);

  /// Open the platform share sheet for [filePath].
  Future<void> shareFile(String filePath);
}
