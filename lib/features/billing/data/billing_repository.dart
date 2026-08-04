/// The four billing calls, and nothing else.
///
/// The client never grants an entitlement. It sends what the store gave it and
/// takes the server's answer as the truth: `StoreSubscriptionService` verifies
/// the receipt with Apple or Google, and `PlanCatalog::applyToCompany()` writes
/// the plan — the same column and the same function Stripe writes through. That
/// is why a subscription bought on the phone is honoured on banksheet.pro with
/// no second implementation of entitlement anywhere.
///
/// Every method answers with a fresh [BillingSnapshot], because every one of
/// these endpoints returns the full billing picture. Nothing here needs to
/// reason about what changed.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../domain/plan_offer.dart';

class BillingRepository {
  const BillingRepository(this._api);

  final ApiClient _api;

  /// `GET /billing`.
  Future<BillingSnapshot> snapshot({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.billing,
      cancelToken: cancelToken,
    );
    return BillingSnapshot.fromJson(json);
  }

  /// `POST /billing/purchases/apple`.
  ///
  /// [signedTransactionInfo] is StoreKit 2's JWS, forwarded untouched — the
  /// server re-verifies the signature against Apple's pinned root, so anything
  /// this client "cleaned up" would only break the proof.
  Future<BillingSnapshot> purchaseApple(String signedTransactionInfo) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.purchaseApple,
      body: <String, dynamic>{
        'signed_transaction_info': signedTransactionInfo,
      },
    );
    return BillingSnapshot.fromJson(json);
  }

  /// `POST /billing/purchases/google`.
  ///
  /// [productId] is what this build believes was bought; `GooglePlayVerifier`
  /// checks it against what Play actually says before anything is granted, so a
  /// wrong value is refused rather than believed.
  Future<BillingSnapshot> purchaseGoogle(
    String purchaseToken,
    String productId,
  ) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.purchaseGoogle,
      body: <String, dynamic>{
        'purchase_token': purchaseToken,
        'product_id': productId,
      },
    );
    return BillingSnapshot.fromJson(json);
  }

  /// `POST /billing/purchases/restore`.
  ///
  /// Both arrays are optional and are only sent when they carry something: the
  /// server validates `google.*.purchase_token` with `required_with:google`, so
  /// an empty array is accepted but pointless, and sending neither would be a
  /// request that cannot restore anything.
  ///
  /// The response reports per-receipt failures in `failures` instead of failing
  /// the whole call, which is what stops one stale receipt from blocking a
  /// legitimate restore of the others.
  Future<BillingSnapshot> restore({
    List<String> apple = const <String>[],
    List<Map<String, String>> google = const <Map<String, String>>[],
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.restorePurchases,
      body: <String, dynamic>{
        if (apple.isNotEmpty) 'apple': apple,
        if (google.isNotEmpty) 'google': google,
      },
    );
    return BillingSnapshot.fromJson(json);
  }
}

final Provider<BillingRepository> billingRepositoryProvider =
    Provider<BillingRepository>(
  (Ref ref) => BillingRepository(ref.watch(apiClientProvider)),
);
