/// Defensive JSON readers.
///
/// The mobile API promises never to drop a key, but a value can legitimately be
/// null, and Eloquent's `decimal:2` casts arrive as strings on some paths. Every
/// model parses through these helpers so one unexpected type cannot crash a
/// screen — the field degrades to null instead.
library;

abstract final class J {
  static Map<String, dynamic> map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> list(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  static List<String> strings(dynamic value) {
    if (value is List) {
      return value
          .where((dynamic e) => e != null)
          .map((dynamic e) => e.toString())
          .toList(growable: false);
    }
    return const <String>[];
  }

  static String? str(dynamic value) {
    if (value == null) {
      return null;
    }
    final String s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String strOr(dynamic value, String fallback) => str(value) ?? fallback;

  static int? intOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static int intOr(dynamic value, int fallback) => intOrNull(value) ?? fallback;

  static double? doubleOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  static double doubleOr(dynamic value, double fallback) =>
      doubleOrNull(value) ?? fallback;

  static bool boolOr(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String v = value.toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') {
        return true;
      }
      if (v == 'false' || v == '0' || v == 'no') {
        return false;
      }
    }
    return fallback;
  }

  /// Parses an ISO-8601 timestamp. Returns null rather than throwing, because a
  /// malformed date must never take a list screen down.
  static DateTime? date(dynamic value) {
    final String? raw = str(value);
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}

/// Pagination metadata, matching `MobileController::paginated()`.
class PageMeta {
  const PageMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.hasMore,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    final int current = J.intOr(json['current_page'], 1);
    final int last = J.intOr(json['last_page'], current);
    return PageMeta(
      currentPage: current,
      lastPage: last,
      perPage: J.intOr(json['per_page'], 20),
      total: J.intOr(json['total'], 0),
      hasMore: J.boolOr(json['has_more'], fallback: current < last),
    );
  }

  static const PageMeta empty = PageMeta(
    currentPage: 1,
    lastPage: 1,
    perPage: 20,
    total: 0,
    hasMore: false,
  );

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final bool hasMore;
}

/// A page of results plus its metadata.
class Paged<T> {
  const Paged({required this.items, required this.meta});

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    return Paged<T>(
      items: J.list(json['data']).map(parse).toList(growable: false),
      meta: PageMeta.fromJson(J.map(json['meta'])),
    );
  }

  final List<T> items;
  final PageMeta meta;

  bool get isEmpty => items.isEmpty;

  Paged<T> merge(Paged<T> next) => Paged<T>(
        items: <T>[...items, ...next.items],
        meta: next.meta,
      );
}
