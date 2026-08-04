/// A navigation row: icon, label, one-line description, chevron.
///
/// Shared by the More hub and the settings list so the two read as one surface
/// rather than as two lists that happen to look similar. The whole row is one
/// tap target of at least 56dp — comfortably over the 48dp accessibility
/// minimum and the size a thumb actually hits — and it publishes a single
/// merged semantic label, so a screen reader announces "Templates, fill one in,
/// get a PDF back, button" instead of four separate nodes.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

class NavRow extends StatelessWidget {
  const NavRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    super.key,
    this.trailingLabel,
    this.badgeLabel,
  });

  final IconData icon;
  final String label;

  /// One line of "what is behind this row", so the user does not have to open
  /// it to find out.
  final String description;

  final VoidCallback onTap;

  /// A value shown before the chevron, e.g. the current plan name.
  final String? trailingLabel;

  /// A small emphasis chip, e.g. "Upgrade" on a free workspace.
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final String? trailing = trailingLabel;
    final String? badge = badgeLabel;

    return Semantics(
      button: true,
      label: <String>[
        label,
        description,
        if (trailing != null && trailing.isNotEmpty) trailing,
        if (badge != null && badge.isNotEmpty) badge,
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.brandTint,
                      borderRadius: AppRadius.smallAll,
                    ),
                    child: Icon(icon, size: 19, color: AppColors.brandDeep),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: AppText.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          description,
                          style: AppText.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null && trailing.isNotEmpty) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        trailing,
                        style: AppText.bodySm.copyWith(color: AppColors.ink),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (badge != null && badge.isNotEmpty) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    _Badge(label: badge),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Upgrade" chip. Deliberately quiet — a nudge, not an advertisement.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: AppColors.brandDeep,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
