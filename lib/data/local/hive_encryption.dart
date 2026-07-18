import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// At-rest encryption for Hive boxes.
///
/// The 32-byte AES key is generated once with Hive's CSPRNG helper and
/// kept in platform secure storage (Android Keystore-backed
/// EncryptedSharedPreferences / iOS Keychain) — never in a plaintext file.
/// Boxes opened through [openEncryptedBox] get a `_enc` suffix; data from
/// the pre-encryption plaintext box of the same base name is migrated in
/// and the old box is deleted from disk.
class HiveEncryption {
  HiveEncryption._();

  static const String _keyName = 'hive_encryption_key_v1';
  // v10+: Keystore-backed custom ciphers by default; existing
  // EncryptedSharedPreferences data migrates automatically on first
  // access.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Loads (or creates and stores) the box encryption key.
  static Future<HiveAesCipher> getCipher() async {
    var encoded = await _storage.read(key: _keyName);
    if (encoded == null) {
      final key = Hive.generateSecureKey();
      encoded = base64UrlEncode(key);
      await _storage.write(key: _keyName, value: encoded);
    }
    return HiveAesCipher(base64Url.decode(encoded));
  }

  /// Opens the encrypted box for [baseName], migrating any legacy
  /// plaintext box of that name.
  static Future<Box<T>> openEncryptedBox<T>(
    String baseName,
    HiveAesCipher cipher,
  ) async {
    final box = await Hive.openBox<T>(
      '${baseName}_enc',
      encryptionCipher: cipher,
    );
    try {
      if (await Hive.boxExists(baseName)) {
        final legacy = await Hive.openBox<T>(baseName);
        for (final key in legacy.keys) {
          final value = legacy.get(key);
          if (value != null) await box.put(key, value);
        }
        await legacy.deleteFromDisk();
      }
    } catch (_) {
      // A corrupt legacy box must not brick startup; the encrypted box
      // is usable either way and the plaintext file is at worst left
      // behind for the next launch to retry.
    }
    return box;
  }
}
