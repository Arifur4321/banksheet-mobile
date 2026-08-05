/// One captured page, before it becomes a PDF page.
///
/// Holds a *path*, never bytes. A ten-page scan is thirty to forty megabytes of
/// JPEG; keeping that in a Riverpod state object would mean the whole set is
/// resident for as long as the screen is open, copied on every `copyWith`, and
/// carried across the isolate boundary when the PDF is built. The files are
/// already on disk in the OS's own capture cache — the list only has to
/// remember where and in what order.
library;

import 'dart:io';

/// A page waiting to be written into a PDF.
class ScanPage {
  const ScanPage({
    required this.id,
    required this.path,
    required this.capturedAt,
    required this.source,
  });

  /// Stable across reorders, so the grid can key its tiles by identity rather
  /// than by index — without it, deleting page 2 makes page 3's thumbnail
  /// flash as it inherits the removed widget's element.
  final String id;

  final String path;
  final DateTime capturedAt;
  final ScanSource source;

  File get file => File(path);

  /// The on-disk size, or 0 if the OS has already reclaimed the capture. Used
  /// only for display; a missing file is caught at build time with a message
  /// naming the page.
  int get sizeBytes {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  bool get exists => file.existsSync();
}

/// Where a page came from. Kept because the two have different failure modes
/// worth telling apart in a support conversation: a camera page can be denied
/// by a permission, a gallery page can be a cloud placeholder that never
/// downloads.
enum ScanSource { camera, gallery }
