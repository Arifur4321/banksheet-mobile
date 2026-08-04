/// One row of the conversion history.
///
/// The actions are decided by the server's own answers rather than by the
/// status word: download appears when the bytes are actually on disk (a
/// completed row whose file was swept by retention has none), and retry appears
/// for exactly the rows `ToolController::retry()` accepts.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/conversion.dart';

class ConversionCard extends StatelessWidget {
  const ConversionCard({
    required this.conversion,
    super.key,
    this.onTap,
    this.onOpen,
    this.onDownload,
    this.onShare,
    this.onRetry,
    this.onDelete,
    this.busy = false,
  });

  final Conversion conversion;

  /// Used where the card is a preview rather than the working row — the tools
  /// screen shows the last few conversions and hands the whole card to the
  /// history rather than offering half the actions twice.
  final VoidCallback? onTap;

  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  /// True while this row has a download or a delete in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool downloadable = conversion.isDownloadable;

    return AppCard(
      onTap: onTap,
      semanticLabel: conversion.displayTitle,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(
                  _icon(conversion.tool),
                  size: 19,
                  color: AppColors.brandDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fmt.middleEllipsis(conversion.displayTitle, max: 40),
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(conversion),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(conversion.status.wire, compact: true),
            ],
          ),
          if (conversion.error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              conversion.error!,
              style: AppText.caption.copyWith(color: AppColors.danger),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (busy) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              if (downloadable && onOpen != null)
                _Action(
                  icon: Icons.open_in_new_rounded,
                  label: S.openResult,
                  onPressed: busy ? null : onOpen,
                ),
              if (downloadable && onDownload != null)
                _Action(
                  icon: Icons.download_rounded,
                  label: S.downloadResult,
                  onPressed: busy ? null : onDownload,
                ),
              if (downloadable && onShare != null)
                _Action(
                  icon: Icons.ios_share_rounded,
                  label: S.share,
                  onPressed: busy ? null : onShare,
                ),
              if (conversion.canRetry && onRetry != null)
                _Action(
                  icon: Icons.refresh_rounded,
                  label: S.retry,
                  onPressed: busy ? null : onRetry,
                ),
              const Spacer(),
              if (conversion.canDelete && onDelete != null)
                IconButton(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  tooltip: S.delete,
                  color: AppColors.danger,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _subtitle(Conversion conversion) {
    final List<String> parts = <String>[
      conversion.toolLabel ?? Fmt.humanise(conversion.tool),
      if (conversion.fileSize != null) Fmt.bytes(conversion.fileSize),
      if (conversion.pageCount != null) S.pageCount(conversion.pageCount!),
      if (conversion.createdAt != null) Fmt.relative(conversion.createdAt),
    ];
    return parts.join(' · ');
  }

  static IconData _icon(String tool) => switch (tool) {
        'barcode-generator' => Icons.qr_code_2_rounded,
        _ => Icons.picture_as_pdf_rounded,
      };
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        tooltip: label,
        color: AppColors.brandDeep,
      ),
    );
  }
}
