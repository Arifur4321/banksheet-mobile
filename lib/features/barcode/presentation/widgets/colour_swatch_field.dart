/// A `#rrggbb` field with preset swatches.
///
/// A full colour wheel would be a nicer toy and a worse tool: barcode contrast
/// is a scanning requirement, not a taste question, and every preset here is a
/// pairing that scans. The hex field is still there for a brand colour, and it
/// is validated against the server's own regex before it can move the preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

/// Presets, dark first because a foreground has to be the dark one.
const List<String> kBarcodeSwatches = <String>[
  '#000000',
  '#0C0A09',
  '#065F46',
  '#1D4ED8',
  '#B91C1C',
  '#44403C',
  '#FFFFFF',
  '#FAFAF9',
  '#ECFDF5',
  '#EFF6FF',
];

class ColourSwatchField extends StatefulWidget {
  const ColourSwatchField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.error,
  });

  final String label;

  /// `#rrggbb`, upper or lower case.
  final String value;

  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? error;

  @override
  State<ColourSwatchField> createState() => _ColourSwatchFieldState();
}

class _ColourSwatchFieldState extends State<ColourSwatchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant ColourSwatchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the value moved underneath us — a swatch tap — so typing does
    // not fight the caret.
    if (widget.value.toUpperCase() != _controller.text.toUpperCase()) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Color? _parse(String hex) {
    final String clean = hex.replaceFirst('#', '').trim();
    if (clean.length != 6) {
      return null;
    }
    final int? rgb = int.tryParse(clean, radix: 16);
    return rgb == null ? null : Color(0xFF000000 | rgb);
  }

  @override
  Widget build(BuildContext context) {
    final Color? current = _parse(widget.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: current ?? AppColors.surfaceMuted,
                borderRadius: AppRadius.smallAll,
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: current == null
                  ? const Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: AppColors.inkFaint,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                maxLength: 7,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[#0-9A-Fa-f]')),
                ],
                style: AppText.body.copyWith(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '#000000',
                  errorText: widget.error,
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String swatch in kBarcodeSwatches)
              _Swatch(
                hex: swatch,
                selected: swatch.toUpperCase() == widget.value.toUpperCase(),
                onTap: widget.enabled ? () => widget.onChanged(swatch) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color colour =
        _ColourSwatchFieldState._parse(hex) ?? AppColors.surfaceMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: hex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.borderStrong,
              width: selected ? 2.4 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
