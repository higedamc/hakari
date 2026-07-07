import '../../domain/failures/failures.dart';
import '../../domain/services/signer_service.dart';
import '../../bridge_generated/api.dart' as bridge;
import 'nsec_store.dart';

/// [SignerService] backed by a locally stored secret key; all crypto is
/// delegated to the Rust core (nostr-sdk) over FFI.
class LocalKeySignerService implements SignerService {
  final NsecStore _store;

  /// Cached pubkey for the current nsec (invalidated when the key changes).
  String? _cachedNsec;
  String? _cachedPubkeyHex;

  LocalKeySignerService(this._store);

  Future<String?> _nsec() => _store.read();

  Future<String> _requireNsec() async {
    final nsec = await _nsec();
    if (nsec == null || nsec.isEmpty) {
      throw const SignerUnavailableFailure(
        'No local key stored. Log in with an nsec or generate a new key.',
      );
    }
    return nsec;
  }

  @override
  Future<String?> getPublicKey() async {
    final nsec = await _nsec();
    if (nsec == null || nsec.isEmpty) return null;
    if (nsec == _cachedNsec && _cachedPubkeyHex != null) {
      return _cachedPubkeyHex;
    }
    try {
      final bundle = await bridge.deriveKeys(nsecOrHex: nsec);
      _cachedNsec = nsec;
      _cachedPubkeyHex = bundle.pubkeyHex;
      return bundle.pubkeyHex;
    } catch (e) {
      throw SignerFailure('Failed to derive public key from stored key', e);
    }
  }

  @override
  Future<String> signEvent(String unsignedEventJson) async {
    final nsec = await _requireNsec();
    try {
      return await bridge.signEventLocal(
        nsec: nsec,
        unsignedEventJson: unsignedEventJson,
      );
    } catch (e) {
      throw SignerFailure('Failed to sign event with local key', e);
    }
  }

  @override
  Future<String> nip44Encrypt(String plaintext, String recipientPubkeyHex) async {
    final nsec = await _requireNsec();
    try {
      return await bridge.nip44EncryptLocal(
        nsec: nsec,
        receiverPubkeyHex: recipientPubkeyHex,
        plaintext: plaintext,
      );
    } catch (e) {
      throw SignerFailure('NIP-44 encryption failed', e);
    }
  }

  @override
  Future<String> nip44Decrypt(String ciphertext, String senderPubkeyHex) async {
    final nsec = await _requireNsec();
    try {
      return await bridge.nip44DecryptLocal(
        nsec: nsec,
        senderPubkeyHex: senderPubkeyHex,
        ciphertext: ciphertext,
      );
    } catch (e) {
      throw SignerFailure('NIP-44 decryption failed', e);
    }
  }
}
