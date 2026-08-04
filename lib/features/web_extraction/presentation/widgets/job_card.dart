/// One extraction job in the list.
///
/// A running job gets a determinate bar rather than a spinner, because the
/// server publishes a real percentage and a crawl of two hundred domains takes
/// long enough that "how far along is it" is the only question worth answering
/// on this row.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/web_job.dart';

class WebJobCard extends StatelessWidget {
  const WebJobCard({required this.job, required this.onTap, super.key});

  final WebExtractionJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${job.title}. ${job.progressPercent}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      job.title,
                      style: AppText.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        S.websiteCount(job.totalTargets),
                        if (job.emailsFoundCount > 0)
                          S.emailCount(job.emailsFoundCount),
                        if (job.createdAt != null) Fmt.relative(job.createdAt),
                      ].join(' · '),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(job.status, compact: true),
            ],
          ),
          if (job.isRunning) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 6,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${job.progressPercent}%',
                  style: AppText.numeric.copyWith(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              S.websitesProcessed(job.processedTargets, job.totalTargets),
              style: AppText.caption,
            ),
          ] else if (job.failedTargets > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              S.websitesUnusable(job.failedTargets),
              style: AppText.caption.copyWith(color: AppColors.warn),
            ),
          ],
        ],
      ),
    );
  }
}
