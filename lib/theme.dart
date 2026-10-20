import 'package:flutter/material.dart';

/// Palette dell'app (tema scuro).
class AppColors {
  static const bg = Color(0xFF0E0F14);
  static const editorBg = Color(0xFF0A0B0F);
  static const surface = Color(0xFF181A21);
  static const surface2 = Color(0xFF22252E);
  static const line = Color(0xFF2A2D38);
  static const primary = Color(0xFF7C8AFF);
  static const primaryDeep = Color(0xFF5C6BF0);
  static const primarySoft = Color(0x2E7C8AFF);
  static const text = Color(0xFFEEF0F7);
  static const textSoft = Color(0xFFC9CBD8);
  static const muted = Color(0xFF8A8FA3);
  static const danger = Color(0xFFFF6B6B);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6070F5), Color(0xFF3443B8)],
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primaryDeep,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text, fontFamily: 'Inter'),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.surface2,
      thumbColor: Colors.white,
      overlayColor: AppColors.primarySoft,
      trackHeight: 6,
      valueIndicatorColor: AppColors.surface2,
      valueIndicatorTextStyle: TextStyle(color: AppColors.text, fontFamily: 'Inter'),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
  );
}
