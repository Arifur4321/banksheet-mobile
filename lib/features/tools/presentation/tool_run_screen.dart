/// One tool, running.
///
/// Generic on purpose: this screen has no knowledge of merge, split or OCR. It
/// draws a file picker constrained by the tool's own `accepted_extensions` and
/// file cap, a form built from the tool's option schema, and then the three
/// states a job goes through — uploading with a determinate bar and a live
/// cancel, waiting on a worker at the interval the server asked for, and
/// finished with something to open.
///
/// A 402 is the one failure that is not a toast: a user who has run out of
/// conversions cannot fix that on this screen, so they are taken to the plan.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/tool_repository.dart';
import '../domain/conversion.dart';
import '../domain/tool.dart';
import '../domain/tool_copy.dart';
import 'conversion_files.dart';
import 'providers.dart';
import 'widgets/conversion_result_card.dart';
import 'widgets/file_slot.dart';
import 'widgets/tool_option_field.dart';

class ToolRunScreen extends ConsumerStatefulWidget {
  const ToolRunScreen({required this.toolKey, super.key});

  final String toolKey;

  @override
  ConsumerState<ToolRunScreen> createState() => _ToolRunScreenState();
}

class _ToolRunScreenState extends ConsumerState<ToolRunScreen> {
  /// True while a download for the result card is in flight.
  bool _busy = false;

  ToolRunController get _controller =>
      ref.read(conversionRunProvider(widget.toolKey).notifier);

  // ------------------------------------------------------------------ actions

  Future<void> _convert() async {
    FocusScope.of(context).unfocus();

    final bool queued = await _controller.submit();
    if (!context.mounted || queued) {
      return;
    }

    final Object? error = ref.read(conversionRunProvider(widget.toolKey)).error;
    if (error == null) {
      // Client-side validation: the messages are already under the fields.
      return;
    }

    final ApiException failure = ApiException.from(error);
    if (failure.isCancelled) {
      return;
    }
    if (failure.isQuota) {
      Toast.error(context, failure);
      context.pushNamed(AppRoute.billing);
      return;
    }
    Toast.error(context, failure);
  }

  Future<void> _withFile(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
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

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final ToolRunState state = ref.watch(conversionRunProvider(widget.toolKey));

    // Only subscribed while a job is actually in flight; the provider is
    // auto-disposed the moment this stops being true, which is what stops the
    // polling loop.
    final int? jobId = state.isPolling ? state.conversionId : null;
    if (jobId != null) {
      ref.listen<AsyncValue<ConversionStatusInfo>>(
        conversionStatusPollProvider(jobId),
        (AsyncValue<ConversionStatusInfo>? _,
            AsyncValue<ConversionStatusInfo> next) {
          next.whenOrNull(
            data: (ConversionStatusInfo info) =>
                unawaited(_controller.onStatus(info)),
            error: (Object error, StackTrace __) =>
                _controller.onPollFailure(error),
          );
        },
      );
      ref.watch(conversionStatusPollProvider(jobId));
    }

    return PageScaffold(
      title: state.tool.valueOrNull?.label ?? S.pdfTools,
      subtitle: state.tool.valueOrNull?.badge,
      showBack: true,
      scrollable: true,
      child: state.tool.when(
        loading: () => const _FormSkeleton(),
        error: (Object error, StackTrace _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: ErrorState(
            error: error,
            onRetry: () {
              ref.invalidate(toolsProvider);
              ref.invalidate(conversionRunProvider(widget.toolKey));
            },
            onUpgrade: () => context.pushNamed(AppRoute.billing),
          ),
        ),
        data: (ToolDefinition tool) => _Body(
          tool: tool,
          state: state,
          busy: _busy,
          onPick: _controller.pickFiles,
          onRemoveFile: _controller.removeFile,
          onChange: _controller.setValue,
          onConvert: _convert,
          onCancel: _controller.cancel,
          onAgain: _controller.reset,
          onDismissFailure: _controller.dismissFailure,
          onOpen: (Conversion c) => _withFile(
            () => ConversionFiles(ref.read(toolRepositoryProvider))
                .open(context, c),
          ),
          onDownload: (Conversion c) => _withFile(
            () => ConversionFiles(ref.read(toolRepositoryProvider))
                .save(context, c),
          ),
          onShare: (Conversion c) => _withFile(
            () => ConversionFiles(ref.read(toolRepositoryProvider))
                .share(context, c),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.tool,
    required this.state,
    required this.busy,
    required this.onPick,
    required this.onRemoveFile,
    required this.onChange,
    required this.onConvert,
    required this.onCancel,
    required this.onAgain,
    required this.onDismissFailure,
    required this.onOpen,
    required this.onDownload,
    required this.onShare,
  });

  final ToolDefinition tool;
  final ToolRunState state;
  final bool busy;
  final VoidCallback onPick;
  final ValueChanged<int> onRemoveFile;
  final void Function(String name, String? value) onChange;
  final VoidCallback onConvert;
  final VoidCallback onCancel;
  final VoidCallback onAgain;
  final VoidCallback onDismissFailure;
  final ValueChanged<Conversion> onOpen;
  final ValueChanged<Conversion> onDownload;
  final ValueChanged<Conversion> onShare;

  @override
  Widget build(BuildContext context) {
    final bool editing = state.phase == ToolRunPhase.editing ||
        state.phase == ToolRunPhase.uploading;
    final bool enabled = state.phase == ToolRunPhase.editing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ToolCopy, not `tool.description`: the server describes each tool by
        // the program that runs it ("with LibreOffice headless", "local
        // Ghostscript quality presets"), which is right for the API docs and
        // wrong for a phone. Display only — see features/tools/domain/tool_copy.dart.
        if (ToolCopy.description(tool.key, tool.description) != null) ...<Widget>[
          Text(
            ToolCopy.description(tool.key, tool.description)!,
            style: AppText.bodySm,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (!tool.supported) ...<Widget>[
          InlineNotice(
            message: tool.unsupportedReason ?? S.toolWebOnly,
            tone: NoticeTone.warn,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // `tool.warning` is deliberately NOT rendered here.
        //
        // The server still sends it (DocumentConversionService::tools() sets it
        // on pdf-to-word, and ToolResource publishes it), and ToolDefinition
        // still parses it, so the API contract and the website's own warning box
        // are untouched — this is a mobile presentation decision only. On a
        // phone the caveat filled a third of the screen above the file picker
        // and pushed the primary action below the fold.
        //
        // To bring it back, restore:
        //   if (tool.warning != null) ...<Widget>[
        //     InlineNotice(message: tool.warning!, tone: NoticeTone.warn),
        //     const SizedBox(height: AppSpacing.lg),
        //   ],
        if (editing && tool.supported) ...<Widget>[
          if (tool.needsFiles) ...<Widget>[
            FileSlot(
              tool: tool,
              files: state.files,
              maxFiles: state.maxFiles,
              onPick: onPick,
              onRemove: onRemoveFile,
              error: state.fileError,
              enabled: enabled,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          for (final ToolOption option in tool.formOptions)
            ToolOptionField(
              option: option,
              value: state.values[option.name],
              error: state.errors[option.name],
              enabled: enabled,
              form: state.values,
              onChanged: (String? value) => onChange(option.name, value),
            ),
          if (tool.titleOption != null)
            ToolOptionField(
              option: tool.titleOption!,
              value: state.values['title'],
              error: state.errors['title'],
              enabled: enabled,
              form: state.values,
              onChanged: (String? value) => onChange('title', value),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (state.phase == ToolRunPhase.uploading)
            _UploadProgress(state: state, onCancel: onCancel)
          else
            FilledButton(
              onPressed: state.canSubmit ? onConvert : null,
              child: Text(tool.submitLabel ?? S.convert),
            ),
        ],
        if (state.phase == ToolRunPhase.queued)
          _WaitingCard(status: state.status),
        if (state.phase == ToolRunPhase.finished && state.result != null)
          ConversionResultCard(
            conversion: state.result!,
            busy: busy,
            onOpen: () => onOpen(state.result!),
            onDownload: () => onDownload(state.result!),
            onShare: () => onShare(state.result!),
            onAgain: onAgain,
          ),
        if (state.phase == ToolRunPhase.failed)
          _FailureCard(error: state.error, onAgain: onDismissFailure),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }
}

/// Determinate, because dio reports sent and total bytes and a spinner during a
/// three-minute upload on a train is how an app gets force-quit.
class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.state, required this.onCancel});

  final ToolRunState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final int percent = (state.progress * 100).round();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(S.uploadingFiles, style: AppText.h3)),
              Text(
                '$percent%',
                style: AppText.numeric.copyWith(color: AppColors.brandDeep),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: '${S.uploadingFiles} $percent%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.brand),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${Fmt.bytes(state.sentBytes)} / ${Fmt.bytes(state.totalBytes)}',
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

/// Queued: the file is safely on the server and a worker will pick it up.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.status});

  final ConversionStatusInfo? status;

  @override
  Widget build(BuildContext context) {
    final bool started = status?.status == ConversionStatus.processing;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  started ? S.conversionRunning : S.conversionQueued,
                  style: AppText.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(S.conversionWaitBody, style: AppText.bodySm),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.error, required this.onAgain});

  final Object? error;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final ApiException failure =
        ApiException.from(error ?? const ApiException(
          code: ApiException.codeUnknown,
          message: S.conversionFailed,
        ));

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
                  color: AppColors.dangerTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 22,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  failure.title ?? S.conversionFailed,
                  style: AppText.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(failure.message, style: AppText.bodySm),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.tonal(onPressed: onAgain, child: const Text(S.tryAgain)),
        ],
      ),
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Skeleton(height: 140, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 120, height: 13),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 52, radius: AppRadius.control),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 120, height: 13),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 52, radius: AppRadius.control),
      ],
    );
  }
}
