/// The blocking overlay shown while a receipt is with the server.
///
/// It is deliberately not dismissible. Between "the store took the money" and
/// "the server wrote the plan" there is a window of a few seconds in which
/// leaving the screen — or letting the Android back gesture pop it — would send
/// the user away from the only place that reports the outcome. The transaction
/// itself survives (it stays in the store queue until the server answers), but
/// the person holding the phone has no way of knowing that, and a customer who
/// thinks they paid for nothing writes to support or asks for a refund.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

class VerifyingOverlay extends StatelessWidget {
  const VerifyingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // canPop: false swallows the back gesture and the back button for as
      // long as this is on screen.
      child: PopScope(
        canPop: false,
        child: Semantics(
          liveRegion: true,
          label: '${S.verifyingTitle}. ${S.verifyingBody}',
          child: ColoredBox(
            color: AppColors.inkStrong.withValues(alpha: 0.62),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.section),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.cardAll,
                    boxShadow: AppShadows.deep,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        S.verifyingTitle,
                        style: AppText.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        S.verifyingBody,
                        style: AppText.bodySm,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
