/// Change password.
///
/// `PUT /me/password` revokes every OTHER session and keeps this one: whoever
/// just proved they know the current password stays signed in, and a stolen
/// handset loses access immediately rather than at the next token expiry. That
/// is a consequence the user has to be told about — before, in a notice, and
/// after, in the confirmation — because "why did my tablet sign out?" is
/// otherwise a support ticket.
///
/// The only rule the server enforces is eight characters
/// (`Rules\Password::defaults()`), so that is the only rule this form blocks
/// on. The other three are shown as a checklist and are advice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/widgets/auth_fields.dart';
import 'widgets/password_strength_checklist.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _busy = false;
  String? _currentError;
  String? _passwordError;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    if (_currentError != null || _passwordError != null) {
      setState(() {
        _currentError = null;
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
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _password.text,
          );

      if (!mounted) {
        return;
      }

      Toast.success(context, S.passwordChangedSignedOutOthers);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final String? currentError = failure.fieldError('current_password');
      final String? passwordError = failure.fieldError('password');

      setState(() {
        _busy = false;
        _currentError = currentError;
        _passwordError = passwordError;
      });

      if (currentError == null && passwordError == null && context.mounted) {
        Toast.error(context, failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);

    // Reachable by deep link even though the settings list hides the row for a
    // Google account, so it has to explain itself rather than show a form that
    // cannot succeed.
    if (user != null && !user.canChangePassword) {
      return const PageScaffold(
        title: S.changePassword,
        showBack: true,
        scrollable: true,
        child: InlineNotice(
          message: S.passwordManagedByProvider,
          tone: NoticeTone.info,
        ),
      );
    }

    return PageScaffold(
      title: S.changePassword,
      showBack: true,
      scrollable: true,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(S.changePasswordIntro, style: AppText.bodySm),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PasswordField(
                      controller: _current,
                      label: S.currentPassword,
                      enabled: !_busy,
                      errorText: _currentError,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.password],
                      onChanged: (_) => _clearServerErrors(),
                      onSubmitted: _passwordFocus.requestFocus,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PasswordField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      label: S.newPassword,
                      enabled: !_busy,
                      errorText: _passwordError,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      validator: PasswordField.validateNew,
                      onChanged: (_) {
                        _clearServerErrors();
                        // Redraws the checklist as it is typed.
                        setState(() {});
                      },
                      onSubmitted: _confirmFocus.requestFocus,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PasswordField(
                      controller: _confirm,
                      focusNode: _confirmFocus,
                      label: S.confirmPassword,
                      enabled: !_busy,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      validator: (String? value) {
                        if ((value ?? '').isEmpty) {
                          return S.required;
                        }
                        return value == _password.text
                            ? null
                            : S.passwordsDoNotMatch;
                      },
                      onChanged: (_) => _clearServerErrors(),
                      onSubmitted: _submit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PasswordStrengthChecklist(password: _password.text),
              const SizedBox(height: AppSpacing.lg),
              const InlineNotice(
                message: S.otherDevicesWillSignOut,
                tone: NoticeTone.info,
              ),
              const SizedBox(height: AppSpacing.xl),
              SubmitButton(
                label: S.changePassword,
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
