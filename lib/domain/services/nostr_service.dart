import '../entities/app_settings.dart';
import '../entities/daily_wellness.dart';
import '../entities/weight_entry.dart';

class PublishResult {
  final String eventId;
  final int successfulRelays;
  final int failedRelays;
  const PublishResult({
    required this.eventId,
    required this.successfulRelays,
    required this.failedRelays,
  });

  bool get success => successfulRelays > 0;
}

enum RelayState { disconnected, connecting, connected }

class RelayStatus {
  final String url;
  final RelayState state;
  const RelayStatus(this.url, this.state);
}

/// High-level Nostr operations (NIP-101h health events).
/// Backed by the Rust core (nostr-sdk) over FFI.
/// Implementations throw [NostrFailure] subtypes.
abstract interface class NostrService {
  /// (Re)initialize the relay client for [settings]
  /// (relays, Tor/proxy mode, signer mode).
  Future<void> initialize(AppSettings settings);

  Future<List<RelayStatus>> relayStatuses();

  /// Publish one measurement as NIP-101h event(s).
  /// When [encrypt] is true the content is NIP-44 self-encrypted.
  Future<PublishResult> publishEntry(
    WeightEntry entry, {
    required bool encrypt,
  });

  /// Fetch our own NIP-101h weight events since [since]
  /// (decrypting when needed) for restore/sync.
  Future<List<WeightEntry>> fetchOwnEntries({DateTime? since});

  /// Publish one wellness day as a NIP-44 encrypted kind-30078 event
  /// (`d` = `hakari:wellness:<yyyy-MM-dd>`, replaceable per day).
  Future<PublishResult> publishWellnessDay(DailyWellness day);

  /// Fetch our own wellness backup events for restore/sync.
  Future<List<DailyWellness>> fetchOwnWellness({DateTime? since});

  Future<void> dispose();
}
