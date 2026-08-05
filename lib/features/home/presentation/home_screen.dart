/// Home — the signed-in landing screen.
///
/// It replaces the old guest-facing reader landing page. The difference is not
/// cosmetic. That screen existed to argue with a signed-out stranger ("reading
/// is free, no account needed"), and the welcome screen now makes that argument
/// itself, with the two actions on it. A second screen making the same pitch to
/// someone who has already signed up was a page nobody needed to read.
///
/// So this one answers a different question — "what now?" — and answers it in
/// the order the work actually happens:
///
///   1. **The two things you came to do.** Open a PDF, or scan one. Side by
///      side, equal weight, above everything else.
///   2. **What you were last looking at.** Recents, because reopening beats
///      re-finding.
///   3. **What else this app does.** One card into the tools hub.
///
/// Everything here reads from the device — recents come out of SQLite, the two
/// actions are local. It renders identically with the network off, which is
/// what makes it a safe first screen after a cold start on a train.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../scan/domain/scan_page.dart';
import '../../viewer/presentation/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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

    return HeroPageScaffold(
      onRefresh: () async => ref.invalidate(recentFilesProvider),
      slivers: <Widget>[
        const SliverPadding(
          padding: EdgeInsets.all(AppSpacing.page),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: 'BankSheet Pro',
              title: 'Open a PDF, or make one',
              subtitle: 'Read, scan and convert — right here on your phone.',
              scene: DocumentsScene(),
            ),
          ),
        ),

        // The two primary actions. A row rather than a stack: they are peers,
        // and stacking one above the other would say the first is the real
        // feature and the second is the fallback.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: PrimaryActionTile(
                    icon: Icons.folder_open_rounded,
                    label: 'Open PDF',
                    caption: 'From this phone',
                    filled: true,
                    onTap: () => _pickAndOpen(context, ref),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryActionTile(
                    icon: Icons.document_scanner_rounded,
                    label: 'Scan to PDF',
                    caption: 'Photos to pages',
                    onTap: () => context.pushNamed(
                      AppRoute.scan,
                      queryParameters: <String, String>{
                        'source': ScanSource.camera.name,
                      },
                    ),
                  ),
                ),
              ],
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
              actionLabel: (recents.valueOrNull?.isNotEmpty ?? false)
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
                    AppSpacing.xxl,
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

/// A large, square-ish action target.
///
/// Public because the welcome screen renders the same two actions and they must
/// be visibly the same control in both places — a user who taps "Scan to PDF"
/// before signing up and again afterwards should not feel they found two
/// different features.
class PrimaryActionTile extends StatelessWidget {
  const PrimaryActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.caption,
    this.filled = false,
    this.onDark = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  /// Brand-filled rather than outlined. Exactly one of the pair should be.
  final bool filled;

  /// Rendered on a dark panel (the welcome screen) rather than on the app
  /// canvas. Changes the outlined variant's colours, not its shape.
  final bool onDark;

  /// Tighter padding and a smaller icon, ~16pt shorter.
  ///
  /// Used by the welcome screen on anything below a tall phone, where the
  /// screen has a hard no-scroll requirement and this is the cheapest 16 points
  /// to find. Everything stays above the 48pt minimum touch target.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color bg = filled
        ? AppColors.brand
        : (onDark
            ? AppColors.inkInverse.withValues(alpha: 0.08)
            : AppColors.surface);
    final Color fg = filled
        ? AppColors.inkInverse
        : (onDark ? AppColors.inkInverse : AppColors.ink);
    final Color captionFg = filled
        ? AppColors.inkInverse.withValues(alpha: 0.78)
        : (onDark
            ? AppColors.inkInverse.withValues(alpha: 0.60)
            : AppColors.inkMuted);

    return Material(
      color: bg,
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            border: filled
                ? null
                : Border.all(
                    color: onDark
                        ? AppColors.inkInverse.withValues(alpha: 0.20)
                        : AppColors.border,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: compact ? 22 : 26, color: fg),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              Text(
                label,
                style: AppText.bodyStrong.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (caption != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  caption!,
                  style: AppText.caption.copyWith(color: captionFg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
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
