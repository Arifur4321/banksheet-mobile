/// The language picker.
///
/// Thirteen languages, read from `GET /config` so a fourteenth added on the
/// server appears here without an App Store release. When `/config` cannot be
/// reached the bundled catalogue is shown instead, with a notice saying so: a
/// picker that renders nothing on a bad connection is worse than one that
/// renders the list the binary shipped with. Either way the list is never empty,
/// so there is no empty state to reach.
///
/// Choosing a language writes to the device AND to `PATCH /me`, because the
/// server is what renders the emails and the generated documents. The app's own
/// labels stay English for now, and the screen says so rather than letting
/// someone pick Japanese and wonder why nothing moved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/server_config.dart';
import 'providers.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_row.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ServerConfig> config = ref.watch(serverConfigProvider);
    final LocaleState locale = ref.watch(localeControllerProvider);

    return PageScaffold(
      title: S.language,
      showBack: true,
      scrollable: true,
      onRefresh: () => _reload(ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(S.languageIntro, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.lg),
          const InlineNotice(
            message: S.languageAppEnglishNotice,
            tone: NoticeTone.info,
          ),
          const SizedBox(height: AppSpacing.xl),
          config.when(
            loading: () => const _LocaleSkeleton(),
            error: (Object error, StackTrace _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                InlineNotice(
                  message: S.localesFallbackNotice,
                  tone: NoticeTone.warn,
                  actionLabel: S.tryAgain,
                  onAction: () => ref.invalidate(serverConfigProvider),
                ),
                const SizedBox(height: AppSpacing.lg),
                _LocaleList(
                  locales: ServerConfig.fallback.locales,
                  state: locale,
                  onSelect: (String code) => _select(context, ref, code),
                ),
              ],
            ),
            data: (ServerConfig value) => _LocaleList(
              locales: value.locales,
              state: locale,
              onSelect: (String code) => _select(context, ref, code),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reload(WidgetRef ref) async {
    ref.invalidate(serverConfigProvider);
    try {
      await ref.read(serverConfigProvider.future);
    } catch (error) {
      // The screen already shows the bundled list and explains why; a pull to
      // refresh must not throw out of the indicator.
      Log.warn('Language list refresh failed: ${ApiException.from(error).code}');
    }
  }

  Future<void> _select(BuildContext context, WidgetRef ref, String code) async {
    try {
      await ref.read(localeControllerProvider.notifier).select(code);
      if (!context.mounted) {
        return;
      }
      Toast.success(context, S.languageSaved);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      // The controller has already put the selection back.
      Toast.error(context, error);
    }
  }
}

class _LocaleList extends StatelessWidget {
  const _LocaleList({
    required this.locales,
    required this.state,
    required this.onSelect,
  });

  final List<AppLocale> locales;
  final LocaleState state;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: <Widget>[
        for (final AppLocale locale in locales)
          SettingsRow(
            // The native name leads: someone looking for their language reads
            // it in their language, not in English.
            label: locale.native,
            description: locale.name == locale.native ? null : locale.name,
            selected: state.code == locale.code,
            enabled: !state.saving,
            semanticLabel: locale.name == locale.native
                ? locale.native
                : '${locale.native}, ${locale.name}',
            trailing: state.saving && state.code == locale.code
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.brand,
                    ),
                  )
                : null,
            onTap: () => onSelect(locale.code),
          ),
      ],
    );
  }
}

class _LocaleSkeleton extends StatelessWidget {
  const _LocaleSkeleton();

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: <Widget>[
        for (int i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: Skeleton(width: 120, height: 14),
          ),
      ],
    );
  }
}
