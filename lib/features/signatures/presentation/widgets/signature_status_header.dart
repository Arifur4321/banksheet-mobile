/// The panel at the top of a signature request.
///
/// One glance has to answer "is this done, and if not who is holding it up".
/// So the status is a coloured block rather than a badge in a row of metadata,
/// the progress bar is the same "2 of 3" the list shows, and the dates below are
/// only the ones that exist — a request that was never opened does not get an
/// empty "First opened —" line to read past.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/signature.dart';

/// The colour and icon a status is drawn with. Shared by the header and the
/// list row so the two can never disagree.
({Color fg, Color bg, IconData icon}) signatureTone(SignatureStatus status) {
  if (status.isSigned) {
    return (
      fg: AppColors.brandDeep,
      bg: AppColors.brandTint,
      icon: Icons.verified_rounded,
    );
  }
  if (status == SignatureStatus.declined || status == SignatureStatus.error) {
    return (
      fg: AppColors.danger,
      bg: AppColors.dangerTint,
      icon: Icons.block_rounded,
    );
  }
  if (status == SignatureStatus.expired) {
    return (
      fg: AppColors.warn,
      bg: AppColors.warnTint,
      icon: Icons.hourglass_disabled_rounded,
    );
  }
  if (status.isOpen) {
    return (
      fg: AppColors.info,
      bg: AppColors.infoTint,
      icon: Icons.schedule_rounded,
    );
  }
  return (
    fg: AppColors.inkMuted,
    bg: AppColors.surfaceMuted,
    icon: Icons.edit_document,
  );
}

class SignatureStatusHeader extends StatelessWidget {
  const SignatureStatusHeader({required this.request, super.key});

  final SignatureRequest request;

  @override
  Widget build(BuildContext context) {
    final SignatureStatus state = request.state;
    final ({Color fg, Color bg, IconData icon}) tone = signatureTone(state);
    final SignatureProgress progress = request.progress;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(tone.icon, size: 22, color: tone.fg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request.displayName,
                      style: AppText.h3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        StatusBadge(request.status, compact: true),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            progress.label,
                            style: AppText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress.total > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: progress.label,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(tone.fg),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _Dates(request: request),
          if (request.errorMessage != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    request.errorMessage!,
                    style: AppText.caption.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The timestamps that exist, as label/value rows.
class _Dates extends StatelessWidget {
  const _Dates({required this.request});

  final SignatureRequest request;

  @override
  Widget build(BuildContext context) {
    final List<(String, DateTime)> rows = <(String, DateTime)>[
      if (request.sentAt != null) (S.sentOn, request.sentAt!),
      if (request.viewedAt != null) (S.firstOpened, request.viewedAt!),
      if (request.completedAt != null) (S.completedOn, request.completedAt!),
      if (request.expiresAt != null) (S.expiresOn, request.expiresAt!),
      if (request.lastEventAt != null) (S.lastActivity, request.lastEventAt!),
    ];

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: <Widget>[
        for (final (String label, DateTime value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(label, style: AppText.caption)),
                Text(
                  Fmt.dateTime(value),
                  style: AppText.caption.copyWith(color: AppColors.inkBody),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
