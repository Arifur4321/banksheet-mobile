/// Upload a document.
///
/// Two ways in: pick a file, or photograph the pages. The camera path builds a
/// real PDF on the device (see `image_pdf_builder.dart`) because the server
/// stores a JPG but cannot extract anything from one — sending photos would
/// consume a document from the user's allowance and give them nothing back.
///
/// Three things here exist because of failures that are only visible in
/// production:
///   * the size check runs against [AppConfig.maxDocumentUploadBytes] *before*
///     a byte is sent, so a 40 MB scan fails in a second rather than after four
///     minutes of upload and a 413;
///   * the idempotency key is generated once per chosen file and reused across
///     retries, so a retry after a dropped response returns the original
///     document instead of consuming a second unit of quota;
///   * a 402 goes straight to the billing screen, because there is nothing else
///     the user can do on this one.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/scene_3d.dart';
import '../../../core/widgets/states.dart';
import '../data/document_repository.dart';
import '../domain/document.dart';
import 'providers.dart';
import 'widgets/upload_progress.dart';

class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState
    extends ConsumerState<DocumentUploadScreen> {
  void _handleTransition(UploadState? previous, UploadState next) {
    if (previous?.phase == next.phase) {
      return;
    }

    if (next.phase == UploadPhase.success) {
      final UploadResult? result = next.result;
      if (result == null) {
        return;
      }

      // The list behind this screen is now stale in a way the user will see.
      ref.read(documentListProvider.notifier).refresh();

      if (result.idempotentReplay) {
        Toast.info(context, S.alreadyUploaded);
      } else if (result.warning != null) {
        Toast.info(context, result.warning!);
      } else {
        Toast.success(context, S.documentUploaded);
      }

      // Replace rather than push: going "back" to a spent upload form is a dead
      // end, and re-tapping upload there would be confusing at best.
      context.pushReplacementNamed(
        AppRoute.documentDetail,
        pathParameters: <String, String>{'id': '${result.document.id}'},
      );
      return;
    }

    if (next.phase == UploadPhase.failure && next.error != null) {
      final ApiException failure = ApiException.from(next.error!);
      if (failure.isQuota) {
        context.pushNamed(AppRoute.billing);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UploadState>(uploadControllerProvider, _handleTransition);

    final UploadState state = ref.watch(uploadControllerProvider);
    final UploadController controller =
        ref.read(uploadControllerProvider.notifier);

    return PageScaffold(
      title: S.uploadDocument,
      subtitle: S.acceptedFormats,
      showBack: true,
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.phase == UploadPhase.uploading)
            UploadProgress(
              progress: state.progress,
              sentBytes: state.sentBytes,
              totalBytes: state.totalBytes,
              filename: state.selection?.filename,
              onCancel: controller.cancel,
            )
          else ...<Widget>[
            if (state.selection == null && state.scanPages.isEmpty)
              _SourceChoices(
                onPickFile: controller.pickFile,
                onScan: controller.capturePage,
                busy: state.isBusy,
              ),
            if (state.selection == null && state.scanPages.isNotEmpty)
              _ScanTray(
                pages: state.scanPages,
                busy: state.isBusy,
                onAdd: controller.capturePage,
                onRemove: controller.removePage,
                onReorder: controller.reorderPages,
                onClear: controller.clearPages,
                onBuild: controller.buildScanPdf,
              ),
            if (state.selection != null) ...<Widget>[
              _SelectedFile(
                selection: state.selection!,
                tooLarge: state.isTooLarge,
                onChange: controller.reset,
              ),
              const SizedBox(height: AppSpacing.lg),
              _TypeSelector(
                value: state.documentType,
                onChanged: controller.setDocumentType,
              ),
              if (state.isBankStatement) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _ProfilePicker(
                  value: state.profileId,
                  onChanged: controller.setProfile,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: state.canUpload ? controller.upload : null,
                icon: const Icon(Icons.cloud_upload_rounded, size: 19),
                label: const Text(S.uploadNow),
              ),
            ],
          ],
          if (state.phase == UploadPhase.preparing) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const _Preparing(),
          ],
          if (state.error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _FailureNotice(
              error: state.error!,
              onRetry: state.selection == null ? null : controller.upload,
              onDismiss: controller.dismissError,
            ),
          ],
          const SizedBox(height: AppSpacing.section),
        ],
      ),
    );
  }
}

/// The two ways in.
class _SourceChoices extends StatelessWidget {
  const _SourceChoices({
    required this.onPickFile,
    required this.onScan,
    required this.busy,
  });

  final VoidCallback onPickFile;
  final VoidCallback onScan;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TiltCard(
          onTap: busy ? null : onPickFile,
          semanticLabel: S.chooseFile,
          child: const _Choice(
            icon: Icons.folder_open_rounded,
            title: S.chooseFile,
            body: S.fileHint,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TiltCard(
          onTap: busy ? null : onScan,
          semanticLabel: S.scanWithCamera,
          child: const _Choice(
            icon: Icons.photo_camera_rounded,
            title: S.scanWithCamera,
            body: S.scanHint,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          S.acceptedFormatsBody,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.brandTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 26, color: AppColors.brandDeep),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: AppText.h3),
              const SizedBox(height: 2),
              Text(body, style: AppText.bodySm),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: AppColors.inkFaint,
        ),
      ],
    );
  }
}

/// Captured pages, in the order they will appear in the PDF.
class _ScanTray extends StatelessWidget {
  const _ScanTray({
    required this.pages,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.onClear,
    required this.onBuild,
  });

  final List<String> pages;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onClear;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    // Its own scroll area rather than growing inside the page: a ten page scan
    // would otherwise push the primary action below the fold.
    final double height =
        (pages.length * 80.0).clamp(80.0, 360.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(
          title: S.scanPages,
          subtitle: S.reorderHint,
        ),
        SizedBox(
          height: height,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: pages.length,
            onReorder: onReorder,
            itemBuilder: (BuildContext context, int index) {
              return _PageTile(
                key: ValueKey<String>(pages[index]),
                path: pages[index],
                index: index,
                onRemove: busy ? null : () => onRemove(index),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: busy ? null : onAdd,
          icon: const Icon(Icons.add_a_photo_rounded, size: 18),
          label: const Text(S.addPage),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: busy ? null : onBuild,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: Text(S.createPdfFrom(pages.length)),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: busy ? null : onClear,
          child: const Text(S.discardPages),
        ),
      ],
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.path,
    required this.index,
    required this.onRemove,
    super.key,
  });

  final String path;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.smallAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(path),
                width: 40,
                height: 52,
                fit: BoxFit.cover,
                // Decode at thumbnail size — a 12 MP capture held at full
                // resolution in the image cache is 48 MB per page.
                cacheWidth: 120,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 40,
                  height: 52,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                S.pageNumber(index + 1),
                style: AppText.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              tooltip: S.removePage,
              color: AppColors.danger,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 20,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedFile extends StatelessWidget {
  const _SelectedFile({
    required this.selection,
    required this.tooLarge,
    required this.onChange,
  });

  final UploadSelection selection;
  final bool tooLarge;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tooLarge
                      ? AppColors.dangerTint
                      : AppColors.brandTint,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(
                  selection.source == UploadSource.scan
                      ? Icons.document_scanner_rounded
                      : Icons.insert_drive_file_rounded,
                  size: 21,
                  color: tooLarge ? AppColors.danger : AppColors.brandDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fmt.middleEllipsis(selection.filename),
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.bytes(selection.sizeBytes),
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onChange,
                child: const Text(S.changeFile),
              ),
            ],
          ),
        ),
        if (tooLarge) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          InlineNotice(
            message: S.fileTooLarge(
              Fmt.bytes(selection.sizeBytes),
              Fmt.bytes(AppConfig.maxDocumentUploadBytes),
            ),
            tone: NoticeTone.danger,
          ),
        ] else if (selection.isUnprocessable) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const InlineNotice(
            message: S.unprocessableUpload,
            tone: NoticeTone.warn,
          ),
        ],
      ],
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(S.documentType, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String type in DocumentRepository.documentTypes)
              ChoiceChip(
                label: Text(DocumentKind.from(type).label),
                selected: type == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(type),
                selectedColor: AppColors.brandTint,
                backgroundColor: AppColors.surface,
                labelStyle: AppText.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: type == value
                      ? AppColors.brandDeep
                      : AppColors.inkBody,
                ),
                side: BorderSide(
                  color: type == value
                      ? AppColors.brandTintStrong
                      : AppColors.border,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Optional. "Auto-match" is the default and is usually right — the profile
/// picker exists for the case where it is not.
class _ProfilePicker extends ConsumerWidget {
  const _ProfilePicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProfileRef>> options = ref.watch(
      extractionProfileOptionsProvider(DocumentKind.bankStatement.wire),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(S.extractionProfile, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        options.when(
          loading: () => const Skeleton(height: 52, radius: AppRadius.control),
          error: (Object error, _) => const InlineNotice(
            message: S.profilesUnavailable,
            tone: NoticeTone.info,
          ),
          data: (List<ProfileRef> profiles) {
            // A remembered profile that has since been deleted or deactivated
            // must not be handed to the dropdown, which asserts on a value it
            // cannot find among its items.
            final int? selected = profiles.any((ProfileRef p) => p.id == value)
                ? value
                : null;

            return InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.tune_rounded, size: 19),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: selected,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: AppRadius.controlAll,
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      child: Text(S.autoMatchProfile),
                    ),
                    for (final ProfileRef profile in profiles)
                      DropdownMenuItem<int?>(
                        value: profile.id,
                        child: Text(
                          profile.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(child: Text(S.buildingPdf, style: AppText.bodySm)),
        ],
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({
    required this.error,
    required this.onRetry,
    required this.onDismiss,
  });

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ApiException failure = ApiException.from(error);

    if (failure.isQuota) {
      return InlineNotice(
        message: failure.message,
        tone: NoticeTone.warn,
        actionLabel: S.seePlans,
        onAction: () => context.pushNamed(AppRoute.billing),
      );
    }

    return InlineNotice(
      message: failure.message,
      tone: NoticeTone.danger,
      actionLabel: onRetry == null ? S.close : S.tryAgain,
      onAction: onRetry ?? onDismiss,
    );
  }
}
