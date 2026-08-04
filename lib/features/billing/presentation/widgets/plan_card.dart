/// One purchasable plan.
///
/// The price on this card is always the store's own localised string. The
/// server publishes a euro figure for the website, and it is deliberately not
/// rendered here: Apple's and Google's price tiers do not land exactly on €20
/// and €79, and a card that advertises one number while the payment sheet
/// charges another is a guideline 2.3.1 rejection and a support ticket.
///
/// A plan whose product the store did not return still appears, greyed, saying
/// so. Silently dropping it would make an unfinished store console look like a
/// product decision.
library;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/plan_offer.dart';

class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.offer,
    required this.product,
    super.key,
    this.onBuy,
    this.isBusy = false,
  });

  final PlanOffer offer;

  /// What the store says this plan costs, or null when the store did not
  /// recognise the product id.
  final ProductDetails? product;

  /// Null when buying is not offered — the workspace already holds this plan,
  /// or it is billed on the website.
  final VoidCallback? onBuy;

  /// A purchase is already running; every buy button is inert until it ends.
  final bool isBusy;

  bool get _canBuy => onBuy != null && product != null && !isBusy;

  @override
  Widget build(BuildContext context) {
    final ProductDetails? details = product;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(offer.name, style: AppText.h2)),
              if (offer.isCurrent) const _CurrentChip(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (details == null)
            const Text(S.planNotInStore, style: AppText.bodySm)
          else ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(details.price, style: AppText.statValue),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(offer.periodLabel, style: AppText.bodySm),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(S.priceFromStore, style: AppText.caption),
            if (details.description.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(details.description, style: AppText.bodySm),
            ],
          ],

          if (onBuy != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canBuy ? onBuy : null,
                child: Text(S.getPlan(offer.name)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Your plan" — the badge on the tier the workspace already holds.
class _CurrentChip extends StatelessWidget {
  const _CurrentChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brandTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.brandTintStrong),
      ),
      child: Text(
        S.currentPlanChip,
        style: AppText.caption.copyWith(
          color: AppColors.brandDeep,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
