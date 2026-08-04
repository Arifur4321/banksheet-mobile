/// One website inside a job, on the progress screen.
///
/// A skipped row shows what the user typed rather than a normalised domain,
/// because the whole point of keeping unusable lines is that the person can
/// recognise which of their input lines was the problem.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../domain/web_job.dart';

class TargetRow extends StatelessWidget {
  const TargetRow({required this.target, super.key, this.onTap});

  final WebExtractionTarget target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData icon) = _tone(target);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smallAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: AppRadius.smallAll,
                ),
                child: target.isWorking
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, size: 17, color: fg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      target.display,
                      style: AppText.bodySm.copyWith(color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _subtitle(target),
                      style: AppText.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (target.emailsFoundCount > 0) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${target.emailsFoundCount}',
                  style: AppText.numeric.copyWith(
                    fontSize: 13,
                    color: AppColors.brandDeep,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.alternate_email_rounded,
                  size: 14,
                  color: AppColors.brandDeep,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(WebExtractionTarget target) {
    if (target.error != null) {
      return target.error!;
    }
    if (target.warning != null) {
      return target.warning!;
    }
    if (target.isSkipped) {
      return S.targetSkipped;
    }
    if (target.isWorking) {
      return S.targetWorking;
    }
    return <String>[
      S.pagesScanned(target.pagesScanned),
      if (target.confidenceScore != null) '${target.confidenceScore}%',
    ].join(' · ');
  }

  static (Color, Color, IconData) _tone(WebExtractionTarget target) {
    if (target.isFailed) {
      return (AppColors.danger, AppColors.dangerTint, Icons.close_rounded);
    }
    if (target.isSkipped || target.isCancelled) {
      return (AppColors.warn, AppColors.warnTint, Icons.remove_rounded);
    }
    if (target.isDone) {
      return (AppColors.brandDeep, AppColors.brandTint, Icons.check_rounded);
    }
    return (AppColors.info, AppColors.infoTint, Icons.schedule_rounded);
  }
}
