/// The four calls the settings screens make that are not about the session.
///
/// Profile, password and account deletion already live in `AuthRepository` —
/// they write to the same `/me` resource the session is parsed from, and having
/// two repositories able to mutate the signed-in user would be two places to get
/// it wrong. What is left here is the API-key lifecycle and the public
/// `/config` payload.
///
/// `POST /api-keys` is the only response in the whole product that carries a
/// plaintext credential; it is parsed into [MintedApiKey] and handed straight to
/// the reveal sheet, never cached and never logged.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/api_key.dart';
import '../domain/server_config.dart';

class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  /// `GET /config` — public, so this works before the session loads and while
  /// a token is being refreshed.
  Future<ServerConfig> config({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.config,
      cancelToken: cancelToken,
    );
    return ServerConfig.fromJson(json);
  }

  /// `GET /api-keys` — the workspace's keys plus its API allowance.
  ///
  /// Answers 403 `forbidden` for an employee account. That is surfaced to the
  /// user rather than swallowed: someone who cannot find the keys screen needs
  /// to be told who can create a key for them.
  Future<ApiKeyBundle> apiKeys({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.apiKeys,
      cancelToken: cancelToken,
    );
    return ApiKeyBundle.fromJson(json);
  }

  /// `POST /api-keys` — mints a live key and returns its one plaintext.
  ///
  /// `environment` is not sent: the server defaults to `live`, and a test key
  /// is only useful next to the code being written, which is not on a phone.
  Future<MintedApiKey> createApiKey({
    required String name,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.apiKeys,
      body: <String, dynamic>{'name': name.trim()},
      cancelToken: cancelToken,
    );
    return MintedApiKey.fromJson(json);
  }

  /// `DELETE /api-keys/{id}` — revokes, never deletes.
  ///
  /// Returns the updated key so the row can be redrawn as revoked from the
  /// server's own copy instead of a locally guessed one.
  Future<ApiKey> revokeApiKey(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.delete(
      Endpoints.apiKey(id),
      cancelToken: cancelToken,
    );

    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);

    return ApiKey.fromJson(J.map(root['key']));
  }
}

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) => SettingsRepository(ref.watch(apiClientProvider)),
);
