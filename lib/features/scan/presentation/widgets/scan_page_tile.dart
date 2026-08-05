/// One captured page in the scan list.
///
/// The thumbnail is rendered with `cacheWidth` set. That is the single most
/// important line in this file: without it, `Image.file` decodes a 2600px
/// capture at full resolution into the raster cache for a 72px box, and a
/// ten-page scan quietly holds ~270 MB of decoded bitmaps. With it, each page
/// costs a few hundred kilobytes and the list scrolls on a cheap phone.
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
    required this.onRemove,
    super.key,
  });

  final ScanPage page;

  /// Zero-based position in the list; displayed one-based.
  final int index;

  final VoidCallback onRemove;

  /// Decoded thumbnail width in pixels. 3x the 72dp box, which covers every
  /// phone density currently shipping.
  static const int _thumbCacheWidth = 216;

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
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Page ${index + 1}', style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  missing
                      ? 'Image no longer available'
                      : '${page.source == ScanSource.camera ? 'Camera' : 'Gallery'}'
                          ' · ${Fmt.bytes(page.sizeBytes)}',
                  style: AppText.caption.copyWith(
                    color: missing ? AppColors.danger : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.inkMuted,
            tooltip: 'Remove page ${index + 1}',
            onPressed: onRemove,
          ),
          // The drag handle is explicit rather than long-press-anywhere: a list
          // whose rows both scroll and reorder on the same gesture is a list
          // that reorders when the user meant to scroll.
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Icon(
                Icons.drag_handle_rounded,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
