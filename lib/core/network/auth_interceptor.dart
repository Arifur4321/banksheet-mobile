/// Attaches the bearer token and transparently refreshes it.
///
/// The hard part of a refresh interceptor is concurrency: if five screens fire
/// requests at the moment the access token expires, a naive implementation
/// performs five refreshes and — because the server rotates refresh tokens and
/// treats reuse as theft — four of them present an already-rotated token and
/// the whole session is revoked.
///
/// So refresh is *single flight*: the first 401 starts one refresh, everyone
/// else awaits the same future, and each queued request is then replayed once
/// with the new token.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'endpoints.dart';
import 'token_store.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required TokenStore tokens,
    required Dio refreshClient,
    required Future<void> Function() onSessionLost,
  })  : _tokens = tokens,
        _refreshClient = refreshClient,
        _onSessionLost = onSessionLost;

  final TokenStore _tokens;

  /// A bare Dio with no interceptors. Refreshing through the main client would
  /// recurse the moment the refresh call itself returned 401.
  final Dio _refreshClient;

  final Future<void> Function() _onSessionLost;

  Future<bool>? _inFlightRefresh;

  /// Paths that must never carry a bearer token or trigger a refresh.
  static const Set<String> _anonymous = <String>{
    Endpoints.config,
    Endpoints.health,
    Endpoints.login,
    Endpoints.register,
    Endpoints.refresh,
    Endpoints.forgotPassword,
  };

  bool _isAnonymous(RequestOptions options) =>
      _anonymous.contains(options.path) ||
      options.extra['anonymous'] == true;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAnonymous(options)) {
      return handler.next(options);
    }

    // Refresh proactively when we already know the token is stale. This turns
    // the common case into one round trip instead of a 401 plus a retry.
    if (!_tokens.hasFreshAccessToken && _tokens.hasSession) {
      final bool ok = await _refresh();
      if (!ok) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: const ApiException(
              code: 'unauthorized',
              message: 'Your session has ended. Please sign in again.',
            ),
            type: DioExceptionType.cancel,
          ),
        );
      }
    }

    final String? token = _tokens.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final int? status = err.response?.statusCode;

    final bool retryable = status == 401 &&
        !_isAnonymous(options) &&
        options.extra['retried'] != true &&
        _tokens.hasSession;

    if (!retryable) {
      return handler.next(err);
    }

    final ApiException parsed = ApiException.fromResponse(err.response);

    // `unauthorized` / `invalid_token` mean the session is genuinely over —
    // refreshing would only burn the refresh token. Only `token_expired`
    // (and a bare 401 with no code) is worth a retry.
    if (parsed.code == 'invalid_token' || parsed.code == 'invalid_grant') {
      await _endSession();
      return handler.next(err);
    }

    final bool refreshed = await _refresh();
    if (!refreshed) {
      return handler.next(err);
    }

    try {
      options.extra['retried'] = true;
      options.headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
      final Response<dynamic> response = await _refreshClient.fetch<dynamic>(
        options,
      );
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Runs at most one refresh at a time. Returns whether a usable access token
  /// is now available.
  Future<bool> _refresh() {
    return _inFlightRefresh ??= _performRefresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<bool> _performRefresh() async {
    final String? refreshToken = _tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _endSession();
      return false;
    }

    try {
      final Response<dynamic> res = await _refreshClient.post<dynamic>(
        '${AppConfig.apiBase}${Endpoints.refresh}',
        data: <String, dynamic>{'refresh_token': refreshToken},
        options: Options(
          headers: <String, dynamic>{'Accept': 'application/json'},
        ),
      );

      final dynamic body = res.data;
      if (body is! Map) {
        await _endSession();
        return false;
      }

      // The server may wrap the pair in `data` or return it flat; accept both
      // so a later envelope change does not lock every installed app out.
      final Map<String, dynamic> map = Map<String, dynamic>.from(body);
      final Map<String, dynamic> payload = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;

      final String? access = payload['access_token'] as String?;
      final String? refresh = payload['refresh_token'] as String?;
      final int expiresIn = (payload['expires_in'] as num?)?.toInt() ?? 1800;

      if (access == null || refresh == null) {
        await _endSession();
        return false;
      }

      await _tokens.save(
        accessToken: access,
        refreshToken: refresh,
        expiresIn: expiresIn,
      );
      return true;
    } on DioException catch (e) {
      // A 4xx on refresh means the token was rotated, revoked or expired. The
      // server has already ended the session; the only correct move is to sign
      // out locally. A 5xx or a network error is transient — keep the session
      // so the next attempt can succeed.
      final int? status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await _endSession();
      }
      return false;
    }
  }

  Future<void> _endSession() async {
    _tokens.invalidateAccessToken();
    await _onSessionLost();
  }
}
