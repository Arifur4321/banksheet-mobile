/// Type scale.
///
/// The website loads Outfit at weights 400–800 and renders headings at
/// `text-2xl font-semibold` (24/600), card labels at `text-sm` (14) in
/// `stone-500`, and stat values at `text-xl font-semibold` (20/600). This file
/// is that scale, translated to logical pixels.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The bundled family name. Declared once so a rename only touches this file.
const String kFontFamily = 'Outfit';

/// Named styles used across the app. Prefer these over ad-hoc [TextStyle]s so
/// the whole product scales together when the user changes their text size.
abstract final class AppText {
  static const TextStyle display = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.inkStrong,
  );

  /// Page titles — the site's `text-2xl font-semibold text-stone-900`.
  static const TextStyle h1 = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  /// Card headings — `text-lg font-semibold`.
  static const TextStyle h2 = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static const TextStyle body = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.inkBody,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// The site's `text-sm text-stone-500` used on every stat card.
  static const TextStyle bodySm = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.inkMuted,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.inkMuted,
  );

  /// `text-xs font-semibold uppercase tracking-[0.2em]` — the eyebrow the site
  /// puts above every hero card.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    color: AppColors.inkMuted,
  );

  static const TextStyle label = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.7,
    color: AppColors.inkMuted,
  );

  static const TextStyle button = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Money, counts and balances. Tabular figures stop columns from jittering
  /// as values change during polling.
  static const TextStyle numeric = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The big number on a stat card — `text-xl font-semibold tabular-nums`.
  static const TextStyle statValue = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.ink,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
