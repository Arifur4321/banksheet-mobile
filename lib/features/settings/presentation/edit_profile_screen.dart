/// Name and email.
///
/// `PATCH /me` takes only the fields that actually changed — its rules are
/// `sometimes|required`, so sending an untouched field back would be an attempt
/// to rewrite it with the same value, and sending a null would be an attempt to
/// blank it. The form therefore diffs against the session before it submits,
/// and refuses to spend a request when nothing moved.
///
/// Changing the email is called out before it is saved, not after: the server
/// clears `email_verified_at` the moment the address changes, so the account
/// stops being verified and a confirmation has to be answered. Someone fixing a
/// typo in their name should not discover that by accident.
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

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  /// What the account looked like when the form opened. The diff is taken
  /// against this, not against the live session, so a background refresh cannot
  /// silently turn an edit into a no-op.
  late String _initialName;
  late String _initialEmail;

  bool _busy = false;
  String? _nameError;
  String? _emailError;

  @override
  void initState() {
    super.initState();

    final AppUser? user = ref.read(currentUserProvider);
    _initialName = user?.name ?? '';
    _initialEmail = user?.email ?? '';
    _name.text = _initialName;
    _email.text = _initialEmail;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool get _nameChanged => _name.text.trim() != _initialName.trim();

  bool get _emailChanged =>
      _email.text.trim().toLowerCase() != _initialEmail.trim().toLowerCase();

  bool get _dirty => _nameChanged || _emailChanged;

  void _clearServerErrors() {
    if (_nameError != null || _emailError != null) {
      setState(() {
        _nameError = null;
        _emailError = null;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    _clearServerErrors();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_dirty) {
      Toast.info(context, S.nothingChanged);
      return;
    }

    setState(() => _busy = true);

    try {
      await ref.read(authRepositoryProvider).updateProfile(
            name: _nameChanged ? _name.text : null,
            email: _emailChanged ? _email.text : null,
          );

      // The session carries the name and the verification state that the rest
      // of the app draws, so it has to be re-read before this screen closes.
      await ref.read(authControllerProvider.notifier).refreshSession();

      if (!mounted) {
        return;
      }

      Toast.success(context, S.profileSaved);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final String? nameError = failure.fieldError('name');
      final String? emailError = failure.fieldError('email');

      setState(() {
        _busy = false;
        _nameError = nameError;
        _emailError = emailError;
      });

      if (nameError == null && emailError == null && context.mounted) {
        Toast.error(context, failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);
    final bool unverified = user != null && !user.emailVerified;

    return PageScaffold(
      title: S.editProfile,
      showBack: true,
      scrollable: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(S.editProfileSubtitle, style: AppText.bodySm),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: S.fullName,
                      errorText: _nameError,
                      prefixIcon:
                          const Icon(Icons.person_outline_rounded, size: 20),
                    ),
                    validator: (String? value) =>
                        (value ?? '').trim().isEmpty ? S.required : null,
                    onChanged: (_) {
                      _clearServerErrors();
                      setState(() {});
                    },
                    onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  EmailField(
                    controller: _email,
                    focusNode: _emailFocus,
                    enabled: !_busy,
                    errorText: _emailError,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      _clearServerErrors();
                      setState(() {});
                    },
                    onSubmitted: _save,
                  ),
                  if (unverified && !_emailChanged) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    const InlineNotice(
                      message: S.emailNotVerified,
                      tone: NoticeTone.warn,
                    ),
                  ],
                ],
              ),
            ),
            if (_emailChanged) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              const InlineNotice(
                message: S.emailChangeWarning,
                tone: NoticeTone.warn,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SubmitButton(
              label: S.save,
              busy: _busy,
              onPressed: _dirty ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
