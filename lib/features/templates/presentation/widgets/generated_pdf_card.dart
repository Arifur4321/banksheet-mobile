/// One generated PDF, as both the list and the "it worked" panel render it.
///
/// The same card is reused straight after a successful generate, so the thing
/// the user is looking at when the spinner stops is exactly the row they will
/// find later in the list — no second layout to keep in step.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../exports/data/file_downloader.dart';
import '../../domain/generated_pdf.dart';

class GeneratedPdfCard extends StatelessWidget {
  const GeneratedPdfCard({
    required this.pdf,
    required this.isBusy,
    required this.onAction,
    super.key,
  });

  final GeneratedPdf pdf;

  /// True while this card's file is being fetched.
  final bool isBusy;

  /// [origin] is the share button's rectangle, which iPadOS needs to anchor the
  /// share popover to.
  final void Function(FileAction action, Rect? origin) onAction;

  IconData get _icon => switch (pdf.kind) {
        GeneratedPdfKind.template => Icons.description_rounded,
        GeneratedPdfKind.contract => Icons.gavel_rounded,
        GeneratedPdfKind.uploadedPdf => Icons.picture_as_pdf_rounded,
        GeneratedPdfKind.unknown => Icons.insert_drive_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final bool enabled = pdf.isAvailable && !isBusy;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pdf.isAvailable
                      ? AppColors.brandTint
                      : AppColors.surfaceMuted,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(
                  _icon,
                  size: 21,
                  color: pdf.isAvailable
                      ? AppColors.brandDeep
                      : AppColors.inkFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fmt.middleEllipsis(pdf.displayName),
                      style: AppText.bodyStrong.copyWith(
                        color: pdf.isAvailable
                            ? AppColors.ink
                            : AppColors.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pdf.sourceLabel,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _meta,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!pdf.isAvailable)
            Row(
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S.fileUnavailableBody,
                    style: AppText.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        enabled ? () => onAction(FileAction.open, null) : null,
                    icon: isBusy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(isBusy ? S.downloading : S.open),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed:
                      enabled ? () => onAction(FileAction.save, null) : null,
                  tooltip: S.downloadFile,
                  icon: const Icon(Icons.download_rounded, size: 20),
                ),
                Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    onPressed: enabled
                        ? () => onAction(
                              FileAction.share,
                              FileDownloader.originOf(buttonContext),
                            )
                        : null,
                    tooltip: S.share,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (pdf.sizeBytes != null) Fmt.bytes(pdf.sizeBytes),
      if (pdf.hasSignatureFields)
        S.signatureFieldCount(pdf.signatureFieldCount),
      Fmt.dateTime(pdf.createdAt),
    ];
    return parts.join(' · ');
  }
}
