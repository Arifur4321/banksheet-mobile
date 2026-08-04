/// State for the settings screens.
///
/// Three things need to outlive a single widget: the workspace's API keys, the
/// public `/config` payload, and the language the account has chosen. The first
/// two are plain futures — they are read far more often than they are written —
/// and the third is a controller, because choosing a language writes to two
/// places (the device and `PATCH /me`) and has to roll both back together when
/// the server refuses.
///
/// [apiKeysProvider] watches [sessionSignalProvider] so signing out drops the
/// cached credentials; the next account must never see the previous one's keys.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/settings_repository.dart';
import '../domain/api_key.dart';
import '../domain/server_config.dart';

/// `GET /config`. Public, so it resolves before the session does and survives a
/// token refresh.
///
/// It is allowed to fail: every screen that reads it falls back to a bundled
/// value ([ServerConfig.fallback]) rather than showing an error, because a
/// language picker or an About screen that renders nothing when the network is
/// down is worse than one that renders what the binary shipped with.
final FutureProvider<ServerConfig> serverConfigProvider =
    FutureProvider<ServerConfig>((Ref ref) {
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);

  return ref.watch(settingsRepositoryProvider).config(cancelToken: cancelToken);
});

/// `GET /api-keys`. Answers 403 `forbidden` for an employee account, which the
/// screen renders as an explanation rather than as an error.
final FutureProvider<ApiKeyBundle> apiKeysProvider =
    FutureProvider<ApiKeyBundle>((Ref ref) {
  // Re-runs when the session ends, so the keys of a signed-out workspace are
  // never handed to whoever signs in next.
  ref.watch(sessionSignalProvider);

  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);

  return ref.watch(settingsRepositoryProvider).apiKeys(cancelToken: cancelToken);
});

/// The application version and build number, read once from the platform.
final FutureProvider<PackageInfo> packageInfoProvider =
    FutureProvider<PackageInfo>((Ref ref) => PackageInfo.fromPlatform());

/// Which language is selected, and whether a change is in flight.
@immutable
class LocaleState {
  const LocaleState({required this.code, this.saving = false});

  /// ISO code, e.g. `it`. Never empty — it falls back to the device preference.
  final String code;

  /// True while `PATCH /me` is in flight; the picker disables itself so a
  /// second tap cannot race the first.
  final bool saving;

  LocaleState copyWith({String? code, bool? saving}) => LocaleState(
        code: code ?? this.code,
        saving: saving ?? this.saving,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocaleState && other.code == code && other.saving == saving;

  @override
  int get hashCode => Object.hash(code, saving);

  @override
  String toString() => 'LocaleState($code, saving: $saving)';
}

/// Owns the language choice.
///
/// The account's language is server state — it decides what an emailed
/// notification is written in — so the device preference alone is not enough.
/// Both are written, and both are rolled back together if the server refuses:
/// a phone that thinks it is Italian while the server sends English emails is
/// worse than a failed save.
class LocaleController extends StateNotifier<LocaleState> {
  LocaleController(Ref ref)
      : _ref = ref,
        super(LocaleState(code: _initialCode(ref))) {
    // `refreshSession()` after a save — and a different account signing in —
    // both arrive here, so the selected row always matches `GET /me`.
    _ref.listen<AppUser?>(currentUserProvider, _adopt);
  }

  final Ref _ref;

  /// The account's own choice wins over the device preference: the phone may
  /// have been set to English before signing in to an Italian account.
  static String _initialCode(Ref ref) {
    final String? chosen = ref.read(currentUserProvider)?.locale;
    if (chosen != null && chosen.isNotEmpty) {
      return chosen;
    }
    return ref.read(prefsProvider).locale;
  }

  void _adopt(AppUser? previous, AppUser? next) {
    final String? code = next?.locale;
    if (code == null || code.isEmpty || state.saving || code == state.code) {
      return;
    }
    state = LocaleState(code: code);
  }

  /// Persists [code] on the device and on the account.
  ///
  /// Rethrows the server's failure so the screen can show it; the selected row
  /// is already back where it was by then.
  Future<void> select(String code) async {
    if (state.saving || code == state.code || code.isEmpty) {
      return;
    }

    final String previous = state.code;
    state = LocaleState(code: code, saving: true);

    try {
      await _ref.read(prefsProvider).setLocale(code);
      await _ref.read(authRepositoryProvider).updateProfile(locale: code);
      await _ref.read(authControllerProvider.notifier).refreshSession();

      if (mounted) {
        state = LocaleState(code: code);
      }
    } catch (_) {
      // The server refused, so the account's language did not change and the
      // device must not pretend otherwise.
      await _ref.read(prefsProvider).setLocale(previous);
      if (mounted) {
        state = LocaleState(code: previous);
      }
      rethrow;
    }
  }
}

final StateNotifierProvider<LocaleController, LocaleState>
    localeControllerProvider =
    StateNotifierProvider<LocaleController, LocaleState>(
  (Ref ref) => LocaleController(ref),
);
