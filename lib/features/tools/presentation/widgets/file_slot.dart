/// The file area of the tool form.
///
/// Draws the empty drop zone, the chosen files, and the one line that matters
/// most on a metered connection: what this tool accepts and how many files it
/// will take. Both come from the server's schema, so a tool whose rules change
/// needs no change here.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/states.dart';
import '../../data/tool_repository.dart';
import '../../domain/tool.dart';

class FileSlot extends StatelessWidget {
  const FileSlot({
    required this.tool,
    required this.files,
    required this.maxFiles,
    required this.onPick,
    required this.onRemove,
    super.key,
    this.error,
    this.enabled = true,
  });

  final ToolDefinition tool;
  final List<ToolUpload> files;

  /// The lower of the validator's ceiling and this workspace's plan ceiling.
  final int maxFiles;

  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final String? error;
  final bool enabled;

  bool get _canAddMore => tool.multiple && files.length < maxFiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (files.isEmpty)
          _DropZone(tool: tool, maxFiles: maxFiles, onTap: enabled ? onPick : null)
        else ...<Widget>[
          for (int i = 0; i < files.length; i++)
            _FileRow(
              file: files[i],
              index: i,
              showOrder: tool.multiple,
              onRemove: enabled ? () => onRemove(i) : null,
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              if (_canAddMore)
                TextButton.icon(
                  onPressed: enabled ? onPick : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(S.addFiles),
                ),
              if (!tool.multiple)
                TextButton.icon(
                  onPressed: enabled ? onPick : null,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text(S.changeFile),
                ),
            ],
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          InlineNotice(message: error!, tone: NoticeTone.danger),
        ],
      ],
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.tool,
    required this.maxFiles,
    required this.onTap,
  });

  final ToolDefinition tool;
  final int maxFiles;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String accepted =
        tool.acceptedLabel ?? tool.acceptedExtensions.join(', ').toUpperCase();

    return Semantics(
      button: true,
      label: '${S.chooseFile}. $accepted',
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.cardAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.section,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Column(
              children: <Widget>[
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.brandTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    size: 26,
                    color: AppColors.brandDeep,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  tool.multiple ? S.chooseFiles : S.chooseFile,
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  accepted,
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  tool.multiple
                      ? S.upToFiles(maxFiles, Fmt.bytes(tool.maxFileBytes))
                      : S.upToSize(Fmt.bytes(tool.maxFileBytes)),
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.index,
    required this.showOrder,
    required this.onRemove,
  });

  final ToolUpload file;
  final int index;

  /// Merge and images-to-pdf both build their output in selection order, so the
  /// position is information rather than decoration.
  final bool showOrder;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.brandTint,
                borderRadius: AppRadius.smallAll,
              ),
              child: showOrder
                  ? Text(
                      '${index + 1}',
                      style: AppText.numeric.copyWith(
                        fontSize: 13,
                        color: AppColors.brandDeep,
                      ),
                    )
                  : const Icon(
                      Icons.insert_drive_file_rounded,
                      size: 17,
                      color: AppColors.brandDeep,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fmt.middleEllipsis(file.filename),
                    style: AppText.bodySm.copyWith(color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(Fmt.bytes(file.sizeBytes), style: AppText.caption),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: S.remove,
              ),
          ],
        ),
      ),
    );
  }
}
