/// Camera and gallery captures in, a PDF on disk out.
///
/// Everything here happens **on the device**. There is a server-side
/// `images-to-pdf` conversion tool and this deliberately does not use it, for
/// three reasons that all point the same way:
///
///   * it has to work with no account, and every mobile API route except
///     `/auth/*` is behind a bearer token;
///   * uploading ten full-resolution photos over mobile data to get back a file
///     the phone could have produced in under a second is a worse product on
///     every axis — time, data, battery, offline;
///   * it must not spend a signed-in user's monthly conversion quota. The
///     server counts one `used_conversions` per `images-to-pdf` run
///     (`PlanEnforcementService::reserveDocumentConversion`), so routing the
///     scanner through it would silently bill scanning against the same
///     allowance as PDF-to-Word.
///
/// The PDF writing itself is [ImagePdfBuilder], which already existed for the
/// statement-capture flow and is unchanged — this is a second caller, not a
/// second implementation.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../../documents/data/image_pdf_builder.dart';
import '../domain/scan_page.dart';

/// A page could not be read — the capture was corrupt, or the OS reclaimed it
/// between selection and build.
class ScanPageUnreadable implements Exception {
  const ScanPageUnreadable(this.pageNumber);

  /// 1-based, as the user counts pages.
  final int pageNumber;
}

/// The platform picker refused, and said why.
///
/// Carries a message fit to show the user rather than a `PlatformException`
/// dump: "camera_access_denied" on screen is a bug report, not an explanation.
class ScanPickerFailed implements Exception {
  const ScanPickerFailed(this.detail);

  final String detail;

  @override
  String toString() => 'ScanPickerFailed($detail)';
}

/// The user has spent the install's free PDFs.
///
/// Thrown rather than returned so it cannot be ignored at a call site: the one
/// thing this must never do is quietly write a fourth free PDF.
class ScanQuotaExhausted implements Exception {
  const ScanQuotaExhausted(this.used, this.limit);

  final int used;
  final int limit;
}

/// A finished scan.
class ScanResult {
  const ScanResult({
    required this.path,
    required this.filename,
    required this.pageCount,
    required this.sizeBytes,
  });

  final String path;
  final String filename;
  final int pageCount;
  final int sizeBytes;
}

class ScanRepository {
  ScanRepository(this._db, {ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final LocalDb _db;
  final ImagePicker _picker;

  /// Where finished scans live.
  ///
  /// Documents, not cache: a PDF the user made is theirs and must still be
  /// there tomorrow. The OS empties the cache directory whenever it is short of
  /// space, and "my scan disappeared" is not a bug anyone can debug later.
  static const String _folder = 'scans';

  // ------------------------------------------------------------- capturing

  /// One photo from the camera.
  ///
  /// Capped at 2600px on the long edge and 88% quality at capture time rather
  /// than after: a modern phone hands back a 12-megapixel, 5 MB JPEG per page,
  /// and asking the plugin to downscale first means the resize inside
  /// [ImagePdfBuilder] starts from something reasonable instead of decoding
  /// 48 MB of pixels per page. Still comfortably above the 1600px the builder
  /// targets, so nothing is lost twice.
  Future<ScanPage?> capture() => _pick(ImageSource.camera, ScanSource.camera);

  /// One or more images from the gallery.
  Future<List<ScanPage>> pickFromGallery() async {
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: 2600,
      maxHeight: 2600,
      imageQuality: 88,
    );

    final DateTime now = DateTime.now();
    return <ScanPage>[
      for (int i = 0; i < files.length; i++)
        ScanPage(
          id: _mintId(now, i),
          path: files[i].path,
          capturedAt: now,
          source: ScanSource.gallery,
        ),
    ];
  }

  Future<ScanPage?> _pick(ImageSource source, ScanSource kind) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 2600,
      maxHeight: 2600,
      imageQuality: 88,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) {
      // The user backed out of the camera. An ordinary outcome, not an error.
      return null;
    }

    final DateTime now = DateTime.now();
    return ScanPage(
      id: _mintId(now, 0),
      path: file.path,
      capturedAt: now,
      source: kind,
    );
  }

  /// Claims a capture Android threw away, and returns it as pages.
  ///
  /// **This is the fix for "I took a photo and nothing happened."** The camera
  /// is a separate app in a separate process. While it is in the foreground
  /// Android is free to kill this one — and on a mid-range phone with a large
  /// app open it routinely does. The photo was still taken and is sitting in
  /// the picker's cache; `pickImage`'s future, however, belongs to a process
  /// that no longer exists, so it never completes and the app comes back to an
  /// empty scan with no error and nothing to retry.
  ///
  /// `retrieveLostData` is the platform channel's answer to exactly that, and
  /// it is Android-only — on iOS the response is always empty, which is why
  /// this is safe to call unconditionally on resume.
  ///
  /// Returns an empty list when there is nothing to claim, which is the normal
  /// case; callers should not treat that as a failure.
  Future<List<ScanPage>> recoverLostCaptures() async {
    late final LostDataResponse lost;
    try {
      lost = await _picker.retrieveLostData();
    } on Object catch (e) {
      // A platform that does not implement the call is not an error worth
      // surfacing — there is simply nothing to recover.
      Log.debug('retrieveLostData unavailable: $e');
      return const <ScanPage>[];
    }

    if (lost.isEmpty) {
      return const <ScanPage>[];
    }

    if (lost.exception != null) {
      Log.warn('Lost capture carried an error: ${lost.exception}');
      return const <ScanPage>[];
    }

    final List<XFile> files = lost.files ??
        <XFile>[if (lost.file != null) lost.file!];
    if (files.isEmpty) {
      return const <ScanPage>[];
    }

    Log.info('Recovered ${files.length} capture(s) the OS had discarded');

    final DateTime now = DateTime.now();
    return <ScanPage>[
      for (int i = 0; i < files.length; i++)
        ScanPage(
          id: _mintId(now, i),
          path: files[i].path,
          capturedAt: now,
          source: ScanSource.camera,
        ),
    ];
  }

  // -------------------------------------------------------------- quota

  Future<int> freeRemaining() => _db.installRemaining(InstallMeter.scanPdf);

  Future<bool> hasFreeQuota() => _db.installHasQuota(InstallMeter.scanPdf);

  // -------------------------------------------------------------- building

  /// Builds the PDF and writes it into the documents directory.
  ///
  /// [metered] is false for a signed-in user: their account is the thing that
  /// unlocked unlimited scanning, so nothing is counted. It is true for a
  /// guest, and the counter is incremented **after** the file is safely on
  /// disk — spending an allowance on a build that then failed would be the one
  /// unforgivable version of this.
  Future<ScanResult> buildPdf(
    List<ScanPage> pages, {
    required bool metered,
    String? title,
  }) async {
    if (pages.isEmpty) {
      throw const ScanPageUnreadable(1);
    }

    if (metered) {
      final int used = await _db.installUsed(InstallMeter.scanPdf);
      if (used >= InstallMeter.scanPdf.freeLimit) {
        throw ScanQuotaExhausted(used, InstallMeter.scanPdf.freeLimit);
      }
    }

    // Every page is checked before a single one is decoded, so a missing
    // capture is reported as "page 3" rather than as a failure two seconds into
    // a build the user thinks is nearly done.
    for (int i = 0; i < pages.length; i++) {
      if (!pages[i].exists) {
        throw ScanPageUnreadable(i + 1);
      }
    }

    final Uint8List bytes;
    try {
      // compute(): decoding, rotating, resizing and re-encoding ten photos is
      // seconds of CPU, and on the UI isolate that is seconds of frozen app.
      bytes = await compute(
        ImagePdfBuilder.buildFromPaths,
        pages.map((ScanPage page) => page.path).toList(growable: false),
      );
    } on ImagePdfException catch (e) {
      throw ScanPageUnreadable(e.pageNumber);
    }

    final Directory dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, _folder),
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final File out = File(p.join(dir.path, _uniqueName(dir, title)));
    await out.writeAsBytes(bytes, flush: true);

    if (metered) {
      final int used = await _db.bumpInstallUsage(InstallMeter.scanPdf);
      Log.info('Scan PDF written; $used of '
          '${InstallMeter.scanPdf.freeLimit} free scans used');
    }

    return ScanResult(
      path: out.path,
      filename: p.basename(out.path),
      pageCount: pages.length,
      sizeBytes: bytes.length,
    );
  }

  /// Deletes a scan the user discarded from the result screen.
  Future<void> discard(String path) async {
    final File file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  // -------------------------------------------------------------- naming

  /// `Scan 2026-08-05 21-40.pdf`, with a counter appended only on collision.
  ///
  /// Date-first so the user's file manager sorts scans chronologically, and
  /// minute precision so two scans a second apart do not silently overwrite —
  /// hence the collision loop rather than trusting the timestamp to be unique.
  static String _uniqueName(Directory dir, String? title) {
    final String base = (title ?? '').trim().isNotEmpty
        ? _sanitise(title!.trim())
        : 'Scan ${_stamp(DateTime.now())}';

    String candidate = '$base.pdf';
    int n = 2;
    while (File(p.join(dir.path, candidate)).existsSync()) {
      candidate = '$base ($n).pdf';
      n++;
    }
    return candidate;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}-${two(t.minute)}';
  }

  /// Strips what Android's MediaStore, iOS's Files app and Windows all refuse.
  /// A user who names a scan "Invoice 3/2026" should get a file, not an error.
  static String _sanitise(String raw) {
    final String cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return 'Scan ${_stamp(DateTime.now())}';
    }
    return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
  }

  static String _mintId(DateTime at, int index) =>
      '${at.microsecondsSinceEpoch}-$index';
}
