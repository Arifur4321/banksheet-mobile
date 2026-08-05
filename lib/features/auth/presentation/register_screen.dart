/// Create an account.
///
/// One screen creates the person, the workspace and the session, because that
/// is what `POST /auth/register` does — splitting it into a wizard would invent
/// a state (a user with no workspace) that the rest of the app cannot render.
///
/// The workspace name is `company_name` on the wire; the mapping lives in the
/// repository, and the server's field errors are mapped back onto the right
/// controls here. `email_taken` gets special handling: the server sends it as a
/// code with no `errors` map, and pinning it to the email field is far more
/// useful than a toast that leaves the user staring at a form with no red on it.
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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _workspace = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  final FocusNode _workspaceFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _busy = false;
  Map<String, String> _serverErrors = const <String, String>{};

  @override
  void dispose() {
    _name.dispose();
    _workspace.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _workspaceFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    if (_serverErrors.isNotEmpty) {
      setState(() => _serverErrors = const <String, String>{});
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
      await ref.read(authControllerProvider.notifier).register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            workspaceName: _workspace.text,
          );

      TextInput.finishAutofillContext();

      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final Map<String, String> errors = <String, String>{
        for (final String field in const <String>[
          'name',
          'company_name',
          'email',
          'password',
        ])
          if (failure.fieldError(field) != null)
            field: failure.fieldError(field)!,
        // A returning user, told where they actually need to go.
        if (failure.code == 'email_taken') 'email': failure.message,
      };

      setState(() {
        _busy = false;
        _serverErrors = errors;
      });

      if (errors.isEmpty && context.mounted) {
        Toast.error(context, failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: S.signUp,
      subtitle: S.signUpSubtitle,
      footer: _Footer(busy: _busy),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const <String>[AutofillHints.name],
                decoration: InputDecoration(
                  labelText: S.fullName,
                  errorText: _serverErrors['name'],
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                ),
                validator: _required,
                onChanged: (_) => _clearServerErrors(),
                onFieldSubmitted: (_) => _workspaceFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _workspace,
                focusNode: _workspaceFocus,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const <String>[AutofillHints.organizationName],
                decoration: InputDecoration(
                  labelText: S.workspaceNameOptional,
                  helperText: S.workspaceHint,
                  errorText: _serverErrors['company_name'],
                  prefixIcon: const Icon(Icons.business_outlined, size: 20),
                ),
                // No validator: the workspace name is optional on the phone.
                // Left blank, the server names the workspace after the person
                // — a sole trader signing up to keep the PDF they just scanned
                // should not have to invent a company first.
                onChanged: (_) => _clearServerErrors(),
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.lg),
              EmailField(
                controller: _email,
                focusNode: _emailFocus,
                enabled: !_busy,
                errorText: _serverErrors['email'],
                onChanged: (_) => _clearServerErrors(),
                onSubmitted: _passwordFocus.requestFocus,
              ),
              const SizedBox(height: AppSpacing.lg),
              PasswordField(
                controller: _password,
                focusNode: _passwordFocus,
                label: S.password,
                enabled: !_busy,
                errorText: _serverErrors['password'],
                helperText: S.passwordTooShort,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                validator: PasswordField.validateNew,
                onChanged: (_) => _clearServerErrors(),
                onSubmitted: _confirmFocus.requestFocus,
              ),
              const SizedBox(height: AppSpacing.lg),
              PasswordField(
                controller: _confirm,
                focusNode: _confirmFocus,
                label: S.confirmPassword,
                enabled: !_busy,
                autofillHints: const <String>[AutofillHints.newPassword],
                validator: _validateConfirmation,
                onChanged: (_) => _clearServerErrors(),
                onSubmitted: _submit,
              ),
              const SizedBox(height: AppSpacing.xl),
              SubmitButton(
                label: S.createFreeAccount,
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                S.termsNotice,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? S.required : null;

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) {
      return S.required;
    }
    return value == _password.text ? null : S.passwordsDoNotMatch;
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
        Text(S.haveAccount, style: AppText.bodySm),
        TextButton(
          onPressed:
              busy ? null : () => context.pushReplacementNamed(AppRoute.login),
          child: const Text(S.signIn),
        ),
      ],
    );
  }
}
