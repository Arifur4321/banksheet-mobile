/// Does the statement add up?
///
/// This is the one thing a user can verify against the paper in their hand:
/// opening balance plus every credit minus every debit either equals the
/// closing balance or it does not. The card says which, in a sentence, before
/// it shows any numbers — a reviewer who is about to book these rows needs the
/// verdict, not a table to derive it from.
///
/// "We could not check" is stated as its own outcome rather than being dressed
/// up as a pass. A statement with no opening balance in it is not a balanced
/// statement.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/document.dart';

class ReconciliationCard extends StatelessWidget {
  const ReconciliationCard({
    required this.info,
    super.key,
    this.currency,
  });

  final ReconciliationInfo info;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final (NoticeTone tone, String headline, String body) = _verdict;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.reconciliation, style: AppText.h3),
          const SizedBox(height: AppSpacing.md),
          InlineNotice(message: '$headline. $body', tone: tone),
          const SizedBox(height: AppSpacing.lg),
          _Line(
            label: S.expectedNetChange,
            value: Fmt.money(
              info.expectedNetChange,
              currency: currency,
              signed: true,
            ),
          ),
          _Line(
            label: S.computedNetChange,
            value: Fmt.money(
              info.computedNetChange,
              currency: currency,
              signed: true,
            ),
          ),
          _Line(
            label: S.discrepancy,
            value: Fmt.money(info.discrepancy, currency: currency, signed: true),
            emphasis: info.isKnown && !info.isBalanced,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _Count(label: S.rowsChecked, value: info.rowsChecked),
              ),
              Expanded(
                child: _Count(label: S.rowsMatched, value: info.rowsMatched),
              ),
              Expanded(
                child: _Count(
                  label: S.rowsFlagged,
                  value: info.rowsFlagged,
                  tone: info.rowsFlagged > 0
                      ? AppColors.warn
                      : AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (NoticeTone, String, String) get _verdict {
    if (!info.isKnown) {
      return (
        NoticeTone.info,
        S.reconciliationUnknown,
        S.reconciliationUnknownBody,
      );
    }
    if (info.isBalanced) {
      return (
        NoticeTone.success,
        S.statementBalanced,
        S.statementBalancedBody,
      );
    }
    return (
      NoticeTone.danger,
      S.statementUnbalanced,
      S.statementUnbalancedBody(
        Fmt.money(info.discrepancy, currency: currency, signed: true),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.bodySm)),
          Text(
            value,
            style: AppText.numeric.copyWith(
              fontSize: 14,
              color: emphasis ? AppColors.danger : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    this.tone = AppColors.inkMuted,
  });

  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          Fmt.number(value),
          style: AppText.numeric.copyWith(fontSize: 17, color: tone),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.caption, maxLines: 1),
      ],
    );
  }
}
