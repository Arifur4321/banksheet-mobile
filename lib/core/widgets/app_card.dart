/// The card primitives every screen is built from.
///
/// These reproduce the website's card exactly: white, `rounded-3xl`, a hairline
/// `stone-200` ring, and `shadow-sm`. Using them everywhere is what makes the
/// app and the site look like the same product rather than a reskin.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A plain surface card.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.shadow = AppShadows.soft,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final List<BoxShadow> shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: borderColor),
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: content,
        ),
      ),
    );
  }
}

/// A stat tile — the dashboard's `rounded-3xl bg-white p-6` block with a
/// `text-sm text-stone-500` label above a `text-xl font-semibold` value.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    super.key,
    this.caption,
    this.icon,
    this.tone = StatTone.neutral,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final StatTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (tone) {
      StatTone.neutral => (AppColors.inkMuted, AppColors.surfaceMuted),
      StatTone.brand => (AppColors.brandDeep, AppColors.brandTint),
      StatTone.warn => (AppColors.warn, AppColors.warnTint),
      StatTone.danger => (AppColors.danger, AppColors.dangerTint),
    };

    return AppCard(
      onTap: onTap,
      semanticLabel: '$label: $value',
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: AppText.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: AppRadius.smallAll,
                  ),
                  child: Icon(icon, size: 17, color: fg),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: AppText.statValue, maxLines: 1),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: AppText.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

enum StatTone { neutral, brand, warn, danger }

/// The section heading the site uses above every card group.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppText.h3),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.bodySm),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// A status pill. Colours follow the server's own status vocabulary so the app
/// never invents a state the backend does not have.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.compact = false});

  final String status;
  final bool compact;

  static (Color, Color, String) _resolve(String raw) {
    final String s = raw.toLowerCase();
    return switch (s) {
      'processed' ||
      'completed' ||
      'succeeded' ||
      'approved' ||
      'ready' ||
      'active' ||
      'reconciled' =>
        (AppColors.brandDeep, AppColors.brandTint, 'Done'),
      'processing' || 'queued' || 'pending' || 'running' || 'uploaded' => (
          AppColors.info,
          AppColors.infoTint,
          'Working'
        ),
      'pending_review' || 'partial' || 'needs_review' || 'grace_period' => (
          AppColors.warn,
          AppColors.warnTint,
          'Review'
        ),
      'failed' ||
      'rejected' ||
      'cancelled' ||
      'expired' ||
      'unreconciled' ||
      'declined' =>
        (AppColors.danger, AppColors.dangerTint, 'Problem'),
      _ => (AppColors.inkMuted, AppColors.surfaceMuted, 'Status'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String _) = _resolve(status);
    final String label = status
        .replaceAll('_', ' ')
        .split(' ')
        .map((String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: (compact ? AppText.caption : AppText.bodySm).copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10.5 : 12,
        ),
      ),
    );
  }
}

/// A usage meter: `12 / 200` plus a bar that turns amber then red as the
/// allowance runs out.
class UsageMeter extends StatelessWidget {
  const UsageMeter({
    required this.label,
    required this.used,
    required this.limit,
    super.key,
  });

  final String label;
  final num? used;
  final num? limit;

  @override
  Widget build(BuildContext context) {
    final bool unlimited = limit == null || limit == 0;
    final double ratio =
        unlimited ? 0 : ((used ?? 0) / limit!).clamp(0.0, 1.0).toDouble();

    final Color bar = switch (ratio) {
      >= 1.0 => AppColors.danger,
      >= 0.85 => AppColors.warn,
      _ => AppColors.brand,
    };

    return Semantics(
      label: unlimited
          ? '$label: ${used ?? 0} used, unlimited'
          : '$label: ${used ?? 0} of $limit used',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: AppText.bodySm)),
              Text(
                unlimited ? '${used ?? 0}' : '${used ?? 0} / $limit',
                style: AppText.numeric.copyWith(fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: unlimited ? 0 : ratio,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(bar),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark hero panel the dashboard uses for its headline call to action
/// (`rounded-3xl bg-stone-950 p-6 text-white`).
class DarkActionCard extends StatelessWidget {
  const DarkActionCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.onTap,
    super.key,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String eyebrow;
  final String title;
  final String body;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TiltCardShim(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow.toUpperCase(),
            style: AppText.eyebrow.copyWith(color: AppColors.brandLight),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: AppText.h3.copyWith(color: AppColors.inkInverse)),
          const SizedBox(height: 6),
          Text(
            body,
            style: AppText.bodySm.copyWith(
              color: AppColors.inkInverse.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Text(
                'Open',
                style: AppText.button.copyWith(color: AppColors.brandLight),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 17, color: AppColors.brandLight),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small indirection so `DarkActionCard` gets the tilt treatment without
/// `app_card.dart` importing the 3D kit and creating a cycle.
class TiltCardShim extends StatelessWidget {
  const TiltCardShim({required this.child, required this.onTap, super.key});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: AppColors.inkStrong,
      borderColor: AppColors.forestSoft,
      shadow: AppShadows.lifted,
      child: child,
    );
  }
}
