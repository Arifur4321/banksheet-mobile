/// The vertical list of people on a signature request.
///
/// Drawn as a timeline rather than a table because for a sequential request the
/// order *is* the meaning: the first unsigned row is the person the whole thing
/// is waiting on. A decline is surfaced with its reason inline — that sentence
/// is usually the only thing that explains why a contract stopped, and burying
/// it costs a phone call.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/signature.dart';

class SignerTimeline extends StatelessWidget {
  const SignerTimeline({required this.signers, super.key});

  final List<SignatureSigner> signers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < signers.length; i++)
          _SignerRow(
            signer: signers[i],
            isLast: i == signers.length - 1,
          ),
      ],
    );
  }
}

class _SignerRow extends StatelessWidget {
  const _SignerRow({required this.signer, required this.isLast});

  final SignatureSigner signer;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final SignerStatus state = signer.state;
    final ({Color fg, Color bg, IconData icon}) tone = _toneFor(state);

    // The email is only worth a second line when it says something the name
    // does not, which for a signer added by address alone it does not.
    final bool showEmail =
        signer.email != null && signer.email != signer.name;

    // An expired link on somebody who already signed is history, not a problem.
    final bool showExpiry = signer.isExpired && state != SignerStatus.signed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: tone.fg.withValues(alpha: 0.28)),
                ),
                child: state == SignerStatus.pending
                    ? Text(
                        signer.initials,
                        style: AppText.caption.copyWith(
                          color: tone.fg,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Icon(tone.icon, size: 17, color: tone.fg),
              ),
              // The connector, which is what makes a list of people read as an
              // order rather than a set.
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    signer.displayName,
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showEmail) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      signer.email!,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      _StatusPill(label: state.label, fg: tone.fg, bg: tone.bg),
                      if (signer.lastActivityAt != null) ...<Widget>[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            Fmt.relative(signer.lastActivityAt),
                            style: AppText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (signer.declineReason != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _Reason(reason: signer.declineReason!),
                  ],
                  if (showExpiry) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.link_off_rounded,
                          size: 14,
                          color: AppColors.warn,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            S.signingLinkExpired,
                            style:
                                AppText.caption.copyWith(color: AppColors.warn),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ({Color fg, Color bg, IconData icon}) _toneFor(SignerStatus status) {
    return switch (status) {
      SignerStatus.signed => (
          fg: AppColors.brandDeep,
          bg: AppColors.brandTint,
          icon: Icons.check_rounded,
        ),
      SignerStatus.declined => (
          fg: AppColors.danger,
          bg: AppColors.dangerTint,
          icon: Icons.close_rounded,
        ),
      SignerStatus.viewed => (
          fg: AppColors.info,
          bg: AppColors.infoTint,
          icon: Icons.visibility_rounded,
        ),
      SignerStatus.sent => (
          fg: AppColors.info,
          bg: AppColors.infoTint,
          icon: Icons.send_rounded,
        ),
      SignerStatus.pending || SignerStatus.unknown => (
          fg: AppColors.inkMuted,
          bg: AppColors.surfaceMuted,
          icon: Icons.person_outline_rounded,
        ),
    };
  }
}

/// Why somebody refused. Given its own block because it is the single most
/// useful sentence on the screen when it exists.
class _Reason extends StatelessWidget {
  const _Reason({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            S.declineReason,
            style: AppText.caption.copyWith(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reason,
            style: AppText.bodySm.copyWith(color: AppColors.inkBody),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        maxLines: 1,
      ),
    );
  }
}
