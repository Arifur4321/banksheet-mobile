/// The launch animation: loose pages becoming one bound PDF.
///
/// Separate from [PdfShowcaseScene] on purpose. That scene tells the *product*
/// story — a statement becoming a spreadsheet — over six seconds, and it is
/// right for the welcome screen, where the user is reading and deciding.
///
/// This one has a different job. It plays while the app is starting, so it has
/// to satisfy three constraints the showcase does not:
///
///   * **It must read as progress, not as decoration.** A user staring at a
///     cold start wants to know something is happening. So the loop is short
///     (2.4s), it always moves in the same direction, and a determinate-looking
///     sweep crosses the stack once per cycle.
///   * **It must look right cut off at any frame.** Startup finishes when it
///     finishes; an animation with a payoff at 90% would be seen by nobody.
///     Every frame here is a legible arrangement of pages.
///   * **It must be cheap.** This runs while the engine is still warming and
///     the keychain is being read. One [AnimationController], one
///     [CustomPainter], no images, no Rive, no Lottie, nothing new in
///     `pubspec.yaml`.
///
/// The loop, in one sentence: three sheets rise in sequence from below, stack
/// with a slight fan, a scan bar sweeps down the stack, and the front sheet
/// resolves into a PDF page with its corner folded and its badge lit.
///
/// Respects [MediaQueryData.disableAnimations] — a user who switched animations
/// off in accessibility settings gets the resolved final arrangement, held,
/// rather than an empty box.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PdfLoaderScene extends StatefulWidget {
  const PdfLoaderScene({
    super.key,
    this.height = 200,
    this.showBadge = true,
  });

  final double height;

  /// The "PDF" badge on the front sheet. Off when the scene is rendered small
  /// enough that the label would be unreadable.
  final bool showBadge;

  @override
  State<PdfLoaderScene> createState() => _PdfLoaderSceneState();
}

class _PdfLoaderSceneState extends State<PdfLoaderScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
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

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      _c.stop();
      // 0.72 is the beat where all three sheets have landed and the badge is
      // lit — the frame this animation is building towards.
      _c.value = 0.72;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }

    // Composed at a fixed reference size and scaled, so a 4.7" phone and a
    // tablet show the same picture rather than the same picture with different
    // margins.
    const double refW = 240;
    const double refH = 200;
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
                  builder: (BuildContext context, _) => CustomPaint(
                    painter: _LoaderPainter(
                      t: _c.value,
                      showBadge: widget.showBadge,
                    ),
                    size: const Size(refW, refH),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Eased progress for one beat of the timeline, clamped either side.
double _beat(double t, double start, double end, {Curve curve = Curves.easeOutCubic}) {
  if (end <= start) {
    return 1;
  }
  return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter({required this.t, required this.showBadge});

  final double t;
  final bool showBadge;

  /// Page geometry in reference units. A4 proportions, because the pages this
  /// app actually makes are A4 and a subtly wrong aspect ratio is the kind of
  /// thing a designer notices without being able to say why.
  static const double _pw = 92;
  static const double _ph = 122;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2 - 4);

    // The three sheets, back to front. Each enters on its own beat so they
    // arrive in sequence rather than as a single block.
    _sheet(canvas, centre, index: 2, enter: _beat(t, 0.00, 0.34));
    _sheet(canvas, centre, index: 1, enter: _beat(t, 0.12, 0.46));
    _sheet(canvas, centre, index: 0, enter: _beat(t, 0.24, 0.58), front: true);

    _scanSweep(canvas, centre);
    _progressRail(canvas, size);
  }

  /// One sheet of the stack.
  ///
  /// `index` counts back from the front, and drives every difference between
  /// the layers — offset, rotation, scale and opacity — from a single number,
  /// so the fan stays consistent if a fourth sheet is ever added.
  void _sheet(
    Canvas canvas,
    Offset centre, {
    required int index,
    required double enter,
    bool front = false,
  }) {
    if (enter <= 0) {
      return;
    }

    final double depth = index.toDouble();
    // Back sheets sit up and to the left, and are slightly smaller — a cheap,
    // reliable depth cue that costs no transform matrix.
    final double dx = -depth * 13;
    final double dy = -depth * 9 + (1 - enter) * 44;
    final double rotation = (depth * -4.5) * math.pi / 180;
    final double scale = 1 - depth * 0.05;
    final double opacity = enter * (front ? 1.0 : 0.92 - depth * 0.12);

    canvas.save();
    canvas.translate(centre.dx + dx, centre.dy + dy);
    canvas.rotate(rotation);
    canvas.scale(scale);

    final Rect page = Rect.fromCenter(
      center: Offset.zero,
      width: _pw,
      height: _ph,
    );

    // The fold is part of the page's geometry rather than a hole punched
    // through it afterwards. Clearing pixels with BlendMode.clear would work
    // on this scene's dark background and then quietly punch a transparent
    // notch through whatever surface a future caller puts it on.
    final double fold = front ? _beat(t, 0.46, 0.66) * 22 : 0;
    final Path shape = _pagePath(page, 7, fold);

    // Drop shadow. Drawn as a blurred copy rather than with an elevation,
    // because a CustomPaint has no material to elevate.
    canvas.drawPath(
      shape.shift(const Offset(0, 7)),
      Paint()
        ..color = AppColors.forest.withValues(alpha: 0.26 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.drawPath(
      shape,
      Paint()..color = AppColors.paperWhite.withValues(alpha: opacity),
    );

    if (front) {
      _frontFace(canvas, page, fold);
    } else {
      _ruledLines(canvas, page, opacity * 0.5, rows: 4);
    }

    canvas.restore();
  }

  /// A rounded page rectangle whose top-right corner is cut back by [fold].
  static Path _pagePath(Rect r, double radius, double fold) {
    if (fold <= 1) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    }

    return Path()
      ..moveTo(r.left + radius, r.top)
      ..lineTo(r.right - fold, r.top)
      ..lineTo(r.right, r.top + fold)          // the fold's diagonal
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: Radius.circular(radius),
      )
      ..close();
  }

  /// The front sheet: ruled lines, the folded flap and the PDF badge.
  void _frontFace(Canvas canvas, Rect page, double fold) {
    _ruledLines(canvas, page, 1, rows: 5);

    // The flap the fold turned back. Drawn a shade down from the page so the
    // diagonal reads as paper rather than as a missing corner.
    if (fold > 1) {
      final Path flap = Path()
        ..moveTo(page.right - fold, page.top)
        ..lineTo(page.right, page.top + fold)
        ..lineTo(page.right - fold, page.top + fold)
        ..close();
      canvas.drawPath(flap, Paint()..color = AppColors.sand);
    }

    if (!showBadge) {
      return;
    }

    // The badge pops last. `elasticOut` overshoots, which is what makes it
    // read as an event rather than as another thing fading in.
    final double pop = _beat(t, 0.58, 0.86, curve: Curves.elasticOut);
    if (pop <= 0.01) {
      return;
    }

    final Rect badge = Rect.fromCenter(
      center: Offset(0, page.bottom - 26),
      width: 54 * pop.clamp(0.0, 1.15),
      height: 20 * pop.clamp(0.0, 1.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, const Radius.circular(6)),
      Paint()..color = AppColors.jadeBright,
    );

    final TextPainter label = TextPainter(
      text: const TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: AppColors.forest,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      badge.center - Offset(label.width / 2, label.height / 2),
    );
  }

  void _ruledLines(Canvas canvas, Rect page, double opacity, {required int rows}) {
    final Paint paint = Paint()
      ..color = AppColors.sand.withValues(alpha: opacity);
    final double left = page.left + 12;
    final double maxWidth = page.width - 24;
    double y = page.top + 22;

    // Ragged line lengths. A block of identical bars reads as a barcode; this
    // reads as text.
    const List<double> fracs = <double>[1.0, 0.84, 0.94, 0.62, 0.88];
    for (int i = 0; i < rows; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y, maxWidth * fracs[i % fracs.length], 5),
          const Radius.circular(2.5),
        ),
        paint,
      );
      y += 13;
    }
  }

  /// A soft jade bar crossing the stack once per loop.
  ///
  /// This is the element doing the actual "we are working" job. It is a sweep
  /// rather than a spinner because a sweep has a direction and an end, and a
  /// spinner is what every hung app in the world also shows.
  void _scanSweep(Canvas canvas, Offset centre) {
    final double p = _beat(t, 0.20, 0.78, curve: Curves.easeInOut);
    if (p <= 0 || p >= 1) {
      return;
    }

    // Fade in and out at the extremes so the bar never pops on or off.
    final double alpha = math.sin(p * math.pi).clamp(0.0, 1.0);
    final double y = centre.dy - _ph / 2 + _ph * p;

    final Rect band = Rect.fromLTWH(
      centre.dx - _pw / 2 - 16,
      y - 10,
      _pw + 32,
      20,
    );
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.jadeBright.withValues(alpha: 0),
            AppColors.jadeBright.withValues(alpha: 0.42 * alpha),
            AppColors.jadeBright.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.drawRect(
      Rect.fromLTWH(centre.dx - _pw / 2 - 8, y - 0.9, _pw + 16, 1.8),
      Paint()..color = AppColors.jadeBright.withValues(alpha: 0.85 * alpha),
    );
  }

  /// A thin rail under the stack that fills across the loop.
  ///
  /// It is honest about being indeterminate — it resets every cycle rather than
  /// creeping towards 99% and stopping, which is the pattern users have learned
  /// to read as "stuck".
  void _progressRail(Canvas canvas, Size size) {
    const double railWidth = 96;
    final double left = (size.width - railWidth) / 2;
    final double top = size.height - 14;

    final RRect track = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, railWidth, 3),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(
      track,
      Paint()..color = AppColors.paperWhite.withValues(alpha: 0.16),
    );

    final double fill = Curves.easeInOutCubic.transform(t);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, railWidth * fill, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = AppColors.jadeBright.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.t != t || old.showBadge != showBadge;
}
