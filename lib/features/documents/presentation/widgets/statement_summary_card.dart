/// The bank-statement header: whose account this is, for which period, and what
/// it totalled.
///
/// Everything shown here comes from `summary_json`, which is the same blob the
/// website's document page reads — so the two products state the same facts
/// about the same file.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/document.dart';
import 'transaction_row.dart';

class StatementSummaryCard extends StatelessWidget {
  const StatementSummaryCard({required this.summary, super.key});

  final StatementSummary summary;

  @override
  Widget build(BuildContext context) {
    final String currency = summary.currency ?? '';
    final List<String> notes = <String>[
      ...summary.warnings,
      ...summary.ocrWarnings,
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(S.statementSummary, style: AppText.h3)),
              ConfidenceChip(level: summary.confidence, showLabel: true),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _Field(label: S.bank, value: summary.bankName),
          _Field(label: S.accountHolder, value: summary.accountHolder),
          _Field(label: S.account, value: _account),
          _Field(label: S.period, value: _period),
          if (summary.matchedProfile != null)
            _Field(label: S.extractionProfile, value: summary.matchedProfile),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _Figure(
                  label: S.openingBalance,
                  value: Fmt.money(summary.openingBalance, currency: currency),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: S.closingBalance,
                  value: Fmt.money(summary.closingBalance, currency: currency),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _Figure(
                  label: S.totalCredits,
                  value: Fmt.money(
                    summary.totals.totalCredits,
                    currency: currency,
                  ),
                  tone: AppColors.brandDeep,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: S.totalDebits,
                  value: Fmt.money(
                    summary.totals.totalDebits,
                    currency: currency,
                  ),
                  tone: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _Figure(
            label: S.netChange,
            value: Fmt.money(
              summary.totals.netChange,
              currency: currency,
              signed: true,
            ),
          ),
          if (notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            InlineNotice(
              message: '${S.extractionWarnings}: ${notes.join(' · ')}',
              tone: NoticeTone.warn,
            ),
          ],
        ],
      ),
    );
  }

  /// The account line.
  ///
  /// The server already masks the IBAN and the account number — the full value
  /// deliberately never reaches the device — so [Fmt.maskIban] is applied only
  /// as a belt-and-braces guard for a value that arrived unmasked. Running it
  /// over an already-masked string would produce a second row of bullets and
  /// hide the four digits that make the account recognisable.
  String? get _account {
    final String? value = summary.accountDisplay ??
        summary.ibanMasked ??
        summary.accountNumberMasked;
    if (value == null) {
      return null;
    }
    return value.contains('•') ? value : Fmt.maskIban(value);
  }

  String? get _period {
    final StatementPeriod period = summary.period;
    if (period.start != null && period.end != null) {
      return '${Fmt.date(period.start)} — ${Fmt.date(period.end)}';
    }
    return period.label ?? (period.start == null ? null : Fmt.date(period.start));
  }
}

/// A label/value line. Absent values render as an em dash rather than
/// disappearing, so a missing bank name reads as "we could not find it" instead
/// of as a layout that quietly changed shape.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(label, style: AppText.bodySm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value ?? '—',
              style: AppText.bodyStrong.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.tone = AppColors.ink,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.caption),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppText.numeric.copyWith(fontSize: 16, color: tone),
        ),
      ],
    );
  }
}
