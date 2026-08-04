/// Sign in.
///
/// The form does three things the user can feel: it validates on device before
/// spending a round trip, it puts the server's own field messages next to the
/// fields they belong to, and it finishes the autofill context on success so
/// iOS and Android offer to save the credential. Anything the server reports
/// that is not a field — wrong password, rate limit, offline — is a toast,
/// because the fields are not what needs correcting.
///
/// It never navigates. `GoRouter`'s redirect owns where a signed-in user goes,
/// so there is exactly one place that can get that wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states.dart';
import 'auth_controller.dart';
import 'widgets/auth_fields.dart';
import 'widgets/auth_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _busy = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    if (_emailError != null || _passwordError != null) {
      setState(() {
        _emailError = null;
        _passwordError = null;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _clearServerErrors();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _busy = true);

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _email.text,
            password: _password.text,
          );

      // Tells the platform the credential is worth offering to save. Without
      // this the keychain prompt never appears, and the next sign-in is typed
      // by hand again.
      TextInput.finishAutofillContext();

      // No navigation here on purpose — the router redirect takes over the
      // moment the token pair is written.
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final String? emailError = failure.fieldError('email');
      final String? passwordError = failure.fieldError('password');

      setState(() {
        _busy = false;
        _emailError = emailError;
        _passwordError = passwordError;
      });

      if (emailError == null && passwordError == null && context.mounted) {
        Toast.error(context, failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: S.signIn,
      subtitle: S.signInSubtitle,
      footer: _Footer(busy: _busy),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              EmailField(
                controller: _email,
                enabled: !_busy,
                errorText: _emailError,
                onChanged: (_) => _clearServerErrors(),
                onSubmitted: _passwordFocus.requestFocus,
              ),
              const SizedBox(height: AppSpacing.lg),
              PasswordField(
                controller: _password,
                focusNode: _passwordFocus,
                label: S.password,
                enabled: !_busy,
                errorText: _passwordError,
                onChanged: (_) => _clearServerErrors(),
                onSubmitted: _submit,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.pushNamed(AppRoute.forgotPassword),
                  child: const Text(S.forgotPassword),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SubmitButton(
                label: S.signIn,
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(S.noAccountYet, style: AppText.bodySm),
        TextButton(
          // Replaces rather than pushes, so tapping between the two forms
          // cannot build a stack of alternating sign-in and sign-up screens.
          onPressed: busy
              ? null
              : () => context.pushReplacementNamed(AppRoute.register),
          child: const Text(S.signUp),
        ),
      ],
    );
  }
}
