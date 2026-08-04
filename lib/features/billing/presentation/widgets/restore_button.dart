/// The Restore action, and the outcome of the last one.
///
/// App Store guideline 3.1.1 requires a visible restore mechanism, and it is
/// the only recovery path for a customer who reinstalled the app, changed
/// phone, or signed in to a workspace from a device that already owns a
/// subscription. It is a card rather than a hidden menu item because a reviewer
/// has to be able to find it, and because the person who needs it is already
/// annoyed.
///
/// The result is rendered here, inline and persistent, instead of in a toast: a
/// restore that found nothing is exactly the case where the user wants to read
/// the sentence twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/plan_offer.dart';
import '../providers.dart';

class RestoreButton extends ConsumerWidget {
  const RestoreButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PurchaseState state = ref.watch(purchaseControllerProvider);
    final bool running = state.isRestoring;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.restorePurchases, style: AppText.h3),
          const SizedBox(height: AppSpacing.xs),
          const Text(S.restoreBody, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(purchaseControllerProvider.notifier).restore(),
              icon: running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded, size: 18),
              label: Text(running ? S.restoreRunning : S.restorePurchases),
            ),
          ),
          if (!running) _RestoreOutcome(state: state),
        ],
      ),
    );
  }
}

/// What the last restore concluded. Nothing at all before the first run.
class _RestoreOutcome extends StatelessWidget {
  const _RestoreOutcome({required this.state});

  final PurchaseState state;

  @override
  Widget build(BuildContext context) {
    final int? count = state.restoredCount;
    if (count == null) {
      return const SizedBox.shrink();
    }

    final List<RestoreFailure> failures = state.restoreFailures;

    final (String message, Color colour) = switch ((count, failures.isEmpty)) {
      (0, true) => (S.restoreNothing, AppColors.inkMuted),
      (0, false) => (S.restoreSomeFailed, AppColors.warn),
      (_, true) => (S.restoredCount(count), AppColors.success),
      (_, false) => (
          '${S.restoredCount(count)} · ${S.restoreSomeFailed}',
          AppColors.warn,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        message,
        style: AppText.bodySm.copyWith(color: colour),
      ),
    );
  }
}
