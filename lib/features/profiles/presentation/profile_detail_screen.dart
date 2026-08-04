/// One extraction profile, explained.
///
/// This screen exists to answer "why did that statement parse the way it did?",
/// which the raw rules can technically answer and practically cannot. So the
/// four blobs are re-cut into the four questions a person actually asks — what
/// is this for, what region and formats does it assume, how does it recognise
/// the statement and its table, and which column is which — and the exact JSON
/// stays one tap away under "Advanced" for whoever wrote it.
///
/// Read-only: the switch on the list is the only thing the app changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/extraction_profile.dart';
import 'providers.dart';
import 'widgets/rule_section.dart';

class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({required this.profileId, super.key});

  final int profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ExtractionProfile> state =
        ref.watch(profileDetailProvider(profileId));

    return PageScaffold(
      title: state.valueOrNull?.displayName ?? S.profiles,
      showBack: true,
      scrollable: true,
      onRefresh: () => ref.refresh(profileDetailProvider(profileId).future),
      child: state.when(
        loading: () => const _DetailSkeleton(),
        error: (Object error, _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(profileDetailProvider(profileId)),
            onUpgrade: () => context.pushNamed(AppRoute.billing),
          ),
        ),
        data: (ExtractionProfile profile) => _Detail(profile: profile),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.profile});

  final ExtractionProfile profile;

  @override
  Widget build(BuildContext context) {
    final ProfileRules rules = profile.rules ?? const ProfileRules();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Summary(profile: profile),
        const SizedBox(height: AppSpacing.xl),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: EmptyState(
              icon: Icons.rule_folder_outlined,
              title: S.noRules,
              body: S.noRulesBody,
            ),
          )
        else ...<Widget>[
          _IdentitySection(profile: profile, rules: rules),
          _FormatsSection(rules: rules),
          _RecognitionSection(rules: rules),
          _ColumnsSection(rules: rules),
          _AdvancedSection(rules: rules),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Text(
          S.profilesAuthoredOnWeb,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }
}

/// Name, state, and what this profile has actually done.
class _Summary extends StatelessWidget {
  const _Summary({required this.profile});

  final ExtractionProfile profile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: profile.isActive
                      ? AppColors.brandTint
                      : AppColors.surfaceMuted,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  size: 22,
                  color: profile.isActive
                      ? AppColors.brandDeep
                      : AppColors.inkFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.displayName,
                      style: AppText.h3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    StatusBadge(
                      profile.isActive ? S.profileActive : S.profileInactive,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: S.documentsParsed,
                  value: Fmt.number(profile.documentsCount ?? 0),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: S.rowsExtractedTotal,
                  value: Fmt.number(profile.transactionsCount ?? 0),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: S.lastMatched,
                  value: profile.lastMatchedAt == null
                      ? S.neverMatched
                      : Fmt.relative(profile.lastMatchedAt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppText.caption, maxLines: 1),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppText.numeric.copyWith(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.profile, required this.rules});

  final ExtractionProfile profile;
  final ProfileRules rules;

  @override
  Widget build(BuildContext context) {
    return RuleSection(
      title: S.sectionIdentity,
      icon: Icons.badge_outlined,
      children: <Widget>[
        if (profile.bankName != null)
          RuleRow(label: S.bank, value: profile.bankName!),
        if (profile.documentType != null)
          RuleRow(
            label: S.documentType,
            value: Fmt.humanise(profile.documentType),
          ),
        if (rules.country != null)
          RuleRow(label: S.country, value: rules.country!),
        if (rules.language != null)
          RuleRow(label: S.statementLanguage, value: rules.language!),
        if (profile.hasSample)
          const RuleRow(label: S.sampleOnFile, value: S.yes),
      ],
    );
  }
}

class _FormatsSection extends StatelessWidget {
  const _FormatsSection({required this.rules});

  final ProfileRules rules;

  @override
  Widget build(BuildContext context) {
    final bool? dayFirst = rules.dayFirst;

    return RuleSection(
      title: S.sectionRegionFormats,
      icon: Icons.public_rounded,
      children: <Widget>[
        if (rules.dateFormat != null)
          RuleRow(
            label: S.dateFormat,
            value: rules.dateFormat!,
            monospace: true,
          ),
        if (dayFirst != null)
          RuleRow(label: S.dayFirst, value: dayFirst ? S.yes : S.no),
        if (rules.currency != null)
          RuleRow(label: S.currency, value: rules.currency!),
        if (rules.decimalSeparator != null)
          RuleRow(
            label: S.decimalSeparator,
            value: rules.decimalSeparator!,
            monospace: true,
          ),
        if (rules.numberFormat != null)
          RuleRow(
            label: S.numberFormat,
            value: rules.numberFormat!.toUpperCase(),
          ),
      ],
    );
  }
}

class _RecognitionSection extends StatelessWidget {
  const _RecognitionSection({required this.rules});

  final ProfileRules rules;

  @override
  Widget build(BuildContext context) {
    // Filtered here rather than left to RuleChips to collapse itself: a
    // section whose every list is empty must render as nothing at all, and
    // RuleSection decides that by counting its children.
    return RuleSection(
      title: S.sectionRecognition,
      icon: Icons.manage_search_rounded,
      children: <Widget>[
        if (rules.statementKeywords.isNotEmpty)
          RuleChips(
            label: S.statementKeywords,
            values: rules.statementKeywords,
          ),
        if (rules.headerKeywords.isNotEmpty)
          RuleChips(label: S.headerKeywords, values: rules.headerKeywords),
        if (rules.tableStartKeywords.isNotEmpty)
          RuleChips(
            label: S.tableStartKeywords,
            values: rules.tableStartKeywords,
          ),
        if (rules.tableEndKeywords.isNotEmpty)
          RuleChips(label: S.tableEndKeywords, values: rules.tableEndKeywords),
        if (rules.ignoredLines.isNotEmpty)
          RuleChips(
            label: S.ignoredLines,
            values: rules.ignoredLines,
            monospace: true,
          ),
        if (rules.cleanupRules.isNotEmpty)
          RuleChips(
            label: S.cleanupRules,
            values: rules.cleanupRules,
            monospace: true,
          ),
      ],
    );
  }
}

class _ColumnsSection extends StatelessWidget {
  const _ColumnsSection({required this.rules});

  final ProfileRules rules;

  @override
  Widget build(BuildContext context) {
    final Map<ProfileColumnField, String> map = rules.columnMap;
    final bool? infer = rules.inferFromBalance;
    final bool? merge = rules.mergeMultiline;

    return RuleSection(
      title: S.sectionColumnMapping,
      icon: Icons.view_column_outlined,
      children: <Widget>[
        for (final ProfileColumnField field in ProfileColumnField.values)
          if (map[field] != null)
            RuleRow(label: field.label, value: map[field]!),
        if (map.isEmpty && rules.columns.isNotEmpty)
          RuleChips(label: S.columnHeaders, values: rules.columns),
        if (rules.amountMode != null)
          RuleRow(
            label: S.amountMode,
            value: rules.amountMode == 'single'
                ? S.amountModeSingle
                : S.amountModeSeparate,
          ),
        if (infer != null)
          RuleRow(label: S.inferFromBalance, value: infer ? S.yes : S.no),
        if (merge != null)
          RuleRow(label: S.mergeMultiline, value: merge ? S.yes : S.no),
        if (rules.amountPattern != null)
          RuleRow(
            label: S.amountPattern,
            value: rules.amountPattern!,
            monospace: true,
          ),
      ],
    );
  }
}

/// The exact JSON, for whoever wrote it. Collapsed by default — it is the
/// answer to a question most readers of this screen are not asking.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.rules});

  final ProfileRules rules;

  @override
  Widget build(BuildContext context) {
    final List<(String, Map<String, dynamic>)> sections = rules.rawSections;
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          // The card already draws the hairline; ExpansionTile's own dividers
          // would double it.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            title: const Text(S.advanced, style: AppText.h3),
            subtitle: const Text(S.rawRulesBody, style: AppText.caption),
            leading: const Icon(
              Icons.code_rounded,
              size: 19,
              color: AppColors.brandDeep,
            ),
            children: <Widget>[
              for (final (String title, Map<String, dynamic> data) in sections)
                RuleJsonBlock(title: title, data: data),
            ],
          ),
        ),
      ),
    );
  }
}

/// The detail's shape while it loads.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Skeleton(height: 140, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 120, height: 15),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 120, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 150, height: 15),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 120, radius: AppRadius.card),
      ],
    );
  }
}
