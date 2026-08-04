/// Downloading a server-held file onto the phone, then opening or sharing it.
///
/// Four features need exactly this — the export archive, generated PDFs, signed
/// PDFs and (through the archive) a document's spreadsheets — and every one of
/// those files sits behind an authenticated route on a private disk. A plain
/// URL handed to the browser would 401, so the bytes have to come through
/// [ApiClient] and land on disk before the OS can be asked to do anything with
/// them.
///
/// It lives in `features/exports` because that is the feature the archive
/// belongs to; it is imported by templates, signatures and profiles as a shared
/// helper rather than being copied four times.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// What to do with a file once it is on the device.
enum FileAction {
  /// Hand it to whichever app the OS thinks owns the type.
  open,

  /// Put it in the system share sheet.
  share,

  /// Leave it in the app's documents folder and say so.
  save,
}

class FileDownloader {
  const FileDownloader(this._api);

  final ApiClient _api;

  /// A folder of our own inside the app documents directory, so a user browsing
  /// Files sees `BankSheet/intesa-marzo-2025-88.xlsx` rather than a loose pile
  /// at the root of the container.
  static const String folderName = 'BankSheet';

  /// Streams [path] (an [Endpoints] value, never a raw URL) to the app
  /// documents directory and returns the file.
  ///
  /// Re-downloading the same item overwrites rather than making `file (2).pdf`:
  /// the server builds these filenames deterministically precisely so the phone
  /// and the website agree about what a given export is called.
  Future<File> download({
    required String path,
    required String filename,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory folder = Directory(p.join(root.path, folderName));

    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }

    return _api.download(
      path,
      p.join(folder.path, safeFilename(filename)),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Does the thing the user actually asked for with a file already on disk.
  ///
  /// Shared so the four screens that download something all treat "open" and
  /// "share" identically, down to the failure message.
  static Future<void> apply(
    FileAction action,
    File file, {
    String? subject,
    Rect? origin,
  }) async {
    switch (action) {
      case FileAction.open:
        await open(file);
      case FileAction.share:
        await share(file, subject: subject, origin: origin);
      case FileAction.save:
        break;
    }
  }

  /// Opens the file with the system handler.
  ///
  /// A missing handler is a normal outcome — a phone with no spreadsheet app
  /// cannot open an XLSX — so it is turned into a message the user can act on
  /// instead of a silent no-op.
  static Future<void> open(File file) async {
    final OpenResult result = await OpenFilex.open(file.path);

    if (result.type == ResultType.done) {
      return;
    }

    throw ApiException(
      code: ApiException.codeUnknown,
      message: result.type == ResultType.noAppToOpen
          ? S.couldNotOpenFile
          : (result.message.isEmpty ? S.couldNotOpenFile : result.message),
    );
  }

  /// Puts the file in the system share sheet.
  ///
  /// [origin] matters on iPad, where the sheet is a popover anchored to the
  /// control that opened it; without it iPadOS throws.
  static Future<void> share(
    File file, {
    String? subject,
    Rect? origin,
  }) async {
    await Share.shareXFiles(
      <XFile>[XFile(file.path)],
      subject: subject,
      sharePositionOrigin: origin,
    );
  }

  /// The rectangle of the widget that triggered a share, in global
  /// coordinates. Null when the element is gone, which the share sheet accepts.
  static Rect? originOf(BuildContext context) {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Strips anything that could escape the download folder or upset a file
  /// system. The server already slugs these names; this is belt and braces
  /// around a value that arrived over the network.
  static String safeFilename(String raw) {
    final String base = p.basename(raw.trim());
    final String cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '-');
    final String trimmed = cleaned.replaceAll(RegExp(r'^[.-]+'), '');
    return trimmed.isEmpty ? 'banksheet-download' : trimmed;
  }
}

final Provider<FileDownloader> fileDownloaderProvider =
    Provider<FileDownloader>(
  (Ref ref) => FileDownloader(ref.watch(apiClientProvider)),
);
