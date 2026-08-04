/// A plain settings row: label, optional value, optional action.
///
/// Where [NavRow] is "go somewhere", this is "read something or do something
/// here" — a version number, a language choice, sign out, revoke. It carries a
/// destructive tone rather than leaving each caller to colour its own red text,
/// which is how a delete row ends up looking different on two screens.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

enum SettingsRowTone { normal, destructive }

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.label,
    super.key,
    this.icon,
    this.description,
    this.value,
    this.trailing,
    this.onTap,
    this.tone = SettingsRowTone.normal,
    this.selected = false,
    this.enabled = true,
    this.showChevron = true,
    this.semanticLabel,
  });

  final String label;

  /// Leading glyph. Omitted for value rows, where the label carries itself.
  final IconData? icon;

  final String? description;

  /// The right-hand value, e.g. `1.0.0` next to "Version".
  final String? value;

  /// Replaces the default trailing widget entirely — a switch, a spinner, a
  /// text button.
  final Widget? trailing;

  final VoidCallback? onTap;
  final SettingsRowTone tone;

  /// Draws a check and tells the screen reader this option is chosen.
  final bool selected;

  final bool enabled;

  /// False for a row that acts in place — sign out, revoke — where a chevron
  /// would promise a screen that never arrives.
  final bool showChevron;

  /// Overrides the announced text when the visible layout would read badly.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool destructive = tone == SettingsRowTone.destructive;
    final bool interactive = enabled && onTap != null;

    final Color labelColour = !enabled
        ? AppColors.inkFaint
        : destructive
            ? AppColors.danger
            : AppColors.ink;

    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 20,
                color: !enabled
                    ? AppColors.inkFaint
                    : destructive
                        ? AppColors.danger
                        : AppColors.inkMuted,
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: AppText.bodyStrong.copyWith(color: labelColour),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description != null) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(
                      description!,
                      style: AppText.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  value!,
                  style: AppText.bodySm,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ] else if (selected) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.check_rounded,
                size: 20,
                color: AppColors.brand,
              ),
            ] else if (interactive && showChevron) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: interactive
          ? Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            )
          : content,
    );
  }
}
