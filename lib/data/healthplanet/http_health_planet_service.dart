import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/health_planet_config.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/health_planet_service.dart';
import 'health_planet_codec.dart';

/// [HealthPlanetService] talking to www.healthplanet.jp with dart:io.
/// Tokens live in Keystore/Keychain-backed secure storage.
class HttpHealthPlanetService implements HealthPlanetService {
  HttpHealthPlanetService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const String _host = 'www.healthplanet.jp';
  static const String _accessTokenKey = 'hp_access_token';
  static const String _refreshTokenKey = 'hp_refresh_token';
  static const String _clientSecretKey = 'hp_client_secret';
  static const Duration _timeout = Duration(seconds: 20);

  final FlutterSecureStorage _storage;
  final Uuid _uuid = const Uuid();

  @override
  Uri authorizationUrl() => Uri.https(_host, '/oauth/auth', {
    'client_id': HealthPlanetConfig.clientId,
    'redirect_uri': HealthPlanetConfig.redirectUri,
    'scope': 'innerscan',
    'response_type': 'code',
  });

  @override
  Future<bool> hasClientSecret() async => (await _clientSecret()).isNotEmpty;

  @override
  Future<void> setClientSecret(String secret) async {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) {
      throw const HealthPlanetFailure('The client secret is empty.');
    }
    await _storage.write(key: _clientSecretKey, value: trimmed);
  }

  /// Build-time secret wins; otherwise the one pasted on this device.
  Future<String> _clientSecret() async {
    if (HealthPlanetConfig.clientSecret.isNotEmpty) {
      return HealthPlanetConfig.clientSecret;
    }
    return (await _storage.read(key: _clientSecretKey)) ?? '';
  }

  Future<String> _requireClientSecret() async {
    final secret = await _clientSecret();
    if (secret.isEmpty) {
      throw const HealthPlanetFailure(
        'No Health Planet client secret is set. Enter it when linking '
        '(shown next to the client ID on the Health Planet developer '
        'page).',
      );
    }
    return secret;
  }

  @override
  Future<void> linkWithCode(String code) async {
    final secret = await _requireClientSecret();
    final trimmed = _extractCode(code);
    if (trimmed.isEmpty) {
      throw const HealthPlanetFailure('The authorization code is empty.');
    }
    final body = await _postForm('/oauth/token', {
      'client_id': HealthPlanetConfig.clientId,
      'client_secret': secret,
      'redirect_uri': HealthPlanetConfig.redirectUri,
      'code': trimmed,
      'grant_type': 'authorization_code',
    });
    final (access, refresh) = HealthPlanetCodec.parseTokenResponse(body);
    await _storage.write(key: _accessTokenKey, value: access);
    if (refresh != null) {
      await _storage.write(key: _refreshTokenKey, value: refresh);
    }
  }

  @override
  Future<bool> isLinked() async =>
      (await _storage.read(key: _accessTokenKey))?.isNotEmpty ?? false;

  @override
  Future<void> unlink() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  @override
  Future<List<WeightEntry>> fetchEntries(DateTime from, DateTime to) async {
    var token = await _storage.read(key: _accessTokenKey);
    if (token == null || token.isEmpty) {
      throw const HealthPlanetFailure(
        'Health Planet is not linked. Link it from Settings first.',
      );
    }
    var body = await _fetchInnerscan(token, from, to);
    if (_looksLikeAuthError(body)) {
      token = await _refreshAccessToken();
      body = await _fetchInnerscan(token, from, to);
    }
    return HealthPlanetCodec.parseInnerscan(body, generateId: () => _uuid.v4());
  }

  // ------------------------------------------------------------------

  Future<String> _fetchInnerscan(String token, DateTime from, DateTime to) {
    return _postForm('/status/innerscan.json', {
      'access_token': token,
      // 1 = measurement date (not upload date).
      'date': '1',
      'from': HealthPlanetCodec.formatRequestDate(from),
      'to': HealthPlanetCodec.formatRequestDate(to),
      'tag': HealthPlanetCodec.requestTags,
    });
  }

  Future<String> _refreshAccessToken() async {
    final secret = await _requireClientSecret();
    final refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) {
      throw const HealthPlanetFailure(
        'Health Planet session expired. Please link again from Settings.',
      );
    }
    final body = await _postForm('/oauth/token', {
      'client_id': HealthPlanetConfig.clientId,
      'client_secret': secret,
      'redirect_uri': HealthPlanetConfig.redirectUri,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    final (access, newRefresh) = HealthPlanetCodec.parseTokenResponse(body);
    await _storage.write(key: _accessTokenKey, value: access);
    if (newRefresh != null) {
      await _storage.write(key: _refreshTokenKey, value: newRefresh);
    }
    return access;
  }

  Future<String> _postForm(String path, Map<String, String> fields) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .postUrl(Uri.https(_host, path))
          .timeout(_timeout);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        fields.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}='
                  '${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const HealthPlanetFailure(
          'Health Planet rate limit reached (60 requests/hour). '
          'Try again later.',
        );
      }
      // Auth errors surface in the JSON body (handled by callers);
      // other non-200s are hard failures.
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.unauthorized &&
          response.statusCode != HttpStatus.forbidden) {
        throw HealthPlanetFailure(
          'Health Planet returned HTTP ${response.statusCode}',
        );
      }
      return body;
    } on HealthPlanetFailure {
      rethrow;
    } on Exception catch (e) {
      throw HealthPlanetFailure('Could not reach Health Planet', e);
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeAuthError(String body) {
    // Error responses are tiny JSON objects like {"error":"invalid_token"}.
    if (body.length > 512) return false;
    return body.contains('"error"') &&
        (body.contains('token') || body.contains('unauthorized'));
  }

  /// Accepts either the bare code or a pasted success-page URL containing
  /// `?code=...`.
  static String _extractCode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.contains('code=')) return trimmed;
    final uri = Uri.tryParse(trimmed);
    final fromQuery = uri?.queryParameters['code'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final match = RegExp('code=([^&#\\s]+)').firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }
}
