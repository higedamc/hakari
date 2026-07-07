/// Tor routing mode, mirroring meiso's TorMode.
/// [orbot] routes relay websockets through a local SOCKS5 proxy
/// (Orbot default: socks5://127.0.0.1:9050).
enum TorMode { disabled, orbot }

/// How events get signed.
enum SignerMode { none, localKey, amber }

class AppSettings {
  final List<String> relays;
  final TorMode torMode;
  final String proxyUrl;
  final SignerMode signerMode;

  /// Hex public key of the logged-in user (from nsec or Amber).
  final String? pubkeyHex;

  /// Encrypt health events with NIP-44 (self-encrypted) before publishing.
  final bool encryptHealthEvents;

  /// Auto-write new entries to Health Connect / HealthKit.
  final bool autoSyncToHealth;

  /// Auto-publish new entries to Nostr relays.
  final bool autoPublishToNostr;

  final bool useMetricUnits;

  /// First-run onboarding has been finished (logged in or skipped).
  final bool onboardingComplete;

  const AppSettings({
    this.relays = defaultRelays,
    this.torMode = TorMode.disabled,
    this.proxyUrl = 'socks5://127.0.0.1:9050',
    this.signerMode = SignerMode.none,
    this.pubkeyHex,
    this.encryptHealthEvents = true,
    this.autoSyncToHealth = false,
    this.autoPublishToNostr = false,
    this.useMetricUnits = true,
    this.onboardingComplete = false,
  });

  static const defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
  ];

  AppSettings copyWith({
    List<String>? relays,
    TorMode? torMode,
    String? proxyUrl,
    SignerMode? signerMode,
    String? pubkeyHex,
    bool clearPubkey = false,
    bool? encryptHealthEvents,
    bool? autoSyncToHealth,
    bool? autoPublishToNostr,
    bool? useMetricUnits,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      relays: relays ?? this.relays,
      torMode: torMode ?? this.torMode,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      signerMode: signerMode ?? this.signerMode,
      pubkeyHex: clearPubkey ? null : (pubkeyHex ?? this.pubkeyHex),
      encryptHealthEvents: encryptHealthEvents ?? this.encryptHealthEvents,
      autoSyncToHealth: autoSyncToHealth ?? this.autoSyncToHealth,
      autoPublishToNostr: autoPublishToNostr ?? this.autoPublishToNostr,
      useMetricUnits: useMetricUnits ?? this.useMetricUnits,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  Map<String, dynamic> toMap() => {
    'relays': relays,
    'torMode': torMode.name,
    'proxyUrl': proxyUrl,
    'signerMode': signerMode.name,
    'pubkeyHex': pubkeyHex,
    'encryptHealthEvents': encryptHealthEvents,
    'autoSyncToHealth': autoSyncToHealth,
    'autoPublishToNostr': autoPublishToNostr,
    'useMetricUnits': useMetricUnits,
    'onboardingComplete': onboardingComplete,
  };

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) => AppSettings(
    relays: (map['relays'] as List?)?.cast<String>() ?? defaultRelays,
    torMode: TorMode.values.firstWhere(
      (t) => t.name == map['torMode'],
      orElse: () => TorMode.disabled,
    ),
    proxyUrl: (map['proxyUrl'] as String?) ?? 'socks5://127.0.0.1:9050',
    signerMode: SignerMode.values.firstWhere(
      (s) => s.name == map['signerMode'],
      orElse: () => SignerMode.none,
    ),
    pubkeyHex: map['pubkeyHex'] as String?,
    encryptHealthEvents: (map['encryptHealthEvents'] as bool?) ?? true,
    autoSyncToHealth: (map['autoSyncToHealth'] as bool?) ?? false,
    autoPublishToNostr: (map['autoPublishToNostr'] as bool?) ?? false,
    useMetricUnits: (map['useMetricUnits'] as bool?) ?? true,
    onboardingComplete: (map['onboardingComplete'] as bool?) ?? false,
  );
}
