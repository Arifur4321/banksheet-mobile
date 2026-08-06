/// What happens the second a scan finishes.
///
/// A file written to a directory the user cannot browse is not a finished job.
/// This sheet is the handover: it names the file, says how big it is, and gives
/// the three things anyone actually wants next — read it, send it, or throw it
/// away.
///
/// It also records the PDF in the reader's recent files, so the scan appears in
/// the app's own history rather than only existing in whatever the share sheet
/// did with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../viewer/presentation/providers.dart';
import '../../data/scan_repository.dart';
import '../providers.dart';

Future<void> showScanResult(BuildContext context, ScanResult result) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    // Dismissing by swipe would leave the user staring at an empty scanner with
    // no idea whether the file was saved. There is a Done button.
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
    builder: (BuildContext ctx) => _ScanResultSheet(result: result),
  );
}

class _ScanResultSheet extends ConsumerStatefulWidget {
  const _ScanResultSheet({required this.result});

  final ScanResult result;

  @override
  ConsumerState<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<_ScanResultSheet> {
  @override
  void initState() {
    super.initState();
    // Recorded on arrival rather than on "Open": the file exists and belongs in
    // the history whether or not the user reads it right now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _remember());
  }

  Future<void> _remember() async {
    try {
      await ref.read(recentFilesRepositoryProvider).remember(
            widget.result.path,
            source: RecentSource.conversion,
            filename: widget.result.filename,
            pageCount: widget.result.pageCount,
          );
      ref.invalidate(recentFilesProvider);
    } on Object catch (e, s) {
      // A history entry is a convenience. Losing it must not look like losing
      // the PDF, which is safely on disk by this point.
      Log.warn('Could not record scan in recents: $e');
      Log.debug(s.toString());
    }
  }

  Future<void> _share() async {
    // Same call shape as every other share in this app (the viewer, exports,
    // barcodes) so there is one share API to reason about, not two — including
    // the anchor. On iPad the share sheet is a popover: with no origin
    // rectangle to attach to, `shareXFiles` throws instead of opening. See the
    // identical note in features/tools/presentation/conversion_files.dart.
    final RenderObject? box = context.findRenderObject();

    await Share.shareXFiles(
      <XFile>[
        XFile(
          widget.result.path,
          name: widget.result.filename,
          mimeType: 'application/pdf',
        ),
      ],
      subject: widget.result.filename,
      sharePositionOrigin:
          box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Future<void> _delete() async {
    await ref.read(scanRepositoryProvider).discard(widget.result.path);
    await ref.read(recentFilesRepositoryProvider).forget(widget.result.path);
    ref.invalidate(recentFilesProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScanResult r = widget.result;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: AppColors.successTint,
                    borderRadius: AppRadius.smallAll,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('PDF created', style: AppText.h3),
                      const SizedBox(height: 2),
                      Text(
                        '${r.pageCount} ${r.pageCount == 1 ? 'page' : 'pages'}'
                        ' · ${Fmt.bytes(r.sizeBytes)}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.smallAll,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 18,
                    color: AppColors.brandDeep,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      Fmt.middleEllipsis(r.filename),
                      style: AppText.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(
                  AppRoute.pdfView,
                  queryParameters: <String, String>{
                    'path': r.path,
                    'title': r.filename,
                  },
                );
              },
              icon: const Icon(Icons.menu_book_rounded, size: 20),
              label: const Text('Open PDF'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text('Share or save'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Saved on this device. Find it again under Recent.',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
