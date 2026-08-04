/// API credentials.
///
/// Three things make this screen different from every other list in the app.
/// The plaintext key exists in exactly one response and is shown exactly once,
/// in a sheet that cannot be dismissed by accident. Revoking does not delete —
/// the server keeps the row so the audit trail of which key submitted which
/// document survives — so revoked keys stay on screen, greyed out. And a 403 is
/// an expected answer here, not a failure: only an owner or a company admin may
/// manage keys, and an employee who taps through deserves a sentence explaining
/// who can help rather than a blank screen or a red error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/settings_repository.dart';
import '../domain/api_key.dart';
import 'providers.dart';
import 'widgets/api_key_reveal_sheet.dart';

class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ApiKeyBundle> state = ref.watch(apiKeysProvider);

    return HeroPageScaffold(
      onRefresh: () => _reload(ref),
      slivers: <Widget>[
        const SliverAppBar(
          floating: true,
          toolbarHeight: 52,
          titleSpacing: AppSpacing.lg,
          title: Text(S.apiKeys),
        ),
        state.when(
          loading: () => const SliverToBoxAdapter(child: SkeletonList(count: 3)),
          error: (Object error, StackTrace _) =>
              _errorSliver(context, ref, error),
          data: (ApiKeyBundle bundle) => _dataSliver(context, ref, bundle),
        ),
      ],
    );
  }

  Widget _errorSliver(BuildContext context, WidgetRef ref, Object error) {
    final ApiException failure = ApiException.from(error);

    // Not a failure: the server is telling an employee that key management
    // belongs to the owner. Retrying would answer 403 again.
    if (failure.code == 'forbidden') {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: S.apiKeysForbiddenTitle,
          body: S.apiKeysForbiddenBody,
        ),
      );
    }

    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorState(
        error: failure,
        onRetry: () => ref.invalidate(apiKeysProvider),
      ),
    );
  }

  Widget _dataSliver(
    BuildContext context,
    WidgetRef ref,
    ApiKeyBundle bundle,
  ) {
    final List<ApiKey> keys = bundle.sorted;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.section,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(S.apiKeysIntro, style: AppText.bodySm),
            if (bundle.usage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _UsageCard(usage: bundle.usage!),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text(S.createApiKey),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (keys.isEmpty)
              const EmptyState(
                icon: Icons.vpn_key_outlined,
                title: S.noApiKeys,
                body: S.noApiKeysBody,
              )
            else ...<Widget>[
              SectionHeader(
                title: S.apiKeys,
                subtitle: S.apiKeyCount(keys.length),
              ),
              for (int i = 0; i < keys.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                _KeyCard(
                  apiKey: keys[i],
                  onRevoke: () => _revoke(context, ref, keys[i]),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reload(WidgetRef ref) async {
    ref.invalidate(apiKeysProvider);
    try {
      await ref.read(apiKeysProvider.future);
    } catch (_) {
      // Already rendered by the error branch above; a pull to refresh must not
      // throw out of the indicator.
      return;
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final MintedApiKey? minted = await showApiKeyCreateSheet(context);

    if (minted == null) {
      return;
    }

    ref.invalidate(apiKeysProvider);

    if (!context.mounted) {
      return;
    }

    if (minted.hasPlainKey) {
      await showApiKeyRevealSheet(context, minted);
      if (!context.mounted) {
        return;
      }
    }

    Toast.success(context, S.apiKeyCreated);
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, ApiKey key) async {
    final bool confirmed = await confirmAction(
      context,
      title: S.revokeKeyTitle,
      message: S.revokeKeyBody,
      confirmLabel: S.revokeKey,
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await ref.read(settingsRepositoryProvider).revokeApiKey(key.id);
      ref.invalidate(apiKeysProvider);

      if (!context.mounted) {
        return;
      }
      Toast.success(context, S.apiKeyRevoked);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    }
  }
}

/// How much of the workspace's API allowance is left.
///
/// Without this the screen lists credentials but cannot answer the only
/// question anyone actually has about them.
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage});

  final ApiUsage usage;

  @override
  Widget build(BuildContext context) {
    final DateTime? resets = usage.resetsAt;
    final int? trial = usage.trialRemaining;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          UsageMeter(
            label: S.apiDocumentsThisPeriod,
            used: usage.used,
            limit: usage.limit,
          ),
          if (resets != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(child: Text(S.allowanceResets, style: AppText.caption)),
                Text(Fmt.date(resets), style: AppText.caption),
              ],
            ),
          ],
          if (!usage.includedInPlan) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            InlineNotice(
              message: trial == null
                  ? S.apiNotIncludedInPlan
                  : '${S.apiNotIncludedInPlan} ${S.apiTrialRemaining(trial)}.',
              tone: NoticeTone.warn,
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.apiKey, required this.onRevoke});

  final ApiKey apiKey;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final bool revoked = apiKey.isRevoked;
    final Color titleColour = revoked ? AppColors.inkFaint : AppColors.ink;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  apiKey.name.isEmpty ? S.apiKeyName : apiKey.name,
                  style: AppText.bodyStrong.copyWith(color: titleColour),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (revoked)
                const _Chip(label: S.revoked, tone: _ChipTone.danger)
              else if (apiKey.isTest)
                const _Chip(label: S.apiEnvironmentTest, tone: _ChipTone.info)
              else
                const _Chip(label: S.apiEnvironmentLive, tone: _ChipTone.brand),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            apiKey.maskedKey,
            style: AppText.numeric.copyWith(
              fontSize: 13.5,
              color: revoked ? AppColors.inkFaint : AppColors.inkBody,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          _MetaLine(label: S.created, value: Fmt.date(apiKey.createdAt)),
          _MetaLine(
            label: S.lastUsed,
            value: apiKey.hasBeenUsed
                ? Fmt.relative(apiKey.lastUsedAt)
                : S.neverUsed,
          ),
          if (!revoked) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRevoke,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text(S.revokeKey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.caption)),
          Text(
            value,
            style: AppText.caption.copyWith(color: AppColors.inkBody),
          ),
        ],
      ),
    );
  }
}

enum _ChipTone { brand, info, danger }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tone});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (tone) {
      _ChipTone.brand => (AppColors.brandDeep, AppColors.brandTint),
      _ChipTone.info => (AppColors.info, AppColors.infoTint),
      _ChipTone.danger => (AppColors.danger, AppColors.dangerTint),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Asks for a name and mints the key. Returns the minted key, or null if the
/// sheet was dismissed.
///
/// The request is made here rather than by the caller so the server's own
/// validation — including the ten-active-key ceiling, which it reports against
/// `name` — lands under the field the user is looking at.
Future<MintedApiKey?> showApiKeyCreateSheet(BuildContext context) {
  return showModalBottomSheet<MintedApiKey>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => const _CreateApiKeySheet(),
  );
}

class _CreateApiKeySheet extends ConsumerStatefulWidget {
  const _CreateApiKeySheet();

  @override
  ConsumerState<_CreateApiKeySheet> createState() => _CreateApiKeySheetState();
}

class _CreateApiKeySheetState extends ConsumerState<_CreateApiKeySheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();

  bool _busy = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _busy = true;
      _nameError = null;
    });

    try {
      final MintedApiKey minted = await ref
          .read(settingsRepositoryProvider)
          .createApiKey(name: _name.text);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(minted);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final ApiException failure = ApiException.from(error);
      final String? nameError = failure.fieldError('name');

      setState(() {
        _busy = false;
        _nameError = nameError;
      });

      if (nameError == null && context.mounted) {
        Toast.error(context, failure);
      }
    }
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(S.createApiKey, style: AppText.h3),
              const SizedBox(height: AppSpacing.sm),
              Text(S.apiKeysIntro, style: AppText.bodySm),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _name,
                enabled: !_busy,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: S.apiKeyName,
                  hintText: S.apiKeyNameHint,
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                ),
                validator: (String? value) =>
                    (value ?? '').trim().isEmpty ? S.required : null,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.inkInverse,
                        ),
                      )
                    : const Text(S.createApiKey),
              ),
              const SizedBox(height: AppSpacing.sm),
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
