/// Request a password reset link.
///
/// The confirmation is deliberately neutral. `POST /auth/forgot-password`
/// answers 200 with the same body whether or not the address is registered, so
/// that the endpoint cannot be used to discover who has a BankSheet account —
/// and this screen has to hold that line. It says "if that address has an
/// account", never "we've sent it", and it says the same thing every time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/states.dart';
import 'auth_controller.dart';
import 'widgets/auth_fields.dart';
import 'widgets/auth_shell.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_emailError != null) {
      setState(() => _emailError = null);
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _busy = true);

    try {
      await ref
          .read(authControllerProvider.notifier)
          .forgotPassword(_email.text);

      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final String? emailError = failure.fieldError('email');

      setState(() {
        _busy = false;
        _emailError = emailError;
      });

      if (emailError == null && context.mounted) {
        Toast.error(context, failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: _sent ? S.checkYourInbox : S.resetPassword,
      subtitle: _sent ? null : S.forgotPasswordSubtitle,
      child: _sent ? const _SentPanel() : _form(),
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          EmailField(
            controller: _email,
            enabled: !_busy,
            errorText: _emailError,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
            onSubmitted: _submit,
          ),
          const SizedBox(height: AppSpacing.xl),
          SubmitButton(
            label: S.sendResetLink,
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// The neutral confirmation. It reveals nothing, and offers the one action that
/// makes sense next.
class _SentPanel extends StatelessWidget {
  const _SentPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          child: Column(
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: AppColors.brandTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 30,
                  color: AppColors.brandDeep,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                S.resetSent,
                textAlign: TextAlign.center,
                style: AppText.body,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => context.goNamed(AppRoute.login),
          child: const Text(S.backToSignIn),
        ),
      ],
    );
  }
}
