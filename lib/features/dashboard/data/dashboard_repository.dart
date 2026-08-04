/// Reads `GET /dashboard`.
///
/// One endpoint, one call, one model. The controller bundles thirteen counters
/// and the five newest documents into a single response precisely so the home
/// screen costs one round trip on a phone connection, and this repository keeps
/// it that way — nothing here fans out into extra requests.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../domain/dashboard_data.dart';

class DashboardRepository {
  const DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardData> load() async {
    final Map<String, dynamic> response = await _api.get(Endpoints.dashboard);
    return DashboardData.fromJson(response);
  }
}

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>(
  (Ref ref) => DashboardRepository(ref.watch(apiClientProvider)),
);
