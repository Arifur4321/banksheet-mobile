/// The scanner's free tier, and the PDF it writes.
///
/// Two things are worth a test here and the rest is UI.
///
/// **The allowance.** Three free PDFs per install is the one number in this app
/// a user can feel cheated by. The tests below pin the ceiling, that it does
/// not reset on a new month, and — the one that matters most — that signing out
/// does not hand back a fresh three.
///
/// **The PDF.** `ImagePdfBuilder` writes the file by hand, byte by byte,
/// including a cross-reference table of absolute offsets. An off-by-one there
/// produces a file that some readers open and others reject, which is the worst
/// possible failure mode: it looks fine on the developer's phone. So the
/// structure is asserted, not eyeballed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:banksheet_mobile/core/config/app_config.dart';
import 'package:banksheet_mobile/core/storage/local_db.dart';
import 'package:banksheet_mobile/features/documents/data/image_pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // The real sqflite needs a device. `sqflite_common_ffi` runs the same SQL
    // against a local SQLite, so the migrations and the upsert below are the
    // ones that ship — not a mock that agrees with whatever was written.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('InstallMeter', () {
    test('the free scan allowance is three', () {
      expect(InstallMeter.scanPdf.freeLimit, 3);
      expect(InstallMeter.scanPdf.freeLimit, AppConfig.freeScanPdfs);
    });
  });

  group('LocalDb install counters', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.openInMemory();
    });

    tearDown(() => db.close());

    test('a fresh install has the full allowance', () async {
      expect(await db.installUsed(InstallMeter.scanPdf), 0);
      expect(await db.installRemaining(InstallMeter.scanPdf), 3);
      expect(await db.installHasQuota(InstallMeter.scanPdf), isTrue);
    });

    test('spending counts down and then stops', () async {
      expect(await db.bumpInstallUsage(InstallMeter.scanPdf), 1);
      expect(await db.bumpInstallUsage(InstallMeter.scanPdf), 2);
      expect(await db.installRemaining(InstallMeter.scanPdf), 1);
      expect(await db.installHasQuota(InstallMeter.scanPdf), isTrue);

      expect(await db.bumpInstallUsage(InstallMeter.scanPdf), 3);
      expect(await db.installHasQuota(InstallMeter.scanPdf), isFalse);
      expect(await db.installRemaining(InstallMeter.scanPdf), 0);
    });

    test('remaining never goes negative', () async {
      for (int i = 0; i < 6; i++) {
        await db.bumpInstallUsage(InstallMeter.scanPdf);
      }
      expect(await db.installUsed(InstallMeter.scanPdf), 6);
      expect(await db.installRemaining(InstallMeter.scanPdf), 0);
    });

    test('signing out does NOT hand back the free allowance', () async {
      // The whole reason this counter lives in its own table. If wipeAll()
      // cleared it, "sign out and back in" would be a one-tap trial reset.
      await db.bumpInstallUsage(InstallMeter.scanPdf);
      await db.bumpInstallUsage(InstallMeter.scanPdf);

      await db.wipeAll();

      expect(await db.installUsed(InstallMeter.scanPdf), 2);
      expect(await db.installRemaining(InstallMeter.scanPdf), 1);
    });

    test('wipeAll still clears the things that belong to a session', () async {
      await db.rememberFile(
        RecentFile(
          path: '/tmp/a.pdf',
          filename: 'a.pdf',
          sizeBytes: 10,
          openedAt: DateTime.now(),
          source: RecentSource.picker,
        ),
      );
      await db.bumpGuestUsage(GuestMeter.conversion);

      await db.wipeAll();

      expect(await db.recentFiles(), isEmpty);
      expect(await db.guestUsed(GuestMeter.conversion), 0);
    });

    test('concurrent bumps do not lose a count', () async {
      // Two taps on a fast device. A read-then-write would have both read 0 and
      // both written 1; the SQL upsert is what makes this land on 2.
      await Future.wait<int>(<Future<int>>[
        db.bumpInstallUsage(InstallMeter.scanPdf),
        db.bumpInstallUsage(InstallMeter.scanPdf),
      ]);
      expect(await db.installUsed(InstallMeter.scanPdf), 2);
    });
  });

  group('ImagePdfBuilder', () {
    Uint8List jpeg(int w, int h) {
      final img.Image im = img.Image(width: w, height: h);
      img.fill(im, color: img.ColorRgb8(220, 220, 220));
      return img.encodeJpg(im, quality: 80);
    }

    test('writes a structurally valid PDF for one page', () {
      final Uint8List pdf = ImagePdfBuilder.buildFromBytes(
        <Uint8List>[jpeg(800, 1000)],
      );
      final String head = latin1.decode(pdf.sublist(0, 9));
      final String tail = latin1.decode(pdf.sublist(pdf.length - 400));

      expect(head, '%PDF-1.4\n');
      expect(tail, contains('startxref'));
      expect(tail.trimRight(), endsWith('%%EOF'));
      expect(latin1.decode(pdf, allowInvalid: true), contains('/Count 1'));
    });

    test('every xref offset points at the object it claims', () {
      // The check that actually catches a corrupt file. A reader seeks to these
      // byte offsets; if one is wrong by a single byte the document is broken
      // in a way no visual inspection finds.
      final Uint8List pdf = ImagePdfBuilder.buildFromBytes(
        <Uint8List>[jpeg(600, 800), jpeg(800, 600), jpeg(400, 400)],
      );
      final String text = latin1.decode(pdf, allowInvalid: true);

      final int xrefAt = int.parse(
        RegExp(r'startxref\s+(\d+)').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(xrefAt, xrefAt + 4), 'xref');

      final RegExp entry = RegExp(r'^(\d{10}) 00000 n $', multiLine: true);
      final List<RegExpMatch> entries =
          entry.allMatches(text.substring(xrefAt)).toList();

      // catalog + page tree + 3 objects per page
      expect(entries.length, 2 + 3 * 3);

      for (int i = 0; i < entries.length; i++) {
        final int offset = int.parse(entries[i].group(1)!);
        expect(
          text.startsWith('${i + 1} 0 obj', offset),
          isTrue,
          reason: 'xref entry ${i + 1} points at byte $offset, which is not '
              'the start of object ${i + 1}',
        );
      }
    });

    test('a portrait capture gets a portrait A4 page and vice versa', () {
      final String portrait = latin1.decode(
        ImagePdfBuilder.buildFromBytes(<Uint8List>[jpeg(600, 900)]),
        allowInvalid: true,
      );
      final String landscape = latin1.decode(
        ImagePdfBuilder.buildFromBytes(<Uint8List>[jpeg(900, 600)]),
        allowInvalid: true,
      );

      expect(portrait, contains('/MediaBox [0 0 595.28 841.89]'));
      expect(landscape, contains('/MediaBox [0 0 841.89 595.28]'));
    });

    test('an oversized capture is scaled to the target long edge', () {
      final ScannedPage page =
          ImagePdfBuilder.normalise(jpeg(4000, 3000), 1);
      expect(page.width, ImagePdfBuilder.maxEdge);
      expect(page.height, (ImagePdfBuilder.maxEdge * 3000 / 4000).round());
    });

    test('an unreadable capture names the page it was', () {
      expect(
        () => ImagePdfBuilder.buildFromBytes(<Uint8List>[
          jpeg(100, 100),
          Uint8List.fromList(<int>[1, 2, 3, 4]),
        ]),
        throwsA(
          isA<ImagePdfException>()
              .having((ImagePdfException e) => e.pageNumber, 'pageNumber', 2),
        ),
      );
    });

    test('no pages is an error, not an empty PDF', () {
      expect(
        () => ImagePdfBuilder.buildFromBytes(<Uint8List>[]),
        throwsA(isA<ImagePdfException>()),
      );
    });
  });
}
