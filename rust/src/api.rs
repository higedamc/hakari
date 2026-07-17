//! FFI surface for the hakari Nostr core (NIP-101h health events).
//!
//! All functions are synchronous from the FFI point of view and internally
//! block on a shared Tokio runtime (flutter_rust_bridge runs them on a
//! worker thread pool, so Dart callers still get non-blocking Futures).

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use nostr_sdk::nips::nip44;
use nostr_sdk::prelude::*;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

// ========================================
// Constants (NIP-101h)
// ========================================

/// NIP-101h weight event kind.
pub const KIND_WEIGHT: u16 = 1351;
/// NIP-78 addressable event kind used for full-entry backups.
pub const KIND_BACKUP: u16 = 30078;
/// `d` tag prefix for backup events: `hakari:entry:<entry_id>`.
pub const BACKUP_D_PREFIX: &str = "hakari:entry:";
/// `t` tag used to find our backup events.
pub const BACKUP_HASHTAG: &str = "hakari-health";

/// `d` tag prefix for daily wellness (sleep / active energy) backups.
pub const WELLNESS_D_PREFIX: &str = "hakari:wellness:";

// ========================================
// Globals
// ========================================

static TOKIO_RUNTIME: Lazy<tokio::runtime::Runtime> =
    Lazy::new(|| tokio::runtime::Runtime::new().expect("Failed to create Tokio runtime"));

static NOSTR_CLIENT: Lazy<Arc<tokio::sync::Mutex<Option<HakariClient>>>> =
    Lazy::new(|| Arc::new(tokio::sync::Mutex::new(None)));

/// Internal client wrapper stored in the global slot.
struct HakariClient {
    client: Client,
    /// `None` in `PublicKeyOnly` (Amber) mode — Rust never sees the secret.
    keys: Option<Keys>,
    /// Identity this client was initialized for; publish paths must not
    /// accept events signed by anyone else.
    public_key: PublicKey,
    /// Send timeout (longer when routing through Orbot).
    send_timeout: Duration,
}

// ========================================
// FFI types
// ========================================

/// Key material derived from / for a secret key.
#[derive(Clone)]
pub struct KeyBundle {
    pub nsec: String,
    pub npub: String,
    pub pubkey_hex: String,
}

// Manual Debug: a stray `{:?}` log line must never print the nsec.
// (Drop-based zeroization is NOT possible here: flutter_rust_bridge's
// generated code moves fields out of these structs, which Rust forbids
// for Drop types. The nsec inevitably crosses the FFI boundary as a
// plain String either way — a known, documented residual.)
impl std::fmt::Debug for KeyBundle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("KeyBundle")
            .field("nsec", &"<redacted>")
            .field("npub", &self.npub)
            .field("pubkey_hex", &self.pubkey_hex)
            .finish()
    }
}

/// How the client is allowed to operate.
/// (Unit enum + config struct instead of an enum with fields so the
/// generated Dart code does not require the freezed package.)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClientModeKind {
    /// Local-key mode: Rust holds the secret and can sign/encrypt.
    SecretKey,
    /// Amber mode: signing/encryption happen in the external signer app;
    /// Rust only knows the public key.
    PublicKeyOnly,
}

#[derive(Clone)]
pub struct ClientMode {
    pub kind: ClientModeKind,
    /// Required when [kind] is SecretKey (nsec1... bech32 or hex).
    pub nsec: Option<String>,
    /// Required when [kind] is PublicKeyOnly.
    pub pubkey_hex: Option<String>,
}

// Manual Debug: never print the nsec (see KeyBundle for why there is
// no Drop-based zeroization).
impl std::fmt::Debug for ClientMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ClientMode")
            .field("kind", &self.kind)
            .field("nsec", &self.nsec.as_ref().map(|_| "<redacted>"))
            .field("pubkey_hex", &self.pubkey_hex)
            .finish()
    }
}

/// Tor routing mode. Orbot = SOCKS5 proxy (e.g. socks5://127.0.0.1:9050).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TorModeKind {
    Disabled,
    Orbot,
}

#[derive(Debug, Clone)]
pub struct TorModeFfi {
    pub kind: TorModeKind,
    /// Required when [kind] is Orbot.
    pub proxy_url: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RelayStatusFfi {
    pub url: String,
    /// One of: initialized, pending, connecting, connected, disconnected, terminated
    pub state: String,
}

/// Result of publishing an event.
#[derive(Debug, Clone)]
pub struct SendResultFfi {
    /// For `publish_weight_entry` this is the kind-1351 event id (hex).
    pub event_id: String,
    pub successful_relays: u32,
    pub failed_relays: u32,
}

/// Raw relay event handed to Dart (decryption happens Dart-side via
/// SignerService so it works in both local-key and Amber modes).
#[derive(Debug, Clone)]
pub struct RawEventFfi {
    pub id: String,
    pub kind: u16,
    pub created_at: i64,
    pub content: String,
    pub tags: Vec<Vec<String>>,
}

/// Measurement payload coming from Dart (mirrors domain WeightEntry).
#[derive(Debug, Clone)]
pub struct FfiWeightEntry {
    pub id: String,
    /// Unix seconds of the measurement.
    pub recorded_at_unix: i64,
    pub weight_kg: f64,
    pub body_fat_percent: Option<f64>,
    pub body_water_percent: Option<f64>,
    pub muscle_mass_kg: Option<f64>,
    pub visceral_fat_rating: Option<i32>,
    pub bone_mass_kg: Option<f64>,
    pub basal_metabolic_rate_kcal: Option<i32>,
    pub metabolic_age: Option<i32>,
    /// Dart MeasurementSource enum name: manual | bleScale | healthSync | imported
    pub source: String,
}

/// JSON shape of the (NIP-44 encrypted) kind-30078 backup content.
/// Field names are a wire contract shared with the Dart codec
/// (lib/data/nostr/nip101h_codec.dart) — do not rename.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct BackupEntryJson {
    id: String,
    recorded_at: i64,
    weight_kg: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    body_fat_percent: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    body_water_percent: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    muscle_mass_kg: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    visceral_fat_rating: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bone_mass_kg: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    basal_metabolic_rate_kcal: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    metabolic_age: Option<i32>,
    source: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    weight_event_id: Option<String>,
}

// ========================================
// Key operations
// ========================================

/// Generate a brand-new keypair.
pub fn generate_keys() -> Result<KeyBundle> {
    let keys = Keys::generate();
    bundle_from_keys(&keys)
}

/// Derive key material from an existing secret (nsec1... bech32 or 64-char hex).
pub fn derive_keys(nsec_or_hex: String) -> Result<KeyBundle> {
    let keys = Keys::parse(&nsec_or_hex)
        .map_err(|e| anyhow!("Invalid secret key (expected nsec1... or hex): {e}"))?;
    bundle_from_keys(&keys)
}

fn bundle_from_keys(keys: &Keys) -> Result<KeyBundle> {
    Ok(KeyBundle {
        nsec: keys
            .secret_key()
            .to_bech32()
            .context("Failed to encode nsec")?,
        npub: keys
            .public_key()
            .to_bech32()
            .context("Failed to encode npub")?,
        pubkey_hex: keys.public_key().to_hex(),
    })
}

// ========================================
// Client lifecycle
// ========================================

/// Parse a SOCKS proxy URL like "socks5://127.0.0.1:9050" (scheme optional)
/// into a socket address.
fn parse_proxy_url(proxy_url: &str) -> Result<SocketAddr> {
    let trimmed = proxy_url.trim();
    // The nostr-sdk Connection proxy speaks SOCKS5 only — accepting
    // socks4:// here would silently mislabel the actual protocol used.
    if let Some(scheme_end) = trimmed.find("://") {
        let scheme = &trimmed[..scheme_end];
        if scheme != "socks5" && scheme != "socks5h" {
            return Err(anyhow!(
                "Unsupported proxy scheme '{scheme}': only socks5:// / socks5h:// are supported"
            ));
        }
    }
    let without_scheme = trimmed
        .strip_prefix("socks5h://")
        .or_else(|| trimmed.strip_prefix("socks5://"))
        .unwrap_or(trimmed)
        .trim_end_matches('/');
    without_scheme
        .parse::<SocketAddr>()
        .map_err(|e| anyhow!("Invalid proxy URL '{proxy_url}': {e}"))
}

/// (Re)initialize the global Nostr client. Disconnects and replaces any
/// existing client. Returns the hex public key of the active identity.
pub fn init_client(mode: ClientMode, relays: Vec<String>, tor: TorModeFfi) -> Result<String> {
    TOKIO_RUNTIME.block_on(async {
        // Drop + disconnect any previous client first.
        {
            let mut guard = NOSTR_CLIENT.lock().await;
            if let Some(old) = guard.take() {
                let _ = old.client.disconnect().await;
            }
        }

        let (keys, public_key) = match mode.kind {
            ClientModeKind::SecretKey => {
                let nsec = mode
                    .nsec
                    .as_deref()
                    .ok_or_else(|| anyhow!("nsec is required in SecretKey mode"))?;
                let keys = Keys::parse(nsec)
                    .map_err(|e| anyhow!("Invalid secret key (nsec1... or hex): {e}"))?;
                let pk = keys.public_key();
                (Some(keys), pk)
            }
            ClientModeKind::PublicKeyOnly => {
                let pubkey_hex = mode
                    .pubkey_hex
                    .as_deref()
                    .ok_or_else(|| anyhow!("pubkey_hex is required in PublicKeyOnly mode"))?;
                let pk = PublicKey::parse(pubkey_hex)
                    .map_err(|e| anyhow!("Invalid public key '{pubkey_hex}': {e}"))?;
                (None, pk)
            }
        };

        // Build connection options (Orbot -> SOCKS5 proxy for ALL relays).
        let opts = match tor.kind {
            TorModeKind::Disabled => Options::new(),
            TorModeKind::Orbot => {
                let proxy_url = tor
                    .proxy_url
                    .as_deref()
                    .ok_or_else(|| anyhow!("proxy_url is required in Orbot mode"))?;
                let addr = parse_proxy_url(proxy_url)?;
                // Note: no env-var fallback (unlike meiso). set_var is
                // thread-unsafe once the Tokio runtime is up, and stale
                // *_proxy vars would keep routing traffic after the user
                // disables Tor. The explicit Connection proxy below covers
                // the only network stack in this crate.
                let connection = Connection::new().proxy(addr).target(ConnectionTarget::All);
                Options::new().connection(connection)
            }
        };

        let client = match &keys {
            Some(k) => Client::builder().signer(k.clone()).opts(opts).build(),
            None => Client::builder().opts(opts).build(),
        };

        for relay_url in &relays {
            if let Err(e) = client.add_relay(relay_url).await {
                eprintln!("hakari_core: failed to add relay {relay_url}: {e}");
            }
        }

        // Tor circuits are slow to establish; give Orbot more headroom.
        let (connect_timeout, send_timeout) = match tor.kind {
            TorModeKind::Disabled => (Duration::from_secs(5), Duration::from_secs(10)),
            TorModeKind::Orbot => (Duration::from_secs(15), Duration::from_secs(20)),
        };

        // connect() resolves when attempts finish; timeout just means we
        // continue in the background (offline-tolerant).
        let _ = tokio::time::timeout(connect_timeout, client.connect()).await;

        let mut guard = NOSTR_CLIENT.lock().await;
        *guard = Some(HakariClient {
            client,
            keys,
            public_key,
            send_timeout,
        });

        Ok(public_key.to_hex())
    })
}

/// Disconnect and drop the global client.
pub fn dispose_client() -> Result<()> {
    TOKIO_RUNTIME.block_on(async {
        let mut guard = NOSTR_CLIENT.lock().await;
        if let Some(old) = guard.take() {
            let _ = old.client.disconnect().await;
        }
        Ok(())
    })
}

/// Per-relay connection states of the current client.
pub fn relay_statuses() -> Result<Vec<RelayStatusFfi>> {
    TOKIO_RUNTIME.block_on(async {
        let guard = NOSTR_CLIENT.lock().await;
        let hc = guard
            .as_ref()
            .ok_or_else(|| anyhow!("Nostr client not initialized"))?;
        let relays = hc.client.relays().await;
        let mut statuses: Vec<RelayStatusFfi> = relays
            .into_iter()
            .map(|(url, relay)| RelayStatusFfi {
                url: url.to_string(),
                state: format!("{:?}", relay.status()).to_lowercase(),
            })
            .collect();
        statuses.sort_by(|a, b| a.url.cmp(&b.url));
        Ok(statuses)
    })
}

// ========================================
// Event building (NIP-101h)
// ========================================

/// Format weight for the 1351 content ("72.5"; integral values keep one
/// decimal, matching Dart's double.toString()).
fn format_weight(weight_kg: f64) -> String {
    if weight_kg.fract() == 0.0 {
        format!("{weight_kg:.1}")
    } else {
        format!("{weight_kg}")
    }
}

fn entry_method(source: &str) -> &'static str {
    match source {
        "bleScale" => "automated_device",
        _ => "manual",
    }
}

fn iso8601(unix_seconds: i64) -> String {
    chrono::DateTime::<chrono::Utc>::from_timestamp(unix_seconds, 0)
        .unwrap_or_else(|| chrono::DateTime::<chrono::Utc>::from_timestamp(0, 0).unwrap())
        .to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

/// Tags for a kind-1351 weight event per NIP-101h.
fn build_weight_tags(entry: &FfiWeightEntry, encrypted: bool, own_pubkey: &PublicKey) -> Vec<Tag> {
    let mut tags = vec![
        Tag::custom(TagKind::custom("unit"), ["kg"]),
        Tag::hashtag("health"),
        Tag::hashtag("weight"),
        Tag::custom(
            TagKind::custom("timestamp"),
            [iso8601(entry.recorded_at_unix)],
        ),
        Tag::custom(TagKind::custom("source"), ["hakari"]),
        Tag::custom(
            TagKind::custom("entry_method"),
            [entry_method(&entry.source)],
        ),
    ];
    if entry.source == "bleScale" {
        tags.push(Tag::custom(TagKind::custom("accuracy"), ["accurate"]));
    }
    if encrypted {
        tags.push(Tag::custom(TagKind::custom("encryption_algo"), ["nip44"]));
        tags.push(Tag::public_key(*own_pubkey));
        tags.push(Tag::custom(TagKind::custom("encrypted"), ["true"]));
    }
    tags
}

/// Tags for the kind-30078 full-entry backup event.
fn build_backup_tags(entry_id: &str) -> Vec<Tag> {
    vec![
        Tag::identifier(format!("{BACKUP_D_PREFIX}{entry_id}")),
        Tag::hashtag(BACKUP_HASHTAG),
    ]
}

fn backup_plaintext(entry: &FfiWeightEntry, weight_event_id: Option<String>) -> Result<String> {
    let json = BackupEntryJson {
        id: entry.id.clone(),
        recorded_at: entry.recorded_at_unix,
        weight_kg: entry.weight_kg,
        body_fat_percent: entry.body_fat_percent,
        body_water_percent: entry.body_water_percent,
        muscle_mass_kg: entry.muscle_mass_kg,
        visceral_fat_rating: entry.visceral_fat_rating,
        bone_mass_kg: entry.bone_mass_kg,
        basal_metabolic_rate_kcal: entry.basal_metabolic_rate_kcal,
        metabolic_age: entry.metabolic_age,
        source: entry.source.clone(),
        weight_event_id,
    };
    serde_json::to_string(&json).context("Failed to serialize backup entry")
}

/// Build the unsigned kind-1351 weight event JSON (NIP-01 shape, id included)
/// for external signing (Amber / NIP-55).
///
/// When [content_override] is provided it is used verbatim (Dart passes the
/// NIP-44 ciphertext obtained from Amber); otherwise the plain weight string.
pub fn build_unsigned_weight_event(
    entry: FfiWeightEntry,
    pubkey_hex: String,
    content_override: Option<String>,
    encrypted: bool,
) -> Result<String> {
    let pk = PublicKey::parse(&pubkey_hex)
        .map_err(|e| anyhow!("Invalid public key '{pubkey_hex}': {e}"))?;
    let content = content_override.unwrap_or_else(|| format_weight(entry.weight_kg));
    let tags = build_weight_tags(&entry, encrypted, &pk);
    let mut unsigned = EventBuilder::new(Kind::Custom(KIND_WEIGHT), content)
        .tags(tags)
        .custom_created_at(Timestamp::from(entry.recorded_at_unix.max(0) as u64))
        .build(pk);
    unsigned.ensure_id();
    Ok(unsigned.as_json())
}

/// Build the unsigned kind-30078 backup event JSON for external signing.
/// [encrypted_content] must be the NIP-44 self-encrypted backup JSON
/// (see BackupEntryJson) produced by the signer.
pub fn build_unsigned_backup_event(
    entry: FfiWeightEntry,
    pubkey_hex: String,
    encrypted_content: String,
) -> Result<String> {
    let pk = PublicKey::parse(&pubkey_hex)
        .map_err(|e| anyhow!("Invalid public key '{pubkey_hex}': {e}"))?;
    let tags = build_backup_tags(&entry.id);
    let mut unsigned = EventBuilder::new(Kind::Custom(KIND_BACKUP), encrypted_content)
        .tags(tags)
        .build(pk);
    unsigned.ensure_id();
    Ok(unsigned.as_json())
}

/// Build the unsigned kind-30078 wellness backup event JSON for external
/// signing. [day_key] is the calendar day (`yyyy-MM-dd`);
/// [encrypted_content] must be the NIP-44 self-encrypted wellness JSON.
/// Parameterized-replaceable: one event per day, updates replace.
pub fn build_unsigned_wellness_event(
    pubkey_hex: String,
    day_key: String,
    encrypted_content: String,
) -> Result<String> {
    let pk = PublicKey::parse(&pubkey_hex)
        .map_err(|e| anyhow!("Invalid public key '{pubkey_hex}': {e}"))?;
    let tags = vec![
        Tag::identifier(format!("{WELLNESS_D_PREFIX}{day_key}")),
        Tag::hashtag(BACKUP_HASHTAG),
    ];
    let mut unsigned = EventBuilder::new(Kind::Custom(KIND_BACKUP), encrypted_content)
        .tags(tags)
        .build(pk);
    unsigned.ensure_id();
    Ok(unsigned.as_json())
}

// ========================================
// Publishing
// ========================================

async fn send_event_counting(
    client: &Client,
    timeout: Duration,
    event: Event,
) -> Result<(u32, u32)> {
    match tokio::time::timeout(timeout, client.send_event(event)).await {
        Ok(Ok(output)) => Ok((output.success.len() as u32, output.failed.len() as u32)),
        Ok(Err(e)) => Err(anyhow!("Failed to send event: {e}")),
        Err(_) => Err(anyhow!(
            "Timed out sending event after {}s",
            timeout.as_secs()
        )),
    }
}

/// Publish one measurement as BOTH a kind-1351 weight event (interop) and a
/// kind-30078 encrypted full-entry backup (lossless restore).
///
/// SecretKey mode only. When [encrypt] is true the 1351 content is NIP-44
/// self-encrypted; the 30078 backup content is ALWAYS encrypted.
pub fn publish_weight_entry(entry: FfiWeightEntry, encrypt: bool) -> Result<SendResultFfi> {
    TOKIO_RUNTIME.block_on(async {
        let guard = NOSTR_CLIENT.lock().await;
        let hc = guard
            .as_ref()
            .ok_or_else(|| anyhow!("Nostr client not initialized"))?;
        let keys = hc.keys.as_ref().ok_or_else(|| {
            anyhow!("publish_weight_entry requires SecretKey mode (use the unsigned-event flow for Amber)")
        })?;
        let own_pk = keys.public_key();

        // --- kind 1351 (weight, interop) ---
        let plain_content = format_weight(entry.weight_kg);
        let content = if encrypt {
            nip44::encrypt(keys.secret_key(), &own_pk, &plain_content, nip44::Version::V2)
                .context("NIP-44 encryption failed")?
        } else {
            plain_content
        };
        let weight_event = EventBuilder::new(Kind::Custom(KIND_WEIGHT), content)
            .tags(build_weight_tags(&entry, encrypt, &own_pk))
            .custom_created_at(Timestamp::from(entry.recorded_at_unix.max(0) as u64))
            .sign(keys)
            .await
            .context("Failed to sign weight event")?;
        let weight_event_id = weight_event.id.to_hex();

        // --- kind 30078 (full-entry backup, always encrypted) ---
        let backup_plain = backup_plaintext(&entry, Some(weight_event_id.clone()))?;
        let backup_content =
            nip44::encrypt(keys.secret_key(), &own_pk, &backup_plain, nip44::Version::V2)
                .context("NIP-44 encryption failed (backup)")?;
        let backup_event = EventBuilder::new(Kind::Custom(KIND_BACKUP), backup_content)
            .tags(build_backup_tags(&entry.id))
            .sign(keys)
            .await
            .context("Failed to sign backup event")?;

        let (ok, failed) = send_event_counting(&hc.client, hc.send_timeout, weight_event).await?;
        // Backup failure must not mask a successful 1351 publish.
        if let Err(e) = send_event_counting(&hc.client, hc.send_timeout, backup_event).await {
            eprintln!("hakari_core: backup event send failed: {e}");
        }

        Ok(SendResultFfi {
            event_id: weight_event_id,
            successful_relays: ok,
            failed_relays: failed,
        })
    })
}

/// Verify and publish an externally signed event (Amber flow).
pub fn publish_signed_event(event_json: String) -> Result<SendResultFfi> {
    TOKIO_RUNTIME.block_on(async {
        let event = Event::from_json(&event_json).context("Invalid signed event JSON")?;
        event
            .verify()
            .map_err(|e| anyhow!("Event signature verification failed: {e}"))?;
        // A valid signature is not enough: only publish our own health
        // events, so a compromised signer app cannot use Hakari as a
        // relay-publishing proxy for arbitrary identities or kinds.
        let kind = event.kind.as_u16();
        if kind != KIND_WEIGHT && kind != KIND_BACKUP {
            return Err(anyhow!(
                "Refusing to publish event of unexpected kind {kind}"
            ));
        }
        let event_id = event.id.to_hex();

        let guard = NOSTR_CLIENT.lock().await;
        let hc = guard
            .as_ref()
            .ok_or_else(|| anyhow!("Nostr client not initialized"))?;
        if event.pubkey != hc.public_key {
            return Err(anyhow!(
                "Refusing to publish event signed by a different identity"
            ));
        }
        let (ok, failed) = send_event_counting(&hc.client, hc.send_timeout, event).await?;
        Ok(SendResultFfi {
            event_id,
            successful_relays: ok,
            failed_relays: failed,
        })
    })
}

// ========================================
// Fetching
// ========================================

/// Fetch our own NIP-101h events: kind 1351 (weight) and kind 30078 with
/// #t=hakari-health (full-entry backups). Content is returned raw;
/// decryption happens Dart-side via SignerService.
pub fn fetch_health_events(
    pubkey_hex: String,
    since_unix: Option<i64>,
) -> Result<Vec<RawEventFfi>> {
    TOKIO_RUNTIME.block_on(async {
        let pk = PublicKey::parse(&pubkey_hex)
            .map_err(|e| anyhow!("Invalid public key '{pubkey_hex}': {e}"))?;

        // Cap results: a hostile relay can replay unbounded copies of our
        // own (validly signed) events; without a limit that means memory
        // growth here and one signer decrypt round-trip per event upstream.
        const FETCH_LIMIT: usize = 1000;
        let mut weight_filter = Filter::new()
            .author(pk)
            .kind(Kind::Custom(KIND_WEIGHT))
            .limit(FETCH_LIMIT);
        let mut backup_filter = Filter::new()
            .author(pk)
            .kind(Kind::Custom(KIND_BACKUP))
            .hashtag(BACKUP_HASHTAG)
            .limit(FETCH_LIMIT);
        if let Some(since) = since_unix {
            let ts = Timestamp::from(since.max(0) as u64);
            weight_filter = weight_filter.since(ts);
            backup_filter = backup_filter.since(ts);
        }

        let guard = NOSTR_CLIENT.lock().await;
        let hc = guard
            .as_ref()
            .ok_or_else(|| anyhow!("Nostr client not initialized"))?;
        let events = hc
            .client
            .fetch_events(
                vec![weight_filter, backup_filter],
                Some(Duration::from_secs(10)),
            )
            .await
            .map_err(|e| anyhow!("Failed to fetch events from relays: {e}"))?;

        Ok(events
            .into_iter()
            .map(|event| RawEventFfi {
                id: event.id.to_hex(),
                kind: event.kind.as_u16(),
                // Clamp: a hostile relay can claim absurd timestamps that
                // would wrap negative in a plain `as i64` cast.
                created_at: i64::try_from(event.created_at.as_u64()).unwrap_or(i64::MAX),
                content: event.content.clone(),
                tags: event
                    .tags
                    .iter()
                    .map(|tag| tag.as_slice().to_vec())
                    .collect(),
            })
            .collect())
    })
}

// ========================================
// Local-key crypto helpers (SecretKey mode, callable from Dart)
// ========================================

/// NIP-44 encrypt with a locally held secret key.
pub fn nip44_encrypt_local(
    nsec: String,
    receiver_pubkey_hex: String,
    plaintext: String,
) -> Result<String> {
    let keys = Keys::parse(&nsec).map_err(|e| anyhow!("Invalid secret key: {e}"))?;
    let receiver = PublicKey::parse(&receiver_pubkey_hex)
        .map_err(|e| anyhow!("Invalid receiver public key: {e}"))?;
    nip44::encrypt(keys.secret_key(), &receiver, plaintext, nip44::Version::V2)
        .map_err(|e| anyhow!("NIP-44 encryption failed: {e}"))
}

/// NIP-44 decrypt with a locally held secret key.
pub fn nip44_decrypt_local(
    nsec: String,
    sender_pubkey_hex: String,
    ciphertext: String,
) -> Result<String> {
    let keys = Keys::parse(&nsec).map_err(|e| anyhow!("Invalid secret key: {e}"))?;
    let sender = PublicKey::parse(&sender_pubkey_hex)
        .map_err(|e| anyhow!("Invalid sender public key: {e}"))?;
    nip44::decrypt(keys.secret_key(), &sender, ciphertext)
        .map_err(|e| anyhow!("NIP-44 decryption failed: {e}"))
}

/// Sign an unsigned NIP-01 event JSON with a locally held secret key.
/// Returns the full signed event JSON.
pub fn sign_event_local(nsec: String, unsigned_event_json: String) -> Result<String> {
    TOKIO_RUNTIME.block_on(async {
        let keys = Keys::parse(&nsec).map_err(|e| anyhow!("Invalid secret key: {e}"))?;
        let unsigned = UnsignedEvent::from_json(&unsigned_event_json)
            .context("Invalid unsigned event JSON")?;
        let event = unsigned
            .sign(&keys)
            .await
            .map_err(|e| anyhow!("Failed to sign event: {e}"))?;
        Ok(event.as_json())
    })
}

// ========================================
// Tests
// ========================================

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_entry() -> FfiWeightEntry {
        FfiWeightEntry {
            id: "entry-123".to_string(),
            recorded_at_unix: 1_752_000_000,
            weight_kg: 72.5,
            body_fat_percent: Some(21.3),
            body_water_percent: Some(55.0),
            muscle_mass_kg: Some(54.2),
            visceral_fat_rating: Some(7),
            bone_mass_kg: Some(2.9),
            basal_metabolic_rate_kcal: Some(1620),
            metabolic_age: Some(30),
            source: "bleScale".to_string(),
        }
    }

    fn tag_value<'a>(tags: &'a [Vec<String>], key: &str) -> Option<&'a str> {
        tags.iter()
            .find(|t| t.first().map(String::as_str) == Some(key))
            .and_then(|t| t.get(1))
            .map(String::as_str)
    }

    fn hashtags(tags: &[Vec<String>]) -> Vec<&str> {
        tags.iter()
            .filter(|t| t.first().map(String::as_str) == Some("t"))
            .filter_map(|t| t.get(1))
            .map(String::as_str)
            .collect()
    }

    #[test]
    fn key_generate_derive_roundtrip() {
        let generated = generate_keys().unwrap();
        assert!(generated.nsec.starts_with("nsec1"));
        assert!(generated.npub.starts_with("npub1"));
        assert_eq!(generated.pubkey_hex.len(), 64);

        // Roundtrip via nsec
        let derived = derive_keys(generated.nsec.clone()).unwrap();
        assert_eq!(derived.pubkey_hex, generated.pubkey_hex);
        assert_eq!(derived.npub, generated.npub);

        // Hex secret is also accepted
        let keys = Keys::parse(&generated.nsec).unwrap();
        let hex_secret = keys.secret_key().to_secret_hex();
        let derived_hex = derive_keys(hex_secret).unwrap();
        assert_eq!(derived_hex.pubkey_hex, generated.pubkey_hex);
    }

    #[test]
    fn derive_keys_rejects_garbage() {
        assert!(derive_keys("not-a-key".to_string()).is_err());
    }

    #[test]
    fn proxy_url_parsing() {
        let addr = parse_proxy_url("socks5://127.0.0.1:9050").unwrap();
        assert_eq!(addr.to_string(), "127.0.0.1:9050");

        let addr = parse_proxy_url("socks5h://127.0.0.1:9150/").unwrap();
        assert_eq!(addr.to_string(), "127.0.0.1:9150");

        let addr = parse_proxy_url("127.0.0.1:9050").unwrap();
        assert_eq!(addr.to_string(), "127.0.0.1:9050");

        assert!(parse_proxy_url("socks5://localhost:9050").is_err()); // no DNS names
        assert!(parse_proxy_url("").is_err());

        // Only SOCKS5 is actually spoken — other schemes must be rejected,
        // not silently treated as SOCKS5.
        assert!(parse_proxy_url("socks4://127.0.0.1:9050").is_err());
        assert!(parse_proxy_url("socks4a://127.0.0.1:9050").is_err());
        assert!(parse_proxy_url("http://127.0.0.1:8118").is_err());
    }

    #[test]
    fn unsigned_weight_event_plain() {
        let keys = Keys::generate();
        let entry = sample_entry();
        let json =
            build_unsigned_weight_event(entry, keys.public_key().to_hex(), None, false).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["kind"], 1351);
        assert_eq!(value["content"], "72.5");
        assert_eq!(value["created_at"], 1_752_000_000);
        assert_eq!(value["pubkey"], keys.public_key().to_hex());
        assert!(value["id"].is_string(), "unsigned event must carry its id");

        let tags: Vec<Vec<String>> = serde_json::from_value(value["tags"].clone()).unwrap();
        assert_eq!(tag_value(&tags, "unit"), Some("kg"));
        assert_eq!(tag_value(&tags, "source"), Some("hakari"));
        assert_eq!(tag_value(&tags, "entry_method"), Some("automated_device"));
        assert_eq!(tag_value(&tags, "accuracy"), Some("accurate"));
        let ht = hashtags(&tags);
        assert!(ht.contains(&"health") && ht.contains(&"weight"));
        // Not encrypted: no encryption markers
        assert_eq!(tag_value(&tags, "encrypted"), None);
        assert_eq!(tag_value(&tags, "encryption_algo"), None);
    }

    #[test]
    fn unsigned_weight_event_encrypted_with_override() {
        let keys = Keys::generate();
        let mut entry = sample_entry();
        entry.source = "manual".to_string();
        let json = build_unsigned_weight_event(
            entry,
            keys.public_key().to_hex(),
            Some("ciphertext-from-amber".to_string()),
            true,
        )
        .unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["content"], "ciphertext-from-amber");
        let tags: Vec<Vec<String>> = serde_json::from_value(value["tags"].clone()).unwrap();
        assert_eq!(tag_value(&tags, "encryption_algo"), Some("nip44"));
        assert_eq!(tag_value(&tags, "encrypted"), Some("true"));
        assert_eq!(
            tag_value(&tags, "p"),
            Some(keys.public_key().to_hex().as_str())
        );
        assert_eq!(tag_value(&tags, "entry_method"), Some("manual"));
        assert_eq!(tag_value(&tags, "accuracy"), None);
    }

    #[test]
    fn unsigned_backup_event_shape() {
        let keys = Keys::generate();
        let entry = sample_entry();
        let json = build_unsigned_backup_event(
            entry,
            keys.public_key().to_hex(),
            "encrypted-backup-content".to_string(),
        )
        .unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["kind"], 30078);
        assert_eq!(value["content"], "encrypted-backup-content");
        let tags: Vec<Vec<String>> = serde_json::from_value(value["tags"].clone()).unwrap();
        assert_eq!(tag_value(&tags, "d"), Some("hakari:entry:entry-123"));
        assert_eq!(hashtags(&tags), vec!["hakari-health"]);
    }

    #[test]
    fn backup_plaintext_roundtrip() {
        let entry = sample_entry();
        let json = backup_plaintext(&entry, Some("abc123".to_string())).unwrap();
        let parsed: BackupEntryJson = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.id, "entry-123");
        assert_eq!(parsed.recorded_at, 1_752_000_000);
        assert_eq!(parsed.weight_kg, 72.5);
        assert_eq!(parsed.body_fat_percent, Some(21.3));
        assert_eq!(parsed.weight_event_id.as_deref(), Some("abc123"));
        assert_eq!(parsed.source, "bleScale");

        // None fields are omitted from the wire format
        let sparse = FfiWeightEntry {
            body_fat_percent: None,
            body_water_percent: None,
            muscle_mass_kg: None,
            visceral_fat_rating: None,
            bone_mass_kg: None,
            basal_metabolic_rate_kcal: None,
            metabolic_age: None,
            ..sample_entry()
        };
        let json = backup_plaintext(&sparse, None).unwrap();
        assert!(!json.contains("body_fat_percent"));
        assert!(!json.contains("weight_event_id"));
    }

    #[test]
    fn nip44_local_roundtrip() {
        let keys = Keys::generate();
        let nsec = keys.secret_key().to_bech32().unwrap();
        let pubkey_hex = keys.public_key().to_hex();

        let ciphertext =
            nip44_encrypt_local(nsec.clone(), pubkey_hex.clone(), "72.5".to_string()).unwrap();
        assert_ne!(ciphertext, "72.5");
        let plain = nip44_decrypt_local(nsec, pubkey_hex, ciphertext).unwrap();
        assert_eq!(plain, "72.5");
    }

    #[test]
    fn sign_event_local_produces_valid_event() {
        let keys = Keys::generate();
        let nsec = keys.secret_key().to_bech32().unwrap();
        let unsigned =
            build_unsigned_weight_event(sample_entry(), keys.public_key().to_hex(), None, false)
                .unwrap();
        let signed = sign_event_local(nsec, unsigned).unwrap();
        let event = Event::from_json(&signed).unwrap();
        event.verify().unwrap();
        assert_eq!(event.kind.as_u16(), 1351);
    }

    #[test]
    fn format_weight_strings() {
        assert_eq!(format_weight(72.5), "72.5");
        assert_eq!(format_weight(72.0), "72.0");
        assert_eq!(format_weight(103.25), "103.25");
    }
}
