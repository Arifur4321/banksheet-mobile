/// One field of the schema-driven tool form.
///
/// Everything about how this widget renders comes from the [ToolOption] the
/// server published: a dropdown for a closed set, a stepper clamped to the
/// server's own min and max for an integer, a single-line field with the
/// server's `maxlength` and regex for a string, and a tall field for HTML,
/// variable lists and JSON.
///
/// The field owns a [TextEditingController] because a `TextField` fed straight
/// from provider state moves the caret to the end on every keystroke. The
/// controller is only written to when the value changed underneath it — a
/// reset, or the server filling in a default — which is the one case where
/// jumping the caret is correct.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../domain/tool.dart';
import '../../domain/tool_copy.dart';

class ToolOptionField extends StatefulWidget {
  const ToolOptionField({
    required this.option,
    required this.value,
    required this.onChanged,
    super.key,
    this.error,
    this.enabled = true,
    this.form = const <String, String>{},
  });

  final ToolOption option;

  /// The current raw value, or null when the field is empty.
  final String? value;

  final ValueChanged<String?> onChanged;
  final String? error;
  final bool enabled;

  /// The rest of the form, so a `required_if` option can mark itself.
  final Map<String, String> form;

  @override
  State<ToolOptionField> createState() => _ToolOptionFieldState();
}

class _ToolOptionFieldState extends State<ToolOptionField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant ToolOptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String incoming = widget.value ?? '';
    if (incoming != _controller.text) {
      _controller.value = TextEditingValue(
        text: incoming,
        selection: TextSelection.collapsed(offset: incoming.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ToolOption option = widget.option;
    final bool required = option.isRequiredIn(widget.form);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  ToolCopy.optionLabel(option.name, option.label),
                  style: AppText.label,
                ),
              ),
              Text(
                required ? S.required : S.optional,
                style: AppText.caption.copyWith(
                  color:
                      required ? AppColors.brandDeep : AppColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          switch (option.type) {
            ToolOptionType.enumChoice => _Choice(
                option: option,
                value: widget.value,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
              ),
            ToolOptionType.integer => _Stepper(
                option: option,
                value: widget.value,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
              ),
            ToolOptionType.text || ToolOptionType.longText => TextField(
                controller: _controller,
                enabled: widget.enabled,
                maxLength: option.maxLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                maxLines: option.type == ToolOptionType.longText ? 8 : 1,
                minLines: option.type == ToolOptionType.longText ? 4 : 1,
                keyboardType: option.type == ToolOptionType.longText
                    ? TextInputType.multiline
                    : TextInputType.text,
                style: option.isJson
                    ? AppText.body.copyWith(fontFamily: 'monospace')
                    : AppText.body,
                onChanged: widget.onChanged,
                decoration: InputDecoration(
                  hintText: option.defaultValue,
                  // The counter is noise on a 200 000 character HTML field and
                  // useful on a 100 character page range.
                  counterText: (option.maxLength ?? 0) > 1000 ? '' : null,
                  errorText: widget.error,
                ),
              ),
          },
          if (option.type != ToolOptionType.text &&
              option.type != ToolOptionType.longText &&
              widget.error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.error!,
              style: AppText.caption.copyWith(color: AppColors.danger),
            ),
          ],
          // Display only: the wire name, type, bounds and pattern are the
          // server's and are untouched. See features/tools/domain/tool_copy.dart.
          if (ToolCopy.optionHelp(option.name, option.help) != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              ToolCopy.optionHelp(option.name, option.help)!,
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// A dropdown over the server's `values`.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.option,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ToolOption option;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final String? preferred =
        option.values.contains(value) ? value : option.defaultValue;
    // A value the server does not offer must never reach the dropdown, which
    // asserts on a selection it cannot find among its items.
    final String? selected =
        option.values.contains(preferred) ? preferred : null;

    return InputDecorator(
      decoration: const InputDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          isDense: true,
          borderRadius: AppRadius.controlAll,
          hint: Text(S.choose, style: AppText.bodySm),
          items: <DropdownMenuItem<String>>[
            for (final String choice in option.values)
              DropdownMenuItem<String>(
                value: choice,
                child: Text(
                  // `choice` is still exactly what gets posted; only the text
                  // beside it changes.
                  ToolCopy.choiceLabel(option.name, choice),
                  style: AppText.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

/// A clamped integer stepper with a slider, for `dpi`.
///
/// A slider alone cannot express 200 exactly on a 72–600 range with a thumb, so
/// the two buttons step by a sensible amount and the value is printed.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.option,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ToolOption option;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  int get _min => option.min ?? 0;

  int get _max => option.max ?? (option.min ?? 0) + 100;

  int get _step {
    final int span = _max - _min;
    if (span <= 20) {
      return 1;
    }
    if (span <= 200) {
      return 10;
    }
    return 25;
  }

  int get _current {
    final int? parsed = int.tryParse(value ?? '');
    final int fallback = option.defaultInt ?? _min;
    return (parsed ?? fallback).clamp(_min, _max).toInt();
  }

  void _set(int next) => onChanged('${next.clamp(_min, _max).toInt()}');

  @override
  Widget build(BuildContext context) {
    final int current = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton.filledTonal(
              onPressed:
                  enabled && current > _min ? () => _set(current - _step) : null,
              icon: const Icon(Icons.remove_rounded, size: 18),
              tooltip: S.decrease,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$current',
                  style: AppText.numeric.copyWith(fontSize: 17),
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed:
                  enabled && current < _max ? () => _set(current + _step) : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: S.increase,
            ),
          ],
        ),
        Slider(
          value: current.toDouble(),
          min: _min.toDouble(),
          max: _max.toDouble(),
          divisions: ((_max - _min) ~/ _step).clamp(1, 200).toInt(),
          label: '$current',
          onChanged:
              enabled ? (double v) => _set(v.round()) : null,
        ),
        Text('$_min – $_max', style: AppText.caption),
      ],
    );
  }
}
