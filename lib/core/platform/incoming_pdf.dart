/// PDFs handed to us by another app.
///
/// The Dart half of the bridge whose native half is `MainActivity.kt` (written
/// by `tool/native/apply.py`). Android hands the app a `content://` URI it
/// cannot read directly; the Activity copies the bytes into our cache and sends
/// back a real path. Everything above this file only ever sees a path.
///
/// Two arrival paths, and they are genuinely different:
///
///   * **Cold start** — the app was launched *by* the PDF. The intent is
///     already sitting on the Activity before Dart exists, so Dart has to ask
///     for it. That is [consumePending].
///   * **Already running** — the user tapped a PDF while the app was in the
///     background. `onNewIntent` fires natively and pushes to us. That is
///     [stream].
///
/// "Consume" is deliberate in the name: the pending value is cleared on read.
/// Without that, a hot restart during development reopens the same document
/// forever, and more importantly a real user who backgrounds and resumes the
/// app would get the document they opened an hour ago thrown back at them.
///
/// iOS is not wired yet — `Info.plist` declares the document type so the app
/// appears in the share sheet, but `AppDelegate` does not forward the URL. It
/// is out of scope until the Play closed test is running; the calls below
/// simply return nothing there rather than throwing.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/logger.dart';

class IncomingPdf {
  IncomingPdf._();

  static final IncomingPdf instance = IncomingPdf._();

  static const MethodChannel _channel =
      MethodChannel('pro.banksheet/incoming_file');

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  bool _wired = false;

  /// Paths arriving while the app is already running.
  Stream<String> get stream => _controller.stream;

  /// Starts listening for `onNewIntent` deliveries. Safe to call more than once.
  void start() {
    if (_wired) {
      return;
    }
    _wired = true;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'openFile') {
        return null;
      }
      final Object? arg = call.arguments;
      if (arg is String && arg.isNotEmpty) {
        Log.info('Incoming PDF while running: $arg');
        _controller.add(arg);
      }
      return null;
    });
  }

  /// The document the app was launched with, if any. Clears it on read.
  ///
  /// Returns null on iOS, on a normal launch, and on any platform error — a
  /// missing bridge must never stop the app from starting.
  Future<String?> consumePending() async {
    try {
      final String? path = await _channel.invokeMethod<String>('consumePending');
      if (path != null && path.isNotEmpty) {
        Log.info('Launched with PDF: $path');
        return path;
      }
    } on MissingPluginException {
      // iOS, or an Android build made before tool/native/apply.py was run.
      Log.debug('Incoming-file channel not available on this platform.');
    } on PlatformException catch (e) {
      Log.warn('Incoming-file channel failed: ${e.code}');
    }
    return null;
  }

  /// The name to show in the reader's app bar.
  ///
  /// The native side names the cache copy after the document's real display
  /// name, so the last path segment is the filename the user recognises rather
  /// than a provider's opaque id.
  static String titleFor(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final String name = slash < 0 ? path : path.substring(slash + 1);
    return name.isEmpty ? 'Document' : name;
  }
}
