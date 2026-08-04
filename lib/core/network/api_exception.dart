/// One error type for the whole app.
///
/// The server always answers failures with
/// `{"error": {"code", "status", "title", "detail", ...}}` (see
/// `app/Services/Mobile/MobileErrors.php`). Branching on `code` — never on the
/// message — is what keeps the client stable when copy changes.
library;

import 'dart:io';

import 'package:dio/dio.dart';

/// A failure the UI can render without knowing anything about HTTP.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.status,
    this.title,
    this.fieldErrors = const <String, List<String>>{},
    this.extra = const <String, dynamic>{},
  });

  /// Machine-readable code from `MobileErrors::CATALOG`, or one of the
  /// client-side codes below.
  final String code;

  /// Human-readable, already localised by the server where applicable.
  final String message;

  final int? status;
  final String? title;

  /// Per-field validation messages, when the server sent `errors`.
  final Map<String, List<String>> fieldErrors;

  /// Sibling keys that came alongside the error, e.g. `usage` on a 402 or
  /// `minimum_version` on a 426.
  final Map<String, dynamic> extra;

  // ------------------------------------------------- client-side only codes
  static const String codeOffline = 'offline';
  static const String codeTimeout = 'timeout';
  static const String codeCancelled = 'cancelled';
  static const String codeMalformed = 'malformed_response';
  static const String codeUnknown = 'unknown_error';

  bool get isOffline => code == codeOffline;
  bool get isTimeout => code == codeTimeout;
  bool get isCancelled => code == codeCancelled;

  /// The token is gone or dead — the session must end.
  bool get isAuthFailure =>
      code == 'unauthorized' ||
      code == 'invalid_token' ||
      code == 'invalid_grant';

  /// The access token merely expired; a refresh should be attempted.
  bool get isTokenExpired => code == 'token_expired';

  /// A quota or plan wall the user can act on by upgrading.
  bool get isQuota => code == 'quota_exceeded' || code == 'plan_feature_required';

  /// The binary is too old for this server.
  bool get isClientOutdated => code == 'client_outdated';

  bool get isRetryable =>
      isOffline || isTimeout || code == 'server_error' || code == 'store_unavailable';

  /// Builds an [ApiException] from anything dio can throw.
  factory ApiException.from(Object error, [StackTrace? _]) {
    if (error is ApiException) {
      return error;
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.cancel:
          return const ApiException(
            code: codeCancelled,
            message: 'Request cancelled.',
          );
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const ApiException(
            code: codeTimeout,
            message:
                'The server took too long to respond. Check your connection and try again.',
          );
        case DioExceptionType.connectionError:
          return const ApiException(
            code: codeOffline,
            message: 'No connection. Your changes will be sent when you are back online.',
          );
        case DioExceptionType.unknown:
          if (error.error is SocketException) {
            return const ApiException(
              code: codeOffline,
              message: 'No connection.',
            );
          }
          return ApiException(
            code: codeUnknown,
            message: error.message ?? 'Something went wrong.',
          );
        case DioExceptionType.badCertificate:
          return const ApiException(
            code: codeUnknown,
            message: 'The server certificate could not be verified.',
          );
        case DioExceptionType.badResponse:
          return ApiException.fromResponse(error.response);
      }
    }

    return ApiException(code: codeUnknown, message: error.toString());
  }

  /// Parses the server's error envelope.
  factory ApiException.fromResponse(Response<dynamic>? response) {
    final int? status = response?.statusCode;
    final dynamic data = response?.data;

    if (data is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(data);

      // Preferred shape: MobileErrors.
      final dynamic err = map['error'];
      if (err is Map) {
        final Map<String, dynamic> e = Map<String, dynamic>.from(err);
        final Map<String, dynamic> extra = <String, dynamic>{
          ...Map<String, dynamic>.fromEntries(
            map.entries
                .where((MapEntry<dynamic, dynamic> kv) => kv.key != 'error')
                .map((MapEntry<dynamic, dynamic> kv) =>
                    MapEntry<String, dynamic>(kv.key.toString(), kv.value)),
          ),
          ...Map<String, dynamic>.fromEntries(
            e.entries.where((MapEntry<String, dynamic> kv) => const <String>{
                  'code',
                  'status',
                  'title',
                  'detail',
                  'errors',
                }.contains(kv.key) ==
                false),
          ),
        };

        return ApiException(
          code: (e['code'] as String?) ?? _codeForStatus(status),
          status: (e['status'] as num?)?.toInt() ?? status,
          title: e['title'] as String?,
          message: (e['detail'] as String?) ??
              (e['title'] as String?) ??
              _messageForStatus(status),
          fieldErrors: _parseFieldErrors(e['errors']),
          extra: extra,
        );
      }

      // Laravel's default validation envelope, in case a route slips through
      // without the mobile exception renderer.
      if (map.containsKey('errors') || map.containsKey('message')) {
        return ApiException(
          code: status == 422 ? 'validation_failed' : _codeForStatus(status),
          status: status,
          message: (map['message'] as String?) ?? _messageForStatus(status),
          fieldErrors: _parseFieldErrors(map['errors']),
        );
      }
    }

    return ApiException(
      code: _codeForStatus(status),
      status: status,
      message: _messageForStatus(status),
    );
  }

  static Map<String, List<String>> _parseFieldErrors(dynamic raw) {
    if (raw is! Map) {
      return const <String, List<String>>{};
    }
    final Map<String, List<String>> out = <String, List<String>>{};
    raw.forEach((dynamic key, dynamic value) {
      if (value is List) {
        out[key.toString()] =
            value.map((dynamic v) => v.toString()).toList(growable: false);
      } else if (value != null) {
        out[key.toString()] = <String>[value.toString()];
      }
    });
    return out;
  }

  static String _codeForStatus(int? status) => switch (status) {
        400 => 'invalid_request',
        401 => 'unauthorized',
        402 => 'quota_exceeded',
        403 => 'forbidden',
        404 => 'not_found',
        409 => 'conflict',
        413 => 'file_too_large',
        422 => 'validation_failed',
        426 => 'client_outdated',
        429 => 'rate_limited',
        503 => 'store_unavailable',
        _ => 'server_error',
      };

  static String _messageForStatus(int? status) => switch (status) {
        401 => 'Please sign in again.',
        403 => 'You do not have access to that.',
        404 => 'That item no longer exists.',
        413 => 'That file is too large.',
        429 => 'Too many requests. Please slow down and try again.',
        503 => 'The service is busy. Please try again shortly.',
        _ => 'Something went wrong. Please try again.',
      };

  /// First message for a field, for inline form errors.
  String? fieldError(String field) {
    final List<String>? list = fieldErrors[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  @override
  String toString() => 'ApiException($code, status: $status): $message';
}
