import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/app_settings.dart';

void main() {
  group('AppSettings body profile', () {
    test('defaults to no height and no goal', () {
      const s = AppSettings();
      expect(s.heightCm, isNull);
      expect(s.goalWeightKg, isNull);
    });

    test('toMap / fromMap round-trips both fields', () {
      const s = AppSettings(heightCm: 177.5, goalWeightKg: 68);
      final restored = AppSettings.fromMap(s.toMap());
      expect(restored.heightCm, 177.5);
      expect(restored.goalWeightKg, 68);
      expect(restored.toMap(), s.toMap());
    });

    test('a map written by the previous version still loads', () {
      // Exactly the keys v0.4.3 persisted; no heightCm / goalWeightKg.
      final legacy = <String, dynamic>{
        'relays': ['wss://relay.example'],
        'torMode': 'orbot',
        'proxyUrl': 'socks5://127.0.0.1:9050',
        'signerMode': 'localKey',
        'pubkeyHex': 'ab',
        'encryptHealthEvents': false,
        'autoSyncToHealth': true,
        'autoPublishToNostr': true,
        'useMetricUnits': false,
        'onboardingComplete': true,
      };
      final s = AppSettings.fromMap(legacy);
      expect(s.heightCm, isNull);
      expect(s.goalWeightKg, isNull);
      expect(s.relays, ['wss://relay.example']);
      expect(s.torMode, TorMode.orbot);
      expect(s.signerMode, SignerMode.localKey);
      expect(s.pubkeyHex, 'ab');
      expect(s.encryptHealthEvents, isFalse);
      expect(s.autoSyncToHealth, isTrue);
      expect(s.autoPublishToNostr, isTrue);
      expect(s.useMetricUnits, isFalse);
      expect(s.onboardingComplete, isTrue);
    });

    test('fromMap accepts ints, rejects non-numbers and non-finite', () {
      expect(AppSettings.fromMap({'heightCm': 170}).heightCm, 170.0);
      expect(AppSettings.fromMap({'goalWeightKg': 65}).goalWeightKg, 65.0);
      expect(AppSettings.fromMap({'heightCm': '170'}).heightCm, isNull);
      expect(AppSettings.fromMap({'heightCm': null}).heightCm, isNull);
      expect(AppSettings.fromMap({'heightCm': double.nan}).heightCm, isNull);
      expect(
        AppSettings.fromMap({'goalWeightKg': double.infinity}).goalWeightKg,
        isNull,
      );
    });

    test('copyWith keeps, replaces and clears independently', () {
      const s = AppSettings(heightCm: 170, goalWeightKg: 65);
      expect(s.copyWith().heightCm, 170);
      expect(s.copyWith().goalWeightKg, 65);
      expect(s.copyWith(heightCm: 172).heightCm, 172);
      expect(s.copyWith(heightCm: 172).goalWeightKg, 65);
      expect(s.copyWith(goalWeightKg: 60).goalWeightKg, 60);
      expect(s.copyWith(goalWeightKg: 60).heightCm, 170);

      final clearedHeight = s.copyWith(clearHeightCm: true);
      expect(clearedHeight.heightCm, isNull);
      expect(clearedHeight.goalWeightKg, 65);

      final clearedGoal = s.copyWith(clearGoalWeightKg: true);
      expect(clearedGoal.goalWeightKg, isNull);
      expect(clearedGoal.heightCm, 170);
    });
  });
}
