/// Picking PDFs off the device, and remembering which ones were opened.
///
/// The reader is the one part of BankSheet Pro that works with no account and
/// no network, so this repository talks to the filesystem and [LocalDb] only —
/// it never touches [ApiClient]. That is what lets the viewer render on the
/// first launch of a fresh install, before the user has decided whether to sign
/// up, which is the whole point of leading with it.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';

/// Raised when the user picked something that is not a readable PDF.
class PickCancelled implements Exception {
  const PickCancelled();
}

class RecentFilesRepository {
  const RecentFilesRepository(this._db);

  final LocalDb _db;

  /// Recents, with entries whose file has disappeared filtered out *and*
  /// removed from the table.
  ///
  /// This is not defensive coding for its own sake. On Android `file_picker`
  /// returns a path into the app's cache directory, and the OS reclaims that
  /// cache whenever it feels like it — so a recents list that trusts its own
  /// rows will show the user a row that explodes when tapped. Checking on read
  /// costs one `stat` per row and removes an entire class of support ticket.
  Future<List<RecentFile>> load({int limit = 20}) async {
    final List<RecentFile> rows = await _db.recentFiles(limit: limit);
    final List<RecentFile> alive = <RecentFile>[];

    for (final RecentFile row in rows) {
      if (File(row.path).existsSync()) {
        alive.add(row);
      } else {
        await _db.forgetFile(row.path);
        Log.debug('Recent file vanished, dropped: ${row.filename}');
      }
    }

    return alive;
  }

  /// Opens the system picker filtered to PDFs.
  ///
  /// Returns null when the user backed out, which is an ordinary outcome and
  /// not an error — the caller shows nothing rather than a toast.
  Future<RecentFile?> pickPdf() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
      // The bytes are not wanted: a 40 MB PDF read into memory to then be
      // handed to a renderer that wants a path is 40 MB of pure waste.
      withData: false,
    );

    final PlatformFile? picked = result?.files.singleOrNull;
    final String? path = picked?.path;
    if (picked == null || path == null || path.isEmpty) {
      return null;
    }

    final File file = File(path);
    if (!file.existsSync()) {
      Log.warn('Picker returned a path that does not exist: $path');
      return null;
    }

    final RecentFile entry = RecentFile(
      path: path,
      filename: picked.name,
      sizeBytes: picked.size,
      openedAt: DateTime.now(),
      source: RecentSource.picker,
    );

    await _db.rememberFile(entry);
    return entry;
  }

  /// Records an open of a file the app already had — a conversion output or a
  /// download — so the reader's history covers the whole product, not just
  /// files the user picked by hand.
  Future<void> remember(
    String path, {
    required RecentSource source,
    String? filename,
    int? pageCount,
  }) async {
    final File file = File(path);
    if (!file.existsSync()) {
      return;
    }

    await _db.rememberFile(
      RecentFile(
        path: path,
        filename: filename ?? path.split(Platform.pathSeparator).last,
        sizeBytes: file.lengthSync(),
        pageCount: pageCount,
        openedAt: DateTime.now(),
        source: source,
      ),
    );
  }

  /// Called once the renderer knows the real page count, which is not
  /// available at pick time without opening the document twice.
  Future<void> recordPageCount(RecentFile file, int pageCount) =>
      _db.rememberFile(
        RecentFile(
          path: file.path,
          filename: file.filename,
          sizeBytes: file.sizeBytes,
          pageCount: pageCount,
          openedAt: file.openedAt,
          source: file.source,
        ),
      );

  Future<void> forget(String path) => _db.forgetFile(path);

  Future<void> clear() => _db.clearRecents();
}
