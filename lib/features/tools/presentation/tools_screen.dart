/// The PDF tools grid — the second thing most people open the app for.
///
/// The tiles are built entirely from `GET /tools`, grouped into the three
/// families the website uses. Nothing about a tool is hard-coded here: its
/// label, its badge, what it accepts and whether it works on a phone at all all
/// arrive from the server, so adding a tool there adds it here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/conversion.dart';
import '../domain/tool.dart';
import 'providers.dart';
import 'widgets/conversion_card.dart';
import 'widgets/tool_tile.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  /// How many history rows the tools screen previews before handing over to the
  /// full history screen.
  static const int _recentCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ToolCatalogue> catalogue = ref.watch(toolsProvider);
    final ConversionListState history = ref.watch(conversionListProvider);

    return HeroPageScaffold(
      onRefresh: () async {
        ref.invalidate(toolsProvider);
        await Future.wait<void>(<Future<void>>[
          ref.read(toolsProvider.future),
          ref.read(conversionListProvider.notifier).refresh(),
        ]);
      },
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.page,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: S.pdfTools,
              title: S.pdfToolsSubtitle,
              scene: const ToolsScene(),
              subtitle: _allowance(catalogue.valueOrNull),
            ),
          ),
        ),
        ...catalogue.when(
          loading: () => const <Widget>[
            SliverToBoxAdapter(child: SkeletonList(count: 3, height: 120)),
          ],
          error: (Object error, StackTrace _) => <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: error,
                onRetry: () => ref.invalidate(toolsProvider),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            ),
          ],
          data: (ToolCatalogue data) => _toolSlivers(context, data),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: S.recentConversions,
              actionLabel: S.viewAll,
              onAction: () => context.pushNamed(AppRoute.conversions),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: _recent(context, history),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.section,
            AppSpacing.page,
            AppSpacing.section + 60,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              const SectionHeader(title: S.moreTools),
              // Both cards are gated on the flag that decides whether
              // lib/app/router.dart registers their route. Offering a card for
              // a route that was never registered is a tap that throws.
              if (Features.barcode) ...<Widget>[
                DarkActionCard(
                  eyebrow: S.barcode,
                  title: S.barcodeSubtitle,
                  body: S.barcodeCardBody,
                  icon: Icons.qr_code_2_rounded,
                  onTap: () => context.pushNamed(AppRoute.barcode),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (Features.webExtraction)
                DarkActionCard(
                  eyebrow: S.webExtraction,
                  title: S.webExtractionSubtitle,
                  body: S.webExtractionCardBody,
                  icon: Icons.travel_explore_rounded,
                  onTap: () => context.pushNamed(AppRoute.webExtractions),
                ),
            ]),
        ),
      ]);
  }

  /// One line of plan context under the hero title, when the server sent it.
  static String? _allowance(ToolCatalogue? catalogue) {
    final ToolUsage? usage = catalogue?.usage;
    if (usage == null || usage.conversionsUnlimited) {
      return null;
    }
    return S.conversionsLeft(usage.remainingConversions ?? 0);
  }

  List<Widget> _toolSlivers(BuildContext context, ToolCatalogue catalogue) {
    final List<Widget> slivers = <Widget>[];

    for (final ToolCategory category in ToolCategory.values) {
      final List<ToolDefinition> tools = catalogue.inCategory(category);
      if (tools.isEmpty) {
        continue;
      }

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(title: category.label),
          ),
        ),
      );

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              // Two columns on a phone, three or four on a tablet, without a
              // breakpoint table to keep in sync with anything.
              maxCrossAxisExtent: 215,
              mainAxisExtent: 152,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemCount: tools.length,
            itemBuilder: (BuildContext context, int index) {
              final ToolDefinition tool = tools[index];
              return ToolTile(
                tool: tool,
                onTap: () => _open(context, tool),
              );
            },
          ),
        ),
      );
    }

    return slivers;
  }

  void _open(BuildContext context, ToolDefinition tool) {
    if (!tool.supported) {
      Toast.info(context, tool.unsupportedReason ?? S.toolWebOnly);
      return;
    }
    context.pushNamed(
      AppRoute.toolRun,
      pathParameters: <String, String>{'tool': tool.key},
    );
  }

  Widget _recent(BuildContext context, ConversionListState history) {
    if (history.page.isLoading && !history.page.hasValue) {
      return const SliverToBoxAdapter(
        child: SkeletonList(count: 2, height: 84),
      );
    }

    final List<Conversion> rows =
        history.items.take(_recentCount).toList(growable: false);

    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(S.noConversionsBody, style: AppText.bodySm),
        ),
      );
    }

    return SliverList.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) => ConversionCard(
        conversion: rows[index],
        onTap: () => context.pushNamed(AppRoute.conversions),
      ),
    );
  }
}
