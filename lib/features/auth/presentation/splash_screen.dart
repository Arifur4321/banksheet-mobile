/// The launch hold.
///
/// The router parks here until [TokenStore.restore] has read the keychain, so
/// this screen exists to make one unavoidable async gap look deliberate rather
/// than like a stalled app. It never decides anything itself — see the redirect
/// in `app/router.dart` — and it never fetches: a spinner that also owns logic
/// is a spinner that can get stuck.
///
/// It now runs the same animated scene as the welcome screen instead of a
/// static mark and a spinner. That is worth the few frames: on a cold start
/// this is the only thing on screen, and a moving 3D document says "working"
/// far better than a circle going round — which every stalled app in the world
/// also shows.
///
/// A subtle point: the scene loops on a six-second timeline and the keychain
/// read usually finishes in well under one, so most users see only the opening
/// beat. It is built to look intentional at any frame it happens to be cut off
/// at, rather than needing to complete.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/pdf_scene.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
              final double scene =
                  (constraints.maxHeight * 0.30).clamp(150.0, 260.0);

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.section),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PdfShowcaseScene(height: scene, showPill: false),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        S.appName,
                        style: AppText.h1.copyWith(
                          color: AppColors.inkInverse,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        S.tagline,
                        textAlign: TextAlign.center,
                        style: AppText.bodySm.copyWith(
                          color:
                              AppColors.inkInverse.withValues(alpha: 0.66),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // Kept for the screen-reader announcement and for the
                      // rare slow keychain read; visually it is now secondary
                      // to the scene rather than the main event.
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.brandLight.withValues(alpha: 0.7),
                          semanticsLabel: S.loading,
                        ),
                      ),
                    ],
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
