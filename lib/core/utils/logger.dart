/// Logging.
///
/// No crash-reporting SDK is wired in: the brief was explicit that no paid
/// third-party service may be added. This writes to the platform log in debug
/// and keeps a small in-memory ring buffer in release so the About screen can
/// show recent errors when a user reports a problem — enough to diagnose
/// without shipping anyone's data off the device.
library;

import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  const LogEntry(this.level, this.message, this.at, [this.detail]);

  final LogLevel level;
  final String message;
  final DateTime at;
  final String? detail;

  @override
  String toString() =>
      '[${at.toIso8601String()}] ${level.name.toUpperCase()} $message'
      '${detail == null ? '' : '\n$detail'}';
}

abstract final class Log {
  static const int _maxEntries = 120;
  static final Queue<LogEntry> _buffer = Queue<LogEntry>();

  /// Newest first, for the diagnostics view.
  static List<LogEntry> get recent => _buffer.toList().reversed.toList();

  static void debug(String message) => _write(LogLevel.debug, message);

  static void info(String message) => _write(LogLevel.info, message);

  static void warn(String message) => _write(LogLevel.warn, message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    _write(
      LogLevel.error,
      message,
      detail: <String>[
        if (error != null) error.toString(),
        if (stack != null && kDebugMode) stack.toString(),
      ].join('\n'),
    );
  }

  static void _write(LogLevel level, String message, {String? detail}) {
    final LogEntry entry = LogEntry(level, message, DateTime.now(), detail);

    _buffer.addLast(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }

    // `debugPrint` is rate limited and `developer.log` is structured; using
    // both keeps output readable in the IDE and in `flutter logs`.
    if (kDebugMode) {
      developer.log(
        message,
        name: 'banksheet',
        level: switch (level) {
          LogLevel.debug => 500,
          LogLevel.info => 800,
          LogLevel.warn => 900,
          LogLevel.error => 1000,
        },
        error: detail,
      );
    }
  }

  static void clear() => _buffer.clear();
}
