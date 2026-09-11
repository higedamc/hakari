import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/core/di/providers.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/domain/repositories/settings_repository.dart';
import 'package:hakari/presentation/providers/settings_provider.dart';

/// Body-profile mutators on [SettingsController]: manual values persist,
/// implausible values are ignored, and a synced height never overwrites a
/// value the user entered.
void main() {
  late _MemorySettingsRepository repo;
  late ProviderContainer container;

  Future<SettingsController> controller() async {
    await container.read(settingsProvider.future);
    return container.read(settingsProvider.notifier);
  }

  setUp(() {
    repo = _MemorySettingsRepository();
    container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  group('setHeightCm', () {
    test('persists a plausible value and clears on null', () async {
      final c = await controller();
      expect((await c.setHeightCm(175)).heightCm, 175);
      expect(repo.saved.last.heightCm, 175);
      expect((await c.setHeightCm(null)).heightCm, isNull);
      expect(repo.saved.last.heightCm, isNull);
    });

    test('ignores implausible values without saving', () async {
      final c = await controller();
      await c.setHeightCm(175);
      final savesBefore = repo.saved.length;
      expect((await c.setHeightCm(0)).heightCm, 175);
      expect((await c.setHeightCm(999)).heightCm, 175);
      expect((await c.setHeightCm(double.nan)).heightCm, 175);
      expect(repo.saved.length, savesBefore);
    });
  });

  group('setGoalWeightKg', () {
    test('persists a plausible value and clears on null', () async {
      final c = await controller();
      expect((await c.setGoalWeightKg(68)).goalWeightKg, 68);
      expect(repo.saved.last.goalWeightKg, 68);
      expect((await c.setGoalWeightKg(null)).goalWeightKg, isNull);
    });

    test('ignores implausible values without saving', () async {
      final c = await controller();
      await c.setGoalWeightKg(68);
      final savesBefore = repo.saved.length;
      expect((await c.setGoalWeightKg(0)).goalWeightKg, 68);
      expect((await c.setGoalWeightKg(600)).goalWeightKg, 68);
      expect(repo.saved.length, savesBefore);
    });
  });

  group('adoptFetchedHeightCm', () {
    test('fills an empty height and persists it', () async {
      final c = await controller();
      expect((await c.adoptFetchedHeightCm(177.5)).heightCm, 177.5);
      expect(repo.saved.last.heightCm, 177.5);
    });

    test('never overwrites a height the user entered', () async {
      final c = await controller();
      await c.setHeightCm(170);
      final savesBefore = repo.saved.length;
      expect((await c.adoptFetchedHeightCm(177.5)).heightCm, 170);
      expect(repo.saved.length, savesBefore, reason: 'no save on no-op');
    });

    test('does not overwrite a previously adopted height either', () async {
      final c = await controller();
      await c.adoptFetchedHeightCm(177.5);
      expect((await c.adoptFetchedHeightCm(180)).heightCm, 177.5);
    });

    test('fills again after the user clears the manual value', () async {
      final c = await controller();
      await c.setHeightCm(170);
      await c.setHeightCm(null);
      expect((await c.adoptFetchedHeightCm(177.5)).heightCm, 177.5);
    });

    test('ignores null and implausible fetched values', () async {
      final c = await controller();
      final savesBefore = repo.saved.length;
      expect((await c.adoptFetchedHeightCm(null)).heightCm, isNull);
      expect((await c.adoptFetchedHeightCm(10)).heightCm, isNull);
      expect((await c.adoptFetchedHeightCm(double.nan)).heightCm, isNull);
      expect(repo.saved.length, savesBefore);
    });
  });
}

class _MemorySettingsRepository implements SettingsRepository {
  AppSettings current = const AppSettings();
  final saved = <AppSettings>[];

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
    saved.add(settings);
  }

  @override
  Stream<AppSettings> watch() => Stream.value(current);
}
