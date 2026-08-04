/// Application-wide dependency injection.
///
/// Riverpod without codegen: every provider here is declared by hand, so a
/// fresh clone runs with `flutter pub get && flutter run` and no build step.
///
/// [bootstrapProvider] is overridden in `main.dart` with the values resolved
/// during startup, which is what lets the rest of the tree read them
/// synchronously instead of every screen awaiting a future.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'network/token_store.dart';
import 'storage/prefs.dart';
import 'storage/secure_store.dart';

/// Everything resolved once at startup and then treated as constant.
class Bootstrap {
  const Bootstrap({
    required this.prefs,
    required this.secureStore,
    required this.tokenStore,
    required this.identity,
  });

  final Prefs prefs;
  final SecureStore secureStore;
  final TokenStore tokenStore;
  final ClientIdentity identity;
}

/// Overridden in `main.dart`. Reading it before the override is a programming
/// error, and the thrown message says so rather than failing mysteriously later.
final Provider<Bootstrap> bootstrapProvider = Provider<Bootstrap>(
  (Ref ref) => throw StateError(
    'bootstrapProvider must be overridden in ProviderScope at app start.',
  ),
);

final Provider<Prefs> prefsProvider =
    Provider<Prefs>((Ref ref) => ref.watch(bootstrapProvider).prefs);

final Provider<SecureStore> secureStoreProvider =
    Provider<SecureStore>((Ref ref) => ref.watch(bootstrapProvider).secureStore);

final Provider<TokenStore> tokenStoreProvider =
    Provider<TokenStore>((Ref ref) => ref.watch(bootstrapProvider).tokenStore);

final Provider<ClientIdentity> clientIdentityProvider =
    Provider<ClientIdentity>((Ref ref) => ref.watch(bootstrapProvider).identity);

/// Raised when the session ends for any reason — an expired refresh token, a
/// revoked device, or the user tapping sign out. The router listens and sends
/// the user to the welcome screen; feature providers listen and drop cached
/// data so the next account never sees the previous one's documents.
class SessionSignal extends StateNotifier<int> {
  SessionSignal() : super(0);

  /// Bumping an int is enough — listeners only care that *something* changed.
  void signOutHappened() => state = state + 1;
}

final StateNotifierProvider<SessionSignal, int> sessionSignalProvider =
    StateNotifierProvider<SessionSignal, int>((Ref ref) => SessionSignal());

/// The configured HTTP client. Created once and kept for the process lifetime
/// so dio's connection pool is reused.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final TokenStore tokens = ref.watch(tokenStoreProvider);
  final ClientIdentity identity = ref.watch(clientIdentityProvider);

  return ApiClient(
    tokens: tokens,
    identity: identity,
    onSessionLost: () async {
      await tokens.clear();
      ref.read(sessionSignalProvider.notifier).signOutHappened();
    },
  );
});

/// Live connectivity. Used only to decide whether to show the offline banner
/// and whether a retry is worth attempting — never to gate a request, because
/// "has an interface" and "can reach the server" are different questions.
final StreamProvider<bool> connectivityProvider = StreamProvider<bool>((Ref ref) {
  return Connectivity().onConnectivityChanged.map(
        (List<ConnectivityResult> results) =>
            results.any((ConnectivityResult r) => r != ConnectivityResult.none),
      );
});

final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  // Assume online until proven otherwise; a false negative on first frame
  // would show an offline banner over perfectly good data.
  return ref.watch(connectivityProvider).maybeWhen(
        data: (bool online) => online,
        orElse: () => true,
      );
});
