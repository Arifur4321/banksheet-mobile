/// One row in the documents list.
///
/// Deliberately a fixed height. The list is the screen users live in and it can
/// run to hundreds of rows, so it is built with `itemExtent` — which requires
/// the height to be known before the row is laid out. [extentFor] is that
/// height, and it grows with the user's text scale so the card cannot overflow
/// at 200%; every line inside is capped at one line for the same reason.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/document.dart';

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    required this.document,
    required this.onTap,
    super.key,
  });

  final DocumentSummary document;
  final VoidCallback onTap;

  /// The card's height at the current text scale.
  static double extentFor(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return 112 + (scale.clamp(1.0, 2.4) - 1.0) * 68;
  }

  IconData get _icon => switch (document.kind) {
        DocumentKind.bankStatement => Icons.account_balance_rounded,
        DocumentKind.invoice => Icons.receipt_long_rounded,
        DocumentKind.genericPdf => Icons.picture_as_pdf_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final DocumentStatus state = document.state;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${document.displayName}, '
          '${document.kind.label}, ${Fmt.humanise(document.status)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: state.isFailed
                  ? AppColors.dangerTint
                  : (state.isWorking
                      ? AppColors.infoTint
                      : AppColors.brandTint),
              borderRadius: AppRadius.smallAll,
            ),
            child: Icon(
              _icon,
              size: 21,
              color: state.isFailed
                  ? AppColors.danger
                  : (state.isWorking ? AppColors.info : AppColors.brandDeep),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fmt.middleEllipsis(document.displayName),
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    _TypeBadge(kind: document.kind),
                    const SizedBox(width: 6),
                    Flexible(
                      child: StatusBadge(document.status, compact: true),
                    ),
                    if (document.needsReview) ...<Widget>[
                      const SizedBox(width: 6),
                      const _ReviewDot(),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _meta,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: AppColors.inkFaint,
          ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (document.pageCount > 0) S.pageCount(document.pageCount),
      if (document.transactionsCount != null)
        S.transactionCount(document.transactionsCount!),
      Fmt.relative(document.createdAt),
    ];
    return parts.join(' · ');
  }
}

/// The document type, as a quiet outline pill so it never competes with the
/// status badge next to it.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.kind});

  final DocumentKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        kind.label,
        style: AppText.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkBody,
        ),
        maxLines: 1,
      ),
    );
  }
}

/// A single amber dot meaning "rows here still need a decision". Deliberately
/// not a number: the list payload cannot tell rejected rows from pending ones,
/// and a precise-looking count that is slightly wrong is worse than a hint.
class _ReviewDot extends StatelessWidget {
  const _ReviewDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.needsReview,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.warn,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
