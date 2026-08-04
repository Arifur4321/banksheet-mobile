/// The launch hold.
///
/// The router parks here until [TokenStore.restore] has read the keychain, so
/// this screen exists to make one unavoidable async gap look deliberate rather
/// than like a stalled app. It never decides anything itself — see the redirect
/// in `app/router.dart` — and it never fetches: a spinner that also owns logic
/// is a spinner that can get stuck.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/scene_3d.dart';
import 'widgets/auth_shell.dart';

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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.section),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Scene3D(
                  height: 168,
                  interactive: false,
                  children: <Widget>[
                    GlowOrb(size: 240, opacity: 0.36),
                    DepthLayer(
                      z: 44,
                      child: BrandMark(size: 60, showWordmark: false),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  S.appName,
                  style: AppText.h1.copyWith(color: AppColors.inkInverse),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  S.tagline,
                  textAlign: TextAlign.center,
                  style: AppText.bodySm.copyWith(
                    color: AppColors.inkInverse.withValues(alpha: 0.66),
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.brandLight,
                    semanticsLabel: S.loading,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
