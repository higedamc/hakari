import 'dart:convert';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/daily_wellness.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/nostr_service.dart';
import '../../domain/services/signer_service.dart';
import '../../bridge_generated/api.dart' as bridge;
import '../../bridge_generated/frb_generated.dart';
import 'nip101h_codec.dart';
import 'nsec_store.dart';

/// [NostrService] backed by the Rust core (nostr-sdk over
/// flutter_rust_bridge). Handles both signer modes:
/// - localKey: Rust holds the nsec and signs/encrypts natively.
/// - amber: events are built unsigned in Rust, encrypted & signed through
///   [SignerService] (NIP-55), then published as pre-signed JSON.
class RustNostrService implements NostrService {
  final SignerService _signer;
  final NsecStore _nsecStore;

  AppSettings? _settings;
  bool _clientReady = false;

  RustNostrService({
    required SignerService signer,
    required NsecStore nsecStore,
  }) : _signer = signer,
       _nsecStore = nsecStore;

  /// Load the native library. Call once from main() before any other
  /// method of this class (and before LocalKeySignerService is used).
  static Future<void> initRustLib() => RustLib.init();

  // ---------------------------------------------------------------------
  // Local key lifecycle (SignerMode.localKey)
  // ---------------------------------------------------------------------

  /// Generate a fresh keypair, persist the nsec, return the key material
  /// (caller should store pubkeyHex into AppSettings and re-initialize).
  Future<bridge.KeyBundle> loginWithNewKey() async {
    final bundle = await bridge.generateKeys();
    await _nsecStore.save(bundle.nsec);
    return bundle;
  }

  /// Validate + persist an existing secret key (nsec1... or hex).
  Future<bridge.KeyBundle> loginWithNsec(String nsecOrHex) async {
    final bridge.KeyBundle bundle;
    try {
      bundle = await bridge.deriveKeys(nsecOrHex: nsecOrHex.trim());
    } catch (e) {
      throw SignerFailure('Invalid secret key (expected nsec1... or hex)', e);
    }
    await _nsecStore.save(bundle.nsec);
    return bundle;
  }

  /// Forget the stored local key and drop the relay client.
  Future<void> logout() async {
    await _nsecStore.clear();
    await dispose();
  }

  /// The stored nsec, if any (used by LocalKeySignerService via NsecStore).
  Future<String?> currentNsec() => _nsecStore.read();

  // ---------------------------------------------------------------------
  // NostrService
  // ---------------------------------------------------------------------

  @override
  Future<void> initialize(AppSettings settings) async {
    _settings = settings;
    _clientReady = false;

    final bridge.ClientMode mode;
    switch (settings.signerMode) {
      case SignerMode.none:
        // Logged out: nothing to connect as. Leave the client down.
        return;
      case SignerMode.localKey:
        final nsec = await _nsecStore.read();
        if (nsec == null || nsec.isEmpty) {
          throw const NostrFailure(
            'Local key mode selected but no key is stored. '
            'Log in with an nsec first.',
          );
        }
        mode = bridge.ClientMode(
          kind: bridge.ClientModeKind.secretKey,
          nsec: nsec,
        );
      case SignerMode.amber:
        final pubkey = settings.pubkeyHex ?? await _signer.getPublicKey();
        if (pubkey == null || pubkey.isEmpty) {
          throw const NostrFailure(
            'Amber mode selected but no public key is available.',
          );
        }
        mode = bridge.ClientMode(
          kind: bridge.ClientModeKind.publicKeyOnly,
          pubkeyHex: pubkey,
        );
    }

    final tor = settings.torMode == TorMode.orbot
        ? bridge.TorModeFfi(
            kind: bridge.TorModeKind.orbot,
            proxyUrl: settings.proxyUrl,
          )
        : const bridge.TorModeFfi(kind: bridge.TorModeKind.disabled);

    try {
      await bridge.initClient(mode: mode, relays: settings.relays, tor: tor);
      _clientReady = true;
    } catch (e) {
      throw _mapError(e, connecting: true);
    }
  }

  @override
  Future<List<RelayStatus>> relayStatuses() async {
    if (!_clientReady) return const [];
    try {
      final statuses = await bridge.relayStatuses();
      return statuses
          .map((s) => RelayStatus(s.url, _mapRelayState(s.state)))
          .toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<PublishResult> publishEntry(
    WeightEntry entry, {
    required bool encrypt,
  }) async {
    final settings = _requireSettings();
    if (!_clientReady) {
      throw const NostrFailure('Nostr client not initialized');
    }

    if (settings.signerMode == SignerMode.localKey) {
      try {
        final result = await bridge.publishWeightEntry(
          entry: _toFfi(entry),
          encrypt: encrypt,
        );
        return PublishResult(
          eventId: result.eventId,
          successfulRelays: result.successfulRelays,
          failedRelays: result.failedRelays,
        );
      } catch (e) {
        throw _mapError(e);
      }
    }

    // Amber mode: encrypt via signer, build unsigned in Rust, sign via
    // signer, publish pre-signed.
    final ownPubkey = settings.pubkeyHex ?? await _signer.getPublicKey();
    if (ownPubkey == null) {
      throw const NostrFailure('No public key available for publishing');
    }

    String? contentOverride;
    if (encrypt) {
      contentOverride = await _signer.nip44Encrypt(
        weightContent(entry.weightKg),
        ownPubkey,
      );
    }
    final ffiEntry = _toFfi(entry);
    final String signed1351;
    final String signed30078;
    try {
      final unsigned1351 = await bridge.buildUnsignedWeightEvent(
        entry: ffiEntry,
        pubkeyHex: ownPubkey,
        contentOverride: contentOverride,
        encrypted: encrypt,
      );
      signed1351 = await _signer.signEvent(unsigned1351);

      final weightEventId =
          (jsonDecode(signed1351) as Map<String, dynamic>)['id'] as String?;
      final backupCipher = await _signer.nip44Encrypt(
        backupPlaintext(entry, weightEventId: weightEventId),
        ownPubkey,
      );
      final unsigned30078 = await bridge.buildUnsignedBackupEvent(
        entry: ffiEntry,
        pubkeyHex: ownPubkey,
        encryptedContent: backupCipher,
      );
      signed30078 = await _signer.signEvent(unsigned30078);
    } on Failure {
      rethrow;
    } catch (e) {
      throw NostrFailure('Failed to build/sign health events', e);
    }

    try {
      final result = await bridge.publishSignedEvent(eventJson: signed1351);
      // Backup publish failure must not mask a successful 1351 publish.
      try {
        await bridge.publishSignedEvent(eventJson: signed30078);
      } catch (_) {
        // Best-effort: the next publish/sync can recreate the backup.
      }
      return PublishResult(
        eventId: result.eventId,
        successfulRelays: result.successfulRelays,
        failedRelays: result.failedRelays,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<PublishResult> publishWellnessDay(DailyWellness day) async {
    _requireSettings();
    if (!_clientReady) {
      throw const NostrFailure('Nostr client not initialized');
    }
    final ownPubkey =
        _requireSettings().pubkeyHex ?? await _signer.getPublicKey();
    if (ownPubkey == null) {
      throw const NostrFailure('No public key available for publishing');
    }
    // Same path for both signer modes: LocalKeySignerService performs
    // these ops in-process, Amber via the silent/foreground flow.
    final cipher = await _signer.nip44Encrypt(
      wellnessPlaintext(day),
      ownPubkey,
    );
    final String unsigned;
    try {
      unsigned = await bridge.buildUnsignedWellnessEvent(
        pubkeyHex: ownPubkey,
        dayKey: day.dayKey,
        encryptedContent: cipher,
      );
    } catch (e) {
      throw _mapError(e);
    }
    final signed = await _signer.signEvent(unsigned);
    try {
      final eventId =
          (jsonDecode(signed) as Map<String, dynamic>)['id'] as String? ?? '';
      final result = await bridge.publishSignedEvent(eventJson: signed);
      return PublishResult(
        eventId: eventId,
        successfulRelays: result.successfulRelays,
        failedRelays: result.failedRelays,
      );
    } on Failure {
      rethrow;
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<DailyWellness>> fetchOwnWellness({DateTime? since}) async {
    final settings = _requireSettings();
    if (!_clientReady) {
      throw const NostrFailure('Nostr client not initialized');
    }
    final ownPubkey = settings.pubkeyHex ?? await _signer.getPublicKey();
    if (ownPubkey == null) {
      throw const NostrFailure('No public key available for fetching');
    }
    final List<bridge.RawEventFfi> events;
    try {
      events = await bridge.fetchHealthEvents(
        pubkeyHex: ownPubkey,
        sinceUnix: since == null ? null : since.millisecondsSinceEpoch ~/ 1000,
      );
    } catch (e) {
      throw _mapError(e);
    }

    final days = <DailyWellness>[];
    final seenEventIds = <String>{};
    final seenDays = <String>{};
    for (final event in events.where(
      (e) => e.kind == backupEventKind && isWellnessEvent(e.tags),
    )) {
      if (!seenEventIds.add(event.id)) continue;
      try {
        final plain = await _signer.nip44Decrypt(event.content, ownPubkey);
        final day = wellnessFromBackupMap(
          jsonDecode(plain) as Map<String, dynamic>,
          backupEventId: event.id,
        );
        // Replaceable events: relays should keep only the newest per d
        // tag, but a hostile/lagging relay may return several — events
        // arrive newest-first, keep the first per day.
        if (day != null && seenDays.add(day.dayKey)) days.add(day);
      } catch (_) {
        // Undecryptable / malformed: skip rather than failing the sync.
      }
    }
    return days;
  }

  @override
  Future<List<WeightEntry>> fetchOwnEntries({DateTime? since}) async {
    final settings = _requireSettings();
    if (!_clientReady) {
      throw const NostrFailure('Nostr client not initialized');
    }
    final ownPubkey = settings.pubkeyHex ?? await _signer.getPublicKey();
    if (ownPubkey == null) {
      throw const NostrFailure('No public key available for fetching');
    }

    final List<bridge.RawEventFfi> events;
    try {
      events = await bridge.fetchHealthEvents(
        pubkeyHex: ownPubkey,
        sinceUnix: since == null ? null : since.millisecondsSinceEpoch ~/ 1000,
      );
    } catch (e) {
      throw _mapError(e);
    }

    final entries = <WeightEntry>[];
    // 1351 ids already covered by a full-entry backup (deduped below).
    final referencedWeightEventIds = <String>{};
    // A hostile relay can replay the same (validly signed) event many
    // times; each decrypt is a signer round-trip (a full Amber prompt in
    // intent mode), so drop duplicates by event id before decrypting.
    final seenEventIds = <String>{};

    // Wellness backups are handled by fetchOwnWellness; skipping them
    // here avoids one signer decrypt round-trip per wellness day.
    for (final event in events.where(
      (e) => e.kind == backupEventKind && !isWellnessEvent(e.tags),
    )) {
      if (!seenEventIds.add(event.id)) continue;
      try {
        final plain = await _signer.nip44Decrypt(event.content, ownPubkey);
        final map = jsonDecode(plain) as Map<String, dynamic>;
        final weightEventId = weightEventIdOfBackup(map);
        if (weightEventId != null) {
          referencedWeightEventIds.add(weightEventId);
        }
        entries.add(entryFromBackupMap(map, backupEventId: event.id));
      } catch (_) {
        // Undecryptable / malformed backup (e.g. from another device with
        // different keys): skip rather than failing the whole sync.
      }
    }

    for (final event in events.where((e) => e.kind == weightEventKind)) {
      if (!seenEventIds.add(event.id)) continue;
      if (referencedWeightEventIds.contains(event.id)) continue;
      try {
        var content = event.content;
        if (isEncryptedWeightEvent(event.tags)) {
          content = await _signer.nip44Decrypt(content, ownPubkey);
        }
        final entry = entryFromWeightEvent(
          eventId: event.id,
          createdAtUnix: event.createdAt,
          content: content,
          tags: event.tags,
        );
        if (entry != null) entries.add(entry);
      } catch (_) {
        // Skip events we cannot decrypt/parse.
      }
    }

    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return entries;
  }

  @override
  Future<void> dispose() async {
    _clientReady = false;
    try {
      await bridge.disposeClient();
    } catch (_) {
      // Already gone — nothing to clean up.
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  AppSettings _requireSettings() {
    final settings = _settings;
    if (settings == null) {
      throw const NostrFailure(
        'NostrService.initialize(settings) must be called first',
      );
    }
    return settings;
  }

  bridge.FfiWeightEntry _toFfi(WeightEntry entry) => bridge.FfiWeightEntry(
    id: entry.id,
    recordedAtUnix: entry.recordedAt.millisecondsSinceEpoch ~/ 1000,
    weightKg: entry.weightKg,
    bodyFatPercent: entry.bodyFatPercent,
    bodyWaterPercent: entry.bodyWaterPercent,
    muscleMassKg: entry.muscleMassKg,
    visceralFatRating: entry.visceralFatRating,
    boneMassKg: entry.boneMassKg,
    basalMetabolicRateKcal: entry.basalMetabolicRateKcal,
    metabolicAge: entry.metabolicAge,
    source: entry.source.name,
  );

  RelayState _mapRelayState(String state) => switch (state) {
    'connected' => RelayState.connected,
    'connecting' || 'pending' || 'initialized' => RelayState.connecting,
    _ => RelayState.disconnected,
  };

  NostrFailure _mapError(Object e, {bool connecting = false}) {
    if (e is NostrFailure) return e;
    final message = e.toString();
    final lower = message.toLowerCase();
    final orbot = _settings?.torMode == TorMode.orbot;
    if (lower.contains('proxy') || (orbot && connecting)) {
      return TorFailure(
        'Tor/Orbot connection failed. Is Orbot running with its SOCKS5 '
        'proxy enabled?',
        e,
      );
    }
    if (lower.contains('relay') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connect') ||
        lower.contains('send event')) {
      return RelayFailure(message, e);
    }
    return NostrFailure(message, e);
  }
}
