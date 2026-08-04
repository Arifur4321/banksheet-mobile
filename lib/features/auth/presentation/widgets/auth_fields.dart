/// The three form controls the auth screens share.
///
/// Sign in, sign up and reset all need an email field with the same keyboard,
/// the same autofill hints and the same validator, and two of them need a
/// password field with a visibility toggle. Writing those once means the
/// password rule cannot say eight characters on one screen and six on another,
/// and it means the autofill contract with the OS keychain is identical
/// everywhere — which is what makes "save this password?" actually appear.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';

/// Deliberately permissive: the server is the authority on whether an address
/// exists, and a clever regex here only ever rejects somebody's real address.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// The shortest password `Rules\Password::defaults()` accepts.
const int kMinPasswordLength = 8;

class EmailField extends StatelessWidget {
  const EmailField({
    required this.controller,
    super.key,
    this.focusNode,
    this.enabled = true,
    this.errorText,
    this.textInputAction = TextInputAction.next,
    this.autofillHints = const <String>[
      AutofillHints.username,
      AutofillHints.email,
    ],
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;

  /// A message from the server, shown until the field is edited.
  final String? errorText;

  final TextInputAction textInputAction;
  final List<String> autofillHints;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  static String? validate(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) {
      return S.required;
    }
    return _emailPattern.hasMatch(email) ? null : S.invalidEmail;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: S.email,
        errorText: errorText,
        prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
      ),
      validator: validate,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    super.key,
    this.focusNode,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.textInputAction = TextInputAction.done,
    this.autofillHints = const <String>[AutofillHints.password],
    this.validator,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool enabled;
  final String? errorText;
  final String? helperText;
  final TextInputAction textInputAction;
  final List<String> autofillHints;

  /// Defaults to "not empty". Pass [PasswordField.validateNew] on a field that
  /// is choosing a password rather than presenting one.
  final FormFieldValidator<String>? validator;

  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  /// For a password being set: the server's minimum, checked on device so the
  /// user is not told about it only after a round trip.
  static String? validateNew(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) {
      return S.required;
    }
    return password.length < kMinPasswordLength ? S.passwordTooShort : null;
  }

  static String? validateRequired(String? value) =>
      (value == null || value.isEmpty) ? S.required : null;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 20,
          ),
          tooltip: _obscure ? S.showPassword : S.hidePassword,
        ),
      ),
      validator: widget.validator ?? PasswordField.validateRequired,
      onChanged: widget.onChanged,
      onFieldSubmitted:
          widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    );
  }
}

/// A full-width primary button that swaps its label for a spinner while the
/// request is in flight, and refuses a second tap while it is.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy && onPressed != null,
      label: label,
      child: ExcludeSemantics(
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.inkMuted,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}
