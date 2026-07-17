import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../domain/failures/failures.dart';
import '../../domain/services/signer_service.dart';
import 'bech32.dart';

/// [SignerService] backed by the Amber external signer (NIP-55) on Android.
///
/// Every operation first tries Amber's ContentProvider (silent, no app
/// switch — works when the user granted "always approve" for this app in
/// Amber) and falls back to the foreground `startActivityForResult`
/// intent flow when the silent path is unavailable or denied. Both paths
/// are delegated over a [MethodChannel] to `MainActivity.kt`, which pins
/// Amber's package + signing cert.
///
/// Error mapping (PlatformException code -> Failure):
/// - `AMBER_REJECTED` / `AMBER_CANCELLED` -> [SignerRejectedFailure]
/// - `AMBER_NOT_INSTALLED`                -> [SignerUnavailableFailure]
/// - foreground intent timeout            -> [SignerTimeoutFailure]
/// - anything else                        -> [SignerFailure]
class AmberSignerService implements SignerService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'org.lekt.hakari/amber',
  );

  final MethodChannel _channel;

  /// Supplies the logged-in account's pubkey (hex). The ContentProvider
  /// path needs the npub to address the right Amber account; when this
  /// is null / returns null the silent path is skipped entirely.
  final Future<String?> Function()? _pubkeyHexProvider;

  /// How long a foreground Amber intent may stay unanswered before the
  /// call fails with [SignerTimeoutFailure]. A late reply after the
  /// timeout is discarded harmlessly.
  final Duration _foregroundTimeout;

  final bool? _isAndroidOverride;

  /// [channel], [foregroundTimeout] and [isAndroidOverride] are
  /// overridable for tests; production code uses the defaults.
  const AmberSignerService({
    MethodChannel channel = _defaultChannel,
    Future<String?> Function()? pubkeyHexProvider,
    Duration foregroundTimeout = const Duration(seconds: 60),
    bool? isAndroidOverride,
  }) : _channel = channel,
       _pubkeyHexProvider = pubkeyHexProvider,
       _foregroundTimeout = foregroundTimeout,
       _isAndroidOverride = isAndroidOverride;

  bool get _isAndroid => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

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
    // Foreground-only on purpose: this is the one-time login op and the
    // visible prompt doubles as Amber's permission registration.
    final raw = await _invoke(
      'getPublicKeyFromAmber',
      null,
      timeout: _foregroundTimeout,
    );
    if (raw == null || raw.trim().isEmpty) return null;
    return _normalizePubkey(raw.trim());
  }

  @override
  Future<String> signEvent(String unsignedEventJson) {
    return _signerOp(
      cpMethod: 'signEventWithAmberContentProvider',
      fgMethod: 'signEventWithAmber',
      args: <String, String>{'event': unsignedEventJson},
      emptyError: 'Amber returned no signed event',
    );
  }

  @override
  Future<String> nip44Encrypt(String plaintext, String recipientPubkeyHex) {
    return _signerOp(
      cpMethod: 'nip44EncryptWithAmberContentProvider',
      fgMethod: 'nip44EncryptWithAmber',
      args: <String, String>{
        'plaintext': plaintext,
        'pubkey': recipientPubkeyHex,
      },
      emptyError: 'Amber returned no NIP-44 ciphertext',
    );
  }

  @override
  Future<String> nip44Decrypt(String ciphertext, String senderPubkeyHex) {
    return _signerOp(
      cpMethod: 'nip44DecryptWithAmberContentProvider',
      fgMethod: 'nip44DecryptWithAmber',
      args: <String, String>{
        'ciphertext': ciphertext,
        'pubkey': senderPubkeyHex,
      },
      emptyError: 'Amber returned no NIP-44 plaintext',
    );
  }

  /// ContentProvider first (silent), foreground intent as fallback.
  ///
  /// Any failure on the silent path — no "always approve" grant
  /// (surfaces as AMBER_ERROR "No response..." or AMBER_REJECTED), old
  /// Amber without the provider, npub/account mismatch — falls through
  /// to the visible flow, so behavior is never worse than before.
  Future<String> _signerOp({
    required String cpMethod,
    required String fgMethod,
    required Map<String, String> args,
    required String emptyError,
  }) async {
    final npub = await _npub();
    if (npub != null) {
      try {
        final silent = await _invoke(cpMethod, {...args, 'npub': npub});
        if (silent != null && silent.isNotEmpty) return silent;
      } on SignerUnavailableFailure {
        rethrow; // not installed / non-Android: fallback would fail too
      } on SignerFailure {
        // Fall back to the foreground intent flow.
      }
    }
    final visible = await _invoke(fgMethod, args, timeout: _foregroundTimeout);
    if (visible == null || visible.isEmpty) {
      throw SignerFailure(emptyError);
    }
    return visible;
  }

  Future<String?> _npub() async {
    final hex = await _pubkeyHexProvider?.call();
    if (hex == null || hex.isEmpty) return null;
    try {
      return encodeNpub(hex);
    } on FormatException {
      return null;
    }
  }

  /// Invoke [method] on the Amber channel, mapping platform errors to
  /// the [SignerFailure] hierarchy. [timeout] applies to foreground
  /// intent calls only; ContentProvider queries return promptly.
  Future<String?> _invoke(
    String method,
    Map<String, String>? args, {
    Duration? timeout,
  }) async {
    if (!_isAndroid) {
      throw const SignerUnavailableFailure(
        'Amber (NIP-55) is only available on Android',
      );
    }
    try {
      var future = _channel.invokeMethod<String>(method, args);
      if (timeout != null) {
        future = future.timeout(
          timeout,
          onTimeout: () => throw SignerTimeoutFailure(
            'Amber did not respond within ${timeout.inSeconds}s',
          ),
        );
      }
      return await future;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'AMBER_REJECTED':
        case 'AMBER_CANCELLED':
          throw SignerRejectedFailure(
            e.message ?? 'Request rejected in Amber',
            e,
          );
        case 'AMBER_NOT_INSTALLED':
          throw SignerUnavailableFailure(
            e.message ?? 'Amber is not installed',
            e,
          );
        default:
          throw SignerFailure(
            e.message ?? 'Amber request failed (${e.code})',
            e,
          );
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
    throw SignerFailure(
      'Amber returned an unrecognized pubkey format: '
      '${raw.length > 16 ? '${raw.substring(0, 16)}...' : raw}',
    );
  }
}
