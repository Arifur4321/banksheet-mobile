/// The launch hold.
///
/// The router parks here until [TokenStore.restore] has read the keychain, so
/// this screen exists to make one unavoidable async gap look deliberate rather
/// than like a stalled app. It never decides anything itself — see the redirect
/// in `app/router.dart` — and it never fetches: a spinner that also owns logic
/// is a spinner that can get stuck.
///
/// It runs [PdfLoaderScene] — loose pages stacking into one bound PDF — rather
/// than a static mark and a spinner. That is worth the few frames: on a cold
/// start this is the only thing on screen, and moving pages say "working" far
/// better than a circle going round, which every stalled app in the world also
/// shows.
///
/// It is deliberately *not* the welcome screen's `PdfShowcaseScene`. That one
/// tells the product story over six seconds and is right for a screen the user
/// is reading and deciding on; this is a 2.4-second loop built to read as
/// progress and to look finished at whatever frame startup happens to cut it
/// off at.
///
/// The keychain read usually finishes in tens of milliseconds, which would make
/// all of this a flicker — so `SplashHold` keeps the route up for
/// [AppConfig.minimumSplash] and the router waits on both it and the token
/// restore. The native launch screen written by `tool/native/apply.py` paints
/// the same green behind it, so tapping the icon goes brand colour → brand
/// colour → this, with no white frame anywhere in the sequence.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/pdf_loader_scene.dart';

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
                      PdfLoaderScene(height: scene),
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
                      // The scene draws its own progress rail, so a second
                      // indicator would be two things claiming to report the
                      // same state. What is left is the part a rail cannot do:
                      // tell a screen reader the app is loading.
                      Semantics(
                        label: S.loading,
                        liveRegion: true,
                        child: const SizedBox.shrink(),
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
