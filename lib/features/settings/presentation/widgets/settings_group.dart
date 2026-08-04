/// A titled card of rows, divided by hairlines.
///
/// This is the site's `divide-y divide-stone-200` list inside a `rounded-3xl`
/// card. The rows are clipped to the card radius so an ink splash on the first
/// or last row cannot square off the corner — the one detail that makes a
/// hand-built list look unfinished next to a platform one.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.children,
    super.key,
    this.title,
    this.footnote,
    this.borderColor = AppColors.border,
  });

  /// Rows, in display order. Hairlines are inserted between them.
  final List<Widget> children;

  final String? title;

  /// Small print under the card — the place for a consequence the user should
  /// read before tapping, not after.
  final String? footnote;

  /// Overridden by the destructive group, which rings itself in red.
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null) SectionHeader(title: title!),
        AppCard(
          padding: EdgeInsets.zero,
          borderColor: borderColor,
          child: ClipRRect(
            borderRadius: AppRadius.cardAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _divided(),
            ),
          ),
        ),
        if (footnote != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(footnote!, style: AppText.caption),
          ),
        ],
      ],
    );
  }

  List<Widget> _divided() {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(const _Hairline());
      }
      out.add(children[i]);
    }
    return out;
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1,
      child: ColoredBox(color: AppColors.border),
    );
  }
}
