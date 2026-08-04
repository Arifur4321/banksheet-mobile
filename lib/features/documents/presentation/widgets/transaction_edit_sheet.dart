/// The row editor.
///
/// Every field here is one the server actually accepts — the list is
/// `TransactionController::update()`'s validation rules, in the same order, with
/// the same limits — so nothing in this sheet can be typed and then silently
/// discarded.
///
/// The three actions map to the three review outcomes. "Save changes" sends
/// `edited` when anything actually changed, because that is what the export
/// writer treats as a human-touched row; approving or rejecting sends the edits
/// too, so a reviewer never has to save and then approve.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/transaction.dart';
import 'transaction_row.dart';

/// Opens the editor. Resolves with the server's copy of the row when something
/// was saved, or null when the sheet was dismissed.
Future<ExtractedTransaction?> showTransactionEditSheet(
  BuildContext context, {
  required ExtractedTransaction transaction,
  required Future<ExtractedTransaction> Function(TransactionEdit edit) onSave,
}) {
  return showModalBottomSheet<ExtractedTransaction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => _TransactionEditSheet(
      transaction: transaction,
      onSave: onSave,
    ),
  );
}

class _TransactionEditSheet extends StatefulWidget {
  const _TransactionEditSheet({
    required this.transaction,
    required this.onSave,
  });

  final ExtractedTransaction transaction;
  final Future<ExtractedTransaction> Function(TransactionEdit edit) onSave;

  @override
  State<_TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<_TransactionEditSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _description;
  late final TextEditingController _reference;
  late final TextEditingController _counterparty;
  late final TextEditingController _category;
  late final TextEditingController _debit;
  late final TextEditingController _credit;
  late final TextEditingController _balance;
  late final TextEditingController _currency;

  late DateTime? _transactionDate;
  late DateTime? _valueDate;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final ExtractedTransaction t = widget.transaction;
    _description = TextEditingController(text: t.description ?? '');
    _reference = TextEditingController(text: t.reference ?? '');
    _counterparty = TextEditingController(text: t.counterparty ?? '');
    _category = TextEditingController(text: t.category ?? '');
    _debit = TextEditingController(text: _money(t.debit));
    _credit = TextEditingController(text: _money(t.credit));
    _balance = TextEditingController(text: _money(t.balance));
    _currency = TextEditingController(text: t.currency ?? '');
    _transactionDate = t.transactionDate;
    _valueDate = t.valueDate;
  }

  @override
  void dispose() {
    _description.dispose();
    _reference.dispose();
    _counterparty.dispose();
    _category.dispose();
    _debit.dispose();
    _credit.dispose();
    _balance.dispose();
    _currency.dispose();
    super.dispose();
  }

  /// Plain decimal, never thousands-separated — this string is parsed back.
  static String _money(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  /// Accepts a comma as the decimal separator, which is what an Italian or
  /// German keyboard offers and what the statement itself printed.
  static double? _parse(String raw) {
    final String clean = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    return clean.isEmpty ? null : double.tryParse(clean);
  }

  static String? _text(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  bool get _isDirty {
    final ExtractedTransaction t = widget.transaction;
    return _text(_description) != t.description ||
        _text(_reference) != t.reference ||
        _text(_counterparty) != t.counterparty ||
        _text(_category) != t.category ||
        _parse(_debit.text) != t.debit ||
        _parse(_credit.text) != t.credit ||
        _parse(_balance.text) != t.balance ||
        _text(_currency) != t.currency ||
        _transactionDate != t.transactionDate ||
        _valueDate != t.valueDate;
  }

  TransactionEdit _edit(ReviewStatus status) => TransactionEdit.full(
        reviewStatus: status,
        transactionDate: _transactionDate,
        valueDate: _valueDate,
        description: _text(_description),
        reference: _text(_reference),
        counterparty: _text(_counterparty),
        category: _text(_category),
        debit: _parse(_debit.text),
        credit: _parse(_credit.text),
        balance: _parse(_balance.text),
        currency: _text(_currency),
      );

  Future<void> _submit(ReviewStatus status) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _busy = true);
    try {
      final ExtractedTransaction updated = await widget.onSave(_edit(status));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      Toast.error(context, error);
    }
  }

  Future<void> _pickDate({required bool isValueDate}) async {
    final DateTime seed =
        (isValueDate ? _valueDate : _transactionDate) ?? DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: seed,
      // A statement can legitimately be years old, and a future value date is a
      // real thing on a pending transfer.
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );

    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      if (isValueDate) {
        _valueDate = picked;
      } else {
        _transactionDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExtractedTransaction t = widget.transaction;

    // A constrained, shrink-wrapping list rather than a
    // DraggableScrollableSheet: this sheet is a form, and a sheet whose height
    // changes as the keyboard opens is one the user loses their place in.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(S.editTransaction, style: AppText.h3),
                  ),
                  ReviewStatusPill(status: t.reviewStatus),
                  const SizedBox(width: 6),
                  ConfidenceChip(level: t.confidence, showLabel: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (t.validationFlags.isNotEmpty) ...<Widget>[
                InlineNotice(
                  message: t.validationFlags.map(Fmt.humanise).join(' · '),
                  tone: NoticeTone.warn,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: _DateField(
                      label: S.date,
                      value: _transactionDate,
                      onPick: () => _pickDate(isValueDate: false),
                      onClear: () => setState(() => _transactionDate = null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DateField(
                      label: S.valueDate,
                      value: _valueDate,
                      onPick: () => _pickDate(isValueDate: true),
                      onClear: () => setState(() => _valueDate = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Field(
                controller: _description,
                label: S.description,
                maxLength: 5000,
                maxLines: 3,
              ),
              _Field(
                controller: _counterparty,
                label: S.counterparty,
                maxLength: 2000,
              ),
              _Field(
                controller: _reference,
                label: S.reference,
                maxLength: 2000,
              ),
              _Field(
                controller: _category,
                label: S.category,
                maxLength: 1000,
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Field(
                      controller: _debit,
                      label: S.debit,
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Field(
                      controller: _credit,
                      label: S.credit,
                      numeric: true,
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Field(
                      controller: _balance,
                      label: S.balance,
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Field(
                      controller: _currency,
                      label: S.currency,
                      maxLength: 8,
                    ),
                  ),
                ],
              ),
              if (t.sourceLine != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(S.sourceLine, style: AppText.label),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.smallAll,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    t.sourceLine!,
                    style: AppText.caption.copyWith(
                      color: AppColors.inkBody,
                    ),
                  ),
                ),
              ],
              if (t.reviewedBy != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  S.lastReviewedBy(
                    t.reviewedBy?.name ?? '—',
                    Fmt.relative(t.reviewedAt),
                  ),
                  style: AppText.caption,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _submit(ReviewStatus.approved),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(S.approve),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _submit(ReviewStatus.rejected),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(S.reject),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _submit(
                          _isDirty ? ReviewStatus.edited : t.reviewStatus,
                        ),
                child: Text(_busy ? S.loading : S.saveChanges),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text(S.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.maxLength,
    this.maxLines = 1,
    this.numeric = false,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        // The server's `max:` rules are the source of truth; the counter would
        // only be noise at 5000 characters.
        buildCounter: (
          BuildContext context, {
          required int currentLength,
          required int? maxLength,
          required bool isFocused,
        }) =>
            null,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: numeric
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ]
            : null,
        textCapitalization:
            numeric ? TextCapitalization.none : TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        validator: (String? value) {
          final String raw = (value ?? '').trim();
          if (raw.isEmpty) {
            return null;
          }
          if (numeric &&
              double.tryParse(raw.replaceAll(' ', '').replaceAll(',', '.')) ==
                  null) {
            return S.mustBeNumber;
          }
          if (maxLength != null && raw.length > maxLength!) {
            return S.tooLong;
          }
          return null;
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: AppRadius.controlAll,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 17)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: onClear,
                  tooltip: S.clear,
                ),
        ),
        child: Text(
          value == null ? '—' : Fmt.isoDate(value),
          style: AppText.numeric.copyWith(fontSize: 14),
        ),
      ),
    );
  }
}
