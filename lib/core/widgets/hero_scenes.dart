/// Per-page 3D headers.
///
/// The brief asked for "nice 3d design in flutter based on pages" — meaning a
/// different composition per section rather than one decoration reused. Each
/// scene below is built from the same primitives in `scene_3d.dart` (a
/// perspective stage, depth-separated layers, a bloom behind) so they feel like
/// one family, and each one depicts what its page actually does.
///
/// They are decorative: everything is wrapped in [ExcludeSemantics] and none of
/// them animate content the user needs to read.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'scene_3d.dart';

/// Shared shell: a dark forest panel with a bloom, the eyebrow/title block on
/// the left and the 3D stage floating on the right.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    required this.eyebrow,
    required this.title,
    required this.scene,
    super.key,
    this.subtitle,
    this.trailing,
    this.height = 196,
    this.background = AppColors.inkStrong,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget scene;
  final Widget? trailing;
  final double height;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.cardAll,
        boxShadow: AppShadows.lifted,
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -30,
            top: -20,
            bottom: -20,
            width: 220,
            child: ExcludeSemantics(child: scene),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  eyebrow.toUpperCase(),
                  style: AppText.eyebrow.copyWith(color: AppColors.brandLight),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: 210,
                  child: Text(
                    title,
                    style: AppText.h2.copyWith(color: AppColors.inkInverse),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: 210,
                    child: Text(
                      subtitle!,
                      style: AppText.bodySm.copyWith(
                        color: AppColors.inkInverse.withValues(alpha: 0.72),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (trailing != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks shared by the scenes
// ---------------------------------------------------------------------------

/// A sheet of paper with ruled lines — the atom of most scenes, and a direct
/// port of `.bs-esign__paper` (linear gradient, 0.85rem radius, deep shadow).
class _Sheet extends StatelessWidget {
  const _Sheet({
    this.width = 108,
    this.height = 132,
    this.lines = 5,
    this.accent,
    this.tint,
  });

  final double width;
  final double height;
  final int lines;
  final Color? accent;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tint ?? AppColors.paperWhite,
            (tint ?? AppColors.paperWhite) == AppColors.paperWhite
                ? const Color(0xFFF4F1E8)
                : (tint ?? AppColors.paperWhite),
          ],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        boxShadow: AppShadows.deep,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent ?? AppColors.jade,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 22,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.forestSoft.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (int i = 0; i < lines; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                width: width * (i.isEven ? 0.62 : 0.48),
                height: 3.5,
                decoration: BoxDecoration(
                  color: AppColors.forestSoft.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A miniature spreadsheet grid — used wherever the output is a table.
class _Grid extends StatelessWidget {
  const _Grid({this.columns = 4, this.rows = 5, this.width = 116});

  final int columns;
  final int rows;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        boxShadow: AppShadows.deep,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < columns; c++)
                    Expanded(
                      child: Container(
                        height: 7,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: r == 0
                              ? AppColors.jade.withValues(alpha: 0.75)
                              : AppColors.forestSoft.withValues(
                                  alpha: (c == columns - 1) ? 0.26 : 0.12,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A soft glass chip used to label a plane inside a scene.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color = AppColors.jadeBright});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The scenes, one per section
// ---------------------------------------------------------------------------

/// Dashboard — a statement sheet turning into a spreadsheet, the product in one
/// picture.
class DashboardScene extends StatelessWidget {
  const DashboardScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 240),
        const DepthLayer(
          z: -26,
          offset: Offset(-30, 6),
          rotation: -7,
          child: _Sheet(width: 96, height: 118, lines: 4),
        ),
        DepthLayer(
          z: 34,
          offset: const Offset(24, -8),
          rotation: 5,
          child: const _Grid(),
        ),
        const DepthLayer(z: 78, offset: Offset(6, 62), child: _Chip('XLSX')),
      ],
    );
  }
}

/// Documents — a stack of PDFs being lifted off the pile.
class DocumentsScene extends StatelessWidget {
  const DocumentsScene({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        GlowOrb(size: 220, color: AppColors.jade),
        DepthLayer(
          z: -40,
          offset: Offset(-6, 18),
          rotation: -10,
          child: _Sheet(width: 94, height: 116, lines: 4),
        ),
        DepthLayer(
          z: -6,
          offset: Offset(2, 6),
          rotation: -3,
          child: _Sheet(width: 98, height: 120, lines: 5),
        ),
        DepthLayer(
          z: 48,
          offset: Offset(12, -12),
          rotation: 4,
          child: _Sheet(width: 102, height: 124, lines: 6, accent: AppColors.amber),
        ),
      ],
    );
  }
}

/// Review queue — rows being ticked off.
class ReviewScene extends StatelessWidget {
  const ReviewScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 230),
        const DepthLayer(z: -18, offset: Offset(-4, 4), child: _Grid(rows: 6)),
        DepthLayer(
          z: 62,
          offset: const Offset(34, -30),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.jadeBright,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppShadows.deep,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }
}

/// PDF tools — sheets fanning through a converter.
class ToolsScene extends StatelessWidget {
  const ToolsScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 226, color: AppColors.amber, opacity: 0.24),
        for (int i = 0; i < 3; i++)
          DepthLayer(
            z: -30.0 + i * 34,
            offset: Offset(-18.0 + i * 16, 14.0 - i * 12),
            rotation: -12.0 + i * 8,
            child: _Sheet(
              width: 86,
              height: 108,
              lines: 4,
              accent: i == 2 ? AppColors.amber : AppColors.jade,
            ),
          ),
      ],
    );
  }
}

/// Barcode — a slab of bars floating over its label.
class BarcodeScene extends StatelessWidget {
  const BarcodeScene({super.key});

  @override
  Widget build(BuildContext context) {
    final math.Random rnd = math.Random(7);
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 220),
        DepthLayer(
          z: 30,
          rotation: -4,
          child: Container(
            width: 128,
            height: 96,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.paperWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppShadows.deep,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < 22; i++)
                  Container(
                    width: rnd.nextBool() ? 3 : 1.6,
                    margin: const EdgeInsets.only(right: 1.6),
                    color: AppColors.inkStrong,
                  ),
              ],
            ),
          ),
        ),
        const DepthLayer(z: 84, offset: Offset(0, 62), child: _Chip('QR · EAN · CODE128')),
      ],
    );
  }
}

/// E-sign — the site's own signature scene: a page, a pen and a seal.
class SignatureScene extends StatelessWidget {
  const SignatureScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 230),
        const DepthLayer(z: 0, child: _Sheet(width: 108, height: 132, lines: 5)),
        DepthLayer(
          z: 52,
          offset: const Offset(-4, 34),
          rotation: -6,
          child: CustomPaint(
            size: const Size(96, 34),
            painter: _SignaturePainter(),
          ),
        ),
        DepthLayer(
          z: 86,
          offset: const Offset(46, -40),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amber,
              boxShadow: AppShadows.deep,
            ),
            child: const Icon(Icons.verified_rounded,
                color: AppColors.forest, size: 22),
          ),
        ),
      ],
    );
  }
}

/// Web extraction — a globe of nodes resolving into a contact row.
class WebScene extends StatelessWidget {
  const WebScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 234, color: AppColors.jade),
        DepthLayer(
          z: -10,
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.jadeBright.withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
            child: CustomPaint(painter: _MeridianPainter()),
          ),
        ),
        const DepthLayer(z: 66, offset: Offset(22, 44), child: _Chip('@ contacts')),
      ],
    );
  }
}

/// Billing — three plan cards stepping toward the viewer.
class BillingScene extends StatelessWidget {
  const BillingScene({super.key});

  @override
  Widget build(BuildContext context) {
    const List<Color> tints = <Color>[
      AppColors.forestSoft,
      AppColors.jade,
      AppColors.jadeBright,
    ];
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 228, color: AppColors.amber, opacity: 0.22),
        for (int i = 0; i < 3; i++)
          DepthLayer(
            z: -34.0 + i * 40,
            offset: Offset(-24.0 + i * 20, 22.0 - i * 16),
            rotation: -8.0 + i * 6,
            child: Container(
              width: 74,
              height: 96,
              decoration: BoxDecoration(
                color: tints[i],
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppShadows.deep,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Settings / account — a stack of concentric plates.
class AccountScene extends StatelessWidget {
  const AccountScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 220,
      interactive: false,
      children: <Widget>[
        const GlowOrb(size: 210),
        for (int i = 0; i < 3; i++)
          DepthLayer(
            z: -20.0 + i * 36,
            child: Container(
              width: 116.0 - i * 22,
              height: 116.0 - i * 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == 2
                    ? AppColors.jadeBright
                    : Colors.white.withValues(alpha: 0.10 + i * 0.06),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                boxShadow: i == 2 ? AppShadows.deep : null,
              ),
              child: i == 2
                  ? const Icon(Icons.person_rounded,
                      color: AppColors.forest, size: 30)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Auth — the signature scene at rest, used behind the welcome screen.
class WelcomeScene extends StatelessWidget {
  const WelcomeScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Scene3D(
      height: 280,
      children: <Widget>[
        const GlowOrb(size: 300, opacity: 0.40),
        const DepthLayer(
          z: -44,
          offset: Offset(-52, 14),
          rotation: -11,
          child: _Sheet(width: 104, height: 128, lines: 5),
        ),
        DepthLayer(
          z: 26,
          offset: const Offset(46, -10),
          rotation: 6,
          child: const _Grid(width: 124, rows: 6),
        ),
        DepthLayer(
          z: 96,
          offset: const Offset(-6, 76),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.jadeBright,
              borderRadius: BorderRadius.circular(999),
              boxShadow: AppShadows.deep,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.bolt_rounded,
                    size: 15, color: AppColors.forest),
                const SizedBox(width: 5),
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
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _SignaturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.forest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path()
      ..moveTo(size.width * 0.04, size.height * 0.72)
      ..cubicTo(size.width * 0.20, size.height * 0.05, size.width * 0.30,
          size.height * 1.02, size.width * 0.44, size.height * 0.44)
      ..cubicTo(size.width * 0.56, size.height * 0.02, size.width * 0.62,
          size.height * 0.94, size.width * 0.76, size.height * 0.52)
      ..cubicTo(size.width * 0.86, size.height * 0.22, size.width * 0.92,
          size.height * 0.62, size.width * 0.99, size.height * 0.40);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeridianPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.jadeBright.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final Offset centre = Offset(size.width / 2, size.height / 2);

    for (int i = 1; i <= 3; i++) {
      final double w = size.width * (i / 4);
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: w, height: size.height),
        paint,
      );
    }
    canvas.drawLine(
      Offset(0, centre.dy),
      Offset(size.width, centre.dy),
      paint,
    );

    final Paint node = Paint()..color = AppColors.jadeBright;
    for (final Offset o in <Offset>[
      Offset(size.width * 0.22, size.height * 0.34),
      Offset(size.width * 0.74, size.height * 0.28),
      Offset(size.width * 0.58, size.height * 0.74),
      Offset(size.width * 0.30, size.height * 0.66),
    ]) {
      canvas.drawCircle(o, 2.6, node);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
