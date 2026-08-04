/// Every call the app can make about an account.
///
/// The repository is the only place that knows the wire field names — the app
/// says `workspaceName`, the server hears `company_name` — and the only place
/// that writes to [TokenStore]. Keeping the token write next to the call that
/// mints the pair is what guarantees a successful sign-in can never leave the
/// app holding a session it did not persist.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/network/token_store.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/session.dart';

class AuthRepository {
  const AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// `POST /auth/login` then `GET /me`.
  ///
  /// The login response carries the user and the token pair but not the
  /// workspace, plan or usage, so the session is completed with the same `/me`
  /// call a cold start makes. Two round trips once, at sign-in, rather than a
  /// second shape of "session" the rest of the app would have to understand.
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> response = await _api.post(
      Endpoints.login,
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        ..._api.identity.deviceFields,
      },
    );

    await _persistTokens(response);

    return me();
  }

  /// `POST /auth/register`.
  ///
  /// `company_name` is the workspace, and `password_confirmation` is required
  /// by the server's `confirmed` rule even though the app has already checked
  /// the two fields match.
  Future<Session> register({
    required String name,
    required String email,
    required String password,
    required String workspaceName,
    String? locale,
  }) async {
    final Map<String, dynamic> response = await _api.post(
      Endpoints.register,
      body: <String, dynamic>{
        'company_name': workspaceName.trim(),
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'password_confirmation': password,
        if (locale != null && locale.isNotEmpty) 'locale': locale,
        ..._api.identity.deviceFields,
      },
    );

    await _persistTokens(response);

    return me();
  }

  /// `POST /auth/forgot-password`.
  ///
  /// Always succeeds for a well-formed address, whether or not the account
  /// exists — the server refuses to be an oracle for who has an account here,
  /// and the app must not undo that by reporting anything different.
  Future<void> forgotPassword(String email) async {
    await _api.post(
      Endpoints.forgotPassword,
      body: <String, dynamic>{'email': email.trim()},
    );
  }

  /// `POST /auth/logout` — ends this session only; other devices keep working.
  Future<void> logout() async {
    await _api.post(Endpoints.logout);
  }

  /// `GET /me` — user, workspace, plan and usage in one response.
  Future<Session> me() async {
    final Map<String, dynamic> response = await _api.get(Endpoints.me);
    return Session.fromJson(response);
  }

  /// `PATCH /me`.
  ///
  /// Only the fields that were actually edited are sent: the server's rules are
  /// `sometimes|required`, so posting a null for an untouched field would be
  /// rejected as an attempt to blank it.
  Future<AppUser> updateProfile({
    String? name,
    String? email,
    String? locale,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (email != null) 'email': email.trim(),
      if (locale != null) 'locale': locale,
    };

    final Map<String, dynamic> response =
        await _api.patch(Endpoints.me, body: body);

    final Map<String, dynamic> root =
        J.map(response['data']).isEmpty ? response : J.map(response['data']);

    return AppUser.fromJson(J.map(root['user']));
  }

  /// `PUT /me/password` — every other session is revoked, this one survives.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.put(
      Endpoints.password,
      body: <String, dynamic>{
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      },
    );
  }

  /// `DELETE /me` — password-gated on the server, and irreversible.
  Future<void> deleteAccount({required String currentPassword}) async {
    await _api.delete(
      Endpoints.me,
      body: <String, dynamic>{'current_password': currentPassword},
    );
  }

  /// `POST /devices` — upserts this installation.
  ///
  /// Called after every sign-in and on every launch. The push token is null
  /// until a notification SDK exists; the registration is still worth making
  /// because it carries the locale and the last-seen timestamp.
  Future<void> registerDevice({String? pushToken, String? locale}) async {
    final ClientIdentity identity = _api.identity;

    await _api.post(
      Endpoints.devices,
      body: <String, dynamic>{
        'device_id': identity.deviceId,
        'platform': identity.platform,
        'app_version': identity.appVersion,
        if (pushToken != null) 'push_token': pushToken,
        if (locale != null && locale.isNotEmpty) 'locale': locale,
      },
    );
  }

  /// Stores a freshly issued pair. Accepts the flat body the auth endpoints
  /// return and a `{"data": {...}}` envelope, so an envelope change on the
  /// server cannot lock every installed build out of signing in.
  Future<void> _persistTokens(Map<String, dynamic> response) async {
    final Map<String, dynamic> body =
        J.map(response['data']).isEmpty ? response : J.map(response['data']);

    final String? access = J.str(body['access_token']);
    final String? refresh = J.str(body['refresh_token']);

    if (access == null || refresh == null) {
      throw const ApiException(
        code: ApiException.codeMalformed,
        message: 'The server did not return a session. Please try again.',
      );
    }

    await _tokens.save(
      accessToken: access,
      refreshToken: refresh,
      // 1800 s matches `mobile.tokens.access_ttl_seconds`' default, and is only
      // a fallback: the interceptor refreshes on a 401 regardless.
      expiresIn: J.intOr(body['expires_in'], 1800),
    );
  }
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
  (Ref ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  ),
);
