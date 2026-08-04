/// The card a finished conversion lands on.
///
/// Three verbs, in the order people want them: Open (hand the file to whatever
/// app owns that type), Download (keep it), Share. Open is primary because on a
/// phone the usual next step after converting a document is looking at it, and
/// a downloads folder is not a place most people visit on purpose.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/conversion.dart';

class ConversionResultCard extends StatelessWidget {
  const ConversionResultCard({
    required this.conversion,
    required this.onOpen,
    required this.onDownload,
    required this.onShare,
    super.key,
    this.onAgain,
    this.busy = false,
  });

  final Conversion conversion;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  /// "Convert another" — back to the form with the options kept.
  final VoidCallback? onAgain;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool ready = conversion.isDownloadable;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.successTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(S.conversionReady, style: AppText.h3),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.middleEllipsis(conversion.downloadFilename, max: 38),
                      style: AppText.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _Chip(
                label: conversion.toolLabel ?? Fmt.humanise(conversion.tool),
                icon: Icons.build_rounded,
              ),
              if (conversion.fileSize != null)
                _Chip(
                  label: Fmt.bytes(conversion.fileSize),
                  icon: Icons.sd_storage_rounded,
                ),
              if (conversion.pageCount != null)
                _Chip(
                  label: S.pageCount(conversion.pageCount!),
                  icon: Icons.layers_rounded,
                ),
            ],
          ),
          if (busy) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (!ready)
            Text(S.outputUnavailable, style: AppText.bodySm)
          else ...<Widget>[
            FilledButton.icon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              label: const Text(S.openResult),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onDownload,
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: const Text(S.downloadResult),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onShare,
                    icon: const Icon(Icons.ios_share_rounded, size: 19),
                    label: const Text(S.share),
                  ),
                ),
              ],
            ),
          ],
          if (onAgain != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: busy ? null : onAgain,
              child: const Text(S.convertAnother),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.inkMuted),
          const SizedBox(width: 6),
          Text(label, style: AppText.caption),
        ],
      ),
    );
  }
}
