/// The first screen a new user and a store reviewer ever see.
///
/// It has one job: say what the product does in four seconds and offer four
/// ways forward, in two clearly separated pairs.
///
/// **Try it** — Open PDF, Scan to PDF. These do the thing immediately, with no
/// account, and they are the first controls the eye lands on. This pair
/// replaced a single "Just open a PDF — no account" text link that led to a
/// second landing screen making the same argument again; the link is gone, that
/// screen is gone, and the two actions it was standing in for are now on this
/// one directly. A text link is what you write when you are unsure the feature
/// deserves a button. These deserve buttons.
///
/// **Sign up / sign in** — the account pair, below, where a user who has
/// already decided goes.
///
/// The order matters more than it looks. An app that leads with a login wall
/// converts far worse in a closed test, and reads to a store reviewer as a
/// login screen rather than a product.
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/pdf_scene.dart';
import '../../home/presentation/home_screen.dart' show PrimaryActionTile;
import '../../scan/domain/scan_page.dart';
import '../../scan/presentation/providers.dart';
import '../../viewer/presentation/providers.dart';
import 'widgets/auth_shell.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  /// Opens the system picker and goes straight to the reader.
  ///
  /// Deliberately the same two lines the home screen runs, rather than routing
  /// through a shared screen: the whole point of removing the guest landing
  /// page was that tapping "Open PDF" should open a PDF, not open a page that
  /// offers to open a PDF.
  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    final RecentFile? picked =
        await ref.read(recentFilesRepositoryProvider).pickPdf();

    // Null means the user backed out of the picker — an ordinary outcome.
    if (picked == null || !context.mounted) {
      return;
    }

    context.pushNamed(
      AppRoute.pdfView,
      queryParameters: <String, String>{
        'path': picked.path,
        'title': picked.filename,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> freeLeft = ref.watch(freeScansLeftProvider);

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

              // Bands rather than a continuous scale: a formula that is smooth
              // everywhere ends up wrong everywhere, and phones cluster into
              // roughly these heights once the safe area is gone.
              final bool tiny = h < 600;
              final bool short = h < 720;

              // The fourth band, and the one added when the two action tiles
              // arrived. Only a genuinely tall phone can afford the full-size
              // tiles *and* the value bullets underneath them; everything
              // shorter gets compact tiles and no bullets. 780 is where an
              // iPhone 15 (759pt of safe area) falls on the short side, which
              // is deliberate — it is not a tall phone once the notch and the
              // home indicator are gone.
              final bool roomy = h >= 780;

              // These fractions are not taste. `tool/welcome_budget.py`
              // computes this column's height from the same constants for every
              // phone size we support, and these are the largest values that
              // leave every device above zero. Raising one puts the sign-in
              // button under the fold on a 320x548 screen — run that script
              // before changing them.
              final double scene = (h * (tiny ? 0.15 : (short ? 0.17 : 0.20)))
                  .clamp(84.0, 232.0);
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

                          // --- try it, no account ------------------------
                          //
                          // Two peers, side by side and equally weighted. Open
                          // PDF is brand-filled because it is the cheapest
                          // possible first success — one tap, a file the user
                          // already has, no permission prompt.
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: PrimaryActionTile(
                                  icon: Icons.folder_open_rounded,
                                  label: 'Open PDF',
                                  caption: 'From this phone',
                                  filled: true,
                                  compact: !roomy,
                                  onTap: () => _openPdf(context, ref),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: PrimaryActionTile(
                                  icon: Icons.document_scanner_rounded,
                                  label: 'Scan to PDF',
                                  caption: 'Photos to pages',
                                  onDark: true,
                                  compact: !roomy,
                                  onTap: () => context.pushNamed(
                                    AppRoute.scan,
                                    queryParameters: <String, String>{
                                      'source': ScanSource.camera.name,
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: gapSm),
                          Text(
                            _freeLine(freeLeft.valueOrNull),
                            textAlign: TextAlign.center,
                            // Bounded, because this line grows when the count
                            // arrives and an unbounded third line would push
                            // the sign-in button under the fold on a 320pt
                            // screen — the one thing this layout may not do.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: AppColors.inkInverse
                                  .withValues(alpha: 0.52),
                            ),
                          ),

                          // The product story, on phones with room for it. It
                          // is the first thing to go on a shorter screen: two
                          // working buttons say more than three bullets.
                          if (roomy) ...<Widget>[
                            SizedBox(height: gapLg),
                            _ValueRow(
                              icon: Icons.auto_awesome_motion_rounded,
                              label: S.valuePdfTools,
                              compact: tiny,
                            ),
                            SizedBox(height: gapSm),
                            _ValueRow(
                              icon: Icons.check_circle_rounded,
                              label: S.valueReconciled,
                              compact: tiny,
                            ),
                          ],

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

/// The line under the two action tiles.
///
/// Reading is unmetered and always will be, so it is stated first and without
/// qualification. The scan allowance is only mentioned once it is known —
/// showing "3 free" for a frame and then correcting it to "1 free" while the
/// database read lands would be a worse first impression than saying nothing.
String _freeLine(int? scansLeft) {
  // Kept short deliberately. At the caption size on a 320pt screen this has
  // room for about two lines, and every line it takes is a line the sign-in
  // button loses.
  const String reading = 'Reading is always free';
  if (scansLeft == null) {
    return reading;
  }
  if (scansLeft <= 0) {
    return '$reading · free scans used';
  }
  return '$reading · $scansLeft of ${AppConfig.freeScanPdfs} free scans left';
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
