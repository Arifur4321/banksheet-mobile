/// The two transaction calls: the cross-document review queue and the row edit.
///
/// `PATCH /transactions/{id}` is the only write in the product that a reviewer
/// performs dozens of times in a row, so it returns the updated row rather than
/// an acknowledgement — the queue swaps the row in place instead of re-fetching
/// a page after every approval.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/transaction.dart';

class TransactionRepository {
  const TransactionRepository(this._api);

  final ApiClient _api;

  /// The queue. [reviewStatus] defaults server-side to `pending_review`; pass
  /// `all` to drop the filter entirely, which is the server's own escape hatch.
  Future<Paged<ExtractedTransaction>> list({
    int page = 1,
    String? reviewStatus,
    int? documentId,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.transactions,
      query: <String, dynamic>{
        'page': page,
        'review_status': reviewStatus,
        'document_id': documentId,
      },
      cancelToken: cancelToken,
    );

    return Paged<ExtractedTransaction>.fromJson(
      json,
      ExtractedTransaction.fromJson,
    );
  }

  /// Edit and/or decide a row.
  ///
  /// The server recomputes `amount_signed` from the final debit and credit and
  /// mirrors the decision onto the generic `ExtractedRecord` the export writer
  /// reads, so the response — not the local guess — is what the UI keeps.
  Future<ExtractedTransaction> update(
    int id,
    TransactionEdit fields, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.patch(
      Endpoints.transaction(id),
      body: fields.toJson(),
      cancelToken: cancelToken,
    );

    final Map<String, dynamic> row = J.map(json['transaction']);
    return ExtractedTransaction.fromJson(row.isEmpty ? json : row);
  }
}

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>(
  (Ref ref) => TransactionRepository(ref.watch(apiClientProvider)),
);
