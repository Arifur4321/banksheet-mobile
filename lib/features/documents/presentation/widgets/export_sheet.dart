/// The export sheet: pick a format, or re-download something already generated.
///
/// Re-download is offered first because generating an export is not free — it
/// walks every approved row and writes a file the server then keeps — and a
/// user who wants yesterday's spreadsheet again should not create a second copy
/// of it in their archive.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/document.dart';

/// What the user chose.
sealed class ExportChoice {
  const ExportChoice();
}

/// Generate a new export in this format (`xlsx`, `csv` or `json`).
class NewExportChoice extends ExportChoice {
  const NewExportChoice(this.format);

  final String format;
}

/// Download a file the server already has.
class ExistingExportChoice extends ExportChoice {
  const ExistingExportChoice(this.export);

  final DocumentExport export;
}

/// One of the three formats `DocumentController::export()` validates.
class _Format {
  const _Format(this.wire, this.label, this.body, this.icon);

  final String wire;
  final String label;
  final String body;
  final IconData icon;
}

const List<_Format> _formats = <_Format>[
  _Format('xlsx', S.exportXlsx, S.exportXlsxBody, Icons.table_chart_rounded),
  _Format('csv', S.exportCsv, S.exportCsvBody, Icons.grid_on_rounded),
  _Format('json', S.exportJson, S.exportJsonBody, Icons.data_object_rounded),
];

Future<ExportChoice?> showExportSheet(
  BuildContext context, {
  List<DocumentExport> recent = const <DocumentExport>[],
}) {
  final List<DocumentExport> available = recent
      .where((DocumentExport e) => e.isAvailable)
      .take(3)
      .toList(growable: false);

  return showModalBottomSheet<ExportChoice>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(S.exportFormat, style: AppText.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(S.exportFormatBody, style: AppText.bodySm),
            const SizedBox(height: AppSpacing.lg),
            for (final _Format format in _formats)
              _Option(
                icon: format.icon,
                title: format.label,
                subtitle: format.body,
                onTap: () => Navigator.of(sheetContext)
                    .pop(NewExportChoice(format.wire)),
              ),
            if (available.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(S.recentExports, style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              for (final DocumentExport export in available)
                _Option(
                  icon: Icons.download_rounded,
                  title: Fmt.middleEllipsis(export.filename),
                  subtitle: '${Fmt.bytes(export.fileSize)} · '
                      '${Fmt.relative(export.generatedAt ?? export.createdAt)}',
                  onTap: () => Navigator.of(sheetContext)
                      .pop(ExistingExportChoice(export)),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 21, color: AppColors.brandDeep),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppText.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
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
