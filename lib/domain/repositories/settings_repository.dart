import '../entities/app_settings.dart';

/// Persistence contract for app settings.
abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);

  Stream<AppSettings> watch();
}
