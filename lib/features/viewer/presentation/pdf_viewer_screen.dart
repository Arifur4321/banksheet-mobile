/// The PDF reader.
///
/// **This is the only file in the project that imports `pdfx`.** That is a
/// deliberate containment boundary: `pdfx` binds to Pdfium on Android and
/// PDFKit on iOS, so it is the single most likely dependency to change API
/// shape or misbehave on a specific device. Keeping every reference here means
/// swapping renderer — or pinning a different version — touches one file
/// instead of the feature.
///
/// Rendering happens off the widget tree in the plugin's own isolate, so a
/// 300-page statement scrolls without dropping the frame rate. The controller
/// is created in [initState] and disposed in [dispose] rather than living in a
/// provider, because a document held open after its route pops is tens of
/// megabytes of native memory the OS will eventually kill the app for.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/local_db.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/states.dart';
import 'providers.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    required this.path,
    required this.title,
    super.key,
  });

  final String path;
  final String title;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  PdfControllerPinch? _controller;

  /// Set when the document could not be opened at all — a truncated download,
  /// an encrypted file, or a path the OS reclaimed between listing and tapping.
  Object? _openError;

  int _page = 1;
  int _pages = 0;

  /// Chrome hides while reading and comes back on tap, the way every reader
  /// the user already has behaves.
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    final File file = File(widget.path);
    if (!file.existsSync()) {
      setState(() => _openError = const FileSystemException(
            'This file is no longer on the device.',
          ));
      return;
    }

    try {
      _controller = PdfControllerPinch(
        document: PdfDocument.openFile(widget.path),
      );
    } on Object catch (e, st) {
      Log.error('Could not open PDF: ${widget.path}', e, st);
      setState(() => _openError = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    try {
      await Share.shareXFiles(<XFile>[XFile(widget.path)]);
    } on Object catch (e) {
      if (mounted) {
        Toast.error(context, e);
      }
    }
  }

  /// Drops the entry from history when the file has gone, so the user is not
  /// offered the same dead row again next time.
  Future<void> _forgetAndLeave() async {
    await ref.read(recentFilesRepositoryProvider).forget(widget.path);
    ref.invalidate(recentFilesProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PdfControllerPinch? controller = _controller;

    return Scaffold(
      backgroundColor: AppColors.inkStrong,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: AppColors.inkStrong,
              foregroundColor: AppColors.inkInverse,
              elevation: 0,
              title: Text(
                Fmt.middleEllipsis(widget.title),
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.inkInverse,
                ),
              ),
              actions: <Widget>[
                IconButton(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share',
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            )
          : null,
      body: _openError != null
          ? _CannotOpen(error: _openError!, onDismiss: _forgetAndLeave)
          : controller == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.brandLight),
                )
              : GestureDetector(
                  onTap: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                  child: PdfViewPinch(
                    controller: controller,
                    onDocumentLoaded: (PdfDocument document) {
                      if (!mounted) {
                        return;
                      }
                      setState(() => _pages = document.pagesCount);
                      // The page count is only knowable once the renderer has
                      // parsed the file, so history learns it here rather than
                      // opening every PDF twice at pick time.
                      ref.read(recentFilesRepositoryProvider).remember(
                            widget.path,
                            source: RecentSource.picker,
                            filename: widget.title,
                            pageCount: document.pagesCount,
                          );
                    },
                    onPageChanged: (int page) {
                      if (mounted) {
                        setState(() => _page = page);
                      }
                    },
                    onDocumentError: (Object error) {
                      Log.error('PDF render failure', error);
                      if (mounted) {
                        setState(() => _openError = error);
                      }
                    },
                  ),
                ),
      bottomNavigationBar: _chromeVisible && _pages > 0
          ? _PageBar(page: _page, pages: _pages)
          : null,
    );
  }
}

/// The page counter. Deliberately not a scrubber: a slider over 300 pages on a
/// 6-inch screen selects the wrong page more often than the right one.
class _PageBar extends StatelessWidget {
  const _PageBar({required this.page, required this.pages});

  final int page;
  final int pages;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 52,
        color: AppColors.inkStrong,
        alignment: Alignment.center,
        child: Text(
          'Page $page of $pages',
          style: AppText.caption.copyWith(color: AppColors.brandLight),
        ),
      ),
    );
  }
}

class _CannotOpen extends StatelessWidget {
  const _CannotOpen({required this.error, required this.onDismiss});

  final Object error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 56,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'This PDF could not be opened',
              style: AppText.h3.copyWith(color: AppColors.inkInverse),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'It may have been moved or deleted, or it may be password '
              'protected. Android also clears picked files from its cache, so '
              'a file opened days ago can disappear on its own.',
              style: AppText.bodySm.copyWith(color: AppColors.inkFaint),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(onPressed: onDismiss, child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}
