import 'package:hive/hive.dart';

/// Persists the local secret key (nsec) for [SignerMode.localKey].
///
/// SECURITY TRADEOFF (v1): the key lives in a plain Hive box named 'secure'
/// inside the app sandbox. It is protected by OS app sandboxing only — NOT
/// by hardware-backed keystore encryption. Acceptable for v1 because:
/// - privacy-sensitive users are expected to use Amber (the secret then
///   never touches this app at all), and
/// - flutter_secure_storage is not in pubspec and pubspec is frozen for
///   this leaf.
/// TODO(v2): move to flutter_secure_storage / Android Keystore.
class NsecStore {
  static const String boxName = 'secure';
  static const String _nsecKey = 'nsec';

  Box<String>? _box;

  Future<Box<String>> _open() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    return _box = await Hive.openBox<String>(boxName);
  }

  Future<String?> read() async => (await _open()).get(_nsecKey);

  Future<void> save(String nsec) async => (await _open()).put(_nsecKey, nsec);

  Future<void> clear() async => (await _open()).delete(_nsecKey);
}
