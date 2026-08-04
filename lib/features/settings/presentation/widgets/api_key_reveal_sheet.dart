/// The one moment a plaintext API key exists on the device.
///
/// `POST /api-keys` is the only response in the product that carries a raw
/// credential, and there is no endpoint that will ever show it again. So this
/// sheet cannot be dismissed by a swipe or a tap outside: the user leaves it by
/// pressing Done, having been told plainly that this is the only showing. The
/// key is held in the widget for as long as the sheet is on screen and is never
/// written to preferences, the keychain or the log.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/api_key.dart';

/// Shows [minted]'s plaintext once. Completes when the user presses Done.
Future<void> showApiKeyRevealSheet(
  BuildContext context,
  MintedApiKey minted,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Neither a swipe nor a tap on the scrim can close this: a key lost to a
    // stray gesture cannot be recovered, only replaced.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) => _ApiKeyRevealSheet(minted: minted),
  );
}

class _ApiKeyRevealSheet extends StatefulWidget {
  const _ApiKeyRevealSheet({required this.minted});

  final MintedApiKey minted;

  @override
  State<_ApiKeyRevealSheet> createState() => _ApiKeyRevealSheetState();
}

class _ApiKeyRevealSheetState extends State<_ApiKeyRevealSheet> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.minted.plainKey));

    if (!mounted) {
      return;
    }

    // Confirmed in place rather than with a toast: a snackbar renders behind a
    // modal sheet, so the user would copy the key and see nothing happen.
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MintedApiKey minted = widget.minted;

    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.brandTint,
                        borderRadius: AppRadius.smallAll,
                      ),
                      child: const Icon(
                        Icons.vpn_key_rounded,
                        size: 19,
                        color: AppColors.brandDeep,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(S.apiKeyRevealTitle, style: AppText.h3),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(S.apiKeyRevealBody, style: AppText.bodySm),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  minted.key.name.isEmpty ? S.apiKeyName : minted.key.name,
                  style: AppText.label,
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.controlAll,
                    border: Border.all(color: AppColors.borderStrong),
                  ),
                  child: SelectableText(
                    minted.plainKey,
                    style: AppText.numeric.copyWith(
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const InlineNotice(
                  message: S.apiKeyRevealWarning,
                  tone: NoticeTone.warn,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.tonalIcon(
                  onPressed: minted.hasPlainKey ? _copy : null,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copied ? S.copied : S.copyKey),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(S.done),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
