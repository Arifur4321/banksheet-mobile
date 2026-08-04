/// One control in a template's generate form.
///
/// The server publishes the variable schema precisely so the client can build a
/// real form rather than a wall of text boxes, and this is where that pays off:
/// a `date` gets a date picker, a `select` gets its options, a `multiline` gets
/// room to type, and a `number` gets the numeric keyboard. Every type maps to
/// the same rule the server validates with, so what this widget accepts is what
/// `TemplateController::generate()` accepts.
///
/// The value always lives in the [TextEditingController] as the string that will
/// be posted — even for a date, where the field shows `3 Aug 2026` but the
/// controller holds `2026-08-03`. One source of truth, no reconciliation step
/// before submitting.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/template.dart';

class TemplateVariableField extends StatelessWidget {
  const TemplateVariableField({
    required this.variable,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
    this.errorText,
    this.isLast = false,
  });

  final TemplateVariable variable;
  final TextEditingController controller;
  final bool enabled;

  /// Called after any edit so the screen can clear a stale error.
  final VoidCallback onChanged;

  final String? errorText;

  /// The last field submits the form instead of advancing the focus.
  final bool isLast;

  /// A year either side of today is not enough for an invoice due date or a
  /// contract term, so the picker spans a working lifetime.
  static const int _yearsBack = 10;
  static const int _yearsForward = 10;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: switch (variable.type) {
        TemplateVariableType.date => _DateControl(
            variable: variable,
            controller: controller,
            enabled: enabled,
            errorText: errorText,
            onChanged: onChanged,
            yearsBack: _yearsBack,
            yearsForward: _yearsForward,
          ),
        TemplateVariableType.select when variable.options.isNotEmpty =>
          _SelectControl(
            variable: variable,
            controller: controller,
            enabled: enabled,
            errorText: errorText,
            onChanged: onChanged,
          ),
        _ => _TextControl(
            variable: variable,
            controller: controller,
            enabled: enabled,
            errorText: errorText,
            onChanged: onChanged,
            isLast: isLast,
          ),
      },
    );
  }
}

/// The label a control shows. Optional fields say so, because on a form of
/// twelve variables "which of these can I skip?" is the first question.
String _labelFor(TemplateVariable variable) => variable.required
    ? variable.label
    : '${variable.label} · ${S.optional}';

/// Text, long text, number, currency and email — one control, four keyboards.
class _TextControl extends StatelessWidget {
  const _TextControl({
    required this.variable,
    required this.controller,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
    required this.isLast,
  });

  final TemplateVariable variable;
  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final VoidCallback onChanged;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final bool multiline = variable.type == TemplateVariableType.multiline;
    final bool numeric = variable.type == TemplateVariableType.number ||
        variable.type == TemplateVariableType.currency;

    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: multiline ? 4 : 1,
      minLines: multiline ? 3 : 1,
      maxLength: TemplateVariable.maxLength,
      // The counter only earns its place near the ceiling; at 12 of 5000 it is
      // noise on every single field.
      buildCounter: (
        BuildContext context, {
        required int currentLength,
        required int? maxLength,
        required bool isFocused,
      }) =>
          currentLength < TemplateVariable.maxLength - 200
              ? null
              : Text('$currentLength / $maxLength', style: AppText.caption),
      keyboardType: switch (variable.type) {
        TemplateVariableType.multiline => TextInputType.multiline,
        TemplateVariableType.email => TextInputType.emailAddress,
        TemplateVariableType.number ||
        TemplateVariableType.currency =>
          const TextInputType.numberWithOptions(decimal: true, signed: true),
        _ => TextInputType.text,
      },
      inputFormatters: numeric
          ? <TextInputFormatter>[
              // Byte-for-byte the server's `regex:/^-?[0-9.,\s]+$/` character
              // class, so the keyboard cannot produce a value the API rejects.
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,\s]')),
            ]
          : null,
      textCapitalization: variable.type == TemplateVariableType.email
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      autocorrect: variable.type != TemplateVariableType.email,
      textInputAction: multiline
          ? TextInputAction.newline
          : (isLast ? TextInputAction.done : TextInputAction.next),
      decoration: InputDecoration(
        labelText: _labelFor(variable),
        helperText: variable.hint,
        errorText: errorText,
        alignLabelWithHint: multiline,
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// A date. Read-only by design: a typed date is the single most common way a
/// generate call comes back 422, and the picker cannot produce an invalid one.
class _DateControl extends StatelessWidget {
  const _DateControl({
    required this.variable,
    required this.controller,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
    required this.yearsBack,
    required this.yearsForward,
  });

  final TemplateVariable variable;
  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final VoidCallback onChanged;
  final int yearsBack;
  final int yearsForward;

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - yearsBack);
    final DateTime last = DateTime(now.year + yearsForward, 12, 31);

    // A stored default older than the window would make showDatePicker assert
    // rather than open, so the seed is clamped into range first.
    final DateTime seed = DateTime.tryParse(controller.text.trim()) ?? now;
    final DateTime initial = seed.isBefore(first)
        ? first
        : (seed.isAfter(last) ? last : seed);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: variable.label,
    );

    if (picked == null) {
      return;
    }

    // ISO, because that is one of the two formats Template::formatValue()
    // parses and the only one with no day/month ambiguity.
    controller.text = Fmt.isoDate(picked);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        final DateTime? parsed = DateTime.tryParse(value.text.trim());
        final bool empty = parsed == null;

        return Semantics(
          button: true,
          label: '${variable.label}: ${empty ? S.pickDate : Fmt.date(parsed)}',
          child: InkWell(
            onTap: enabled ? () => _pick(context) : null,
            borderRadius: AppRadius.controlAll,
            child: InputDecorator(
              isEmpty: empty,
              decoration: InputDecoration(
                labelText: _labelFor(variable),
                helperText: variable.hint,
                errorText: errorText,
                enabled: enabled,
                suffixIcon: empty || !enabled
                    ? const Icon(Icons.event_rounded, size: 20)
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: S.clear,
                        onPressed: () {
                          controller.clear();
                          onChanged();
                        },
                      ),
              ),
              child: Text(
                empty ? S.pickDate : Fmt.date(parsed),
                style: empty
                    ? AppText.body.copyWith(color: AppColors.inkFaint)
                    : AppText.body.copyWith(color: AppColors.ink),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One of a fixed set of options — the server validates with `Rule::in`, so a
/// free-text box here could only ever produce a rejection.
class _SelectControl extends StatelessWidget {
  const _SelectControl({
    required this.variable,
    required this.controller,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
  });

  final TemplateVariable variable;
  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        final String current = value.text.trim();
        // A stored default that is no longer one of the options would make the
        // dropdown assert, so it falls back to "nothing chosen".
        final String? selected =
            variable.options.contains(current) ? current : null;

        return InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: _labelFor(variable),
            helperText: variable.hint,
            errorText: errorText,
            enabled: enabled,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isExpanded: true,
              isDense: true,
              style: AppText.body.copyWith(color: AppColors.ink),
              hint: Text(
                S.selectOption,
                style: AppText.body.copyWith(color: AppColors.inkFaint),
              ),
              items: <DropdownMenuItem<String>>[
                for (final String option in variable.options)
                  DropdownMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (String? choice) {
                      controller.text = choice ?? '';
                      onChanged();
                    }
                  : null,
            ),
          ),
        );
      },
    );
  }
}
