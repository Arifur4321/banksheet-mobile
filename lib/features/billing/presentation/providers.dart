/// State for the billing screen.
///
/// Four providers, and the split between them matters:
///
///  * [billingSnapshotProvider] is what the server says the workspace holds. It
///    is the authority on the plan and on whether a purchase is even allowed.
///  * [purchaseServiceProvider] owns the store connection for the life of the
///    app. It is created once, disposed with `ref.onDispose`, and never rebuilt
///    on a screen change — a store listener that comes and goes drops the
///    receipt that arrives in between.
///  * [storeProductsProvider] is what the store says things cost, looked up for
///    exactly the product ids the server offers.
///  * [purchaseControllerProvider] is the small state machine the UI renders.
///
/// The controller never grants anything. It reacts to what [PurchaseService]
/// reports, and on a grant it re-reads `GET /me` and `GET /billing` so the plan
/// on screen is the plan the server wrote.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/logger.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/billing_repository.dart';
import '../data/purchase_service.dart';
import '../domain/plan_offer.dart';

/// `GET /billing`. Re-fetched when the session changes, because the whole
/// payload belongs to a workspace.
final FutureProvider<BillingSnapshot> billingSnapshotProvider =
    FutureProvider<BillingSnapshot>((Ref ref) {
  ref.watch(sessionSignalProvider);
  return ref.watch(billingRepositoryProvider).snapshot();
});

/// The store connection. One per app run.
final Provider<PurchaseService> purchaseServiceProvider =
    Provider<PurchaseService>((Ref ref) {
  final PurchaseService service = PurchaseService(
    InAppPurchase.instance,
    ref.watch(billingRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Whether this device can buy anything at all, resolved once.
///
/// Also the provider that drains a purchase left unfinished by a previous run,
/// because [PurchaseService.init] does that as part of connecting.
final FutureProvider<bool> storeAvailableProvider =
    FutureProvider<bool>((Ref ref) => ref.watch(purchaseServiceProvider).init());

/// Live prices for every product the server offers.
///
/// Depends on the snapshot rather than on the ids baked into `AppConfig`, so
/// the app asks for exactly what the server is willing to grant — including the
/// yearly products once `mobile.iap.yearly_enabled` is switched on, with no new
/// binary.
final FutureProvider<StoreProducts> storeProductsProvider =
    FutureProvider<StoreProducts>((Ref ref) async {
  final bool available = await ref.watch(storeAvailableProvider.future);
  if (!available) {
    return const StoreProducts();
  }

  final BillingSnapshot snapshot =
      await ref.watch(billingSnapshotProvider.future);

  return ref.watch(purchaseServiceProvider).loadProducts(snapshot.productIds);
});

/// Where the purchase flow is, as the screen needs to render it.
enum PurchaseStage {
  idle,

  /// Asking the store for prices.
  loadingProducts,

  /// The store sheet is up. The app is a bystander.
  purchasing,

  /// The receipt is with the server. This is the blocking one.
  verifying,

  /// Verified and granted.
  success,

  /// Nothing was granted. [PurchaseState.error] says why.
  failed,
}

@immutable
class PurchaseState {
  const PurchaseState({
    this.stage = PurchaseStage.idle,
    this.productId,
    this.grantedPlanName,
    this.error,
    this.willRetry = false,
    this.isRestoring = false,
    this.restoredCount,
    this.restoreFailures = const <RestoreFailure>[],
    this.cancelled = false,
    this.deferred = false,
  });

  final PurchaseStage stage;

  /// The product the current stage is about.
  final String? productId;

  /// Set on success, for the "X is active" sheet.
  final String? grantedPlanName;

  final ApiException? error;

  /// True when the transaction was left in the store queue on purpose and the
  /// next launch will finish it.
  final bool willRetry;

  final bool isRestoring;

  /// Set once a restore has finished. Null means "no restore has run".
  final int? restoredCount;
  final List<RestoreFailure> restoreFailures;

  /// The user backed out of the store sheet. Not an error.
  final bool cancelled;

  /// The store is waiting on someone else — Ask to Buy, or a slow payment.
  final bool deferred;

  /// The screen blocks the whole page on this.
  bool get isVerifying => stage == PurchaseStage.verifying;

  bool get isBusy =>
      stage == PurchaseStage.purchasing ||
      stage == PurchaseStage.verifying ||
      isRestoring;

  PurchaseState copyWith({
    PurchaseStage? stage,
    String? productId,
    String? grantedPlanName,
    ApiException? error,
    bool? willRetry,
    bool? isRestoring,
    int? restoredCount,
    List<RestoreFailure>? restoreFailures,
    bool? cancelled,
    bool? deferred,
    bool clearError = false,
    bool clearProduct = false,
    bool clearRestore = false,
  }) {
    return PurchaseState(
      stage: stage ?? this.stage,
      productId: clearProduct ? null : (productId ?? this.productId),
      grantedPlanName: grantedPlanName ?? this.grantedPlanName,
      error: clearError ? null : (error ?? this.error),
      willRetry: willRetry ?? this.willRetry,
      isRestoring: isRestoring ?? this.isRestoring,
      restoredCount: clearRestore ? null : (restoredCount ?? this.restoredCount),
      restoreFailures: clearRestore
          ? const <RestoreFailure>[]
          : (restoreFailures ?? this.restoreFailures),
      cancelled: cancelled ?? this.cancelled,
      deferred: deferred ?? this.deferred,
    );
  }
}

/// Drives a purchase and reflects what the store and the server report.
///
/// It deliberately owns no entitlement logic: a plan is granted by the server
/// and read back from it, so the only thing this class does on success is
/// refresh the session and invalidate the snapshot.
class PurchaseController extends StateNotifier<PurchaseState> {
  PurchaseController(this._ref, this._service) : super(const PurchaseState()) {
    _subscription = _service.events.listen(_onEvent);

    // The buy buttons must not be tappable before the store has quoted a
    // price, so the product lookup is part of this state machine rather than
    // something the screen has to remember to check separately.
    _ref.listen<AsyncValue<StoreProducts>>(
      storeProductsProvider,
      (AsyncValue<StoreProducts>? _, AsyncValue<StoreProducts> next) {
        if (!mounted) {
          return;
        }
        if (state.stage != PurchaseStage.idle &&
            state.stage != PurchaseStage.loadingProducts) {
          return;
        }
        state = state.copyWith(
          stage: next.isLoading
              ? PurchaseStage.loadingProducts
              : PurchaseStage.idle,
        );
      },
      fireImmediately: true,
    );

    unawaited(_service.init());
  }

  final Ref _ref;
  final PurchaseService _service;

  StreamSubscription<PurchaseFlowEvent>? _subscription;

  /// Buys [product]. Everything after the store sheet opens arrives on the
  /// event stream and lands in [state].
  Future<void> buy(ProductDetails product) async {
    if (state.isBusy) {
      Log.warn('Billing: buy ignored, the controller is already busy.');
      return;
    }

    state = state.copyWith(
      stage: PurchaseStage.purchasing,
      productId: product.id,
      clearError: true,
      cancelled: false,
      deferred: false,
      willRetry: false,
    );

    final bool started = await _service.buy(
      product,
      accountIdentifier: _accountIdentifier(),
    );

    if (!mounted) {
      return;
    }

    if (!started && state.stage == PurchaseStage.purchasing) {
      // The store refused to open the sheet and will send no event, so this is
      // the only place that can unstick the UI.
      state = state.copyWith(stage: PurchaseStage.idle, clearProduct: true);
    }
  }

  /// Guideline 3.1.1. Sends whatever the store still owns to the server.
  Future<void> restore() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      isRestoring: true,
      clearError: true,
      clearRestore: true,
      cancelled: false,
      deferred: false,
    );
    await _service.restore();
  }

  /// Clears a finished outcome so the screen can be used again.
  void acknowledge() {
    state = const PurchaseState();
  }

  void _onEvent(PurchaseFlowEvent event) {
    if (!mounted) {
      return;
    }

    switch (event) {
      case PurchaseVerifying(:final String productId):
        state = state.copyWith(
          stage: PurchaseStage.verifying,
          productId: productId,
          clearError: true,
        );

      case PurchaseGranted(
          :final String productId,
          :final BillingSnapshot snapshot,
        ):
        state = state.copyWith(
          stage: PurchaseStage.success,
          productId: productId,
          grantedPlanName: snapshot.planName,
          isRestoring: false,
          clearError: true,
        );
        unawaited(_refreshEntitlement());

      case PurchaseCancelled(:final String? productId):
        Log.info('Billing: purchase cancelled ($productId).');
        state = state.copyWith(
          stage: PurchaseStage.idle,
          cancelled: true,
          clearProduct: true,
          clearError: true,
        );

      case PurchaseDeferred(:final String productId):
        state = state.copyWith(
          stage: PurchaseStage.idle,
          productId: productId,
          deferred: true,
          clearError: true,
        );

      case PurchaseFailed(
          :final ApiException error,
          :final bool willRetry,
          :final String? productId,
        ):
        state = state.copyWith(
          stage: PurchaseStage.failed,
          productId: productId,
          error: error,
          willRetry: willRetry,
          isRestoring: false,
        );

      case RestoreFinished(
          :final int restoredCount,
          :final List<RestoreFailure> failures,
          :final ApiException? error,
        ):
        state = state.copyWith(
          stage: error == null ? PurchaseStage.idle : PurchaseStage.failed,
          isRestoring: false,
          restoredCount: restoredCount,
          restoreFailures: failures,
          error: error,
          clearError: error == null,
          willRetry: false,
        );
        if (restoredCount > 0) {
          unawaited(_refreshEntitlement());
        }
    }
  }

  /// The plan lives on the server. After a grant, read it back from there
  /// rather than assuming what was bought — a proration, an upgrade or a
  /// concurrent web change all land in the same answer.
  Future<void> _refreshEntitlement() async {
    try {
      await _ref.read(authControllerProvider.notifier).refreshSession();
    } catch (error) {
      Log.warn(
        'Billing: the session refresh after a purchase failed '
        '(${ApiException.from(error).code}); the plan is granted regardless.',
      );
    }
    _ref.invalidate(billingSnapshotProvider);
  }

  /// An opaque handle for the workspace, used as StoreKit's
  /// `applicationUsername`. It carries no email, no name and nothing Apple can
  /// read as personal data, and it is not sent on Android at all.
  String? _accountIdentifier() {
    final Session? session = _ref.read(sessionProvider);
    if (session == null) {
      return null;
    }
    return 'bsm-u${session.user.id}-w${session.workspace.id}';
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}

final StateNotifierProvider<PurchaseController, PurchaseState>
    purchaseControllerProvider =
    StateNotifierProvider<PurchaseController, PurchaseState>(
  (Ref ref) => PurchaseController(ref, ref.watch(purchaseServiceProvider)),
);
