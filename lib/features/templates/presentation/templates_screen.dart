/// The templates list.
///
/// A template is only interesting for what you can do with it, so every row
/// leads straight to the form that fills it in, and the app bar carries a
/// shortcut to everything already generated — the other half of this feature and
/// the reason people come back to it.
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
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/template.dart';
import 'providers.dart';

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      ref.read(templateListProvider.notifier).loadMore();
    }
    return false;
  }

  void _open(int templateId) {
    context.pushNamed(
      AppRoute.templateDetail,
      pathParameters: <String, String>{'id': '$templateId'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final PagedState<Template> state = ref.watch(templateListProvider);
    final List<Template> rows = state.items;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(templateListProvider.notifier).refresh(),
        slivers: <Widget>[
          SliverAppBar(
            floating: true,
            toolbarHeight: 52,
            titleSpacing: AppSpacing.lg,
            title: const Text(S.templates),
            actions: <Widget>[
              IconButton(
                onPressed: () => context.pushNamed(AppRoute.generatedPdfs),
                tooltip: S.generatedPdfs,
                icon: const Icon(Icons.folder_open_rounded),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: HeroPanel(
                eyebrow: S.templates,
                title: S.templatesSubtitle,
                scene: const DocumentsScene(),
                subtitle:
                    state.total > 0 ? S.templateCount(state.total) : null,
              ),
            ),
          ),
          if (state.page.isLoading && !state.page.hasValue)
            const SliverToBoxAdapter(child: SkeletonList())
          else if (state.page.hasError && !state.page.hasValue)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: state.page.error!,
                onRetry: () => ref
                    .read(templateListProvider.notifier)
                    .refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.article_outlined,
                title: S.noTemplates,
                body: S.noTemplatesBody,
                actionLabel: S.generatedPdfs,
                onAction: () => context.pushNamed(AppRoute.generatedPdfs),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) => _TemplateCard(
                  template: rows[index],
                  onTap: () => _open(rows[index].id),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () => ref.read(templateListProvider.notifier).loadMore(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final Template template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${template.displayName}, '
          '${S.templateFieldCount(template.variablesCount)}',
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: AppRadius.smallAll,
            ),
            child: const Icon(
              Icons.article_rounded,
              size: 21,
              color: AppColors.brandDeep,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fmt.middleEllipsis(template.displayName),
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    if (template.type != null) ...<Widget>[
                      _TypePill(label: Fmt.humanise(template.type)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        _meta,
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
      S.templateFieldCount(template.variablesCount),
      if (template.generatedPdfsCount != null)
        S.generatedPdfCount(template.generatedPdfsCount!),
      Fmt.relative(template.updatedAt ?? template.createdAt),
    ];
    return parts.join(' · ');
  }
}

/// The template's own category, as a quiet outline pill.
class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

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
        label,
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

/// The bottom of the list: a spinner while another page loads, a retry when one
/// failed, breathing room otherwise.
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.error,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: InlineNotice(
          message: S.couldNotLoadMore,
          tone: NoticeTone.warn,
          actionLabel: S.tryAgain,
          onAction: onRetry,
        ),
      );
    }

    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return const SizedBox(height: AppSpacing.section);
  }
}
