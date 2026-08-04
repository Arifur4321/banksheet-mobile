/// Start an extraction job.
///
/// The list is parsed as it is typed so the count above the button is the
/// number of websites that will actually be scanned — which is the number of
/// scans this will cost. Lines that are not websites are named rather than
/// silently dropped, because the most common paste into this field is a column
/// that also contains company names and email addresses.
///
/// The responsible-use notice is the website's, word for word. It is not
/// decoration: a crawler that people use carelessly is a crawler that gets the
/// whole product blocked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/web_job.dart';
import 'providers.dart';

class WebExtractionCreateScreen extends ConsumerStatefulWidget {
  const WebExtractionCreateScreen({super.key});

  @override
  ConsumerState<WebExtractionCreateScreen> createState() =>
      _WebExtractionCreateScreenState();
}

class _WebExtractionCreateScreenState
    extends ConsumerState<WebExtractionCreateScreen> {
  final TextEditingController _domains = TextEditingController();
  final TextEditingController _title = TextEditingController();

  WebCreateController get _controller => ref.read(webCreateProvider.notifier);

  @override
  void dispose() {
    _domains.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final WebExtractionCreated? created = await _controller.submit();
    if (!context.mounted) {
      return;
    }

    if (created != null) {
      // The plan counters moved, so the meters everywhere else are now stale.
      await ref.read(authControllerProvider.notifier).refreshSession();
      if (!context.mounted) {
        return;
      }
      await ref.read(webJobListProvider.notifier).refresh();
      if (!context.mounted) {
        return;
      }
      Toast.success(context, created.message ?? S.extractionQueued);
      context.pushReplacementNamed(
        AppRoute.webExtractionDetail,
        pathParameters: <String, String>{'id': '${created.job.id}'},
      );
      return;
    }

    final Object? error = ref.read(webCreateProvider).error;
    if (error == null) {
      return;
    }
    final ApiException failure = ApiException.from(error);
    Toast.error(context, failure);
    if (failure.isQuota) {
      context.pushNamed(AppRoute.billing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final WebCreateState state = ref.watch(webCreateProvider);
    final Session? session = ref.watch(sessionProvider);
    final UsageLine? scans = session?.limits.line(PlanLimits.keyWebScans);

    return PageScaffold(
      title: S.newExtraction,
      subtitle: S.webExtractionSubtitle,
      showBack: true,
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (scans != null) ...<Widget>[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(S.currentAllowance, style: AppText.eyebrow),
                  const SizedBox(height: AppSpacing.md),
                  UsageMeter(
                    label: S.usageWebScans,
                    used: scans.used,
                    limit: scans.limit,
                  ),
                  if (!scans.isUnlimited) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      S.scansRemaining(scans.remaining ?? 0),
                      style: AppText.caption,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(S.domains, style: AppText.label),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _domains,
            enabled: !state.isSubmitting,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            style: AppText.body.copyWith(fontFamily: 'monospace'),
            onChanged: _controller.setDomains,
            decoration: InputDecoration(
              hintText: S.domainsHint,
              errorText: state.isTooLong ? S.domainListTooLong : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ParseSummary(parsed: state.parsed, raw: state.raw),
          const SizedBox(height: AppSpacing.xl),
          Text(S.jobTitle, style: AppText.label),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _title,
            enabled: !state.isSubmitting,
            maxLength: 255,
            textInputAction: TextInputAction.done,
            onChanged: _controller.setTitle,
            decoration: InputDecoration(
              hintText: S.jobTitleHint,
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const InlineNotice(
            message: S.responsibleUseNotice,
            tone: NoticeTone.warn,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: state.canSubmit && !state.isSubmitting ? _submit : null,
            icon: state.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.inkInverse,
                    ),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 19),
            label: Text(
              state.parsed.isEmpty
                  ? S.queueExtraction
                  : S.queueExtractionCount(state.parsed.count),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _WhatWeCheck(),
          const SizedBox(height: AppSpacing.section),
        ],
      ),
    );
  }
}

/// The live count, and the lines that will not be scanned.
class _ParseSummary extends StatelessWidget {
  const _ParseSummary({required this.parsed, required this.raw});

  final DomainListParse parsed;
  final String raw;

  @override
  Widget build(BuildContext context) {
    if (raw.trim().isEmpty) {
      return Text(S.domainsCountHint, style: AppText.caption);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              parsed.isEmpty
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 15,
              color: parsed.isEmpty ? AppColors.danger : AppColors.brandDeep,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                parsed.isEmpty
                    ? S.noWebsitesFound
                    : S.websitesWillBeScanned(parsed.count),
                style: AppText.caption.copyWith(
                  color:
                      parsed.isEmpty ? AppColors.danger : AppColors.brandDeep,
                ),
              ),
            ),
          ],
        ),
        if (parsed.rejected.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          InlineNotice(
            message: S.linesIgnored(
              parsed.rejected.length,
              parsed.rejected.take(3).join(', '),
            ),
            tone: NoticeTone.info,
          ),
        ],
      ],
    );
  }
}

/// What the crawler actually does — the website's list, so nobody is surprised
/// by what shows up in their export.
class _WhatWeCheck extends StatelessWidget {
  const _WhatWeCheck();

  @override
  Widget build(BuildContext context) {
    const List<String> points = <String>[
      S.crawlPointHomepage,
      S.crawlPointPages,
      S.crawlPointData,
      S.crawlPointSafety,
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.whatWeCheck, style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.md),
          for (final String point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: AppColors.brandDeep,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(point, style: AppText.bodySm)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
