/// The root widget.
///
/// Thin by design: theme, router, a text-scale clamp, and the one piece of
/// app-wide plumbing that has nowhere else to live — receiving a PDF that
/// another app handed us.
///
/// That last part belongs here specifically because it has to work before any
/// screen exists. When the user taps a PDF in Gmail and picks BankSheet Pro,
/// the app cold-starts *because of* that intent; there is no screen yet to ask
/// for it, so the root asks once the first frame is on screen and routes from
/// there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/strings.dart';
import '../core/platform/incoming_pdf.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';
import 'routes.dart';

class BankSheetApp extends ConsumerStatefulWidget {
  const BankSheetApp({super.key});

  @override
  ConsumerState<BankSheetApp> createState() => _BankSheetAppState();
}

class _BankSheetAppState extends ConsumerState<BankSheetApp> {
  @override
  void initState() {
    super.initState();

    IncomingPdf.instance
      ..start()
      ..stream.listen(_open);

    // After the first frame: the router must have built and settled its initial
    // redirect before a push can land anywhere sensible.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final String? path = await IncomingPdf.instance.consumePending();
      if (path != null) {
        _open(path);
      }
    });
  }

  void _open(String path) {
    if (!mounted) {
      return;
    }
    // pushNamed rather than goNamed: the user came from another app, so Back
    // should return them there rather than stranding them on our welcome
    // screen. The reader route is in the router's guest allow-list, so this
    // works with no account — which is the whole promise of the reader.
    ref.read(routerProvider).pushNamed(
      AppRoute.pdfView,
      queryParameters: <String, String>{
        'path': path,
        'title': IncomingPdf.titleFor(path),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
