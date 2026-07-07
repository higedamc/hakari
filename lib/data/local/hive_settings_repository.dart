import 'dart:async';

import 'package:hive/hive.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/failures/failures.dart';
import '../../domain/repositories/settings_repository.dart';

/// [SettingsRepository] backed by a Hive box holding a single map under
/// the key [settingsKey] ([AppSettings.toMap] round-trip, no TypeAdapter).
///
/// Open the box once at startup (after `Hive.initFlutter()` /
/// `Hive.init(path)`) via [openBox] and inject it here.
class HiveSettingsRepository implements SettingsRepository {
  static const String boxName = 'app_settings';
  static const String settingsKey = 'settings';

  final Box _box;

  HiveSettingsRepository(this._box);

  /// Opens (or returns the already-open) box backing this repository.
  static Future<Box> openBox() async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      throw StorageFailure('Failed to open Hive box "$boxName"', e);
    }
  }

  @override
  Future<AppSettings> load() async {
    try {
      final raw = _box.get(settingsKey);
      if (raw == null) return const AppSettings();
      return AppSettings.fromMap(raw as Map);
    } catch (e) {
      throw StorageFailure('Failed to load app settings', e);
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await _box.put(settingsKey, settings.toMap());
    } catch (e) {
      throw StorageFailure('Failed to save app settings', e);
    }
  }

  @override
  Stream<AppSettings> watch() {
    // A StreamController (not async*) so that cancelling the subscription
    // completes immediately instead of waiting for the next box event.
    late final StreamController<AppSettings> controller;
    StreamSubscription<BoxEvent>? boxSub;

    Future<void> emit() async {
      try {
        controller.add(await load());
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller = StreamController<AppSettings>(
      onListen: () {
        emit();
        boxSub = _box.watch(key: settingsKey).listen((_) => emit());
      },
      onCancel: () async {
        await boxSub?.cancel();
      },
    );
    return controller.stream;
  }
}
