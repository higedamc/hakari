/// Event signing contract (NIP-55 Amber, or local key via Rust).
/// Implementations throw [SignerFailure] subtypes.
abstract interface class SignerService {
  /// Hex pubkey of the active identity, or null when logged out.
  Future<String?> getPublicKey();

  /// Sign an unsigned nostr event (JSON string, NIP-01 shape with
  /// pubkey/created_at/kind/tags/content). Returns the full signed
  /// event JSON.
  Future<String> signEvent(String unsignedEventJson);

  /// NIP-44 encrypt [plaintext] to [recipientPubkeyHex]
  /// (self-encryption when it equals our own pubkey).
  Future<String> nip44Encrypt(String plaintext, String recipientPubkeyHex);

  /// NIP-44 decrypt [ciphertext] from [senderPubkeyHex].
  Future<String> nip44Decrypt(String ciphertext, String senderPubkeyHex);
}
