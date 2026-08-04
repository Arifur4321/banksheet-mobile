/// One row in the export archive.
///
/// The row answers three questions in the order people ask them: which
/// statement did this come from, what format is it, and how big — then offers
/// the two things anyone opens this screen to do, download and share. A pruned
/// file is shown greyed with its actions disabled rather than hidden, because a
/// missing export is information and a silently shorter list is not.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/file_downloader.dart';
import '../../domain/export_archive.dart';

class ExportRow extends StatelessWidget {
  const ExportRow({
    required this.archive,
    required this.isBusy,
    required this.onAction,
    super.key,
  });

  final ExportArchive archive;

  /// True while this row's file is being fetched. Only one row is ever busy at
  /// a time, which the screen above enforces.
  final bool isBusy;

  /// [origin] is the share button's rectangle, which iPadOS needs in order to
  /// anchor the share popover.
  final void Function(FileAction action, Rect? origin) onAction;

  @override
  Widget build(BuildContext context) {
    final bool enabled = archive.isAvailable && !isBusy;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FormatTile(format: archive.format, muted: !archive.isAvailable),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fmt.middleEllipsis(archive.sourceName),
                      style: AppText.bodyStrong.copyWith(
                        color: archive.isAvailable
                            ? AppColors.ink
                            : AppColors.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _FormatChip(
                          format: archive.format,
                          muted: !archive.isAvailable,
                        ),
                        const SizedBox(width: 6),
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
                    const SizedBox(height: 3),
                    Text(
                      Fmt.dateTime(archive.madeAt),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!archive.isAvailable)
            Row(
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S.fileUnavailableBody,
                    style: AppText.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        enabled ? () => onAction(FileAction.open, null) : null,
                    icon: isBusy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(isBusy ? S.downloading : S.downloadFile),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    onPressed: enabled
                        ? () => onAction(
                              FileAction.share,
                              FileDownloader.originOf(buttonContext),
                            )
                        : null,
                    tooltip: S.share,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (archive.recordCount > 0) S.recordCount(archive.recordCount),
      if (archive.sizeBytes != null) Fmt.bytes(archive.sizeBytes),
    ];
    return parts.join(' · ');
  }
}

/// The colours and icon a format is drawn with, in one place so the tile and
/// the chip beside it can never disagree.
({Color fg, Color bg, IconData icon}) _paletteFor(ExportFormat format) {
  return switch (format) {
    ExportFormat.xlsx => (
        fg: AppColors.brandDeep,
        bg: AppColors.brandTint,
        icon: Icons.table_chart_rounded,
      ),
    ExportFormat.csv => (
        fg: AppColors.info,
        bg: AppColors.infoTint,
        icon: Icons.grid_on_rounded,
      ),
    ExportFormat.json => (
        fg: AppColors.warn,
        bg: AppColors.warnTint,
        icon: Icons.data_object_rounded,
      ),
    ExportFormat.unknown => (
        fg: AppColors.inkMuted,
        bg: AppColors.surfaceMuted,
        icon: Icons.insert_drive_file_rounded,
      ),
  };
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.muted});

  final ExportFormat format;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ({Color fg, Color bg, IconData icon}) palette = _paletteFor(format);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: muted ? AppColors.surfaceMuted : palette.bg,
        borderRadius: AppRadius.smallAll,
      ),
      child: Icon(
        palette.icon,
        size: 20,
        color: muted ? AppColors.inkFaint : palette.fg,
      ),
    );
  }
}

/// The format, spelled out. A format is not a status, so it deliberately does
/// not reuse [StatusBadge] — colouring XLSX green would read as "this one
/// succeeded".
class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.format, required this.muted});

  final ExportFormat format;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ({Color fg, Color bg, IconData icon}) palette = _paletteFor(format);
    final Color fg = muted ? AppColors.inkFaint : palette.fg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.surfaceMuted : palette.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        format.label,
        style: AppText.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        maxLines: 1,
      ),
    );
  }
}
