/// Shared chrome for the four auth screens.
///
/// Sign in, sign up, reset and the confirmation panel all want the same thing:
/// the brand at the top, a way back, a title, and a form that stays reachable
/// when the keyboard is up. Doing that once here is what stops the three forms
/// from drifting apart, and it is the only place in the app that has to reason
/// about `viewInsets`.
///
/// [Scaffold.resizeToAvoidBottomInset] is off on purpose: letting the scroll
/// view absorb the keyboard as extra bottom padding keeps the header still and
/// scrolls only the fields, which is far less jarring than the whole page
/// jumping on every focus change.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.footer,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;

  /// The form.
  final Widget child;

  /// Pinned to the end of the scroll content — the "no account yet?" row.
  final Widget? footer;

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(showBack: showBack),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.section + keyboard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(title, style: AppText.display),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(subtitle!, style: AppText.body),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    child,
                    if (footer != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xl),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showBack});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          if (showBack)
            IconButton(
              onPressed: () => _back(context),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            )
          else
            const SizedBox(width: AppSpacing.md),
          const Spacer(),
          const BrandMark(size: 30),
        ],
      ),
    );
  }

  /// A deep link can land straight on `/login`, where there is nothing to pop.
  /// Falling back to the welcome screen means the back arrow is never a dead
  /// control.
  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(AppRoute.welcome);
    }
  }
}

/// The product mark: the emerald tile from the website's header plus the
/// wordmark.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 34,
    this.inverse = false,
    this.showWordmark = true,
  });

  final double size;

  /// Light type, for the dark welcome and splash screens.
  final bool inverse;

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.appName,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.jadeBright, AppColors.brandDark],
              ),
              borderRadius: BorderRadius.circular(size * 0.32),
              boxShadow: AppShadows.soft,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: size * 0.56,
              color: Colors.white,
            ),
          ),
          if (showWordmark) ...<Widget>[
            SizedBox(width: size * 0.28),
            ExcludeSemantics(
              child: Text(
                S.appName,
                style: AppText.h3.copyWith(
                  fontSize: size * 0.47,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: inverse ? AppColors.inkInverse : AppColors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
