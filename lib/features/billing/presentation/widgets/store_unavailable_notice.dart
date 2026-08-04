/// What the purchase section shows when the store cannot sell anything.
///
/// Two different failures, told apart because the remedy is different:
///
///  * [StoreUnavailableNotice] — this device cannot buy at all. A restricted
///    profile, parental controls, a simulator, or a device with no store. There
///    is nothing the user can do in the app, so it says where they can
///    subscribe instead rather than leaving dead buttons on screen.
///  * [StoreProductsIncompleteNotice] — the store answered but did not know
///    about some of the products the server offers. That is a store console
///    that has not been finished, and hiding it would make a configuration
///    mistake look like a deliberately shorter plan list.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';

class StoreUnavailableNotice extends StatelessWidget {
  const StoreUnavailableNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.warnTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 20,
                  color: AppColors.warn,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(S.storeUnavailableTitle, style: AppText.h3),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(S.storeUnavailableBody, style: AppText.bodySm),
        ],
      ),
    );
  }
}

class StoreProductsIncompleteNotice extends StatelessWidget {
  const StoreProductsIncompleteNotice({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return InlineNotice(
      message: S.storeProductsMissing,
      tone: NoticeTone.warn,
      actionLabel: onRetry == null ? null : S.tryAgain,
      onAction: onRetry,
    );
  }
}
