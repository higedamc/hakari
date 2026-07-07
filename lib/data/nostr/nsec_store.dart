import 'package:hive/hive.dart';

import '../local/hive_encryption.dart';

/// Persists the local secret key (nsec) for [SignerMode.localKey].
///
/// When constructed with a [HiveAesCipher] (production path, see
/// main.dart) the box is AES-encrypted with a key held in the platform
/// keystore via [HiveEncryption]; a legacy plaintext 'secure' box is
/// migrated on first open. Without a cipher (tests) it falls back to a
/// plain box. Note the UI is Amber-only — with Amber the secret never
/// touches this app at all.
class NsecStore {
  NsecStore({HiveAesCipher? cipher}) : _cipher = cipher;

  static const String boxName = 'secure';
  static const String _nsecKey = 'nsec';

  final HiveAesCipher? _cipher;
  Box<String>? _box;

  Future<Box<String>> _open() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    final cipher = _cipher;
    return _box = cipher != null
        ? await HiveEncryption.openEncryptedBox<String>(boxName, cipher)
        : await Hive.openBox<String>(boxName);
  }

  Future<String?> read() async => (await _open()).get(_nsecKey);

  Future<void> save(String nsec) async => (await _open()).put(_nsecKey, nsec);

  Future<void> clear() async => (await _open()).delete(_nsecKey);
}
