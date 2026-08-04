/// Account deletion, in two steps.
///
/// App Store guideline 5.1.1(v) requires an app that creates an account to let
/// the user delete it from inside the app — not by emailing support, and not by
/// a link to a website. This is that path, and it is why it is a full sheet
/// rather than a confirmation dialog: the first step says exactly what
/// disappears, including the store subscription that does NOT, and only then
/// does it ask for the password `DELETE /me` demands.
///
/// On success the session is ended through the normal sign-out path, so the
/// router sends the user back to the welcome screen and every feature provider
/// drops its cache. The logout request that path makes will fail — the token is
/// already gone with the account — and that failure is already swallowed by
/// design.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/widgets/auth_fields.dart';

/// Opens the deletion flow. Returns true when the account was deleted.
Future<bool> showDeleteAccountSheet(BuildContext context) async {
  final bool? deleted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Nothing is destroyed until the password is entered, so a swipe down is a
    // safe way out and should stay available.
    builder: (BuildContext sheetContext) => const _DeleteAccountSheet(),
  );

  return deleted ?? false;
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();

  bool _confirming = false;
  bool _busy = false;
  String? _passwordError;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _busy = true;
      _passwordError = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .deleteAccount(currentPassword: _password.text);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      // The server reports a wrong password against `current_password`, which
      // is the field the user is looking at.
      final String? fieldError = failure.fieldError('current_password');

      setState(() {
        _busy = false;
        _passwordError = fieldError;
      });

      if (fieldError == null && context.mounted) {
        Toast.error(context, failure);
      }
      return;
    }

    Log.info('Account deleted; ending the session.');

    if (!mounted) {
      return;
    }

    // Close the sheet before the session ends, so the router is not asked to
    // rebuild the tree underneath an open modal route.
    Navigator.of(context).pop(true);

    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: AnimatedSize(
            duration: AppMotion.fast,
            alignment: Alignment.topCenter,
            child: _confirming ? _confirmStep() : _explainStep(),
          ),
        ),
      ),
    );
  }

  Widget _explainStep() {
    return Column(
      key: const ValueKey<String>('explain'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SheetTitle(
          icon: Icons.delete_forever_rounded,
          title: S.deleteAccount,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(S.deleteAccountBody, style: AppText.bodySm),
        const SizedBox(height: AppSpacing.xl),
        Text(S.deleteAccountWhat, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        const _Point(text: S.deleteAccountPointAccount),
        const _Point(text: S.deleteAccountPointDocuments),
        const _Point(text: S.deleteAccountPointContent),
        const _Point(text: S.deleteAccountPointAccess),
        const SizedBox(height: AppSpacing.lg),
        const InlineNotice(
          message: S.deleteAccountStoreNotice,
          tone: NoticeTone.warn,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => setState(() => _confirming = true),
          child: const Text(S.continueLabel),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(S.cancel),
        ),
      ],
    );
  }

  Widget _confirmStep() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey<String>('confirm'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SheetTitle(
            icon: Icons.lock_outline_rounded,
            title: S.deleteAccountPasswordTitle,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(S.deleteAccountPasswordBody, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.xl),
          PasswordField(
            controller: _password,
            label: S.currentPassword,
            enabled: !_busy,
            errorText: _passwordError,
            autofillHints: const <String>[AutofillHints.password],
            onChanged: (_) {
              if (_passwordError != null) {
                setState(() => _passwordError = null);
              }
            },
            onSubmitted: _busy ? null : _delete,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _busy ? null : _delete,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.inkInverse,
                    ),
                  )
                : const Text(S.deleteAccountConfirm),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.dangerTint,
            borderRadius: AppRadius.smallAll,
          ),
          child: Icon(icon, size: 19, color: AppColors.danger),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(title, style: AppText.h3)),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.remove_rounded, size: 15, color: AppColors.danger),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppText.bodySm)),
        ],
      ),
    );
  }
}
