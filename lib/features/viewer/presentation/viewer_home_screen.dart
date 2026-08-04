/// The reader tab — and the first screen a new install shows.
///
/// This screen carries the product's opening argument. A stranger who has just
/// installed BankSheet Pro can open a PDF here with no account, no network and
/// no permission prompt, and the conversion tools are visible one tap away.
/// That ordering is the whole reason the reader leads: an app that demands a
/// sign-up before showing anything converts far worse in a closed test, and
/// reads to a store reviewer as a login wall rather than a product.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/providers.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import 'providers.dart';

class ViewerHomeScreen extends ConsumerWidget {
  const ViewerHomeScreen({super.key});

  Future<void> _pickAndOpen(BuildContext context, WidgetRef ref) async {
    final RecentFile? picked =
        await ref.read(recentFilesRepositoryProvider).pickPdf();

    // Null means the user backed out of the system picker. That is a normal
    // outcome, not a failure, so nothing is said about it.
    if (picked == null) {
      return;
    }

    ref.invalidate(recentFilesProvider);
    if (context.mounted) {
      _open(context, picked);
    }
  }

  void _open(BuildContext context, RecentFile file) {
    context.pushNamed(
      AppRoute.pdfView,
      queryParameters: <String, String>{
        'path': file.path,
        'title': file.filename,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecentFile>> recents =
        ref.watch(recentFilesProvider);
    final bool signedIn = ref.watch(tokenStoreProvider).hasSession;

    return HeroPageScaffold(
      onRefresh: () async => ref.invalidate(recentFilesProvider),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickAndOpen(context, ref),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.inkInverse,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('Open PDF'),
      ),
      slivers: <Widget>[
        const SliverPadding(
          padding: EdgeInsets.all(AppSpacing.page),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: 'Reader',
              title: 'Every PDF, always free',
              subtitle: 'Open, read and share. No account needed.',
              scene: DocumentsScene(),
            ),
          ),
        ),

        // A guest is told what signing in buys before they hit a wall, not
        // after. The offer is honest about the split: reading stays free.
        if (!signedIn)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: InlineNotice(
                message: 'Reading is free forever. Create a free account to '
                    'convert, extract bank statements, sign and generate '
                    'barcodes — 10 of each per month.',
                actionLabel: 'Create account',
                onAction: () => context.pushNamed(AppRoute.register),
              ),
            ),
          ),

        if (Features.tools)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: DarkActionCard(
                eyebrow: 'Tools',
                title: 'Convert, merge, split, sign',
                body: 'PDF to Word, images to PDF, bank statement to Excel, '
                    'e-signature and barcodes.',
                onTap: () => context.goNamed(AppRoute.tools),
              ),
            ),
          ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Recent',
              subtitle: 'Files you opened on this device',
              actionLabel: recents.valueOrNull?.isNotEmpty ?? false
                  ? 'Clear'
                  : null,
              onAction: () async {
                final bool ok = await confirmAction(
                  context,
                  title: 'Clear recent files?',
                  message: 'This only clears the list on this phone. No file '
                      'is deleted.',
                  confirmLabel: 'Clear',
                );
                if (!ok) {
                  return;
                }
                await ref.read(recentFilesRepositoryProvider).clear();
                ref.invalidate(recentFilesProvider);
              },
            ),
          ),
        ),

        recents.when(
          loading: () => const SliverToBoxAdapter(child: SkeletonList()),
          error: (Object e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(recentFilesProvider),
              ),
            ),
          ),
          data: (List<RecentFile> files) => files.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.page),
                    child: EmptyState(
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'No files yet',
                      body: 'Open a PDF from your phone and it will show up '
                          'here next time.',
                      actionLabel: 'Open PDF',
                      onAction: () => _pickAndOpen(context, ref),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    0,
                    AppSpacing.page,
                    // Clears the extended FAB, which would otherwise sit on
                    // top of the last row and make it untappable.
                    96,
                  ),
                  sliver: SliverList.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (BuildContext context, int i) => _RecentTile(
                      file: files[i],
                      onTap: () => _open(context, files[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.file, required this.onTap});

  final RecentFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final List<String> meta = <String>[
      if (file.pageCount != null)
        '${file.pageCount} ${file.pageCount == 1 ? 'page' : 'pages'}',
      Fmt.bytes(file.sizeBytes),
      Fmt.relative(file.openedAt),
    ];

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
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
              Icons.picture_as_pdf_rounded,
              color: AppColors.brandDeep,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.filename,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(meta.join(' · '), style: AppText.caption),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.inkFaint,
          ),
        ],
      ),
    );
  }
}
