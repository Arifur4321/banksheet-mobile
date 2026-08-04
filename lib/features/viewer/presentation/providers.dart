/// Reader state.
///
/// Small on purpose: the viewer holds a list of recent files and a guest usage
/// snapshot, and nothing else. Everything expensive — the rendered document —
/// belongs to the screen's own controller so it is disposed the moment the
/// route pops, rather than living in a provider that outlives it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/local_db.dart';
import '../data/recent_files_repository.dart';

final Provider<RecentFilesRepository> recentFilesRepositoryProvider =
    Provider<RecentFilesRepository>(
  (Ref ref) => RecentFilesRepository(ref.watch(localDbProvider)),
);

/// The reader's history. Auto-disposed so returning to the tab re-checks which
/// files still exist on disk rather than trusting a list built minutes ago.
final FutureProvider<List<RecentFile>> recentFilesProvider =
    FutureProvider<List<RecentFile>>((Ref ref) {
  // Sign-out wipes the database; depending on the signal here means the list
  // rebuilds empty instead of showing the previous account's filenames until
  // something else happens to refresh it.
  ref.watch(sessionSignalProvider);
  return ref.watch(recentFilesRepositoryProvider).load();
});

/// What a signed-out user has spent this month, per meter.
///
/// Advisory only — see the note in [LocalDb]. It exists so the paywall arrives
/// as "you have used 10 of 10 free conversions" rather than as a login screen
/// with no explanation.
final FutureProviderFamily<int, GuestMeter> guestUsageProvider =
    FutureProvider.family<int, GuestMeter>(
  (Ref ref, GuestMeter meter) => ref.watch(localDbProvider).guestUsed(meter),
);
