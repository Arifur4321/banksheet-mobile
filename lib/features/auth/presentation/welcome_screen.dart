/// The first screen a new user and a store reviewer ever see.
///
/// It has one job: say what the product does in four seconds and offer exactly
/// two ways forward. The dark `stone-950` panel and the 3D stage are the same
/// treatment the marketing site opens with, so the app is recognisably the same
/// product as the page that sent them here.
///
/// No network call happens on this screen. It renders identically offline,
/// which matters because it is also what a user sees after being signed out on
/// a train.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/hero_scenes.dart';
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
          child: CustomScrollView(
            slivers: <Widget>[
              SliverFillRemaining(
                // Fills the viewport when the content is shorter and scrolls
                // when it is not — which is what keeps this readable on a 4.7"
                // screen at 200% text size without a second layout.
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.lg,
                    AppSpacing.page,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(inverse: true),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SizedBox(height: 244, child: WelcomeScene()),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        S.welcomeTitle,
                        style: AppText.display.copyWith(
                          color: AppColors.inkInverse,
                          fontSize: 30,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        S.welcomeBody,
                        style: AppText.body.copyWith(
                          color: AppColors.inkInverse.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const _ValueRow(
                        icon: Icons.check_circle_rounded,
                        label: S.valueReconciled,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _ValueRow(
                        icon: Icons.auto_awesome_motion_rounded,
                        label: S.valuePdfTools,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _ValueRow(
                        icon: Icons.draw_rounded,
                        label: S.valueEsign,
                      ),
                      const SizedBox(height: AppSpacing.section),
                      FilledButton(
                        onPressed: () =>
                            context.pushNamed(AppRoute.register),
                        child: const Text(S.createFreeAccount),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: () => context.pushNamed(AppRoute.login),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.inkInverse,
                          side: BorderSide(
                            color:
                                AppColors.inkInverse.withValues(alpha: 0.26),
                          ),
                        ),
                        child: const Text(S.alreadyHaveAccount),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.brandLight.withValues(alpha: 0.14),
            borderRadius: AppRadius.smallAll,
          ),
          child: Icon(icon, size: 17, color: AppColors.brandLight),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: AppText.bodyStrong.copyWith(
              color: AppColors.inkInverse.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }
}
