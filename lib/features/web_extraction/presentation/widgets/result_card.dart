/// One website's extracted contacts.
///
/// Every value is tappable-to-copy, because the reason someone opens this
/// screen on a phone is to get an address into an email they are writing on the
/// same phone. And every value carries the page it was found on: a contact
/// nobody can trace back to where it was published is not a lead, it is a
/// liability, and the person acting on it deserves to be able to check.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/web_job.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({required this.target, super.key, this.onOpenSource});

  final WebExtractionTarget target;

  /// Opens a source URL in the browser.
  final ValueChanged<String>? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final WebExtractionResult? result = target.result;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                      result?.companyName ?? target.display,
                      style: AppText.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (target.domain != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        target.domain!,
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (target.confidenceScore != null)
                _Confidence(score: target.confidenceScore!)
              else
                StatusBadge(target.status, compact: true),
            ],
          ),
          if (result == null || result.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              target.error ?? target.warning ?? S.nothingExtracted,
              style: AppText.caption,
            ),
          ] else ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Group(
              label: S.resultEmails,
              icon: Icons.alternate_email_rounded,
              values: result.emails,
              onOpenSource: onOpenSource,
            ),
            _Group(
              label: S.resultPecEmails,
              icon: Icons.verified_rounded,
              values: result.pecEmails,
              onOpenSource: onOpenSource,
            ),
            _Group(
              label: S.resultPhones,
              icon: Icons.call_rounded,
              values: result.allPhones,
              onOpenSource: onOpenSource,
            ),
            _Group(
              label: S.resultVat,
              icon: Icons.badge_rounded,
              values: result.vatNumbers,
              onOpenSource: onOpenSource,
            ),
            _Group(
              label: S.resultAddresses,
              icon: Icons.place_rounded,
              values: result.addresses,
              onOpenSource: onOpenSource,
            ),
            if (result.people.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(S.resultPeople, style: AppText.label),
              const SizedBox(height: AppSpacing.xs),
              for (final PersonEntry person in result.people)
                _CopyRow(
                  text: person.display,
                  subtitle: <String?>[person.role, person.email]
                      .whereType<String>()
                      .join(' · '),
                  icon: Icons.person_rounded,
                  copyValue: person.email ?? person.display,
                  sourceUrl: person.provenance.sourceUrl,
                  onOpenSource: onOpenSource,
                ),
            ],
            if (result.socialLinks.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(S.resultSocials, style: AppText.label),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final SocialLink link in result.socialLinks)
                    _SocialChip(link: link, onOpen: onOpenSource),
                ],
              ),
            ],
            if (result.sourceUrls.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _SourceLine(
                url: result.sourceUrls.first,
                extra: result.sourceUrls.length - 1,
                onOpen: onOpenSource,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.icon,
    required this.values,
    required this.onOpenSource,
  });

  final String label;
  final IconData icon;
  final List<ContactValue> values;
  final ValueChanged<String>? onOpenSource;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: AppText.label),
        const SizedBox(height: AppSpacing.xs),
        for (final ContactValue value in values)
          _CopyRow(
            text: value.value,
            subtitle: value.locality ?? value.category,
            icon: icon,
            copyValue: value.value,
            sourceUrl: value.provenance.sourceUrl,
            onOpenSource: onOpenSource,
          ),
      ],
    );
  }
}

/// A value, its provenance, and one tap to copy it.
class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.text,
    required this.icon,
    required this.copyValue,
    required this.sourceUrl,
    required this.onOpenSource,
    this.subtitle,
  });

  final String text;
  final String? subtitle;
  final IconData icon;
  final String copyValue;
  final String? sourceUrl;
  final ValueChanged<String>? onOpenSource;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: copyValue));
    if (!context.mounted) {
      return;
    }
    Toast.success(context, S.copied);
  }

  @override
  Widget build(BuildContext context) {
    final String? source = sourceUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.smallAll,
        child: InkWell(
          onTap: () => _copy(context),
          borderRadius: AppRadius.smallAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: AppColors.inkMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        text,
                        style: AppText.bodySm.copyWith(color: AppColors.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: AppText.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (source != null && onOpenSource != null)
                  IconButton(
                    onPressed: () => onOpenSource!(source),
                    icon: const Icon(Icons.link_rounded, size: 17),
                    tooltip: S.openSource,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.inkMuted,
                  ),
                const Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialChip extends StatelessWidget {
  const _SocialChip({required this.link, required this.onOpen});

  final SocialLink link;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(_icon(link.network), size: 15, color: AppColors.brandDeep),
      label: Text(link.network),
      labelStyle: AppText.caption.copyWith(color: AppColors.brandDeep),
      backgroundColor: AppColors.brandTint,
      side: const BorderSide(color: AppColors.brandTintStrong),
      onPressed: onOpen == null ? null : () => onOpen!(link.url),
    );
  }

  static IconData _icon(String network) => switch (network) {
        'linkedin' => Icons.business_center_rounded,
        'facebook' => Icons.groups_rounded,
        'instagram' => Icons.camera_alt_rounded,
        'youtube' => Icons.play_circle_rounded,
        'x' => Icons.tag_rounded,
        _ => Icons.public_rounded,
      };
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({
    required this.url,
    required this.extra,
    required this.onOpen,
  });

  final String url;
  final int extra;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.travel_explore_rounded,
          size: 14,
          color: AppColors.inkFaint,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            extra > 0 ? S.sourceAndMore(url, extra) : url,
            style: AppText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onOpen != null)
          TextButton(
            onPressed: () => onOpen!(url),
            child: const Text(S.openSource),
          ),
      ],
    );
  }
}

class _Confidence extends StatelessWidget {
  const _Confidence({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (score) {
      >= 80 => (AppColors.brandDeep, AppColors.brandTint),
      >= 50 => (AppColors.warn, AppColors.warnTint),
      _ => (AppColors.inkMuted, AppColors.surfaceMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$score%',
        style: AppText.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
