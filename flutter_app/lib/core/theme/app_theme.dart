import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Extra colour tokens the Material scheme doesn't cover (mirrors the web portal's CSS tokens).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.primary,
    required this.primarySoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final Color background, surface, surfaceMuted, border, foreground, muted;
  final Color primary, primarySoft, success, successSoft, warning, warningSoft, danger, dangerSoft;

  static const light = AppPalette(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    foreground: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    primary: Color(0xFF2563EB),
    primarySoft: Color(0xFFEFF6FF),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFECFDF3),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFF7ED),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEF2F2),
  );

  static const dark = AppPalette(
    background: Color(0xFF0B0F17),
    surface: Color(0xFF111827),
    surfaceMuted: Color(0xFF1F2937),
    border: Color(0xFF273244),
    foreground: Color(0xFFE5E7EB),
    muted: Color(0xFF94A3B8),
    primary: Color(0xFF3B82F6),
    primarySoft: Color(0xFF172554),
    success: Color(0xFF22C55E),
    successSoft: Color(0xFF0F2A1A),
    warning: Color(0xFFF59E0B),
    warningSoft: Color(0xFF2E1F06),
    danger: Color(0xFFEF4444),
    dangerSoft: Color(0xFF3B1212),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      border: l(border, other.border),
      foreground: l(foreground, other.foreground),
      muted: l(muted, other.muted),
      primary: l(primary, other.primary),
      primarySoft: l(primarySoft, other.primarySoft),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
    );
  }
}

extension AppThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  static const fontFamily = 'Inter';

  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primary,
      onPrimary: Colors.white,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.primary,
      secondary: p.primary,
      onSecondary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.foreground,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.border,
      outlineVariant: p.border,
    );

    // Fixed type scale: page title 24/600, section 16/600, body 14, caption 12.
    final text = TextTheme(
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.3, color: p.foreground),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.2, color: p.foreground),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35, color: p.foreground),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: p.foreground),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45, color: p.foreground),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: p.foreground),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4, color: p.muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2, color: p.foreground),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2, color: p.muted),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.6, color: p.muted),
      displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.5, color: p.foreground),
    ).apply(fontFamily: fontFamily);

    final inputBorder = OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: p.border));

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        shape: Border(bottom: BorderSide(color: p.border)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardAll, side: BorderSide(color: p.border)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.primary, width: 1.6)),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.danger)),
        labelStyle: TextStyle(color: p.muted, fontSize: 14),
        hintStyle: TextStyle(color: p.muted, fontSize: 14),
        prefixIconColor: p.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.inputAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          foregroundColor: p.foreground,
          side: BorderSide(color: p.border),
          shape: const RoundedRectangleBorder(borderRadius: Radii.inputAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          shape: const RoundedRectangleBorder(borderRadius: Radii.inputAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.primarySoft,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w500, color: p.foreground),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? p.primary : p.muted,
            )),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? p.primary : p.muted),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.inputAll),
        backgroundColor: b == Brightness.dark ? p.surfaceMuted : p.foreground,
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, color: b == Brightness.dark ? p.foreground : Colors.white),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: p.primarySoft,
          selectedForegroundColor: p.primary,
          side: BorderSide(color: p.border),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w600),
          visualDensity: VisualDensity.compact,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.muted,
        indicatorColor: p.primary,
        dividerColor: p.border,
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
        titleTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodySmall,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
