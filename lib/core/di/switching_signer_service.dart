import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/services/signer_service.dart';

/// Delegates signing to the local-key signer or Amber based on the
/// current [AppSettings.signerMode]. While logged out it delegates to
/// Amber, so the settings screen's "Login with Amber" flow works before
/// a mode is persisted.
class SwitchingSignerService implements SignerService {
  final SettingsRepository _settingsRepository;
  final SignerService _localSigner;
  final SignerService _amberSigner;

  SwitchingSignerService(
    this._settingsRepository, {
    required SignerService localSigner,
    required SignerService amberSigner,
  }) : _localSigner = localSigner,
       _amberSigner = amberSigner;

  Future<SignerService> get _active async {
    final settings = await _settingsRepository.load();
    return settings.signerMode == SignerMode.localKey
        ? _localSigner
        : _amberSigner;
  }

  @override
  Future<String?> getPublicKey() async => (await _active).getPublicKey();

  @override
  Future<String> signEvent(String unsignedEventJson) async =>
      (await _active).signEvent(unsignedEventJson);

  @override
  Future<String> nip44Encrypt(
    String plaintext,
    String recipientPubkeyHex,
  ) async => (await _active).nip44Encrypt(plaintext, recipientPubkeyHex);

  @override
  Future<String> nip44Decrypt(
    String ciphertext,
    String senderPubkeyHex,
  ) async => (await _active).nip44Decrypt(ciphertext, senderPubkeyHex);
}
