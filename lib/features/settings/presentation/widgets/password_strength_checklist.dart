/// The password rules, as a checklist rather than a coloured bar.
///
/// A bar that slides from red to green tells someone their password is "weak"
/// without ever telling them what to change; a checklist names the four things
/// and ticks them off as they are typed. Only the first rule is enforced —
/// `Rules\Password::defaults()` on the server is an eight-character minimum and
/// nothing more — so the other three are advice, and the form must not refuse a
/// password the server would happily accept.
///
/// The rule evaluation is pure and lives here, so the same function the widget
/// draws is the one the test suite checks.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

enum PasswordRule { length, mixedCase, digit, symbol }

abstract final class PasswordRules {
  /// The server's floor. Anything shorter is rejected by `PUT /me/password`.
  static const int minLength = 8;

  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _upper = RegExp('[A-Z]');
  static final RegExp _digit = RegExp('[0-9]');

  /// Anything that is not a letter or a digit counts, including a space —
  /// passphrases are good passwords and should not be told otherwise.
  static final RegExp _symbol = RegExp('[^A-Za-z0-9]');

  static bool satisfies(PasswordRule rule, String password) => switch (rule) {
        PasswordRule.length => password.length >= minLength,
        PasswordRule.mixedCase =>
          _lower.hasMatch(password) && _upper.hasMatch(password),
        PasswordRule.digit => _digit.hasMatch(password),
        PasswordRule.symbol => _symbol.hasMatch(password),
      };

  /// Every rule [password] currently meets.
  static Set<PasswordRule> evaluate(String password) => <PasswordRule>{
        for (final PasswordRule rule in PasswordRule.values)
          if (satisfies(rule, password)) rule,
      };

  /// The only rule the server actually enforces.
  static bool meetsServerMinimum(String password) =>
      satisfies(PasswordRule.length, password);

  static bool isStrong(String password) =>
      evaluate(password).length == PasswordRule.values.length;

  static String label(PasswordRule rule) => switch (rule) {
        PasswordRule.length => S.ruleLength,
        PasswordRule.mixedCase => S.ruleMixedCase,
        PasswordRule.digit => S.ruleDigit,
        PasswordRule.symbol => S.ruleSymbol,
      };
}

class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    final Set<PasswordRule> met = PasswordRules.evaluate(password);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(S.passwordChecklistTitle, style: AppText.label),
          const SizedBox(height: AppSpacing.sm),
          for (final PasswordRule rule in PasswordRule.values)
            _RuleLine(rule: rule, met: met.contains(rule)),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.rule, required this.met});

  final PasswordRule rule;
  final bool met;

  @override
  Widget build(BuildContext context) {
    // `checked` makes the screen reader announce "ticked"/"not ticked" without
    // inventing copy for a state the platform already has a word for.
    return Semantics(
      checked: met,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 17,
              color: met ? AppColors.success : AppColors.inkFaint,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                PasswordRules.label(rule),
                style: AppText.bodySm.copyWith(
                  color: met ? AppColors.ink : AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
