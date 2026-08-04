/// The barcode generator.
///
/// The preview is the product here, so it sits above the form and updates as
/// the user types — debounced, never billed, and never blanked between renders.
/// A preview failure is printed under the data field rather than thrown at a
/// snackbar: the user is mid-typing, and a toast for "EAN-13 needs 12 digits"
/// after every keystroke would be hostile.
///
/// Generate is the only control that spends a barcode unit, which is why it is
/// a separate button rather than something that happens when you stop typing.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/barcode_repository.dart';
import '../domain/symbology.dart';
import 'providers.dart';
import 'widgets/barcode_preview.dart';
import 'widgets/colour_swatch_field.dart';

class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key});

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  final TextEditingController _value = TextEditingController();

  bool _busy = false;

  BarcodeController get _controller =>
      ref.read(barcodeControllerProvider.notifier);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- actions

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();

    final GeneratedBarcode? created = await _controller.generate();
    if (!context.mounted) {
      return;
    }

    if (created != null) {
      Toast.success(context, S.barcodeGenerated);
      return;
    }

    final Object? error = ref.read(barcodeControllerProvider).error;
    if (error == null) {
      return;
    }
    final ApiException failure = ApiException.from(error);
    if (failure.isQuota) {
      Toast.error(context, failure);
      context.pushNamed(AppRoute.billing);
      return;
    }
    // A 422 has already been printed under the data field.
    if (failure.fieldError('data') == null) {
      Toast.error(context, failure);
    }
  }

  Future<void> _deliver(
    GeneratedBarcode barcode,
    String format, {
    required bool share,
  }) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);

    try {
      final String filename = barcode.downloadFilename(format);
      final Directory directory = share
          ? await getTemporaryDirectory()
          : await getApplicationDocumentsDirectory();
      final File file = await ref.read(barcodeRepositoryProvider).download(
            barcode.id,
            format,
            p.join(directory.path, _safeName(filename)),
          );

      if (!context.mounted) {
        return;
      }

      if (!share) {
        Toast.success(context, S.savedAs(p.basename(file.path)));
        return;
      }

      final RenderObject? box = context.findRenderObject();
      await Share.shareXFiles(
        <XFile>[XFile(file.path, name: filename)],
        subject: filename,
        // Required on iPad: without an anchor the share sheet has nowhere to
        // attach and the call throws.
        sharePositionOrigin:
            box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static String _safeName(String filename) {
    final String safe =
        p.basename(filename).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'barcode' : safe;
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final BarcodeFormState state = ref.watch(barcodeControllerProvider);

    return HeroPageScaffold(
      onRefresh: _controller.reload,
      slivers: <Widget>[
        const SliverAppBar(
          backgroundColor: AppColors.canvas,
          surfaceTintColor: AppColors.canvas,
          elevation: 0,
          toolbarHeight: 48,
          floating: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: S.barcode,
              title: S.barcodeSubtitle,
              scene: const BarcodeScene(),
              subtitle: _allowance(state.catalogue.valueOrNull?.usage),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.section,
          ),
          sliver: SliverToBoxAdapter(
            child: state.catalogue.when(
              loading: () => const _Skeleton(),
              error: (Object error, StackTrace _) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.section),
                child: ErrorState(
                  error: error,
                  onRetry: _controller.reload,
                  onUpgrade: () => context.pushNamed(AppRoute.billing),
                ),
              ),
              data: (SymbologyCatalogue catalogue) =>
                  _form(context, catalogue, state),
            ),
          ),
        ),
      ],
    );
  }

  static String? _allowance(BarcodeUsage? usage) {
    if (usage == null || usage.isUnlimited) {
      return null;
    }
    return S.barcodesLeft(usage.remaining ?? 0);
  }

  Widget _form(
    BuildContext context,
    SymbologyCatalogue catalogue,
    BarcodeFormState state,
  ) {
    final Symbology? symbology = state.symbology;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BarcodePreviewPanel(
          image: state.preview,
          isLoading: state.isPreviewing,
          transparent: state.transparent,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(S.symbology, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Symbology>(
              value: symbology,
              isExpanded: true,
              isDense: true,
              borderRadius: AppRadius.controlAll,
              items: <DropdownMenuItem<Symbology>>[
                for (final Symbology type in catalogue.types)
                  DropdownMenuItem<Symbology>(
                    value: type,
                    child: Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: state.isGenerating ? null : _controller.setSymbology,
            ),
          ),
        ),
        if (symbology?.help != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(symbology!.help!, style: AppText.caption),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(S.barcodeValue, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _value,
          enabled: !state.isGenerating,
          maxLines: (symbology?.isMatrix ?? false) ? 4 : 1,
          minLines: 1,
          maxLength: symbology?.maxLength ?? catalogue.options.dataMaxLength,
          onChanged: _controller.setValue,
          decoration: InputDecoration(
            hintText: S.barcodeValueHint,
            counterText: '',
            // Inline, under the field, because the user is mid-typing.
            errorText: state.previewError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _OptionsPanel(state: state, controller: _controller),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: state.canGenerate && !_busy ? _generate : null,
          icon: state.isGenerating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.inkInverse,
                  ),
                )
              : const Icon(Icons.qr_code_2_rounded, size: 19),
          label: const Text(S.generate),
        ),
        if (state.created != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          _ResultCard(
            barcode: state.created!,
            busy: _busy,
            onDownload: (String format) =>
                _deliver(state.created!, format, share: false),
            onShare: (String format) =>
                _deliver(state.created!, format, share: true),
          ),
        ],
      ],
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({required this.state, required this.controller});

  final BarcodeFormState state;
  final BarcodeController controller;

  @override
  Widget build(BuildContext context) {
    final BarcodeOptions options = state.options;
    final bool matrix = state.symbology?.isMatrix ?? false;
    final bool enabled = !state.isGenerating;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.barcodeAppearance, style: AppText.label),
          const SizedBox(height: AppSpacing.md),
          _SliderRow(
            label: S.barcodeScale,
            range: options.scale,
            value: state.scale,
            enabled: enabled,
            onChanged: controller.setScale,
          ),
          // A matrix symbology derives its height from its module count, so the
          // slider would move a value the renderer ignores.
          if (!matrix)
            _SliderRow(
              label: S.barcodeHeight,
              range: options.height,
              value: state.height,
              enabled: enabled,
              onChanged: controller.setHeight,
            ),
          _SliderRow(
            label: S.barcodeQuietZone,
            range: options.margin,
            value: state.margin,
            enabled: enabled,
            onChanged: controller.setMargin,
          ),
          const SizedBox(height: AppSpacing.md),
          ColourSwatchField(
            label: S.barcodeForeground,
            value: state.foreground,
            enabled: enabled,
            error: options.foreground.accepts(state.foreground)
                ? null
                : S.barcodeColourFormat,
            onChanged: controller.setForeground,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!state.transparent) ...<Widget>[
            ColourSwatchField(
              label: S.barcodeBackground,
              value: state.background,
              enabled: enabled,
              error: options.background.accepts(state.background)
                  ? null
                  : S.barcodeColourFormat,
              onChanged: controller.setBackground,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (state.canShowText)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: state.showText,
              title: Text(S.barcodeShowText, style: AppText.bodySm),
              onChanged: enabled
                  ? (bool v) => controller.setShowText(enabled: v)
                  : null,
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: state.transparent,
            title: Text(S.barcodeTransparent, style: AppText.bodySm),
            subtitle: Text(S.barcodeTransparentBody, style: AppText.caption),
            onChanged: enabled
                ? (bool v) => controller.setTransparent(enabled: v)
                : null,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.range,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final BarcodeRange range;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: AppText.bodySm)),
            Text('$value', style: AppText.numeric.copyWith(fontSize: 13.5)),
          ],
        ),
        Slider(
          value: range.clamp(value).toDouble(),
          min: range.min.toDouble(),
          max: range.max.toDouble(),
          divisions: range.divisions,
          label: '$value',
          onChanged: enabled ? (double v) => onChanged(v.round()) : null,
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.barcode,
    required this.busy,
    required this.onDownload,
    required this.onShare,
  });

  final GeneratedBarcode barcode;
  final bool busy;
  final ValueChanged<String> onDownload;
  final ValueChanged<String> onShare;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.successTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(S.barcodeSaved, style: AppText.h3),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        barcode.symbologyLabel ?? barcode.symbology ?? '',
                        if (barcode.fileSize != null)
                          Fmt.bytes(barcode.fileSize),
                      ].where((String s) => s.isNotEmpty).join(' · '),
                      style: AppText.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (busy) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => onDownload('png'),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text(S.barcodePng),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => onDownload('svg'),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text(S.barcodeSvg),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: busy ? null : () => onShare('png'),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text(S.share),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Skeleton(height: 220, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 100, height: 13),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 52, radius: AppRadius.control),
        SizedBox(height: AppSpacing.lg),
        Skeleton(width: 130, height: 13),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 52, radius: AppRadius.control),
      ],
    );
  }
}
