/// Turns a handful of camera captures into a real PDF, on the device.
///
/// The server accepts JPG and PNG uploads but cannot extract anything from them
/// ("Processing not supported yet for JPG, PNG, or ZIP uploads") — so a photo of
/// a bank statement is only useful once it is a PDF. Doing that server-side
/// would mean uploading ten full-resolution photos over mobile data and adding a
/// conversion step to the queue; doing it here costs a second of CPU and sends
/// one file.
///
/// There is no PDF package in `pubspec.yaml` and this build may not add one, so
/// the writer below is hand rolled. It emits the smallest structure that is
/// still a valid PDF 1.4: a catalog, a page tree, and one page per capture whose
/// only content is a single JPEG XObject drawn with `/DCTDecode` — i.e. the
/// original JPEG bytes are embedded untouched rather than re-encoded into the
/// file. That is why this is ~200 lines instead of a dependency.
///
/// Nothing here imports Flutter. It is pure Dart so the whole pipeline can be
/// handed to `compute()` — decoding and re-encoding ten 12-megapixel photos on
/// the UI isolate would drop every frame for several seconds — and so it can be
/// unit tested without a widget binding.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A capture that failed to decode, carrying which page it was so the screen
/// can name it.
class ImagePdfException implements Exception {
  const ImagePdfException(this.pageNumber);

  /// 1-based, as the user counts pages.
  final int pageNumber;

  @override
  String toString() => 'ImagePdfException(page $pageNumber could not be read)';
}

/// One normalised page: JPEG bytes plus the pixel size they decode to.
class ScannedPage {
  const ScannedPage({
    required this.jpeg,
    required this.width,
    required this.height,
  });

  final Uint8List jpeg;
  final int width;
  final int height;

  bool get isPortrait => height >= width;
}

/// Where an image sits on its page, in PDF points.
class _Placement {
  const _Placement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pageWidth,
    required this.pageHeight,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double pageWidth;
  final double pageHeight;
}

abstract final class ImagePdfBuilder {
  /// Longest edge, in pixels, any page is allowed to keep.
  ///
  /// 1600 px across an A4 page is roughly 200 dpi — comfortably enough for OCR
  /// and for a human reading a statement, and small enough that ten pages at
  /// [jpegQuality] land around 3–5 MB, well inside the server's 20 MB cap.
  static const int maxEdge = 1600;

  /// JPEG quality. 80 is the knee of the curve: below it, thin statement digits
  /// start to smear and OCR accuracy falls off a cliff.
  static const int jpegQuality = 80;

  /// A4 in PDF points (72 per inch). Statements in this product's market are
  /// A4, and a page that prints to the same size as the original is one less
  /// thing for an accountant to explain.
  static const double a4Short = 595.28;
  static const double a4Long = 841.89;

  /// Isolate entry point: read each file, normalise it, and assemble the PDF.
  ///
  /// Takes paths rather than bytes so the raw photos are never copied across
  /// the isolate boundary — ten 4 MB captures would be 40 MB of message.
  static Uint8List buildFromPaths(List<String> paths) {
    final List<ScannedPage> pages = <ScannedPage>[];
    for (int i = 0; i < paths.length; i++) {
      pages.add(normalise(File(paths[i]).readAsBytesSync(), i + 1));
    }
    return assemble(pages);
  }

  /// The same pipeline from bytes already in memory.
  static Uint8List buildFromBytes(List<Uint8List> sources) {
    final List<ScannedPage> pages = <ScannedPage>[];
    for (int i = 0; i < sources.length; i++) {
      pages.add(normalise(sources[i], i + 1));
    }
    return assemble(pages);
  }

  /// Decode, bake the EXIF rotation in, cap the long edge and re-encode as a
  /// three-channel JPEG.
  ///
  /// The orientation bake matters more than it looks: a phone held sideways
  /// writes an upright sensor image plus an EXIF tag, and a PDF has nowhere to
  /// put that tag — so the page would come out rotated for everyone.
  static ScannedPage normalise(Uint8List source, int pageNumber) {
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null) {
      throw ImagePdfException(pageNumber);
    }

    img.Image working = img.bakeOrientation(decoded);

    final int longEdge = math.max(working.width, working.height);
    if (longEdge > maxEdge) {
      final double ratio = maxEdge / longEdge;
      working = img.copyResize(
        working,
        width: math.max(1, (working.width * ratio).round()),
        height: math.max(1, (working.height * ratio).round()),
        interpolation: img.Interpolation.average,
      );
    }

    // Force three channels. A greyscale capture would otherwise encode as a
    // one-channel JPEG, and the page dictionary below declares /DeviceRGB —
    // the mismatch renders as garbage in strict viewers rather than failing
    // loudly.
    if (working.numChannels != 3) {
      working = working.convert(numChannels: 3);
    }

    return ScannedPage(
      jpeg: img.encodeJpg(working, quality: jpegQuality),
      width: working.width,
      height: working.height,
    );
  }

  /// Write the PDF.
  ///
  /// Object numbering is fixed rather than allocated, because the cross
  /// reference table has to name byte offsets and the simplest way not to get
  /// that wrong is for the layout to be arithmetic: 1 is the catalog, 2 is the
  /// page tree, and page `i` owns `3 + 3i` (the page), `4 + 3i` (its content
  /// stream) and `5 + 3i` (its image).
  static Uint8List assemble(List<ScannedPage> pages) {
    if (pages.isEmpty) {
      throw const ImagePdfException(1);
    }

    final BytesBuilder out = BytesBuilder(copy: false);
    // Byte offset of every object, indexed by object number - 1.
    final List<int> offsets = <int>[];

    void ascii(String value) => out.add(latin1.encode(value));

    ascii('%PDF-1.4\n');
    // The conventional binary marker. Tools that sniff text vs binary need it
    // to stop treating the stream data below as text and mangling line endings.
    out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    offsets.add(out.length);
    ascii('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    final StringBuffer kids = StringBuffer();
    for (int i = 0; i < pages.length; i++) {
      if (i > 0) {
        kids.write(' ');
      }
      kids.write('${3 + i * 3} 0 R');
    }

    offsets.add(out.length);
    ascii(
      '2 0 obj\n'
      '<< /Type /Pages\n'
      '/Kids [$kids]\n'
      '/Count ${pages.length}\n'
      '>>\nendobj\n',
    );

    for (int i = 0; i < pages.length; i++) {
      final ScannedPage page = pages[i];
      final int pageObj = 3 + i * 3;
      final int contentObj = pageObj + 1;
      final int imageObj = pageObj + 2;
      final _Placement box = _place(page);

      offsets.add(out.length);
      ascii(
        '$pageObj 0 obj\n'
        '<< /Type /Page\n'
        '/Parent 2 0 R\n'
        '/MediaBox [0 0 ${_num(box.pageWidth)} ${_num(box.pageHeight)}]\n'
        '/Resources << /XObject << /Im0 $imageObj 0 R >> '
        '/ProcSet [/PDF /ImageC] >>\n'
        '/Contents $contentObj 0 R\n'
        '>>\nendobj\n',
      );

      // `cm` sets the transformation matrix to scale the unit image square up
      // to the placed rectangle; `Do` paints it. q/Q brackets the state change
      // so a future second element on the page would not inherit the scale.
      final List<int> content = latin1.encode(
        'q ${_num(box.width)} 0 0 ${_num(box.height)} '
        '${_num(box.x)} ${_num(box.y)} cm /Im0 Do Q\n',
      );

      offsets.add(out.length);
      ascii('$contentObj 0 obj\n<< /Length ${content.length} >>\nstream\n');
      out.add(content);
      ascii('\nendstream\nendobj\n');

      offsets.add(out.length);
      ascii(
        '$imageObj 0 obj\n'
        '<< /Type /XObject\n'
        '/Subtype /Image\n'
        '/Width ${page.width}\n'
        '/Height ${page.height}\n'
        '/ColorSpace /DeviceRGB\n'
        '/BitsPerComponent 8\n'
        '/Filter /DCTDecode\n'
        '/Length ${page.jpeg.length}\n'
        '>>\nstream\n',
      );
      out.add(page.jpeg);
      ascii('\nendstream\nendobj\n');
    }

    final int xrefOffset = out.length;
    final int size = offsets.length + 1;

    // Every entry is exactly 20 bytes — that is not a style choice, readers
    // seek into this table by multiplying.
    ascii('xref\n0 $size\n');
    ascii('0000000000 65535 f \n');
    for (final int offset in offsets) {
      ascii('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }

    ascii(
      'trailer\n<< /Size $size /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    );

    return out.takeBytes();
  }

  /// Fit the capture inside an A4 page of matching orientation, centred.
  static _Placement _place(ScannedPage page) {
    final double pageWidth = page.isPortrait ? a4Short : a4Long;
    final double pageHeight = page.isPortrait ? a4Long : a4Short;

    final double scale = math.min(
      pageWidth / page.width,
      pageHeight / page.height,
    );
    final double width = page.width * scale;
    final double height = page.height * scale;

    return _Placement(
      x: (pageWidth - width) / 2,
      y: (pageHeight - height) / 2,
      width: width,
      height: height,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
  }

  /// PDF reals have no exponent form, so a plain fixed representation is the
  /// only safe one.
  static String _num(double value) => value.toStringAsFixed(2);
}
