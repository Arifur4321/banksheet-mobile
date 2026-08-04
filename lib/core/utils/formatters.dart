/// Display formatting.
///
/// Hand written rather than pulled from `intl` so the app has one fewer package
/// to keep in step, and so number and date rendering matches what the Laravel
/// views already produce.
library;

abstract final class Fmt {
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `3 Aug 2026`
  static String date(DateTime? d) {
    if (d == null) {
      return '—';
    }
    final DateTime l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  /// `3 Aug 2026, 14:05`
  static String dateTime(DateTime? d) {
    if (d == null) {
      return '—';
    }
    final DateTime l = d.toLocal();
    return '${date(d)}, ${_two(l.hour)}:${_two(l.minute)}';
  }

  /// `2026-01-15` — for anything the user may copy into a spreadsheet.
  static String isoDate(DateTime? d) {
    if (d == null) {
      return '';
    }
    final DateTime l = d.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)}';
  }

  /// `just now`, `4 min ago`, `yesterday`, then an absolute date.
  static String relative(DateTime? d) {
    if (d == null) {
      return '—';
    }
    final Duration diff = DateTime.now().difference(d.toLocal());
    if (diff.inSeconds < 45) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h ago';
    }
    if (diff.inDays == 1) {
      return 'yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    }
    return date(d);
  }

  /// Thousands separators, fixed decimals. `1 234 567.89`
  static String number(num? value, {int decimals = 0}) {
    if (value == null) {
      return '—';
    }
    final String fixed = value.toStringAsFixed(decimals);
    final List<String> parts = fixed.split('.');
    final String whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (Match m) => '${m[1]} ',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  /// Money with the statement's own currency code, never a guessed symbol —
  /// the extractor reports EUR, GBP and USD statements and inventing a symbol
  /// would misrepresent the source document.
  static String money(num? value, {String? currency, bool signed = false}) {
    if (value == null) {
      return '—';
    }
    final String sign = signed && value > 0 ? '+' : '';
    final String amount = number(value, decimals: 2);
    return currency == null || currency.isEmpty
        ? '$sign$amount'
        : '$sign$amount $currency';
  }

  /// `2.4 MB`
  static String bytes(int? value) {
    if (value == null) {
      return '—';
    }
    if (value < 1024) {
      return '$value B';
    }
    const List<String> units = <String>['KB', 'MB', 'GB'];
    double size = value / 1024;
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
  }

  /// `IT60 •••• •••• 3456` — enough to recognise the account, not enough to
  /// use it. Matches how the Blade view masks the IBAN.
  static String maskIban(String? iban) {
    if (iban == null || iban.isEmpty) {
      return '—';
    }
    final String clean = iban.replaceAll(' ', '');
    if (clean.length <= 8) {
      return clean;
    }
    return '${clean.substring(0, 4)} •••• •••• ${clean.substring(clean.length - 4)}';
  }

  /// `Bank statement` from `bank_statement`.
  static String humanise(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '—';
    }
    final String spaced = raw.replaceAll('_', ' ').replaceAll('-', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Truncates a filename in the middle so the extension stays visible.
  static String middleEllipsis(String value, {int max = 34}) {
    if (value.length <= max) {
      return value;
    }
    final int keep = (max - 1) ~/ 2;
    return '${value.substring(0, keep)}…${value.substring(value.length - keep)}';
  }

  /// `12 / 200` plus a 0–1 ratio for a meter.
  static double usageRatio(num? used, num? limit) {
    if (used == null || limit == null || limit <= 0) {
      return 0;
    }
    return (used / limit).clamp(0.0, 1.0).toDouble();
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';
}
