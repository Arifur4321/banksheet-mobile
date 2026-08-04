/// The card shown while an extraction is in flight.
///
/// It is driven by the status poller rather than by a timer, so the counts it
/// shows are real: "we have found 34 rows so far" is the difference between a
/// user waiting and a user assuming the app has hung. The copy is honest about
/// leaving — the work happens on the server's queue and does not need this
/// screen open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/document.dart';

class ProcessingCard extends StatefulWidget {
  const ProcessingCard({
    required this.poll,
    required this.fallbackStatus,
    super.key,
  });

  /// The live status stream. Loading before the first tick lands.
  final AsyncValue<DocumentStatusInfo> poll;

  /// What the detail payload said, used until the first poll answers.
  final DocumentStatus fallbackStatus;

  @override
  State<ProcessingCard> createState() => _ProcessingCardState();
}

class _ProcessingCardState extends State<ProcessingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DocumentStatusInfo? get _info => widget.poll.valueOrNull;

  DocumentStatus get _status => _info?.state ?? widget.fallbackStatus;

  String get _stage => switch (_status) {
        DocumentStatus.uploaded => S.stageUploaded,
        DocumentStatus.queued => S.stageQueued,
        DocumentStatus.processing => S.stageProcessing,
        DocumentStatus.processed ||
        DocumentStatus.failed ||
        DocumentStatus.unknown =>
          S.stageFinishing,
      };

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final int found = _info?.transactionsCount ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                height: 44,
                child: reduceMotion
                    ? const _Badge()
                    : RotationTransition(
                        turns: _controller,
                        child: const _Badge(),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(S.processingDocument, style: AppText.h3),
                    const SizedBox(height: 2),
                    Text(_stage, style: AppText.bodySm),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              // Indeterminate on purpose: the server reports a stage, never a
              // percentage, and inventing one would be a lie the user can time.
              value: reduceMotion ? 0.35 : null,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.brand),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(S.processingBody, style: AppText.bodySm),
          if (found > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.playlist_add_check_rounded,
                  size: 17,
                  color: AppColors.brandDeep,
                ),
                const SizedBox(width: 6),
                Text(
                  S.rowsFoundSoFar(found),
                  style: AppText.bodySm.copyWith(color: AppColors.brandDeep),
                ),
              ],
            ),
          ],
          if (widget.poll.hasError) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const InlineNotice(
              message: S.pollingStopped,
              tone: NoticeTone.warn,
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.brandTint,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.autorenew_rounded,
        size: 22,
        color: AppColors.brandDeep,
      ),
    );
  }
}
