/// The home screen's provider.
///
/// Watching [sessionSignalProvider] is what makes signing out drop the cached
/// dashboard: the signal changes, this future is recreated, and the next
/// account cannot be shown the previous one's counters for even one frame.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_data.dart';

final FutureProvider<DashboardData> dashboardProvider =
    FutureProvider<DashboardData>((Ref ref) async {
  ref.watch(sessionSignalProvider);

  return ref.watch(dashboardRepositoryProvider).load();
});
