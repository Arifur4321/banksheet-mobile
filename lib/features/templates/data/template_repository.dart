/// Templates: list, detail, and generating a PDF from one.
///
/// Editing a template is not offered — it is an HTML editor — but filling one
/// in is the single most useful thing this feature can do from a phone.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/generated_pdf.dart';
import '../domain/template.dart';

class TemplateRepository {
  const TemplateRepository(this._api);

  final ApiClient _api;

  Future<Paged<Template>> list({
    int page = 1,
    String? type,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.templates,
      query: <String, dynamic>{'page': page, 'type': type},
      cancelToken: cancelToken,
    );

    return Paged<Template>.fromJson(json, Template.fromJson);
  }

  /// The full template, including the HTML the list omits.
  Future<Template> detail(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.template(id),
      cancelToken: cancelToken,
    );
    return Template.fromJson(_unwrap(json, 'template'));
  }

  /// Renders the template and stores the PDF.
  ///
  /// [title] is not optional: `TemplateController::generate()` validates it as
  /// `required|string|max:255` and uses it for both the row and the download
  /// filename. [variables] is keyed by [TemplateVariable.name]; a variable the
  /// caller omits is sent as an empty string by the server, which is what an
  /// unfilled optional field means.
  Future<GeneratedPdf> generate(
    int id, {
    required String title,
    required Map<String, String> variables,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.templateGenerate(id),
      body: <String, dynamic>{
        'title': title,
        'variables': variables,
      },
      cancelToken: cancelToken,
    );

    return GeneratedPdf.fromJson(_unwrap(json, 'generated_pdf'));
  }

  /// Single-object responses are `{"<key>": {...}}`, but the contract also
  /// allows `{"data": {...}}` and the bare object — all three are handled so a
  /// server-side envelope change cannot break the screen.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> json, String key) {
    final Map<String, dynamic> keyed = J.map(json[key]);
    if (keyed.isNotEmpty) {
      return keyed;
    }
    final Map<String, dynamic> data = J.map(json['data']);
    return data.isEmpty ? json : data;
  }
}

final Provider<TemplateRepository> templateRepositoryProvider =
    Provider<TemplateRepository>(
  (Ref ref) => TemplateRepository(ref.watch(apiClientProvider)),
);
