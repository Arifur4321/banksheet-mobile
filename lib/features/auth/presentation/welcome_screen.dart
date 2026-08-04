/// The first screen a new user and a store reviewer ever see.
///
/// It has one job: say what the product does in four seconds and offer three
/// ways forward — create an account, sign in, or just start reading.
///
/// **Everything must be visible without scrolling, on every phone.** That is a
/// hard requirement, not a preference: a call to action below the fold is a
/// call to action that does not exist, and "I already have an account" being
/// off-screen is how a returning user concludes the app is broken. The previous
/// version used `SliverFillRemaining` with a fixed 244px stage, which fit a
/// Pixel and pushed the sign-in button under the fold on anything shorter.
///
/// So the layout is measured, not assumed: [LayoutBuilder] hands us the real
/// height and every vertical dimension below is derived from it. The scroll
/// view underneath is a safety net for extreme text scaling, never the normal
/// path — at the default text size nothing scrolls on any phone from a 4.7"
/// upwards.
///
/// No network call happens here. It renders identically offline, which matters
/// because it is also what a user sees after being signed out on a train.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/pdf_scene.dart';
import 'widgets/auth_shell.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.inkStrong,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double h = constraints.maxHeight;

              // Three bands rather than a continuous scale: a formula that is
              // smooth everywhere ends up wrong everywhere, and phones cluster
              // into roughly these three heights once the safe area is gone.
              final bool tiny = h < 600;
              final bool short = h < 720;

              final double scene = (h * (tiny ? 0.21 : (short ? 0.24 : 0.27)))
                  .clamp(96.0, 232.0);
              final double titleSize = tiny ? 25 : (short ? 28 : 31);
              final double gapSm = tiny ? 6 : AppSpacing.sm;
              final double gapMd = tiny ? 8 : AppSpacing.md;
              final double gapLg = tiny ? 12 : AppSpacing.lg;
              final double gapXl = tiny ? 16 : (short ? 20 : AppSpacing.xxl);

              return SingleChildScrollView(
                // Clamping, not bouncing: an overscroll bounce on a screen that
                // is not meant to scroll reads as a bug.
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: h),
                  // IntrinsicHeight is what makes the Spacer below legal. A
                  // SingleChildScrollView hands its child UNBOUNDED height, and
                  // a flex child in an unbounded Column throws "RenderFlex
                  // children have non-zero flex but incoming height constraints
                  // are unbounded" at runtime — an error no static check
                  // catches, only a device. This resolves the column to a
                  // definite height first. Cheap over a dozen children; it
                  // would be the wrong tool inside a long list.
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        gapMd,
                        AppSpacing.page,
                        gapLg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: BrandMark(inverse: true),
                          ),
                          SizedBox(height: gapSm),

                          PdfShowcaseScene(height: scene),
                          SizedBox(height: gapLg),

                          Text(
                            S.welcomeTitle,
                            style: AppText.display.copyWith(
                              color: AppColors.inkInverse,
                              fontSize: titleSize,
                              height: 1.13,
                            ),
                          ),
                          SizedBox(height: gapSm),
                          Text(
                            S.welcomeBody,
                            maxLines: tiny ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(
                              fontSize: tiny ? 13.5 : null,
                              color: AppColors.inkInverse
                                  .withValues(alpha: 0.70),
                            ),
                          ),

                          SizedBox(height: gapXl),
                          _ValueRow(
                            icon: Icons.check_circle_rounded,
                            label: S.valueReconciled,
                            compact: tiny,
                          ),
                          SizedBox(height: gapSm),
                          _ValueRow(
                            icon: Icons.auto_awesome_motion_rounded,
                            label: S.valuePdfTools,
                            compact: tiny,
                          ),
                          SizedBox(height: gapSm),
                          _ValueRow(
                            icon: Icons.draw_rounded,
                            label: S.valueEsign,
                            compact: tiny,
                          ),

                          // Absorbs the slack on a tall phone so the buttons
                          // sit low, and collapses to nothing on a short one
                          // rather than forcing a scroll.
                          const Spacer(),
                          SizedBox(height: gapLg),

                          FilledButton(
                            onPressed: () =>
                                context.pushNamed(AppRoute.register),
                            child: const Text(S.createFreeAccount),
                          ),
                          SizedBox(height: gapSm),
                          OutlinedButton(
                            onPressed: () => context.pushNamed(AppRoute.login),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.inkInverse,
                              side: BorderSide(
                                color: AppColors.inkInverse
                                    .withValues(alpha: 0.26),
                              ),
                            ),
                            child: const Text(S.alreadyHaveAccount),
                          ),

                          // The reader needs no account, so say so here rather
                          // than making a first-run user guess the wall is
                          // optional. Highest-leverage line on the screen for
                          // closed-test conversion.
                          SizedBox(height: gapSm),
                          TextButton(
                            onPressed: () => context.goNamed(AppRoute.viewer),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.brandLight
                                  .withValues(alpha: 0.92),
                            ),
                            child: const Text('Just open a PDF — no account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double box = compact ? 26 : 30;

    return Row(
      children: <Widget>[
        Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
            color: AppColors.brandLight.withValues(alpha: 0.14),
            borderRadius: AppRadius.smallAll,
          ),
          child: Icon(
            icon,
            size: compact ? 15 : 17,
            color: AppColors.brandLight,
          ),
        ),
        SizedBox(width: compact ? 10 : AppSpacing.md),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong.copyWith(
              fontSize: compact ? 13.5 : null,
              color: AppColors.inkInverse.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }
}
