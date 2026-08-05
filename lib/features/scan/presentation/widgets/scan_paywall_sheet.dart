/// The one wall in the free scanner.
///
/// It arrives at the moment the user tries to create their fourth PDF, and not
/// before: they have already seen the feature work three times, so this is an
/// offer rather than a gate. That ordering is the whole design — a wall shown
/// on first launch converts a fraction as well and reads to a store reviewer as
/// a login screen wearing a product's clothes.
///
/// Two rules it follows, both worth keeping:
///
///   * **It says what is free.** Reading and opening PDFs are not metered and
///     never will be; if the sheet did not say so, the user would reasonably
///     assume the whole app just locked.
///   * **It offers sign-in too.** A returning user who reinstalled hits this
///     sheet with an account they already have, and "Create account" alone
///     would send them the long way round.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

Future<void> showScanPaywall(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
    builder: (BuildContext ctx) => const _ScanPaywallSheet(),
  );
}

class _ScanPaywallSheet extends StatelessWidget {
  const _ScanPaywallSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.brandTint,
                borderRadius: AppRadius.smallAll,
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.brandDeep,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'That is your ${AppConfig.freeScanPdfs} free PDFs',
              style: AppText.h2,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a free account and scanning is unlimited — plus PDF '
              'conversion, bank statement extraction, e-signature and barcodes.',
              style: AppText.body.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _Point(text: 'Unlimited scan to PDF'),
            const _Point(text: 'Your PDFs synced to the workspace'),
            const _Point(text: 'Opening and reading PDFs stays free either way'),

            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(AppRoute.register);
              },
              child: const Text('Create a free account'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(AppRoute.login);
              },
              child: const Text('I already have an account'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.brand,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppText.bodySm)),
        ],
      ),
    );
  }
}
