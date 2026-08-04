/// The store integration: the only file in the app that talks to StoreKit or
/// Play Billing.
///
/// The rule the whole design hangs on: **a purchase is a claim, not an
/// entitlement.** The store tells this class that money moved; the server tells
/// it whether the workspace may have the plan. So a transaction is finished
/// with `completePurchase()` only after `POST /billing/purchases/*` has
/// answered 200, or after the server has said something that will never become
/// a 200 no matter how often it is asked. Anything else — a 500, a timeout, a
/// flight-mode tunnel — leaves the transaction in the store's queue, where the
/// store will hand it back on the next launch and this class will try again.
/// Getting that backwards is how a customer pays and receives nothing.
///
/// Three failure modes this file exists to prevent:
///
///  * **The killed-app purchase.** A transaction that completed while the app
///    was not running arrives on the next launch. [init] subscribes to
///    `purchaseStream` before anything else can consume it, and asks Play for
///    anything still unfinished; StoreKit re-delivers unfinished transactions
///    to the observer on its own.
///  * **The immortal receipt.** A receipt the server will always reject
///    (`purchase_invalid`, `purchase_already_claimed`, `subscription_conflict`)
///    is finished anyway, or it is re-delivered on every launch forever.
///  * **The lost sale.** A network failure never finishes a transaction.
///
/// The event stream is the only way state leaves this class, so the controller
/// above it cannot reach into the queue and finish something itself.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/logger.dart';
import '../domain/plan_offer.dart';
import 'billing_repository.dart';

/// What to do with a receipt the server has just answered about.
enum ReceiptDisposition {
  /// Verified and granted. Finish the transaction.
  granted,

  /// The server will never accept this receipt. Finish the transaction anyway —
  /// an unfinished one is re-delivered on every launch for the life of the
  /// install — and tell the user why.
  rejected,

  /// A temporary failure. Leave the transaction in the queue so the next launch
  /// retries it. The customer has paid; the plan is owed to them.
  retryLater,
}

/// Server answers that mean "this receipt is finished, and the answer is no".
///
/// Everything else — 5xx, 401, 429, offline, timeout — is temporary by
/// assumption. Being wrong in that direction costs one extra request on the
/// next launch; being wrong in the other direction costs a paying customer
/// their plan.
const Set<String> _terminalCodes = <String>{
  // The store receipt itself was rejected by Apple or Google.
  'purchase_invalid',
  // Already bound to a different workspace. Re-sending cannot change that.
  'purchase_already_claimed',
  // A live Stripe subscription on the website already covers this workspace.
  'subscription_conflict',
  // The body did not pass validation. The same body will never pass either.
  'validation_failed',
};

/// Everything [PurchaseService] tells the layer above it.
@immutable
sealed class PurchaseFlowEvent {
  const PurchaseFlowEvent();
}

/// The receipt is on its way to the server. The UI blocks here.
class PurchaseVerifying extends PurchaseFlowEvent {
  const PurchaseVerifying(this.productId);

  final String productId;
}

/// The server verified the receipt and wrote the plan.
class PurchaseGranted extends PurchaseFlowEvent {
  const PurchaseGranted({
    required this.productId,
    required this.snapshot,
    required this.wasRestored,
  });

  final String productId;
  final BillingSnapshot snapshot;

  /// True when this came from a restore rather than a fresh purchase.
  final bool wasRestored;
}

/// The user backed out of the store sheet. Not an error, and never a red toast.
class PurchaseCancelled extends PurchaseFlowEvent {
  const PurchaseCancelled(this.productId);

  final String? productId;
}

/// The store is waiting on something — Ask to Buy, or a Play payment method
/// that settles later. Nothing is owed yet and nothing has been granted.
class PurchaseDeferred extends PurchaseFlowEvent {
  const PurchaseDeferred(this.productId);

  final String productId;
}

/// The purchase did not complete.
class PurchaseFailed extends PurchaseFlowEvent {
  const PurchaseFailed({
    required this.error,
    required this.willRetry,
    this.productId,
  });

  final String? productId;
  final ApiException error;

  /// True when the transaction was deliberately left in the store queue and
  /// will be presented again on the next launch.
  final bool willRetry;
}

/// A user-initiated restore finished, successfully or not.
class RestoreFinished extends PurchaseFlowEvent {
  const RestoreFinished({
    required this.restoredCount,
    this.snapshot,
    this.failures = const <RestoreFailure>[],
    this.error,
  });

  /// How many receipts the server actually accepted.
  final int restoredCount;

  final BillingSnapshot? snapshot;

  /// Receipts the server refused, one entry each.
  final List<RestoreFailure> failures;

  /// Set when the restore call itself failed, rather than individual receipts.
  final ApiException? error;

  bool get isEmpty => restoredCount == 0 && failures.isEmpty && error == null;
}

/// The answer to [PurchaseService.loadProducts].
@immutable
class StoreProducts {
  const StoreProducts({
    this.details = const <String, ProductDetails>{},
    this.notFoundIds = const <String>[],
    this.error,
  });

  /// Product id => what the store says it costs, in the user's own currency.
  final Map<String, ProductDetails> details;

  /// Ids the store did not recognise. Reported rather than swallowed: silently
  /// showing fewer plans than the server offers looks like a pricing decision
  /// and is actually a misconfigured store console.
  final List<String> notFoundIds;

  /// A store-level failure, if the query itself went wrong.
  final String? error;

  bool get isEmpty => details.isEmpty;

  ProductDetails? operator [](String? id) => id == null ? null : details[id];

  bool get hasGaps => notFoundIds.isNotEmpty || error != null;
}

class PurchaseService {
  PurchaseService(this._iap, this._billing);

  final InAppPurchase _iap;
  final BillingRepository _billing;

  final StreamController<PurchaseFlowEvent> _events =
      StreamController<PurchaseFlowEvent>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Receipts are handled one at a time. Two arriving together — a purchase and
  /// a restore in the same tick — would otherwise race for the same workspace
  /// and produce two POSTs the server has to de-duplicate.
  Future<void> _queue = Future<void>.value();

  bool _initialised = false;
  bool _available = false;

  /// Set while a user-initiated restore is gathering receipts, so they are
  /// batched into one call instead of posted one by one.
  bool _restoring = false;
  final List<PurchaseDetails> _restoreBatch = <PurchaseDetails>[];
  Timer? _restoreQuietTimer;
  Completer<void>? _restoreSettled;

  /// The product currently being bought, used to refuse a second tap.
  String? _inFlightProductId;

  /// How long a restore waits for the store to hand over everything it has.
  static const Duration restoreWindow = Duration(seconds: 8);

  /// How long the restore gather waits after the last receipt before deciding
  /// the store has finished talking.
  static const Duration restoreQuietPeriod = Duration(milliseconds: 900);

  Stream<PurchaseFlowEvent> get events => _events.stream;

  /// False when the device cannot buy anything: no store, a restricted profile,
  /// or a parental control. The screen renders a notice instead of dead buttons.
  bool get isAvailable => _available;

  bool get isPurchasing => _inFlightProductId != null;

  // ---------------------------------------------------------------- lifecycle

  /// Connects to the store and drains anything already queued.
  ///
  /// Safe to call repeatedly; only the first call does work. Returns whether
  /// purchases are possible on this device.
  Future<bool> init() async {
    if (_initialised) {
      return _available;
    }
    _initialised = true;

    try {
      _available = await _iap.isAvailable();
    } catch (error, stack) {
      Log.error('Billing: the store could not be reached.', error, stack);
      _available = false;
      return false;
    }

    if (!_available) {
      Log.warn('Billing: in-app purchase is unavailable on this device.');
      return false;
    }

    // Listen before anything else. On iOS this is what attaches the payment
    // queue observer, and StoreKit immediately replays every transaction that
    // was left unfinished — including one that completed while the app was
    // killed, which is the classic "user paid, got nothing" bug.
    _subscription = _iap.purchaseStream.listen(
      _onPurchasesUpdated,
      onError: (Object error, StackTrace stack) {
        Log.error('Billing: the purchase stream failed.', error, stack);
      },
      onDone: () => Log.info('Billing: the purchase stream closed.'),
    );

    Log.info('Billing: store connected, listening for purchases.');

    unawaited(_drainQueuedPurchases());

    return true;
  }

  /// Asks the store for anything still owed to this device.
  ///
  /// Android only, and deliberately so. Play Billing has no observer that
  /// replays unfinished purchases, so the queue has to be asked for; StoreKit
  /// replays them on its own the moment [init] listens, and calling
  /// `restorePurchases()` at launch on iOS can put an App Store sign-in prompt
  /// in front of a user who never asked for one.
  Future<void> _drainQueuedPurchases() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      Log.debug('Billing: asking Play for unfinished purchases.');
      await _iap.restorePurchases();
    } catch (error, stack) {
      // Nothing is owed to the user by this call failing; the next launch, or
      // an explicit Restore, tries again.
      Log.error('Billing: could not query Play for past purchases.', error, stack);
    }
  }

  /// Cancels the stream subscription and stops accepting events.
  void dispose() {
    _restoreQuietTimer?.cancel();
    _restoreQuietTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_events.close());
    Log.debug('Billing: purchase service disposed.');
  }

  // ----------------------------------------------------------------- products

  /// Looks up live prices for [ids].
  ///
  /// Anything the store does not know about comes back in
  /// [StoreProducts.notFoundIds] rather than being dropped: a plan missing from
  /// the purchase screen is a store console that has not been finished, and the
  /// operator has to be able to see that from the app.
  Future<StoreProducts> loadProducts(Set<String> ids) async {
    if (ids.isEmpty) {
      return const StoreProducts();
    }
    if (!_available) {
      Log.warn('Billing: product lookup skipped, the store is unavailable.');
      return const StoreProducts();
    }

    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        Log.warn(
          'Billing: the store returned an error for a product query — '
          '${response.error!.code}: ${response.error!.message}',
        );
      }
      if (response.notFoundIDs.isNotEmpty) {
        Log.warn(
          'Billing: the store does not know these products — '
          '${response.notFoundIDs.join(', ')}. Check the store console: they '
          'are declared on the server.',
        );
      }

      Log.info(
        'Billing: loaded ${response.productDetails.length} of ${ids.length} '
        'products from the store.',
      );

      return StoreProducts(
        details: <String, ProductDetails>{
          for (final ProductDetails product in response.productDetails)
            product.id: product,
        },
        notFoundIds: response.notFoundIDs,
        error: response.error?.message,
      );
    } catch (error, stack) {
      Log.error('Billing: the product query threw.', error, stack);
      return StoreProducts(error: error.toString());
    }
  }

  // ---------------------------------------------------------------- purchasing

  /// Starts a subscription purchase.
  ///
  /// [accountIdentifier] is an opaque, non-personal handle for the signed-in
  /// workspace. It is sent on iOS only — see the comment on the call below.
  ///
  /// Returns false when the store refused to open the sheet at all. Everything
  /// after that arrives on [events].
  Future<bool> buy(
    ProductDetails product, {
    String? accountIdentifier,
  }) async {
    if (!_available) {
      Log.warn('Billing: buy(${product.id}) refused, the store is unavailable.');
      _emit(
        const PurchaseFailed(
          error: ApiException(
            code: 'store_unavailable',
            message: 'This device cannot reach the store.',
          ),
          willRetry: false,
        ),
      );
      return false;
    }

    if (_inFlightProductId != null) {
      Log.warn(
        'Billing: buy(${product.id}) refused, $_inFlightProductId is already '
        'in flight.',
      );
      return false;
    }

    _inFlightProductId = product.id;

    final PurchaseParam parameters = PurchaseParam(
      productDetails: product,
      // iOS only, on purpose. Apple stamps this onto the transaction and it
      // lets support tie an order id back to a workspace without asking Apple
      // for anything personal. On Android the plugin turns it into Play's
      // obfuscatedAccountId — and this server reads no such field: GooglePlay
      // Verifier matches on the purchase token alone, and BillingController
      // takes the workspace from the bearer token on the request. Sending an
      // identifier there would invent a contract nothing on the other side
      // honours, and would put a workspace handle into Google's records for no
      // benefit.
      applicationUserName: Platform.isIOS ? accountIdentifier : null,
    );

    try {
      // Subscriptions are non-consumable on both stores: they are owned until
      // they lapse, never consumed and re-bought.
      final bool started = await _iap.buyNonConsumable(purchaseParam: parameters);

      if (!started) {
        Log.warn('Billing: the store refused to start ${product.id}.');
        _inFlightProductId = null;
      } else {
        Log.info('Billing: purchase sheet opened for ${product.id}.');
      }

      return started;
    } catch (error, stack) {
      Log.error('Billing: buy(${product.id}) threw.', error, stack);
      _inFlightProductId = null;
      _emit(
        PurchaseFailed(
          productId: product.id,
          error: ApiException(
            code: 'store_unavailable',
            message: error.toString(),
          ),
          willRetry: false,
        ),
      );
      return false;
    }
  }

  /// Guideline 3.1.1: a visible, working Restore action.
  ///
  /// Asks the store for everything this account owns, batches what arrives into
  /// one call to `POST /billing/purchases/restore`, and finishes those
  /// transactions only if the server accepted the batch or told us it never
  /// will.
  Future<void> restore() async {
    if (!_available) {
      Log.warn('Billing: restore refused, the store is unavailable.');
      _emit(
        const RestoreFinished(
          restoredCount: 0,
          error: ApiException(
            code: 'store_unavailable',
            message: 'This device cannot reach the store.',
          ),
        ),
      );
      return;
    }

    if (_restoring) {
      Log.debug('Billing: a restore is already running.');
      return;
    }

    Log.info('Billing: restore started.');

    _restoring = true;
    _restoreBatch.clear();

    try {
      await _iap.restorePurchases();
      await _waitForRestoreToSettle();
    } catch (error, stack) {
      Log.error('Billing: restorePurchases() threw.', error, stack);
      _finishRestoreGathering();
      _emit(
        RestoreFinished(
          restoredCount: 0,
          error: ApiException.from(error),
        ),
      );
      return;
    }

    final List<PurchaseDetails> batch =
        List<PurchaseDetails>.unmodifiable(_restoreBatch);
    _finishRestoreGathering();

    if (batch.isEmpty) {
      Log.info('Billing: the store returned no previous purchases.');
      _emit(const RestoreFinished(restoredCount: 0));
      return;
    }

    await _submitRestoreBatch(batch);
  }

  Future<void> _submitRestoreBatch(List<PurchaseDetails> batch) async {
    final bool apple = Platform.isIOS || Platform.isMacOS;

    final List<String> appleReceipts = <String>[
      if (apple)
        for (final PurchaseDetails detail in batch)
          if (detail.verificationData.serverVerificationData.isNotEmpty)
            detail.verificationData.serverVerificationData,
    ];

    final List<Map<String, String>> googleReceipts = <Map<String, String>>[
      if (!apple)
        for (final PurchaseDetails detail in batch)
          if (detail.verificationData.serverVerificationData.isNotEmpty)
            <String, String>{
              'purchase_token': detail.verificationData.serverVerificationData,
              'product_id': detail.productID,
            },
    ];

    if (appleReceipts.isEmpty && googleReceipts.isEmpty) {
      Log.warn('Billing: every restored receipt was empty.');
      _emit(const RestoreFinished(restoredCount: 0));
      return;
    }

    Log.info(
      'Billing: sending ${appleReceipts.length + googleReceipts.length} '
      'receipts to the restore endpoint.',
    );

    try {
      final BillingSnapshot snapshot = await _billing.restore(
        apple: appleReceipts,
        google: googleReceipts,
      );

      // The batch was accepted as a request, whatever it concluded per receipt,
      // so nothing in it will produce a different answer later.
      await _completeAll(batch);

      Log.info(
        'Billing: restore accepted ${snapshot.restoredCount} receipts, '
        '${snapshot.restoreFailures.length} refused.',
      );

      _emit(
        RestoreFinished(
          restoredCount: snapshot.restoredCount,
          snapshot: snapshot,
          failures: snapshot.restoreFailures,
        ),
      );
    } catch (error, stack) {
      final ApiException failure = ApiException.from(error);
      final ReceiptDisposition disposition = dispositionFor(failure);

      Log.error(
        'Billing: the restore call failed (${failure.code}, '
        'disposition ${disposition.name}).',
        error,
        stack,
      );

      if (disposition == ReceiptDisposition.rejected) {
        await _completeAll(batch);
      }

      _emit(RestoreFinished(restoredCount: 0, error: failure));
    }
  }

  // ------------------------------------------------------------ stream plumbing

  void _onPurchasesUpdated(List<PurchaseDetails> purchases) {
    for (final PurchaseDetails detail in purchases) {
      // Serialised rather than fired in parallel: two receipts landing in the
      // same tick must not produce two overlapping POSTs for one workspace.
      _queue = _queue.then((_) => _handle(detail)).catchError(
        (Object error, StackTrace stack) {
          Log.error('Billing: unhandled failure in the receipt queue.', error, stack);
        },
      );
    }
  }

  Future<void> _handle(PurchaseDetails detail) async {
    Log.debug(
      'Billing: ${detail.productID} → ${detail.status.name} '
      '(pendingComplete: ${detail.pendingCompletePurchase})',
    );

    switch (detail.status) {
      case PurchaseStatus.pending:
        // Ask to Buy, or a Play payment method that settles later. Nothing has
        // been paid and nothing may be finished. The in-flight lock is released
        // because a deferral can last days and must not wedge the buy button.
        Log.info('Billing: ${detail.productID} is pending at the store.');
        _clearInFlight(detail.productID);
        _emit(PurchaseDeferred(detail.productID));

      case PurchaseStatus.canceled:
        // A cancellation is a decision, not a failure. It still has to be
        // finished or StoreKit re-delivers it on every launch.
        Log.info('Billing: ${detail.productID} was cancelled by the user.');
        _clearInFlight(detail.productID);
        await _completeIfPending(detail);
        _emit(PurchaseCancelled(detail.productID));

      case PurchaseStatus.error:
        final IAPError? storeError = detail.error;
        Log.warn(
          'Billing: the store reported an error for ${detail.productID} — '
          '${storeError?.code}: ${storeError?.message}',
        );
        _clearInFlight(detail.productID);
        await _completeIfPending(detail);
        _emit(
          PurchaseFailed(
            productId: detail.productID,
            error: ApiException(
              code: 'store_unavailable',
              message: storeError?.message ?? 'The store could not complete the purchase.',
            ),
            // The store already gave up on this transaction; there is nothing
            // left in the queue to retry.
            willRetry: false,
          ),
        );

      case PurchaseStatus.restored:
        if (_restoring) {
          _restoreBatch.add(detail);
          _armRestoreQuietTimer();
          Log.debug(
            'Billing: batched a restored receipt for ${detail.productID}.',
          );
          return;
        }

        // A restored receipt arriving outside an explicit Restore is the store
        // handing back something it still considers unfinished — the killed-app
        // case. One that is already settled needs no work and must not cost a
        // verification round trip on every single launch.
        if (!detail.pendingCompletePurchase) {
          Log.debug(
            'Billing: ignoring an already-settled receipt for '
            '${detail.productID}.',
          );
          return;
        }
        await _claim(detail, wasRestored: true);

      case PurchaseStatus.purchased:
        await _claim(detail, wasRestored: false);
    }
  }

  /// Sends one receipt to the server and decides what happens to the
  /// transaction based on the answer. The only place that grants anything.
  Future<void> _claim(PurchaseDetails detail, {required bool wasRestored}) async {
    final String receipt = detail.verificationData.serverVerificationData;

    if (receipt.isEmpty) {
      // Nothing to verify with. Finishing it is the only way to stop the store
      // presenting it again on every launch.
      Log.warn('Billing: ${detail.productID} arrived with no receipt data.');
      _clearInFlight(detail.productID);
      await _completeIfPending(detail);
      _emit(
        PurchaseFailed(
          productId: detail.productID,
          error: const ApiException(
            code: 'purchase_invalid',
            message: 'The store did not provide a receipt for this purchase.',
          ),
          willRetry: false,
        ),
      );
      return;
    }

    final bool apple = Platform.isIOS || Platform.isMacOS;

    if (apple && !_looksLikeJws(receipt)) {
      // StoreKit 1 hands back a base64 app receipt; the server verifies a
      // StoreKit 2 JWS and will refuse it. Still sent — the server is the
      // authority, never this client — but the log says exactly what is wrong.
      Log.warn(
        'Billing: the iOS receipt is not a JWS. This build is running '
        'StoreKit 1; the server verifies StoreKit 2 signed transactions. See '
        'features/billing/IAP-CLIENT.md.',
      );
    }

    Log.info('Billing: verifying ${detail.productID} with the server.');
    _emit(PurchaseVerifying(detail.productID));

    try {
      final BillingSnapshot snapshot = apple
          ? await _billing.purchaseApple(receipt)
          : await _billing.purchaseGoogle(receipt, detail.productID);

      // Only now. The plan is written on the server, the website already sees
      // it, and finishing the transaction can no longer lose anything.
      await _completeIfPending(detail);
      _clearInFlight(detail.productID);

      Log.info(
        'Billing: ${detail.productID} granted — plan is now '
        '${snapshot.planKey} via ${snapshot.entitlement.source}.',
      );

      _emit(
        PurchaseGranted(
          productId: detail.productID,
          snapshot: snapshot,
          wasRestored: wasRestored,
        ),
      );
    } catch (error, stack) {
      final ApiException failure = ApiException.from(error);
      final ReceiptDisposition disposition = dispositionFor(failure);

      Log.error(
        'Billing: ${detail.productID} was refused (${failure.code}, '
        'disposition ${disposition.name}).',
        error,
        stack,
      );

      _clearInFlight(detail.productID);

      if (disposition == ReceiptDisposition.rejected) {
        await _completeIfPending(detail);
      } else {
        Log.warn(
          'Billing: leaving ${detail.productID} unfinished; the store will '
          'present it again on the next launch.',
        );
      }

      _emit(
        PurchaseFailed(
          productId: detail.productID,
          error: failure,
          willRetry: disposition == ReceiptDisposition.retryLater,
        ),
      );
    }
  }

  /// The decision table, as one pure function so it can be tested without a
  /// store, a server or a widget.
  static ReceiptDisposition dispositionFor(Object error) {
    final ApiException failure = ApiException.from(error);

    if (_terminalCodes.contains(failure.code)) {
      return ReceiptDisposition.rejected;
    }

    // Everything else is treated as temporary on purpose, including 401 (the
    // session expired mid-purchase and the receipt is still good) and 503
    // store_unavailable (Apple or Google was unreachable *from the server*).
    return ReceiptDisposition.retryLater;
  }

  /// Whether a disposition finishes the store transaction.
  static bool completesTransaction(ReceiptDisposition disposition) =>
      disposition != ReceiptDisposition.retryLater;

  // ------------------------------------------------------------------ helpers

  Future<void> _completeIfPending(PurchaseDetails detail) async {
    if (!detail.pendingCompletePurchase) {
      return;
    }
    try {
      await _iap.completePurchase(detail);
      Log.debug('Billing: finished the transaction for ${detail.productID}.');
    } catch (error, stack) {
      // The plan is already granted server-side, so this is a bookkeeping
      // failure: the store will present the transaction again and the next
      // pass will finish it.
      Log.error(
        'Billing: completePurchase(${detail.productID}) threw.',
        error,
        stack,
      );
    }
  }

  Future<void> _completeAll(List<PurchaseDetails> batch) async {
    for (final PurchaseDetails detail in batch) {
      await _completeIfPending(detail);
    }
  }

  void _clearInFlight(String productId) {
    if (_inFlightProductId == productId) {
      _inFlightProductId = null;
    }
  }

  /// Waits for the store to stop handing over restored receipts: a quiet period
  /// after the last arrival, capped by [restoreWindow] so a store that never
  /// answers cannot hang the button forever.
  Future<void> _waitForRestoreToSettle() {
    final Completer<void> settled = Completer<void>();
    _restoreSettled = settled;
    _armRestoreQuietTimer();

    return settled.future.timeout(
      restoreWindow,
      onTimeout: () {
        Log.warn('Billing: the restore window closed before the store settled.');
      },
    );
  }

  void _armRestoreQuietTimer() {
    _restoreQuietTimer?.cancel();
    _restoreQuietTimer = Timer(restoreQuietPeriod, () {
      final Completer<void>? settled = _restoreSettled;
      if (settled != null && !settled.isCompleted) {
        settled.complete();
      }
    });
  }

  void _finishRestoreGathering() {
    _restoring = false;
    _restoreBatch.clear();
    _restoreQuietTimer?.cancel();
    _restoreQuietTimer = null;
    _restoreSettled = null;
  }

  /// A StoreKit 2 signed transaction is a JWS: three base64url segments.
  static bool _looksLikeJws(String value) {
    final List<String> segments = value.split('.');
    return segments.length == 3 && segments.every((String s) => s.isNotEmpty);
  }

  void _emit(PurchaseFlowEvent event) {
    if (_events.isClosed) {
      return;
    }
    _events.add(event);
  }
}
