/// What the workspace holds right now: the plan, who is billing for it, when it
/// renews, and every allowance with how much of it is left.
///
/// The source badge is not decoration. A customer who cannot tell whether they
/// are billed by Apple, by Google or by card on the website cannot find the
/// place to cancel, and both stores require that the app makes that reachable.
/// The renewal row changes its own label for the same reason: after a
/// cancellation the date is the last day of access, not the next charge, and
/// calling it "Renews" is how a support ticket starts.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../auth/domain/session.dart';
import '../../domain/plan_offer.dart';

class CurrentPlanCard extends StatelessWidget {
  const CurrentPlanCard({required this.snapshot, super.key});

  final BillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final List<UsageLine> lines = snapshot.usageLines;
    final int? storageMb = snapshot.storageLimitMb;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.currentPlan.toUpperCase(), style: AppText.eyebrow),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(snapshot.planName, style: AppText.display)),
              _SourceBadge(snapshot: snapshot),
            ],
          ),

          if (snapshot.isPastDue) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const InlineNotice(
              message: S.subscriptionPastDue,
              tone: NoticeTone.warn,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          if (snapshot.renewsAt != null)
            _MetaRow(
              icon: snapshot.autoRenewing == false
                  ? Icons.event_busy_rounded
                  : Icons.autorenew_rounded,
              label: snapshot.renewalLabel,
              value: Fmt.date(snapshot.renewsAt),
            ),

          if (snapshot.autoRenewing != null)
            _MetaRow(
              icon: Icons.repeat_rounded,
              label: snapshot.autoRenewing! ? S.autoRenewOn : S.autoRenewOff,
              value: '',
            ),

          if (snapshot.usagePeriodEndsAt != null)
            _MetaRow(
              icon: Icons.refresh_rounded,
              label: S.allowanceResets,
              value: Fmt.date(snapshot.usagePeriodEndsAt),
            ),

          if (storageMb != null && storageMb > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              S.storageIncluded(Fmt.bytes(storageMb * 1024 * 1024)),
              style: AppText.caption,
            ),
          ],

          if (lines.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Text(S.usageThisMonth, style: AppText.bodyStrong),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < lines.length; i++) ...<Widget>[
              UsageMeter(
                label: lines[i].label,
                used: lines[i].used,
                limit: lines[i].limit,
              ),
              if (i < lines.length - 1) const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ),
    );
  }
}

/// App Store / Google Play / banksheet.pro / Free plan.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.snapshot});

  final BillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background, IconData icon) =
        switch (snapshot.entitlement.source) {
      Entitlement.sourceApple => (
          AppColors.ink,
          AppColors.surfaceMuted,
          Icons.apple_rounded,
        ),
      Entitlement.sourceGoogle => (
          AppColors.info,
          AppColors.infoTint,
          Icons.shop_rounded,
        ),
      Entitlement.sourceStripe => (
          AppColors.brandDeep,
          AppColors.brandTint,
          Icons.language_rounded,
        ),
      _ => (AppColors.inkMuted, AppColors.surfaceMuted, Icons.card_giftcard_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            snapshot.sourceLabel,
            style: AppText.caption.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One icon + label + value line under the plan name.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.inkFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppText.bodySm)),
          if (value.isNotEmpty)
            Text(value, style: AppText.numeric.copyWith(fontSize: 13.5)),
        ],
      ),
    );
  }
}
