/// Holds the session.
///
/// The access token never touches disk (see [SecureStore] for why). The refresh
/// token does, encrypted. [TokenStore] is a [ChangeNotifier] so the router can
/// react to sign-in and sign-out without any screen having to push routes
/// imperatively.
library;

import 'package:flutter/foundation.dart';

import '../storage/secure_store.dart';

class TokenStore extends ChangeNotifier {
  TokenStore(this._secure);

  final SecureStore _secure;

  String? _accessToken;
  DateTime? _accessExpiresAt;
  String? _refreshToken;

  /// Set once at startup so the router can tell "still checking" from
  /// "definitely signed out" and avoid flashing the login screen.
  bool _restored = false;

  bool get isRestored => _restored;

  String? get accessToken => _accessToken;

  String? get refreshToken => _refreshToken;

  bool get hasSession => _refreshToken != null && _refreshToken!.isNotEmpty;

  /// True when there is a usable access token right now. A 30 s guard band
  /// stops a token expiring mid-flight on a slow connection.
  bool get hasFreshAccessToken {
    if (_accessToken == null || _accessExpiresAt == null) {
      return false;
    }
    return _accessExpiresAt!
        .subtract(const Duration(seconds: 30))
        .isAfter(DateTime.now());
  }

  /// Loads the persisted refresh token. Called once during bootstrap.
  Future<void> restore() async {
    _refreshToken = await _secure.readRefreshToken();
    _restored = true;
    notifyListeners();
  }

  /// Records a freshly issued pair. [expiresIn] is the server's `expires_in`
  /// in seconds.
  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    _accessToken = accessToken;
    _accessExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    final bool wasSignedOut = _refreshToken == null;
    _refreshToken = refreshToken;
    await _secure.writeRefreshToken(refreshToken);
    if (wasSignedOut) {
      notifyListeners();
    }
  }

  /// Drops the in-memory access token only — used when the server says the
  /// token expired but the session is still valid.
  void invalidateAccessToken() {
    _accessToken = null;
    _accessExpiresAt = null;
  }

  /// Ends the session. Idempotent, so it is safe to call from several failure
  /// paths at once.
  Future<void> clear() async {
    final bool wasSignedIn = _refreshToken != null;
    _accessToken = null;
    _accessExpiresAt = null;
    _refreshToken = null;
    await _secure.clearRefreshToken();
    if (wasSignedIn) {
      notifyListeners();
    }
  }
}
