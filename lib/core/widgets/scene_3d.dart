/// The 3D scene kit.
///
/// The BankSheet Pro website already ships a real 3D scene — `.bs-esign` in
/// `resources/css/app.css`. Its recipe is:
///
///   * `perspective: 1100px` on the *viewport*, never on the transformed
///     element (putting it on the element makes depth shift as it rotates),
///   * `transform-style: preserve-3d` on the stage,
///   * a resting pose of `rotateX(14deg) rotateY(-13deg)`,
///   * pointer tilt written into `--bs-rx` / `--bs-ry`, eased with
///     `cubic-bezier(0.22, 1, 0.36, 1)` over 420 ms,
///   * a blurred radial glow parked at `translateZ(-70px)`,
///   * a 9 s float and a 7 s content cycle.
///
/// This file is that recipe in Flutter, so the app's depth language is the same
/// one users already saw on the marketing site.
///
/// Everything here honours [MediaQuery.disableAnimationsOf] and stops ticking
/// when the route is not visible ([TickerMode]), because a perpetual 60 fps
/// matrix animation behind a pushed route is pure battery cost.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Perspective strength. `1 / 1100` reproduces the site's `perspective: 1100px`
/// at the same apparent scale.
const double _kPerspective = 1 / 1100;

/// A perspective viewport with a `preserve-3d` stage inside it.
///
/// Children are laid out in a [Stack]; use [DepthLayer] to push a child forward
/// or back along Z. Drag anywhere on the scene to tilt it — the same affordance
/// the website gives on pointer move.
class Scene3D extends StatefulWidget {
  const Scene3D({
    required this.children,
    super.key,
    this.height = 200,
    this.restingTiltX = 14,
    this.restingTiltY = -13,
    this.maxDragTilt = 10,
    this.float = true,
    this.interactive = true,
    this.alignment = Alignment.center,
  });

  /// Layers, back to front. Wrap each in a [DepthLayer] to give it a Z plane.
  final List<Widget> children;

  final double height;

  /// Resting pose in degrees, matching `.bs-esign__stage`.
  final double restingTiltX;
  final double restingTiltY;

  /// How far a drag may push the tilt past the resting pose, in degrees.
  final double maxDragTilt;

  /// Whether the stage breathes on the site's 9 s float cycle.
  final bool float;

  /// Whether dragging tilts the scene. Off for decorative headers inside a
  /// scrolling list, so a vertical drag is never stolen from the scroll view.
  final bool interactive;

  final Alignment alignment;

  @override
  State<Scene3D> createState() => _Scene3DState();
}

class _Scene3DState extends State<Scene3D> with SingleTickerProviderStateMixin {
  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: AppMotion.sceneFloat,
  );

  /// Extra tilt from the user's finger, in degrees.
  Offset _dragTilt = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.float) {
      _floatController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _handleDrag(Offset local, Size size) {
    if (!widget.interactive) {
      return;
    }
    // Normalise the touch point to [-1, 1] around the centre, then scale to the
    // permitted tilt. Y drag rotates about X and vice versa — that inversion is
    // what makes the surface feel like it is being pushed rather than steered.
    final double nx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final double ny = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() {
      _dragTilt = Offset(-ny * widget.maxDragTilt, nx * widget.maxDragTilt);
    });
  }

  void _release() {
    if (_dragTilt != Offset.zero) {
      setState(() => _dragTilt = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = constraints.biggest;

          final Widget stage = AnimatedBuilder(
            animation: _floatController,
            builder: (BuildContext context, Widget? child) {
              // A gentle ±1.5° breath, mirroring `bs-esign-float`.
              final double breath = reduceMotion
                  ? 0
                  : math.sin(_floatController.value * math.pi * 2) * 1.5;

              final double rx = widget.restingTiltX + _dragTilt.dx + breath;
              final double ry = widget.restingTiltY + _dragTilt.dy;

              final Matrix4 matrix = Matrix4.identity()
                // Row 3 column 2 is the perspective term. It must be applied
                // before the rotations so depth is computed in viewport space.
                ..setEntry(3, 2, _kPerspective)
                ..rotateX(rx * math.pi / 180)
                ..rotateY(ry * math.pi / 180);

              return Transform(
                alignment: widget.alignment,
                transform: matrix,
                child: child,
              );
            },
            child: Stack(
              alignment: widget.alignment,
              clipBehavior: Clip.none,
              children: widget.children,
            ),
          );

          // AnimatedContainer would rebuild the subtree; an implicit tween on
          // the tilt alone is cheaper and matches the site's 420 ms ease.
          final Widget eased = TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(begin: _dragTilt, end: _dragTilt),
            duration: AppMotion.slow,
            curve: AppMotion.tilt,
            builder: (_, __, Widget? child) => child!,
            child: stage,
          );

          if (!widget.interactive) {
            return eased;
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails d) =>
                _handleDrag(d.localPosition, size),
            onPanUpdate: (DragUpdateDetails d) =>
                _handleDrag(d.localPosition, size),
            onPanEnd: (_) => _release(),
            onPanCancel: _release,
            child: eased,
          );
        },
      ),
    );
  }
}

/// Places a child on a Z plane inside a [Scene3D].
///
/// Positive [z] moves the layer toward the viewer. A scale correction keeps the
/// layer's apparent size stable so depth reads as depth rather than as "the
/// front thing is just bigger".
class DepthLayer extends StatelessWidget {
  const DepthLayer({
    required this.child,
    super.key,
    this.z = 0,
    this.offset = Offset.zero,
    this.rotation = 0,
    this.opacity = 1,
    this.compensateScale = true,
  });

  final Widget child;

  /// Depth in logical pixels. The site uses roughly -70 … +90.
  final double z;

  /// In-plane nudge applied before the depth translation.
  final Offset offset;

  /// Roll about the Z axis, in degrees.
  final double rotation;

  final double opacity;

  /// Divide out the perspective magnification introduced by [z].
  final bool compensateScale;

  @override
  Widget build(BuildContext context) {
    // With a perspective term p, a plane at depth z is magnified by
    // 1 / (1 - z*p). Undo it so the designer's sizes are the sizes on screen.
    final double scale = compensateScale ? (1 - z * _kPerspective) : 1.0;

    final Matrix4 matrix = Matrix4.identity()
      ..translate(offset.dx, offset.dy, z)
      ..rotateZ(rotation * math.pi / 180)
      ..scale(scale, scale, 1.0);

    final Widget positioned = Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: child,
    );

    return opacity >= 1
        ? positioned
        : Opacity(opacity: opacity, child: positioned);
  }
}

/// The blurred radial bloom the site parks behind its 3D stages
/// (`.bs-esign__glow`, `translateZ(-70px)`).
class GlowOrb extends StatelessWidget {
  const GlowOrb({
    super.key,
    this.color = AppColors.jadeBright,
    this.size = 260,
    this.opacity = 0.34,
    this.z = -70,
  });

  final Color color;
  final double size;
  final double opacity;
  final double z;

  @override
  Widget build(BuildContext context) {
    return DepthLayer(
      z: z,
      compensateScale: false,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size * 0.7,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.7)),
            gradient: RadialGradient(
              colors: <Color>[
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.68],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card that tilts toward the touch point and lifts its shadow while pressed.
///
/// Used for tappable feature tiles so the whole app shares one depth idiom
/// instead of only the hero headers having dimension.
class TiltCard extends StatefulWidget {
  const TiltCard({
    required this.child,
    super.key,
    this.onTap,
    this.maxTilt = 7,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.borderRadius = AppRadius.cardAll,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double maxTilt;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  Offset _tilt = Offset.zero;
  bool _pressed = false;

  void _update(Offset local, Size size) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final double nx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final double ny = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _tilt = Offset(-ny * widget.maxTilt, nx * widget.maxTilt));
  }

  void _reset() => setState(() {
        _tilt = Offset.zero;
        _pressed = false;
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        return Semantics(
          button: widget.onTap != null,
          label: widget.semanticLabel,
          child: GestureDetector(
            onTapDown: (TapDownDetails d) {
              setState(() => _pressed = true);
              _update(d.localPosition, size);
            },
            onTapUp: (_) => _reset(),
            onTapCancel: _reset,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.tilt,
              transform: Matrix4.identity()
                ..setEntry(3, 2, _kPerspective)
                ..rotateX(_tilt.dx * math.pi / 180)
                ..rotateY(_tilt.dy * math.pi / 180)
                ..scale(_pressed ? 0.985 : 1.0),
              transformAlignment: Alignment.center,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: widget.borderRadius,
                border: Border.all(color: widget.borderColor),
                boxShadow: _pressed ? AppShadows.lifted : AppShadows.soft,
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
