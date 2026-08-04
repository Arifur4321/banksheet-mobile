/// The root widget.
///
/// Deliberately thin: theme, router and a global "your app is out of date"
/// gate. Everything else belongs to a feature.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/strings.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class BankSheetApp extends ConsumerWidget {
  const BankSheetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // Clamp text scaling. The app supports large type — every layout below
        // is tested to 1.3 — but beyond that the dense transaction tables stop
        // being readable, and truncating data is worse than capping the scale.
        final MediaQueryData media = MediaQuery.of(context);
        final double clamped = media.textScaler.scale(14) / 14;

        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(clamped.clamp(0.85, 1.3)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
