/// The live preview panel.
///
/// `gaplessPlayback` is the load-bearing detail: without it, every re-render
/// blanks the widget for a frame and a preview that updates as you type reads
/// as a strobe. The previous image therefore stays on screen, dimmed, while the
/// next one is fetched.
///
/// A transparent background is drawn over a checkerboard rather than over the
/// card, because "transparent" and "white" look identical on a white card and
/// the difference is the whole point of the switch.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../domain/symbology.dart';

class BarcodePreviewPanel extends StatelessWidget {
  const BarcodePreviewPanel({
    required this.image,
    required this.isLoading,
    required this.transparent,
    super.key,
  });

  final BarcodePreviewImage? image;
  final bool isLoading;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final BarcodePreviewImage? preview = image;

    return Container(
      height: 220,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (transparent)
            const CustomPaint(painter: _CheckerPainter())
          else
            const ColoredBox(color: AppColors.surface),
          if (preview == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: _Placeholder(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AnimatedOpacity(
                duration: AppMotion.fast,
                opacity: isLoading ? 0.45 : 1,
                child: Image.memory(
                  preview.bytes,
                  fit: BoxFit.contain,
                  // Keeps the last frame on screen while the next render is
                  // decoded, which is what makes this feel live.
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.none,
                  semanticLabel: S.livePreview,
                ),
              ),
            ),
          if (isLoading)
            const Positioned(
              right: AppSpacing.md,
              top: AppSpacing.md,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          if (preview != null && preview.width != null && preview.height != null)
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              child: _SizeChip(
                label: '${preview.width} × ${preview.height} px',
              ),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.qr_code_2_rounded,
          size: 44,
          color: AppColors.inkFaint,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          S.barcodePreviewHint,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.inkStrong.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.inkInverse),
      ),
    );
  }
}

/// The transparency checkerboard.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter({this.cell = 10});

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint light = Paint()..color = AppColors.surface;
    final Paint dark = Paint()..color = AppColors.border;

    canvas.drawRect(Offset.zero & size, light);

    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool shade = ((x ~/ cell) + (y ~/ cell)).isOdd;
        if (shade) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) =>
      oldDelegate.cell != cell;
}
