/// Assembles the Material theme from the site's tokens.
///
/// The app is light-only on purpose: BankSheet Pro has no dark mode on the web,
/// and shipping one here would mean two visual languages for the same product.
/// Dark surfaces still appear as *deliberate* hero panels (`stone-950`), which
/// is exactly how the website uses them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

abstract final class AppTheme {
  static ThemeData build() {
    const ColorScheme scheme = ColorScheme.light(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brandTint,
      onPrimaryContainer: AppColors.brandDeep,
      secondary: AppColors.forest,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.surfaceMuted,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.border,
      outlineVariant: AppColors.borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: kFontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      textTheme: const TextTheme(
        displaySmall: AppText.display,
        headlineSmall: AppText.h1,
        titleLarge: AppText.h2,
        titleMedium: AppText.h3,
        bodyLarge: AppText.body,
        bodyMedium: AppText.bodySm,
        bodySmall: AppText.caption,
        labelLarge: AppText.button,
        labelMedium: AppText.label,
        labelSmall: AppText.eyebrow,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.h2,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),

      // The site's card: white, rounded-3xl, hairline stone-200 ring, shadow-sm.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderStrong,
          disabledForegroundColor: AppColors.inkFaint,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: AppText.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: AppText.button,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandDark,
          textStyle: AppText.button,
          minimumSize: const Size(48, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.smallAll,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.inkMuted,
          minimumSize: const Size(44, 44),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: AppText.body.copyWith(color: AppColors.inkFaint),
        labelStyle: AppText.bodySm,
        floatingLabelStyle: AppText.bodySm.copyWith(color: AppColors.brandDark),
        errorStyle: AppText.caption.copyWith(color: AppColors.danger),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.brand, width: 1.6),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.brandTint,
        labelStyle: AppText.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.inkBody,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppText.h3,
        contentTextStyle: AppText.body,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inkStrong,
        contentTextStyle: AppText.bodySm.copyWith(color: AppColors.inkInverse),
        actionTextColor: AppColors.brandLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brandTint,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => AppText.caption.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.brandDeep
                : AppColors.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? AppColors.brandDeep
                : AppColors.inkMuted,
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkMuted,
        textColor: AppColors.ink,
        titleTextStyle: AppText.bodyStrong,
        subtitleTextStyle: AppText.bodySm,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearTrackColor: AppColors.brandTintStrong,
        circularTrackColor: AppColors.brandTintStrong,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? Colors.white : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? AppColors.brand
              : AppColors.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inkStrong,
          borderRadius: AppRadius.smallAll,
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.inkInverse),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
