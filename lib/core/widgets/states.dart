/// Loading, empty and error states.
///
/// Every list and detail screen in the app routes through these three widgets,
/// so a network failure looks the same everywhere and no screen can reach a
/// dead end with nothing on it — the fastest way to fail a store review.
library;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../network/api_exception.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

/// A shimmering placeholder block. Hand rolled rather than pulled from a
/// package — it is 40 lines and removes a dependency from the critical path.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _box(0.5);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => _box(_controller.value),
    );
  }

  Widget _box(double t) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            AppColors.border,
            AppColors.surfaceMuted,
            t,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// A card-shaped skeleton used while a list loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.height = 92});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.page),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, __) => Container(
        height: height,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Skeleton(width: 160, height: 15),
            SizedBox(height: 10),
            Skeleton(width: 220, height: 11),
            SizedBox(height: 8),
            Skeleton(width: 90, height: 11),
          ],
        ),
      ),
    );
  }
}

/// Shown when a query succeeds but returns nothing.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    super.key,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColors.brandTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.brandDeep),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: AppText.h3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: AppText.bodySm, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when a request fails. Renders the server's own `detail` message when
/// there is one, because it is already specific and already localised.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.error,
    super.key,
    this.onRetry,
    this.onUpgrade,
  });

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final ApiException e = ApiException.from(error);

    final IconData icon = switch (e.code) {
      ApiException.codeOffline => Icons.wifi_off_rounded,
      ApiException.codeTimeout => Icons.hourglass_empty_rounded,
      'quota_exceeded' || 'plan_feature_required' => Icons.lock_rounded,
      'forbidden' => Icons.block_rounded,
      'not_found' => Icons.search_off_rounded,
      _ => Icons.error_outline_rounded,
    };

    final String title = switch (e.code) {
      ApiException.codeOffline => S.noConnection,
      'quota_exceeded' || 'plan_feature_required' => S.quotaReached,
      _ => e.title ?? S.somethingWentWrong,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: e.isQuota ? AppColors.warnTint : AppColors.dangerTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: e.isQuota ? AppColors.warn : AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: AppText.h3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(e.message, style: AppText.bodySm, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xl),
            if (e.isQuota && onUpgrade != null)
              FilledButton(onPressed: onUpgrade, child: const Text(S.seePlans))
            else if (onRetry != null)
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text(S.tryAgain),
              ),
          ],
        ),
      ),
    );
  }
}

/// A persistent strip shown above content while the device is offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warnTint,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warn),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              S.offline,
              style: AppText.caption.copyWith(color: AppColors.warn),
            ),
          ),
        ],
      ),
    );
  }
}

/// An inline banner for a soft failure inside an otherwise working screen.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    required this.message,
    super.key,
    this.tone = NoticeTone.info,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final NoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData icon) = switch (tone) {
      NoticeTone.info => (AppColors.info, AppColors.infoTint, Icons.info_outline_rounded),
      NoticeTone.success =>
        (AppColors.success, AppColors.successTint, Icons.check_circle_outline_rounded),
      NoticeTone.warn =>
        (AppColors.warn, AppColors.warnTint, Icons.warning_amber_rounded),
      NoticeTone.danger =>
        (AppColors.danger, AppColors.dangerTint, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: AppText.bodySm.copyWith(color: fg),
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

enum NoticeTone { info, success, warn, danger }

/// Snackbars, so success and failure feedback is identical everywhere.
abstract final class Toast {
  static void success(BuildContext context, String message) =>
      _show(context, message, AppColors.success, Icons.check_circle_rounded);

  static void error(BuildContext context, Object error) {
    final ApiException e = ApiException.from(error);
    _show(context, e.message, AppColors.danger, Icons.error_rounded);
  }

  static void info(BuildContext context, String message) =>
      _show(context, message, AppColors.inkStrong, Icons.info_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color accent,
    IconData icon,
  ) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              Icon(icon, color: accent, size: 19),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: AppText.bodySm.copyWith(color: AppColors.inkInverse),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }
}

/// A destructive-action confirmation sheet. Returns true only on explicit
/// confirmation, so `if (await confirm(...))` is always safe.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = S.confirm,
  bool destructive = false,
}) async {
  final bool? result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: AppText.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: AppText.bodySm),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                  : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
