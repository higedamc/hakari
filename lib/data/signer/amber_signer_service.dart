import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../domain/failures/failures.dart';
import '../../domain/services/signer_service.dart';
import 'bech32.dart';

/// [SignerService] backed by the Amber external signer (NIP-55) on Android.
///
/// All operations are delegated over a [MethodChannel] to
/// `MainActivity.kt`, which launches Amber
/// (`com.greenart7c3.nostrsigner`) via `startActivityForResult` and
/// returns the response extras.
///
/// Error mapping (PlatformException code -> Failure):
/// - `AMBER_REJECTED` / `AMBER_CANCELLED` -> [SignerRejectedFailure]
/// - `AMBER_NOT_INSTALLED`                -> [SignerUnavailableFailure]
/// - anything else                        -> [SignerFailure]
class AmberSignerService implements SignerService {
  static const MethodChannel _defaultChannel =
      MethodChannel('org.lekt.hakari/amber');

  final MethodChannel _channel;

  /// [channel] is overridable for tests; production code uses the default.
  const AmberSignerService({MethodChannel channel = _defaultChannel})
      : _channel = channel;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Whether Amber is installed on this device.
  /// Always false on non-Android platforms; never throws.
  Future<bool> isInstalled() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAmberInstalled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> getPublicKey() async {
    final raw = await _invoke('getPublicKeyFromAmber');
    if (raw == null || raw.trim().isEmpty) return null;
    return _normalizePubkey(raw.trim());
  }

  @override
  Future<String> signEvent(String unsignedEventJson) async {
    final signed = await _invoke(
      'signEventWithAmber',
      <String, String>{'event': unsignedEventJson},
    );
    if (signed == null || signed.isEmpty) {
      throw const SignerFailure('Amber returned no signed event');
    }
    return signed;
  }

  @override
  Future<String> nip44Encrypt(
      String plaintext, String recipientPubkeyHex) async {
    final ciphertext = await _invoke(
      'nip44EncryptWithAmber',
      <String, String>{'plaintext': plaintext, 'pubkey': recipientPubkeyHex},
    );
    if (ciphertext == null || ciphertext.isEmpty) {
      throw const SignerFailure('Amber returned no NIP-44 ciphertext');
    }
    return ciphertext;
  }

  @override
  Future<String> nip44Decrypt(String ciphertext, String senderPubkeyHex) async {
    final plaintext = await _invoke(
      'nip44DecryptWithAmber',
      <String, String>{'ciphertext': ciphertext, 'pubkey': senderPubkeyHex},
    );
    if (plaintext == null) {
      throw const SignerFailure('Amber returned no NIP-44 plaintext');
    }
    return plaintext;
  }

  /// Invoke [method] on the Amber channel, mapping platform errors to
  /// the [SignerFailure] hierarchy.
  Future<String?> _invoke(String method, [Map<String, String>? args]) async {
    if (!_isAndroid) {
      throw const SignerUnavailableFailure(
          'Amber (NIP-55) is only available on Android');
    }
    try {
      return await _channel.invokeMethod<String>(method, args);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'AMBER_REJECTED':
        case 'AMBER_CANCELLED':
          throw SignerRejectedFailure(
              e.message ?? 'Request rejected in Amber', e);
        case 'AMBER_NOT_INSTALLED':
          throw SignerUnavailableFailure(
              e.message ?? 'Amber is not installed', e);
        default:
          throw SignerFailure(
              e.message ?? 'Amber request failed (${e.code})', e);
      }
    } on MissingPluginException catch (e) {
      throw SignerUnavailableFailure('Amber channel not available', e);
    }
  }

  static final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Amber may return the public key as 64-char hex or as a NIP-19
  /// `npub1...` string; normalize both to lowercase hex.
  String _normalizePubkey(String raw) {
    if (_hex64.hasMatch(raw)) return raw.toLowerCase();
    if (raw.startsWith('npub1')) {
      try {
        return decodeNpub(raw);
      } on FormatException catch (e) {
        throw SignerFailure('Amber returned an invalid npub: ${e.message}', e);
      }
    }
    throw SignerFailure('Amber returned an unrecognized pubkey format: '
        '${raw.length > 16 ? '${raw.substring(0, 16)}...' : raw}');
  }
}
