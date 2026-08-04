/// One extracted statement row, as both the document detail and the review
/// queue render it.
///
/// Same fixed-height contract as the document card: a statement can be two
/// thousand rows, so the lists that show these are built with `itemExtent` and
/// [extentFor] has to answer before layout. Everything inside is single-line and
/// the extent grows with the text scale.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/transaction.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.transaction,
    required this.onTap,
    super.key,
    this.showDocument = false,
  });

  final ExtractedTransaction transaction;
  final VoidCallback onTap;

  /// True on the cross-document queue, where a row has to say which statement
  /// it came from.
  final bool showDocument;

  static double extentFor(BuildContext context, {bool showDocument = false}) {
    final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final double base = showDocument ? 116 : 96;
    return base + (scale.clamp(1.0, 2.4) - 1.0) * (showDocument ? 76 : 58);
  }

  @override
  Widget build(BuildContext context) {
    final double? amount = transaction.signedAmount;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      semanticLabel: '${transaction.displayDescription}, '
          '${Fmt.money(amount, currency: transaction.currency, signed: true)}, '
          '${transaction.reviewStatus.label}',
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      Fmt.isoDate(transaction.transactionDate).isEmpty
                          ? '—'
                          : Fmt.isoDate(transaction.transactionDate),
                      style: AppText.caption.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: ReviewStatusPill(status: transaction.reviewStatus),
                    ),
                    if (transaction.isSuspicious) ...<Widget>[
                      const SizedBox(width: 6),
                      ConfidenceChip(level: transaction.confidence),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.displayDescription,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showDocument) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '${S.fromDocument} '
                    '${Fmt.middleEllipsis(transaction.document?.displayName ?? S.untitledDocument, max: 28)}',
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fmt.money(amount, currency: transaction.currency, signed: true),
                style: AppText.numeric.copyWith(
                  fontSize: 14,
                  color: amount == null
                      ? AppColors.inkFaint
                      : (transaction.isCredit
                          ? AppColors.brandDeep
                          : AppColors.ink),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Text(
                transaction.balance == null
                    ? '—'
                    : Fmt.money(
                        transaction.balance,
                        currency: transaction.currency,
                      ),
                style: AppText.caption,
                maxLines: 1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The review state, as a pill. Colours come from [ReviewStatus] so the queue,
/// the detail list and the edit sheet cannot drift apart.
class ReviewStatusPill extends StatelessWidget {
  const ReviewStatusPill({required this.status, super.key});

  final ReviewStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, size: 11, color: status.foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: AppText.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: status.foreground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// How sure the extractor was about a row.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({required this.level, super.key, this.showLabel = false});

  final ConfidenceLevel level;

  /// Off in a dense list, where the colour alone is the signal and the label is
  /// carried by the semantics; on in the edit sheet, where there is room.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${S.confidence}: ${level.label}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 8 : 5,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: level.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: level.foreground.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              size: 11,
              color: level.foreground,
            ),
            if (showLabel) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                level.label,
                style: AppText.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: level.foreground,
                ),
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
