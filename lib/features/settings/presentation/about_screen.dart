/// About: what this build is, where the legal text lives, and what went wrong.
///
/// The version and build number come from the platform rather than from a
/// constant, so they cannot drift from what the store actually shipped — the
/// first question support asks is "which build?", and a hand-maintained string
/// answers it wrongly at least once.
///
/// The legal URLs come from `GET /config` when it is reachable and from
/// [AppConfig] when it is not, so a policy that moves does not need a release to
/// follow it, and a phone with no connection still has working links.
///
/// Diagnostics are the in-memory ring buffer from [Log]. Nothing is uploaded,
/// ever: there is no crash-reporting SDK in this app, and the only way anything
/// here reaches us is the user pressing Copy and pasting it into a message.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/server_config.dart';
import 'providers.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_row.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PackageInfo? info = ref.watch(packageInfoProvider).valueOrNull;
    final ServerConfig config =
        ref.watch(serverConfigProvider).valueOrNull ?? ServerConfig.fallback;

    final String? minVersion = config.minClientVersion;

    return PageScaffold(
      title: S.about,
      showBack: true,
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Identity(info: info),
          const SizedBox(height: AppSpacing.xxl),
          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                label: S.version,
                value: info?.version ?? S.loading,
              ),
              SettingsRow(
                label: S.build,
                value: info?.buildNumber ?? S.loading,
              ),
              if (minVersion != null)
                SettingsRow(
                  label: S.minimumSupportedVersion,
                  value: minVersion,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SettingsGroup(
            title: S.legal,
            children: <Widget>[
              SettingsRow(
                icon: Icons.privacy_tip_outlined,
                label: S.privacyLink,
                trailing: const _ExternalGlyph(),
                onTap: () => _open(
                  context,
                  config.privacyUrl ?? AppConfig.privacyUrl,
                ),
              ),
              SettingsRow(
                icon: Icons.gavel_rounded,
                label: S.termsLink,
                trailing: const _ExternalGlyph(),
                onTap: () => _open(
                  context,
                  config.termsUrl ?? AppConfig.termsUrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SettingsGroup(
            title: S.sectionSupport,
            children: <Widget>[
              SettingsRow(
                icon: Icons.language_rounded,
                label: S.openWebsite,
                trailing: const _ExternalGlyph(),
                onTap: () => _open(context, AppConfig.websiteUrl),
              ),
              SettingsRow(
                icon: Icons.support_agent_rounded,
                label: S.contactSupport,
                trailing: const _ExternalGlyph(),
                onTap: () => _open(
                  context,
                  config.supportUrl ?? AppConfig.supportUrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _Diagnostics(),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final Uri? uri = Uri.tryParse(url);

    bool opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (error) {
        // A device with no browser, or a scheme the platform refuses. Not worth
        // an error dialog over a link the user can also type.
        Log.warn('About: could not open $url — $error');
      }
    }

    if (opened || !context.mounted) {
      return;
    }
    Toast.info(context, S.couldNotOpenLink);
  }
}

class _Identity extends StatelessWidget {
  const _Identity({this.info});

  final PackageInfo? info;

  @override
  Widget build(BuildContext context) {
    final PackageInfo? package = info;

    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: AppRadius.controlAll,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 26,
              color: AppColors.brandDeep,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(S.appName, style: AppText.h3),
                const SizedBox(height: 2),
                Text(S.tagline, style: AppText.bodySm),
                if (package != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${package.version} (${package.buildNumber})',
                    style: AppText.caption,
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  const Skeleton(width: 90, height: 11),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The device's own record of what happened, shown only when asked for.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics();

  @override
  Widget build(BuildContext context) {
    final List<LogEntry> entries = Log.recent;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.cardAll,
        child: Theme(
          // The default expansion tile draws its own hairlines, which would sit
          // on top of the card's ring.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            leading: const Icon(
              Icons.bug_report_outlined,
              size: 20,
              color: AppColors.inkMuted,
            ),
            title: Text(S.diagnostics, style: AppText.bodyStrong),
            subtitle: Text(
              entries.isEmpty ? S.noDiagnostics : S.diagnosticsBody,
              style: AppText.caption,
              maxLines: 3,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (entries.isNotEmpty) ...<Widget>[
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.controlAll,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (BuildContext _, int index) =>
                        _LogLine(entry: entries[index]),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _copy(context, entries),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text(S.copyDiagnostics),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, List<LogEntry> entries) async {
    await Clipboard.setData(
      ClipboardData(
        text: entries.map((LogEntry e) => e.toString()).join('\n'),
      ),
    );

    if (!context.mounted) {
      return;
    }
    Toast.success(context, S.diagnosticsCopied);
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color colour = switch (entry.level) {
      LogLevel.error => AppColors.danger,
      LogLevel.warn => AppColors.warn,
      LogLevel.info => AppColors.info,
      LogLevel.debug => AppColors.inkFaint,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: AppSpacing.sm),
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              entry.message,
              style: AppText.caption.copyWith(color: AppColors.inkBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExternalGlyph extends StatelessWidget {
  const _ExternalGlyph();

  @override
  Widget build(BuildContext context) => const Icon(
        Icons.open_in_new_rounded,
        size: 18,
        color: AppColors.inkFaint,
      );
}
