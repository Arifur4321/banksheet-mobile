/// The export archive.
///
/// Grouped by day because that is how people look for a spreadsheet they made
/// ("it was Tuesday"), and because an ungrouped list of forty near-identical
/// filenames is unreadable. Downloading writes into the app documents directory
/// and then hands the file to the OS, which is the only way these can be opened
/// at all: the files sit on a private disk behind an authenticated route.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/export_repository.dart';
import '../data/file_downloader.dart';
import '../domain/export_archive.dart';
import 'providers.dart';
import 'widgets/export_row.dart';

class ExportsScreen extends ConsumerStatefulWidget {
  const ExportsScreen({super.key});

  @override
  ConsumerState<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends ConsumerState<ExportsScreen> {
  /// The row currently downloading. One at a time: two simultaneous downloads
  /// on a phone connection make both slower and neither cancellable.
  int? _busyId;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      ref.read(exportListProvider.notifier).loadMore();
    }
    return false;
  }

  Future<void> _run(
    ExportArchive archive,
    FileAction action,
    Rect? origin,
  ) async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = archive.id);

    try {
      final File file = await ref.read(exportRepositoryProvider).download(
            archive.id,
            filename: archive.filename,
          );
      if (!context.mounted) {
        return;
      }
      await FileDownloader.apply(
        action,
        file,
        subject: archive.filename,
        origin: origin,
      );
      if (!context.mounted) {
        return;
      }
      if (action == FileAction.share) {
        return;
      }
      Toast.success(context, S.savedToDevice);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExportListState state = ref.watch(exportListProvider);
    final List<ExportDayGroup> groups = ref.watch(exportDayGroupsProvider);
    final List<_Entry> entries = _flatten(groups);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(exportListProvider.notifier).refresh(),
        slivers: <Widget>[
          // This route is pushed onto the root navigator, so it carries its own
          // back affordance. Floating rather than pinned: the hero panel below
          // is the screen's real title.
          const SliverAppBar(
            floating: true,
            toolbarHeight: 52,
            titleSpacing: AppSpacing.lg,
            title: Text(S.exports),
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
                eyebrow: S.exports,
                title: S.exportsSubtitle,
                scene: const DashboardScene(),
                subtitle: state.total > 0 ? S.exportCount(state.total) : null,
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
                    .read(exportListProvider.notifier)
                    .refresh(showLoading: true),
              ),
            )
          else if (entries.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.folder_zip_outlined,
                title: S.noExports,
                body: S.noExportsBody,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (BuildContext context, int index) {
                  final _Entry entry = entries[index];

                  return switch (entry) {
                    _DayEntry(:final DateTime? day) => _DayHeader(
                        day: day,
                        isFirst: index == 0,
                      ),
                    _ExportEntry(:final ExportArchive archive) =>
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ExportRow(
                          archive: archive,
                          isBusy: _busyId == archive.id,
                          onAction: (FileAction action, Rect? origin) =>
                              _run(archive, action, origin),
                        ),
                      ),
                  };
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () => ref.read(exportListProvider.notifier).loadMore(),
            ),
          ),
        ],
      ),
    );
  }

  /// Groups flattened into one list so the whole archive still builds lazily —
  /// a nested `Column` per day would build every row on the first frame.
  static List<_Entry> _flatten(List<ExportDayGroup> groups) {
    final List<_Entry> entries = <_Entry>[];
    for (final ExportDayGroup group in groups) {
      entries.add(_DayEntry(group.day));
      entries.addAll(group.exports.map(_ExportEntry.new));
    }
    return entries;
  }
}

sealed class _Entry {
  const _Entry();
}

class _DayEntry extends _Entry {
  const _DayEntry(this.day);

  final DateTime? day;
}

class _ExportEntry extends _Entry {
  const _ExportEntry(this.archive);

  final ExportArchive archive;
}

/// A day divider. "Today" and "Yesterday" are spelled out because a date on its
/// own makes the reader do arithmetic to answer "is this the one I just made?".
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isFirst});

  final DateTime? day;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? 0 : AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Text(_label, style: AppText.label),
    );
  }

  String get _label {
    final DateTime? value = day;
    if (value == null) {
      return S.undated.toUpperCase();
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int days = today.difference(value).inDays;

    return switch (days) {
      0 => S.today.toUpperCase(),
      1 => S.yesterday.toUpperCase(),
      _ => Fmt.date(value).toUpperCase(),
    };
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
