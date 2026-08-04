/// The animated 3D hero: a PDF becoming clean data.
///
/// Separate from `hero_scenes.dart` on purpose. Those scenes are decorative
/// headers that sit inside scrolling lists, so they stay cheap and mostly
/// static. This one is the opposite: it is the first thing a new user and a
/// store reviewer see, it owns the whole viewport for a few seconds, and it has
/// to earn that space. It runs a continuous six-second story rather than a
/// float.
///
/// The story is the product in one loop:
///   0.00–0.30  a PDF page rises and tilts into view
///   0.15–0.55  a scan line sweeps down it, and each line it crosses lights up
///   0.35–0.75  a spreadsheet lifts out to the right, rows filling in order
///   0.60–0.85  the "Reconciled" pill pops
///   0.85–1.00  everything settles and breathes before the loop restarts
///
/// Everything is drawn with transforms and two [CustomPainter]s — no images, no
/// Rive, no Lottie, nothing added to `pubspec.yaml`. One [AnimationController]
/// drives every layer, so the whole scene costs a single ticker.
///
/// Respects [MediaQueryData.disableAnimations]. A user who has switched
/// animations off in Android accessibility settings gets the final frame,
/// held — not a blank box, and not motion they asked not to see.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

class PdfShowcaseScene extends StatefulWidget {
  const PdfShowcaseScene({
    super.key,
    this.height = 220,
    this.showPill = true,
  });

  final double height;

  /// The "Reconciled" badge. Off on the splash, where the scene is small and
  /// the badge would be unreadable.
  final bool showPill;

  @override
  State<PdfShowcaseScene> createState() => _PdfShowcaseSceneState();
}

class _PdfShowcaseSceneState extends State<PdfShowcaseScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6000),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Eased progress for one beat of the timeline, clamped either side.
  double _beat(double t, double start, double end, {Curve curve = Curves.easeOutCubic}) {
    if (end <= start) {
      return 1;
    }
    final double raw = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      _c.stop();
      _c.value = 0.92;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }

    // The scene is composed at a fixed reference size and scaled to whatever it
    // is given, so a phone at 360dp and a tablet at 900dp show the same picture
    // rather than the same picture with different margins.
    const double refW = 300;
    const double refH = 220;
    final double scale = widget.height / refH;

    return SizedBox(
      height: widget.height,
      child: ExcludeSemantics(
        child: ClipRect(
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width: refW,
                height: refH,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (BuildContext context, _) {
                    final double t = _c.value;

                    // A slow figure-of-eight so the whole stage drifts instead
                    // of sitting still between beats.
                    final double driftX = math.sin(t * math.pi * 2) * 4;
                    final double driftY = math.sin(t * math.pi * 4) * 3;

                    final double pageIn = _beat(t, 0.00, 0.30);
                    final double scan = _beat(t, 0.15, 0.55, curve: Curves.easeInOut);
                    final double sheetIn = _beat(t, 0.35, 0.75);
                    final double pillIn = _beat(t, 0.60, 0.85, curve: Curves.elasticOut);

                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        // ---------------------------------------- glow
                        Positioned(
                          left: 30,
                          top: 10,
                          child: _Glow(
                            size: 240,
                            opacity: 0.20 + 0.16 * math.sin(t * math.pi * 2).abs(),
                          ),
                        ),

                        // ------------------------------------ the PDF page
                        Transform.translate(
                          offset: Offset(-58 + driftX, 6 + driftY + (1 - pageIn) * 26),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0014)
                              ..rotateY(-0.22)
                              ..rotateX(0.10)
                              ..rotateZ(-0.13)
                              ..scale(0.90 + 0.10 * pageIn),
                            child: Opacity(
                              opacity: pageIn,
                              child: _Page(scan: scan),
                            ),
                          ),
                        ),

                        // -------------------------------- the spreadsheet
                        Transform.translate(
                          offset: Offset(
                            56 + driftX * 0.6,
                            -18 + driftY * 0.6 + (1 - sheetIn) * 30,
                          ),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0014)
                              ..rotateY(-0.30)
                              ..rotateX(0.13)
                              ..rotateZ(0.08)
                              ..scale(0.88 + 0.12 * sheetIn),
                            child: Opacity(
                              opacity: sheetIn,
                              child: _Sheet(fill: sheetIn),
                            ),
                          ),
                        ),

                        // ------------------------------------- the badge
                        if (widget.showPill)
                          Transform.translate(
                            offset: Offset(-14 + driftX, 74 + driftY * 0.4),
                            child: Transform.scale(
                              scale: (0.6 + 0.4 * pillIn).clamp(0.0, 1.08),
                              child: Opacity(
                                opacity: pillIn.clamp(0.0, 1.0),
                                child: const _Pill(),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              AppColors.jadeBright.withValues(alpha: opacity),
              AppColors.jade.withValues(alpha: opacity * 0.35),
              const Color(0x00000000),
            ],
            stops: const <double>[0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// The source document, with a scan line travelling down it.
class _Page extends StatelessWidget {
  const _Page({required this.scan});

  /// 0 → 1 as the scan sweeps top to bottom.
  final double scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 146,
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppShadows.deep,
      ),
      child: CustomPaint(painter: _PagePainter(scan: scan)),
    );
  }
}

class _PagePainter extends CustomPainter {
  const _PagePainter({required this.scan});

  final double scan;

  static const int _lines = 9;

  @override
  void paint(Canvas canvas, Size size) {
    const double padX = 13;
    const double top = 20;
    final double step = (size.height - top - 18) / _lines;

    // The PDF glyph, top-left.
    final Paint tag = Paint()..color = AppColors.danger.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(padX, 8, 22, 9),
        const Radius.circular(2.5),
      ),
      tag,
    );

    for (int i = 0; i < _lines; i++) {
      final double y = top + step * i;

      // A line is "read" once the scan has passed it. Lit lines turn from grey
      // to jade, which is the entire point of the animation in one detail.
      final double lineProgress = (scan * _lines) - i;
      final bool read = lineProgress > 0;
      final double t = lineProgress.clamp(0.0, 1.0);

      final double width =
          (size.width - padX * 2) * (i.isEven ? 0.92 : 0.66);

      final Paint p = Paint()
        ..color = Color.lerp(
          AppColors.sand,
          AppColors.jade.withValues(alpha: 0.85),
          read ? t : 0,
        )!
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.2;

      canvas.drawLine(
        Offset(padX, y),
        Offset(padX + width, y),
        p,
      );
    }

    // The scan line itself, with a soft leading glow.
    if (scan > 0 && scan < 1) {
      final double y = top + (size.height - top - 18) * scan;
      final Paint beam = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            AppColors.jadeBright.withValues(alpha: 0.0),
            AppColors.jadeBright,
            AppColors.jadeBright.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, y - 2, size.width, 4))
        ..strokeWidth = 2.2;

      canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), beam);
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.scan != scan;
}

/// The clean spreadsheet the statement becomes.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 112,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppShadows.lifted,
      ),
      child: CustomPaint(painter: _SheetPainter(fill: fill)),
    );
  }
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter({required this.fill});

  final double fill;

  static const int _rows = 6;
  static const int _cols = 4;

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = 9;
    final double rowH = (size.height - pad * 2) / _rows;
    final double colW = (size.width - pad * 2) / _cols;

    // Header band.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, size.width - pad * 2, rowH * 0.78),
        const Radius.circular(3),
      ),
      Paint()..color = AppColors.jade,
    );

    for (int r = 1; r < _rows; r++) {
      // Rows fill one after another rather than all at once — the difference
      // between "data appeared" and "data is being produced".
      final double t = ((fill * _rows) - r).clamp(0.0, 1.0);
      if (t <= 0) {
        continue;
      }

      for (int c = 0; c < _cols; c++) {
        final double x = pad + colW * c + 2;
        final double y = pad + rowH * r + rowH * 0.22;
        final double w = (colW - 6) * (c == _cols - 1 ? 0.72 : 0.86) * t;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, rowH * 0.34),
            const Radius.circular(2),
          ),
          Paint()
            ..color = (c == _cols - 1 ? AppColors.jade : AppColors.forestSoft)
                .withValues(alpha: 0.16 + 0.30 * t),
        );
      }
    }

    // Column rules, drawn last so they sit above the cells.
    final Paint rule = Paint()
      ..color = AppColors.forestSoft.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (int c = 1; c < _cols; c++) {
      final double x = pad + colW * c;
      canvas.drawLine(Offset(x, pad + rowH * 0.9), Offset(x, size.height - pad), rule);
    }
  }

  @override
  bool shouldRepaint(_SheetPainter old) => old.fill != fill;
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.jadeBright,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppShadows.deep,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.bolt_rounded, size: 14, color: AppColors.forest),
          const SizedBox(width: 4),
          Text(
            'Reconciled',
            style: AppText.caption.copyWith(
              color: AppColors.forest,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
