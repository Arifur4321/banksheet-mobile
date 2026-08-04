/// Pick an export format.
///
/// Two formats, because those are the two `WebExtractionController::export()`
/// accepts. XLSX is offered first: the file is one sheet per section with the
/// provenance columns intact, which is what most people want, and a CSV of the
/// same data loses the grouping.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/strings.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';

class _Format {
  const _Format(this.wire, this.label, this.body, this.icon);

  final String wire;
  final String label;
  final String body;
  final IconData icon;
}

const List<_Format> _formats = <_Format>[
  _Format('xlsx', S.exportXlsx, S.webExportXlsxBody, Icons.table_chart_rounded),
  _Format('csv', S.exportCsv, S.webExportCsvBody, Icons.grid_on_rounded),
];

/// Returns `xlsx`, `csv`, or null when the user backed out.
Future<String?> showWebExportSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
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
            Text(S.webExportTitle, style: AppText.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(S.webExportBody, style: AppText.bodySm),
            const SizedBox(height: AppSpacing.lg),
            for (final _Format format in _formats)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Material(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.controlAll,
                  child: InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(format.wire),
                    borderRadius: AppRadius.controlAll,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            format.icon,
                            size: 21,
                            color: AppColors.brandDeep,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(format.label, style: AppText.bodyStrong),
                                const SizedBox(height: 2),
                                Text(format.body, style: AppText.caption),
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
              ),
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
