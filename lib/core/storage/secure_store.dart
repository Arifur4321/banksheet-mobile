/// Encrypted storage for the one secret the app holds: the refresh token.
///
/// The split is deliberate and mirrors the Chrome extension's design in the
/// sibling SEO project: the long-lived refresh token goes to the Keychain /
/// Android Keystore, while the short-lived access token lives only in memory.
/// If the process dies, the access token dies with it and is re-minted from the
/// refresh token — so a device dump never yields a usable bearer token.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _kRefreshToken = 'banksheet.refresh_token';
  static const String _kDeviceId = 'banksheet.device_id';

  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _kRefreshToken);

  /// A stable per-install identifier so the server can list and revoke a single
  /// device. Not a hardware id — deleting the app resets it, which is the
  /// privacy-correct behaviour and keeps us out of the stores' device-tracking
  /// disclosure rules.
  Future<String?> readDeviceId() => _storage.read(key: _kDeviceId);

  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _kDeviceId, value: id);

  /// Wipes everything on sign-out or on an unrecoverable auth failure.
  Future<void> clearAll() async {
    await _storage.delete(key: _kRefreshToken);
    // The device id survives sign-out on purpose: the same phone signing back
    // in should reuse its slot rather than accumulating orphan token rows.
  }
}
