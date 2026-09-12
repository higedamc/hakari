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

  /// First-run onboarding has been finished (logged in or skipped).
  final bool onboardingComplete;

  /// Body height in centimetres, for BMI. Entered by the user or adopted
  /// from a Health Planet sync when no manual value exists. `null` when
  /// unknown.
  final double? heightCm;

  /// Target body weight in kilograms, entered by the user. Health Planet
  /// does not expose the goal set on its site, so there is no sync path.
  /// `null` when no goal is set.
  final double? goalWeightKg;

  const AppSettings({
    this.relays = defaultRelays,
    this.torMode = TorMode.disabled,
    this.proxyUrl = 'socks5://127.0.0.1:9050',
    this.signerMode = SignerMode.none,
    this.pubkeyHex,
    this.encryptHealthEvents = true,
    this.autoSyncToHealth = false,
    this.autoPublishToNostr = false,
    this.onboardingComplete = false,
    this.heightCm,
    this.goalWeightKg,
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
    bool? onboardingComplete,
    double? heightCm,
    bool clearHeightCm = false,
    double? goalWeightKg,
    bool clearGoalWeightKg = false,
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
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      heightCm: clearHeightCm ? null : (heightCm ?? this.heightCm),
      goalWeightKg: clearGoalWeightKg
          ? null
          : (goalWeightKg ?? this.goalWeightKg),
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
    'onboardingComplete': onboardingComplete,
    'heightCm': heightCm,
    'goalWeightKg': goalWeightKg,
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
    onboardingComplete: (map['onboardingComplete'] as bool?) ?? false,
    heightCm: _finiteOrNull(map['heightCm']),
    goalWeightKg: _finiteOrNull(map['goalWeightKg']),
  );

  /// Persisted numbers come back as `int` or `double` (Hive keeps the
  /// original type); anything else, or a non-finite value, reads as unset.
  static double? _finiteOrNull(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
}
