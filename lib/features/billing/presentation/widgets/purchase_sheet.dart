/// The two sheets that bracket a purchase, plus the one link opener the
/// billing feature uses.
///
/// [showPurchaseSheet] is an App Store review gate, not decoration. Guideline
/// 3.1.2 requires the title of the subscription, its length, its price, what it
/// buys, a statement that it auto-renews, and reachable Terms and Privacy links
/// — all of them visible in the app before the payment sheet appears. A
/// subscription screen missing any one of them is rejected, and the rejection
/// says exactly that.
///
/// The price is always [ProductDetails.price]: the localised string the store
/// itself will charge. The website's euro figure is never shown next to a buy
/// button, because Apple's and Google's price tiers do not land on €20 and €79
/// and showing one number while charging another is both a rejection and a lie.
///
/// [showPurchaseSuccessSheet] closes the loop the product owner asked for: the
/// plan is live on this phone *and* on banksheet.pro, because the server wrote
/// it through the same `PlanCatalog::applyToCompany()` that Stripe writes
/// through.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/plan_offer.dart';

/// Opens an external URL, and says so quietly if the device cannot.
///
/// Every outbound link in the billing feature goes through here: the legal
/// links below, the store's subscription settings, and the Enterprise contact
/// page. A failure to open a browser is not worth an error dialog over a link
/// the user can still reach on the website, so it is an info toast.
Future<void> openBillingLink(BuildContext context, String url) async {
  final Uri? uri = Uri.tryParse(url);

  if (uri == null) {
    Log.warn('Billing: refusing to open a malformed URL — $url');
    return;
  }

  bool opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error) {
    // A device with no browser, or a scheme the platform refuses — the
    // itms-apps:// deep link on a phone without the App Store, for instance.
    Log.warn('Billing: could not open $url — $error');
  }

  if (!context.mounted || opened) {
    return;
  }
  Log.warn('Billing: the platform declined to open $url');
  Toast.info(context, S.couldNotOpenLink);
}

/// Everything guideline 3.1.2 wants on screen, then a single confirm.
///
/// Returns true only when the user explicitly continues, so
/// `if (await showPurchaseSheet(...))` is always safe.
Future<bool> showPurchaseSheet(
  BuildContext context, {
  required PlanOffer offer,
  required ProductDetails product,
  String? termsUrl,
  String? privacyUrl,
}) async {
  final bool? confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 1. What is being bought.
            Text(offer.name, style: AppText.h2),
            const SizedBox(height: AppSpacing.xs),
            // 2. How long it lasts.
            Text(offer.periodLabel, style: AppText.bodySm),

            const SizedBox(height: AppSpacing.lg),

            // 3. What the store will actually charge.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(product.price, style: AppText.display),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(offer.periodLabel.toLowerCase(), style: AppText.bodySm),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(S.priceFromStore, style: AppText.caption),

            const SizedBox(height: AppSpacing.xl),

            // 4. What it includes — the store's own approved description, so
            // the app cannot describe a plan differently from the listing the
            // reviewer reads.
            Text(S.planIncludes, style: AppText.bodyStrong),
            const SizedBox(height: AppSpacing.xs),
            Text(
              product.description.trim().isEmpty
                  ? S.planBenefitsFromStore
                  : product.description,
              style: AppText.bodySm,
            ),

            const SizedBox(height: AppSpacing.xl),

            // 5. That it renews by itself until cancelled.
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.controlAll,
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.autorenew_rounded,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(S.autoRenewNotice, style: AppText.bodySm),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // 6. Terms and Privacy, tappable.
            _LegalLinks(termsUrl: termsUrl, privacyUrl: privacyUrl),

            const SizedBox(height: AppSpacing.xxl),

            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text(S.confirmPurchase),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    ),
  );

  return confirmed ?? false;
}

/// Confirms, in as many words, that the plan is live in both places.
Future<void> showPurchaseSuccessSheet(
  BuildContext context, {
  required String planName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  color: AppColors.brandTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 34,
                  color: AppColors.brandDeep,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              S.planActiveNow(planName),
              style: AppText.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              S.purchaseActiveEverywhere,
              style: AppText.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text(S.done),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The Terms and Privacy row.
///
/// The URLs come from the server (`config('mobile.urls.*')`) when it sent them,
/// and fall back to the build's own constants so the links are never dead —
/// which is exactly the failure a reviewer taps on.
class _LegalLinks extends StatefulWidget {
  const _LegalLinks({this.termsUrl, this.privacyUrl});

  final String? termsUrl;
  final String? privacyUrl;

  @override
  State<_LegalLinks> createState() => _LegalLinksState();
}

class _LegalLinksState extends State<_LegalLinks> {
  /// Recognisers hold a long-lived gesture arena entry; they leak if they are
  /// not disposed, so they are built once and torn down with the widget.
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => _open(widget.termsUrl ?? AppConfig.termsUrl);

  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => _open(widget.privacyUrl ?? AppConfig.privacyUrl);

  void _open(String url) {
    if (!mounted) {
      return;
    }
    unawaited(openBillingLink(context, url));
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle link = AppText.bodySm.copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.brandDark,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(S.legalAgree, style: AppText.caption),
        const SizedBox(height: AppSpacing.xs),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: S.termsLink, style: link, recognizer: _terms),
              const TextSpan(text: '   ·   ', style: AppText.bodySm),
              TextSpan(text: S.privacyLink, style: link, recognizer: _privacy),
            ],
          ),
        ),
      ],
    );
  }
}
