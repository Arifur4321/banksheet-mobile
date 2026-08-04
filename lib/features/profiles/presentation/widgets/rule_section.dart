/// The read-only vocabulary the profile detail screen is built from.
///
/// A profile is four JSON documents of regular expressions. Dumping them on the
/// screen would be honest and useless; these four widgets turn them into
/// labelled rows and chip lists a person can actually read, and [RuleJsonBlock]
/// keeps the exact source one tap away for anyone who wants it.
///
/// A section with nothing in it renders as nothing at all — a profile that sets
/// no post-processing rules should not show an empty heading for them.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';

/// A monospace stack that resolves on both platforms: `monospace` is the family
/// Android understands, Menlo is the one iOS ships.
const List<String> _monoFallback = <String>['Menlo', 'Courier New'];

/// A titled group of rule rows.
class RuleSection extends StatelessWidget {
  const RuleSection({
    required this.title,
    required this.children,
    super.key,
    this.icon,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 17, color: AppColors.brandDeep),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(title, style: AppText.h3)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled value.
class RuleRow extends StatelessWidget {
  const RuleRow({
    required this.label,
    required this.value,
    super.key,
    this.monospace = false,
  });

  final String label;
  final String value;

  /// True for a regular expression, where every character matters and a
  /// proportional font makes it unreadable.
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(label, style: AppText.bodySm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: monospace
                  ? AppText.caption.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: _monoFallback,
                      color: AppColors.ink,
                    )
                  : AppText.bodySm.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled list of short strings — keywords, headers, ignore patterns.
class RuleChips extends StatelessWidget {
  const RuleChips({
    required this.label,
    required this.values,
    super.key,
    this.monospace = false,
  });

  final String label;
  final List<String> values;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppText.bodySm),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String value in values)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    value,
                    style: monospace
                        ? AppText.caption.copyWith(
                            fontFamily: 'monospace',
                            fontFamilyFallback: _monoFallback,
                            color: AppColors.inkBody,
                          )
                        : AppText.caption.copyWith(color: AppColors.inkBody),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One rule blob, pretty printed, with a copy button.
///
/// Horizontally scrollable rather than wrapped: a regular expression broken
/// across lines at an arbitrary column is worse than one you have to scroll.
class RuleJsonBlock extends StatelessWidget {
  const RuleJsonBlock({required this.title, required this.data, super.key});

  final String title;
  final Map<String, dynamic> data;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Encoding can throw on a value `jsonEncode` does not know — never true for
  /// something that arrived as JSON, but this is a debug view and it must not
  /// be the thing that breaks the screen.
  String get _pretty {
    try {
      return _encoder.convert(data);
    } on JsonUnsupportedObjectError {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String text = _pretty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: AppText.label)),
              IconButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) {
                    return;
                  }
                  Toast.success(context, S.copied);
                },
                tooltip: S.copied,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.inkStrong,
              borderRadius: AppRadius.smallAll,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                text,
                style: AppText.caption.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: _monoFallback,
                  color: AppColors.inkInverse,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
