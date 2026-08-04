/// The upload progress block.
///
/// Determinate, because dio reports sent and total bytes and a spinner during a
/// three-minute upload on a train is how an app gets force-quit. The cancel
/// button is always live: an upload the user cannot stop is an upload they will
/// stop by killing the app, which loses the request without releasing the
/// quota.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';

class UploadProgress extends StatelessWidget {
  const UploadProgress({
    required this.progress,
    required this.sentBytes,
    required this.totalBytes,
    required this.onCancel,
    super.key,
    this.filename,
  });

  /// 0–1.
  final double progress;

  final int sentBytes;
  final int totalBytes;
  final VoidCallback onCancel;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    final int percent = (progress * 100).round();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(S.uploadingDocument, style: AppText.h3),
                    if (filename != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        Fmt.middleEllipsis(filename!),
                        style: AppText.bodySm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: AppText.numeric.copyWith(color: AppColors.brandDeep),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: '${S.uploadingDocument} $percent%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.brand),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${Fmt.bytes(sentBytes)} / ${Fmt.bytes(totalBytes)}',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text(S.cancel),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
