/// Design tokens lifted verbatim from the BankSheet Pro website so the app and
/// the site read as one product.
///
/// Sources in the Laravel repo:
///   * `tailwind.config.js`            — font family
///   * `resources/css/app.css`         — the landing palette and the 3D scene
///   * `resources/views/layouts/app.blade.php` — the authenticated shell
///     (`bg-stone-100`, white cards, `border-stone-200`, emerald active state)
///   * `resources/views/dashboard.blade.php`   — `rounded-3xl` cards,
///     `shadow-sm`, `ring-1 ring-stone-200`, `stone-950` hero panels
///
/// Every value below is the exact hex Tailwind emits for the class the site
/// uses. Do not "improve" these — drift here is drift between the two clients.
library;

import 'package:flutter/widgets.dart';

/// Flat colour constants. Grouped rather than themed so a widget can reach for
/// a specific brand colour (a chart series, a 3D layer) without going through
/// [ColorScheme], which only carries a handful of slots.
abstract final class AppColors {
  // ---------------------------------------------------------------- surfaces
  /// `bg-stone-100` — the app canvas behind every scrollable.
  static const Color canvas = Color(0xFFF5F5F4);

  /// Cards, sheets, app bars.
  static const Color surface = Color(0xFFFFFFFF);

  /// `stone-50` — subtle fills inside a card (table stripes, inert chips).
  static const Color surfaceMuted = Color(0xFFFAFAF9);

  /// `stone-200` — the hairline ring every card carries on the site.
  static const Color border = Color(0xFFE7E5E4);

  /// `stone-300` — inputs and secondary buttons.
  static const Color borderStrong = Color(0xFFD6D3D1);

  // ------------------------------------------------------------------- text
  /// `stone-900` — body headings.
  static const Color ink = Color(0xFF1C1917);

  /// `stone-950` — display headings and the dark hero panels.
  static const Color inkStrong = Color(0xFF0C0A09);

  /// `stone-700` — long-form body copy.
  static const Color inkBody = Color(0xFF44403C);

  /// `stone-500` — labels and secondary copy.
  static const Color inkMuted = Color(0xFF78716C);

  /// `stone-400` — timestamps, disabled text.
  static const Color inkFaint = Color(0xFFA8A29E);

  /// Text on dark panels.
  static const Color inkInverse = Color(0xFFFAFAF9);

  // ------------------------------------------------------------------ brand
  /// `emerald-600` — primary action.
  static const Color brand = Color(0xFF059669);

  /// `emerald-700`.
  static const Color brandDark = Color(0xFF047857);

  /// `emerald-800` — text on `brandTint`.
  static const Color brandDeep = Color(0xFF065F46);

  /// `emerald-50` — the active navigation row on the site.
  static const Color brandTint = Color(0xFFECFDF5);

  /// `emerald-100` — the inset ring on that active row.
  static const Color brandTintStrong = Color(0xFFD1FAE5);

  /// `emerald-300` — accents on dark panels.
  static const Color brandLight = Color(0xFF6EE7B7);

  // ------------------------------------------- landing palette (3D scenes)
  /// The site's `<meta name="theme-color">` and `--landing-ink`.
  static const Color forest = Color(0xFF102820);
  static const Color forestSoft = Color(0xFF1F4036);
  static const Color jade = Color(0xFF1F7A5A);
  static const Color jadeBright = Color(0xFF43C68B);
  static const Color mint = Color(0xFFDFF5E9);
  static const Color paper = Color(0xFFF7F5EF);
  static const Color paperWhite = Color(0xFFFFFEFA);
  static const Color sand = Color(0xFFEFE9DC);

  // --------------------------------------------------------------- feedback
  static const Color amber = Color(0xFFEAB95F);
  static const Color warn = Color(0xFFB45309);
  static const Color warnTint = Color(0xFFFFFBEB);
  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerTint = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoTint = Color(0xFFEFF6FF);
  static const Color success = Color(0xFF047857);
  static const Color successTint = Color(0xFFECFDF5);
}

/// Corner radii. The site uses exactly three, and mixing in a fourth is the
/// fastest way to make the app stop looking like the site.
abstract final class AppRadius {
  /// `rounded-3xl` — cards, sheets, hero panels.
  static const double card = 24;

  /// `rounded-2xl` — buttons, inputs, chips, avatars.
  static const double control = 16;

  /// `rounded-xl` — nav rows, small icon buttons, list tiles.
  static const double small = 12;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlAll =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));

  /// Bottom sheets are rounded on top only.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(28),
  );
}

/// The 4px spacing rhythm the site's Tailwind scale produces.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double page = 20;
}

/// Shadow recipes.
///
/// The site pairs a barely-there `shadow-sm` on flat cards with genuinely deep
/// shadows on the landing 3D scenes (`0 30px 85px rgba(5,22,17,.28)`). Both
/// ends of that range are reproduced so a lifted 3D layer reads as lifted.
abstract final class AppShadows {
  /// Resting card. Matches `shadow-sm` + `ring-1 ring-stone-200`.
  static const List<BoxShadow> soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F0C0A09),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// Pressed / dragged card, and the middle plane of a 3D scene.
  static const List<BoxShadow> lifted = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A0C0A09),
      blurRadius: 34,
      offset: Offset(0, 14),
    ),
  ];

  /// Front plane of a 3D scene. Mirrors `.landing-converter-card`.
  static const List<BoxShadow> deep = <BoxShadow>[
    BoxShadow(
      color: Color(0x33051611),
      blurRadius: 60,
      offset: Offset(0, 26),
    ),
  ];
}

/// Motion constants. The website's e-sign scene runs on a single 7 s timeline
/// (`--bs-cycle: 7s`) with a 9 s float; both are reused so the two products
/// move at the same tempo.
abstract final class AppMotion {
  static const Duration sceneCycle = Duration(seconds: 7);
  static const Duration sceneFloat = Duration(seconds: 9);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  /// `cubic-bezier(0.22, 1, 0.36, 1)` — the tilt easing used by `.bs-esign__stage`.
  static const Cubic tilt = Cubic(0.22, 1, 0.36, 1);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}
