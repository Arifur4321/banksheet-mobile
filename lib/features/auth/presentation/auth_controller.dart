/// The session state machine.
///
/// One controller owns "who is signed in", and the rest of the app reads it.
/// The router is deliberately not one of its readers: it watches [TokenStore],
/// which flips the moment a token pair is written or cleared, so navigation
/// never waits on `GET /me` and a signed-in user never sees the welcome screen
/// flash on a cold start.
///
/// Three things can end a session, and all three land here:
///   * the user tapping sign out ([signOut]),
///   * the refresh interceptor giving up on a dead token, which bumps
///     [sessionSignalProvider],
///   * the account being deleted from the settings screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/token_store.dart';
import '../../../core/providers.dart';
import '../../../core/storage/prefs.dart';
import '../../../core/utils/logger.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

class AuthController extends StateNotifier<AsyncValue<Session?>> {
  AuthController(this._ref) : super(const AsyncValue<Session?>.loading()) {
    // The interceptor clears the tokens and bumps the signal when a refresh
    // fails. Listening rather than polling means the UI drops the session in
    // the same frame the network layer discovers it is gone.
    _ref.listen<int>(
      sessionSignalProvider,
      (int? previous, int next) {
        if (previous == null || previous == next) {
          return;
        }
        _handleSessionLost();
      },
    );

    unawaited(_bootstrap());
  }

  final Ref _ref;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  TokenStore get _tokens => _ref.read(tokenStoreProvider);

  Prefs get _prefs => _ref.read(prefsProvider);

  Future<void> _bootstrap() async {
    if (!_tokens.hasSession) {
      if (mounted) {
        state = const AsyncValue<Session?>.data(null);
      }
      return;
    }
    await loadSession();
  }

  /// Fetches `GET /me` when there is a stored session.
  ///
  /// Returns immediately when a session is already loaded unless [force] is
  /// set, so a screen may call this on mount without costing a request.
  Future<void> loadSession({bool force = false}) async {
    if (!_tokens.hasSession) {
      if (mounted) {
        state = const AsyncValue<Session?>.data(null);
      }
      return;
    }

    if (!force && state.valueOrNull != null) {
      return;
    }

    // Refreshing keeps the current session on screen while it reloads; a first
    // load has nothing to keep and shows the loading state.
    if (state.valueOrNull == null) {
      state = const AsyncValue<Session?>.loading();
    }

    try {
      final Session session = await _repo.me();
      if (!mounted) {
        return;
      }
      state = AsyncValue<Session?>.data(session);
      unawaited(_touchDevice());
    } catch (error, stack) {
      if (!mounted) {
        return;
      }
      final ApiException failure = ApiException.from(error);

      // A dead token is not an error to show — the interceptor has already
      // ended the session and the router is on its way to the welcome screen.
      state = failure.isAuthFailure
          ? const AsyncValue<Session?>.data(null)
          : AsyncValue<Session?>.error(failure, stack);

      if (!failure.isAuthFailure) {
        Log.warn('Session load failed: ${failure.code}');
      }
    }
  }

  /// Signs in and loads the session. Throws [ApiException] so the form can put
  /// the server's field errors next to the fields they belong to.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue<Session?>.loading();
    try {
      final Session session = await _repo.login(
        email: email,
        password: password,
      );
      if (!mounted) {
        return;
      }
      state = AsyncValue<Session?>.data(session);
      unawaited(_touchDevice());
    } catch (error, stack) {
      _recoverFrom(error, stack);
      rethrow;
    }
  }

  /// Creates the account, its workspace and a session in one call.
  ///
  /// [workspaceName] is optional: left blank, the server names the workspace
  /// after the person. The parameter is kept rather than dropped so the field
  /// can stay on the form for the users who do want to name their practice.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? workspaceName,
  }) async {
    state = const AsyncValue<Session?>.loading();
    try {
      final Session session = await _repo.register(
        name: name,
        email: email,
        password: password,
        workspaceName: workspaceName,
        locale: _prefs.locale,
      );
      if (!mounted) {
        return;
      }
      state = AsyncValue<Session?>.data(session);
      unawaited(_touchDevice());
    } catch (error, stack) {
      _recoverFrom(error, stack);
      rethrow;
    }
  }

  /// Asks for a reset link. Never reveals whether the address has an account.
  Future<void> forgotPassword(String email) => _repo.forgotPassword(email);

  /// Ends the session locally, whatever the server says.
  ///
  /// The API call is best effort on purpose: the usual reason a sign-out
  /// request fails is that the token is already dead or the phone is offline,
  /// and neither is a reason to keep someone signed in on a device they are
  /// trying to leave.
  Future<void> signOut() async {
    try {
      await _repo.logout();
    } catch (error) {
      Log.warn(
        'Sign-out request failed (${ApiException.from(error).code}); '
        'ending the session locally anyway.',
      );
    }

    await _tokens.clear();
    await _prefs.clearSessionScoped();

    if (mounted) {
      state = const AsyncValue<Session?>.data(null);
    }

    // Tells every feature provider to drop its cache, so the next account never
    // sees the previous one's documents.
    _ref.read(sessionSignalProvider.notifier).signOutHappened();
  }

  /// Re-fetches `GET /me`, e.g. after a purchase or a profile edit changes
  /// something the rest of the app renders.
  Future<void> refreshSession() => loadSession(force: true);

  /// Restores a usable state after a failed sign-in attempt.
  ///
  /// If the token pair was already written before the failure — a network drop
  /// between `POST /auth/login` and `GET /me` — the session is real and the
  /// error belongs on screen with a retry. Otherwise the user is simply still
  /// signed out.
  void _recoverFrom(Object error, StackTrace stack) {
    if (!mounted) {
      return;
    }
    state = _tokens.hasSession
        ? AsyncValue<Session?>.error(ApiException.from(error), stack)
        : const AsyncValue<Session?>.data(null);
  }

  void _handleSessionLost() {
    if (mounted) {
      state = const AsyncValue<Session?>.data(null);
    }
    unawaited(_prefs.clearSessionScoped());
  }

  /// Registers this installation. Failure is logged and swallowed: push
  /// registration is not worth failing a sign-in over.
  Future<void> _touchDevice() async {
    try {
      await _repo.registerDevice(locale: _prefs.locale);
    } catch (error) {
      Log.warn('Device registration failed: ${ApiException.from(error).code}');
    }
  }
}

final StateNotifierProvider<AuthController, AsyncValue<Session?>>
    authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<Session?>>(
  (Ref ref) => AuthController(ref),
);

/// The current session, or null when signed out or still loading.
///
/// `valueOrNull` rather than `value`: the latter rethrows the stored error when
/// the controller is in its error state, which would turn "the session failed
/// to load" into an exception inside every widget that only wanted the plan.
final Provider<Session?> sessionProvider = Provider<Session?>(
  (Ref ref) => ref.watch(authControllerProvider).valueOrNull,
);

final Provider<AppUser?> currentUserProvider =
    Provider<AppUser?>((Ref ref) => ref.watch(sessionProvider)?.user);

final Provider<Entitlement?> entitlementProvider =
    Provider<Entitlement?>((Ref ref) => ref.watch(sessionProvider)?.entitlement);
