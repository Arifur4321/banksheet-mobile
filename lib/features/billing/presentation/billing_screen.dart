/// Plan and billing.
///
/// The screen the product owner asked for in one sentence: "use in app purchase
/// so if any user pay by app then the same user do not need to pay in website
/// using stripe... every month should auto renew if user do not cancel."
///
/// Both halves of that are enforced on the server and merely respected here:
///
///  * A workspace with a live Stripe subscription gets `can_purchase: false`
///    and `POST /billing/purchases/*` answers 409 `subscription_conflict`. This
///    screen hides every buy button in that state, so the double charge is not
///    even offered. The opposite guard exists too — the website refuses a
///    Stripe subscription while a store subscription is live.
///  * Renewal is the store's job. Nothing in the app renews anything; the
///    subscription auto-renews until the customer cancels it in their store
///    account, which is what the "Manage subscription" row leads to and what
///    `S.autoRenewNotice` says in as many words.
///
/// Prices come from the store, never from the plan catalogue. The server sends
/// a euro figure for the website; Apple's and Google's tiers do not land on it,
/// and showing one number while charging another fails review.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../auth/domain/session.dart';
import '../data/purchase_service.dart';
import '../domain/plan_offer.dart';
import 'providers.dart';
import 'widgets/current_plan_card.dart';
import 'widgets/plan_card.dart';
import 'widgets/purchase_sheet.dart';
import 'widgets/restore_button.dart';
import 'widgets/store_unavailable_notice.dart';
import 'widgets/verifying_overlay.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  static const EdgeInsets _gutter = EdgeInsets.fromLTRB(
    AppSpacing.page,
    0,
    AppSpacing.page,
    AppSpacing.lg,
  );

  @override
  void initState() {
    super.initState();
    // Reading the controller connects to the store and drains anything the
    // store still owes this device — a purchase that completed while the app
    // was killed arrives here, not in a callback nobody is listening to.
    ref.read(purchaseControllerProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(storeProductsProvider);
    try {
      // invalidate + read rather than refresh(): identical behaviour, and it
      // does not return a result the analyzer then insists we consume.
      ref.invalidate(billingSnapshotProvider);
      await ref.read(billingSnapshotProvider.future);
    } catch (error) {
      // The provider already holds the failure and ErrorState renders it;
      // letting it out of onRefresh would only break the indicator.
      Log.warn('Billing: refresh failed — ${ApiException.from(error).code}');
    }
  }

  /// Guideline 3.1.2 wants everything about the subscription on screen before
  /// the payment sheet, so the confirm step is a sheet of its own rather than
  /// an immediate hand-off to the store.
  Future<void> _startPurchase(
    BillingSnapshot snapshot,
    PlanOffer offer,
    ProductDetails product,
  ) async {
    Log.info('Billing: purchase requested for ${product.id} (${offer.key}).');

    final bool confirmed = await showPurchaseSheet(
      context,
      offer: offer,
      product: product,
      termsUrl: snapshot.termsUrl,
      privacyUrl: snapshot.privacyUrl,
    );

    if (!context.mounted) {
      return;
    }
    if (!confirmed) {
      Log.info('Billing: the user backed out before the store sheet.');
      return;
    }

    await ref.read(purchaseControllerProvider.notifier).buy(product);
  }

  void _onPurchaseChanged(PurchaseState? previous, PurchaseState next) {
    if (!mounted) {
      return;
    }

    // A cancellation is a decision, not a failure — no red toast, ever.
    if (next.cancelled && previous?.cancelled != true) {
      Toast.info(context, S.purchaseCancelled);
    }

    if (next.deferred && previous?.deferred != true) {
      Toast.info(context, S.purchasePending);
    }

    if (next.stage == PurchaseStage.failed &&
        previous?.stage != PurchaseStage.failed) {
      final ApiException? failure = next.error;
      if (failure != null) {
        Toast.error(context, failure);
      }
    }

    if (next.stage == PurchaseStage.success &&
        previous?.stage != PurchaseStage.success) {
      unawaited(_confirmSuccess(next.grantedPlanName));
    }
  }

  /// The session and the snapshot are refreshed by the controller the moment
  /// the server grants; this only tells the user, and says the thing that
  /// matters — the plan is live here *and* on the website.
  Future<void> _confirmSuccess(String? planName) async {
    await showPurchaseSuccessSheet(
      context,
      planName: planName ?? S.currentPlan,
    );
    if (!mounted) {
      return;
    }
    ref.read(purchaseControllerProvider.notifier).acknowledge();
  }

  /// Where the customer cancels or changes the subscription.
  ///
  /// iOS uses the https universal link, which opens the App Store app's
  /// subscription page and still works on a device that cannot handle
  /// `itms-apps://`. Android prefers the server's URL because only the server
  /// knows the package name, and with it Play deep-links straight to this
  /// subscription instead of the whole list.
  String _manageUrl(BillingSnapshot snapshot) {
    if (snapshot.entitlement.source == Entitlement.sourceApple) {
      return AppConfig.appleManageUrl;
    }
    final String? fromServer = snapshot.manageUrl;
    return (fromServer == null || fromServer.isEmpty)
        ? AppConfig.googleManageUrl
        : fromServer;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PurchaseState>(purchaseControllerProvider, _onPurchaseChanged);

    final AsyncValue<BillingSnapshot> snapshot =
        ref.watch(billingSnapshotProvider);
    final PurchaseState purchase = ref.watch(purchaseControllerProvider);

    return Stack(
      children: <Widget>[
        HeroPageScaffold(
          onRefresh: _refresh,
          slivers: <Widget>[
            const SliverAppBar(
              floating: true,
              toolbarHeight: 52,
              titleSpacing: AppSpacing.lg,
              title: Text(S.billing),
            ),
            SliverPadding(
              padding: _gutter,
              sliver: SliverToBoxAdapter(
                child: HeroPanel(
                  eyebrow: S.billing,
                  title: S.billingHeroTitle,
                  scene: const BillingScene(),
                  subtitle: snapshot.valueOrNull?.planName,
                ),
              ),
            ),
            ...snapshot.when(
              loading: () => const <Widget>[
                SliverToBoxAdapter(child: SkeletonList(count: 3, height: 140)),
              ],
              error: (Object error, StackTrace _) => <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(billingSnapshotProvider),
                  ),
                ),
              ],
              data: (BillingSnapshot value) => _sections(value, purchase),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.section),
            ),
          ],
        ),
        // Non-dismissible on purpose: between the charge and the grant there is
        // nowhere useful for the user to go.
        if (purchase.isVerifying) const VerifyingOverlay(),
      ],
    );
  }

  List<Widget> _sections(BillingSnapshot snapshot, PurchaseState purchase) {
    final AsyncValue<StoreProducts> products = ref.watch(storeProductsProvider);
    final AsyncValue<bool> available = ref.watch(storeAvailableProvider);

    final StoreProducts catalogue = products.valueOrNull ?? const StoreProducts();
    final bool storeReady = available.valueOrNull ?? false;
    final PlanOffer? enterprise = snapshot.contactOffer;

    return <Widget>[
      _card(CurrentPlanCard(snapshot: snapshot)),

      // A receipt the server could not be told about yet. The transaction is
      // still in the store's queue and the next launch retries it, which is the
      // one thing the user needs to know.
      if (purchase.willRetry && purchase.stage == PurchaseStage.failed)
        _card(
          const InlineNotice(
            message: S.purchaseWillRetry,
            tone: NoticeTone.warn,
          ),
        ),

      if (snapshot.isManagedOnWeb)
        // The double-billing guard. The server refuses a purchase here anyway;
        // offering one would be offering a second charge for the same plan.
        _card(const _ManagedOnWebCard())
      else ...<Widget>[
        if (snapshot.isStoreManaged)
          _card(
            _ManageSubscriptionCard(
              onManage: () => unawaited(
                openBillingLink(context, _manageUrl(snapshot)),
              ),
            ),
          ),

        if (!storeReady && !available.isLoading)
          _card(const StoreUnavailableNotice())
        else ...<Widget>[
          _header(S.choosePlan, S.choosePlanBody),

          if (products.isLoading)
            _card(const _PriceSkeleton())
          else ...<Widget>[
            if (catalogue.hasGaps)
              _card(
                StoreProductsIncompleteNotice(
                  onRetry: () => ref.invalidate(storeProductsProvider),
                ),
              ),
            for (final PlanOffer offer in snapshot.buyableOffers)
              _card(
                PlanCard(
                  offer: offer,
                  product: catalogue[offer.preferredProductId],
                  isBusy: purchase.isBusy,
                  onBuy: () {
                    final ProductDetails? product =
                        catalogue[offer.preferredProductId];
                    if (product == null) {
                      return;
                    }
                    unawaited(_startPurchase(snapshot, offer, product));
                  },
                ),
              ),
          ],

          // Everything guideline 3.1.2 wants readable on the page that presents
          // the subscription, not only inside the confirm sheet.
          _card(_SubscriptionTerms(snapshot: snapshot)),
        ],
      ],

      if (enterprise != null) _card(_EnterpriseCard(offer: enterprise)),

      // Guideline 3.1.1. Hidden only for a workspace billed by card on the
      // website, where the server answers every restore with 409
      // subscription_conflict and the button could never do anything.
      if (storeReady && !snapshot.isManagedOnWeb) _card(const RestoreButton()),
    ];
  }

  Widget _card(Widget child) =>
      SliverPadding(padding: _gutter, sliver: SliverToBoxAdapter(child: child));

  Widget _header(String title, String subtitle) => SliverPadding(
        padding: _gutter,
        sliver: SliverToBoxAdapter(
          child: SectionHeader(title: title, subtitle: subtitle),
        ),
      );
}

/// Billed by card on banksheet.pro: say so, and sell nothing.
class _ManagedOnWebCard extends StatelessWidget {
  const _ManagedOnWebCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.brandTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.language_rounded,
                  size: 20,
                  color: AppColors.brandDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(S.managedOnWeb, style: AppText.h3)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(S.managedOnWebBody, style: AppText.bodySm),
        ],
      ),
    );
  }
}

/// Where a store subscription is cancelled or changed. Required by both stores,
/// and impossible to do from inside the app — only the store holds the payment
/// method.
class _ManageSubscriptionCard extends StatelessWidget {
  const _ManageSubscriptionCard({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.managedByStore, style: AppText.h3),
          const SizedBox(height: AppSpacing.xs),
          const Text(S.manageSubscriptionBody, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text(S.manageSubscription),
            ),
          ),
        ],
      ),
    );
  }
}

/// Enterprise: a real plan with nothing to sell in the app.
///
/// No price and no purchase link. Guideline 3.1.1 forbids sending a user to an
/// external purchase flow, so this is a conversation, not a checkout.
class _EnterpriseCard extends StatelessWidget {
  const _EnterpriseCard({required this.offer});

  final PlanOffer offer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.inkStrong,
      borderColor: AppColors.forestSoft,
      shadow: AppShadows.lifted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            offer.name.toUpperCase(),
            style: AppText.eyebrow.copyWith(color: AppColors.brandLight),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.enterpriseTitle,
            style: AppText.h3.copyWith(color: AppColors.inkInverse),
          ),
          const SizedBox(height: 6),
          Text(
            S.enterpriseBody,
            style: AppText.bodySm.copyWith(
              color: AppColors.inkInverse.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => unawaited(
                openBillingLink(context, AppConfig.supportUrl),
              ),
              child: const Text(S.talkToUs),
            ),
          ),
        ],
      ),
    );
  }
}

/// The renewal statement and the legal links, on the page itself.
class _SubscriptionTerms extends StatelessWidget {
  const _SubscriptionTerms({required this.snapshot});

  final BillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(S.autoRenewNotice, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              _LegalLink(
                label: S.termsLink,
                url: snapshot.termsUrl ?? AppConfig.termsUrl,
              ),
              const SizedBox(width: AppSpacing.lg),
              _LegalLink(
                label: S.privacyLink,
                url: snapshot.privacyUrl ?? AppConfig.privacyUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => unawaited(openBillingLink(context, url)),
      borderRadius: AppRadius.smallAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: AppText.bodySm.copyWith(
            color: AppColors.brandDark,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.brandDark,
          ),
        ),
      ),
    );
  }
}

/// Placeholder for a plan card while the store is quoting a price. Prices are
/// never guessed, so there is nothing else to show in the meantime.
class _PriceSkeleton extends StatelessWidget {
  const _PriceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Skeleton(width: 120, height: 20),
          SizedBox(height: AppSpacing.md),
          Skeleton(width: 90, height: 26),
          SizedBox(height: AppSpacing.sm),
          Skeleton(width: 200, height: 12),
          SizedBox(height: AppSpacing.xl),
          Skeleton(height: 44, radius: AppRadius.control),
        ],
      ),
    );
  }
}
