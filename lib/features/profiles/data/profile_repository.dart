/// Extraction profiles: list, detail and toggle.
///
/// Authoring a profile is a desktop job — it is a regex editor with a PDF sample
/// beside it — so the app does exactly what the server offers: read one to
/// answer "why did this statement parse badly?", and switch it off when it
/// starts matching the wrong bank.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/extraction_profile.dart';

class ProfileRepository {
  const ProfileRepository(this._api);

  final ApiClient _api;

  Future<Paged<ExtractionProfile>> list({
    int page = 1,
    bool activeOnly = false,
    String? documentType,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.extractionProfiles,
      query: <String, dynamic>{
        'page': page,
        'active_only': activeOnly ? 1 : null,
        'document_type': documentType,
      },
      cancelToken: cancelToken,
    );

    return Paged<ExtractionProfile>.fromJson(json, ExtractionProfile.fromJson);
  }

  /// The full profile, including the four rule blobs the list omits.
  Future<ExtractionProfile> detail(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.extractionProfile(id),
      cancelToken: cancelToken,
    );
    return ExtractionProfile.fromJson(_unwrap(json));
  }

  /// Flips `is_active` and returns the profile the server ended up with.
  ///
  /// A toggle rather than a PATCH carrying the next state, because two clients
  /// computing that state from a possibly stale copy is how a profile ends up
  /// in the state nobody asked for. The response is authoritative — the caller
  /// should adopt it rather than assume its optimistic guess was right.
  Future<ExtractionProfile> toggle(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.patch(
      Endpoints.extractionProfileToggle(id),
      cancelToken: cancelToken,
    );
    return ExtractionProfile.fromJson(_unwrap(json));
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> keyed = J.map(json['profile']);
    if (keyed.isNotEmpty) {
      return keyed;
    }
    final Map<String, dynamic> data = J.map(json['data']);
    return data.isEmpty ? json : data;
  }
}

final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
  (Ref ref) => ProfileRepository(ref.watch(apiClientProvider)),
);
