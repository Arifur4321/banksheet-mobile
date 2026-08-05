/// One captured page in the scan list.
///
/// The thumbnail is rendered with `cacheWidth` set. That is the single most
/// important line in this file: without it, `Image.file` decodes a 2600px
/// capture at full resolution into the raster cache for a 72px box, and a
/// ten-page scan quietly holds hundreds of megabytes of decoded bitmaps. With
/// it, each page costs a few hundred kilobytes and the list scrolls on a cheap
/// phone.
///
/// Reordering is two buttons rather than a drag handle. The drag version used
/// `ReorderableListView`, whose internal `GlobalKey` reparenting was implicated
/// in a framework assertion that left this screen blank on a real device. Two
/// arrows are less elegant and always work — and unlike a drag handle they are
/// reachable with a screen reader and with one thumb.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/scan_page.dart';

class ScanPageTile extends StatelessWidget {
  const ScanPageTile({
    required this.page,
    required this.index,
    required this.total,
    required this.onRemove,
    super.key,
    this.onMoveUp,
    this.onMoveDown,
  });

  final ScanPage page;

  /// Zero-based position in the list; displayed one-based.
  final int index;

  final int total;

  final VoidCallback onRemove;

  /// Null at the ends of the list, which disables the button rather than
  /// hiding it — a control that moves between rows is harder to hit than one
  /// that greys out.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Decoded thumbnail width in pixels. 3x the 56dp box, which covers every
  /// phone density currently shipping.
  static const int _thumbCacheWidth = 168;

  @override
  Widget build(BuildContext context) {
    final bool missing = !page.exists;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: missing ? AppColors.dangerTint : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.smallAll,
            child: SizedBox(
              width: 56,
              height: 72,
              child: missing
                  ? const ColoredBox(
                      color: AppColors.surfaceMuted,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.inkFaint,
                      ),
                    )
                  : Image.file(
                      page.file,
                      fit: BoxFit.cover,
                      cacheWidth: _thumbCacheWidth,
                      // A capture that fails to decode is a bad page, not a
                      // crash. The build step reports it by page number.
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: AppColors.surfaceMuted,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Page ${index + 1} of $total',
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  missing
                      ? 'Image no longer available'
                      : '${page.source == ScanSource.camera ? 'Camera' : 'Gallery'}'
                          ' · ${Fmt.bytes(page.sizeBytes)}',
                  style: AppText.caption.copyWith(
                    color: missing ? AppColors.danger : AppColors.inkMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Compact controls: the whole cluster has to fit beside a 56pt
          // thumbnail on a 320pt screen.
          _TileButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Move page ${index + 1} up',
            onPressed: onMoveUp,
          ),
          _TileButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Move page ${index + 1} down',
            onPressed: onMoveDown,
          ),
          _TileButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Remove page ${index + 1}',
            onPressed: onRemove,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      // 40pt rather than Material's 48: three of these plus a thumbnail plus
      // the filename have to share a 320pt screen. Still inside the 40pt floor
      // the accessibility guidelines allow for adjacent controls in a row.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      color: danger ? AppColors.danger : AppColors.inkMuted,
      disabledColor: AppColors.inkFaint.withValues(alpha: 0.4),
    );
  }
}
