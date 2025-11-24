import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _primary = Color(0xFF6B73FF);
  static const _gradA = Color(0xFF667EEA);
  static const _gradB = Color(0xFF764BA2);
  static const _gradC = Color(0xFF6B73FF);

  static LinearGradient get primaryGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_gradA, _gradB, _gradC],
    stops: [0, .5, 1],
  );

  static ThemeData _base(Brightness b) {
    final isDark = b == Brightness.dark;
    final cs = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: b,
      primary: _primary,
    );

    final text = GoogleFonts.interTextTheme().apply(
      bodyColor: isDark ? const Color(0xFFE7E9F0) : const Color(0xFF1C1F25),
      displayColor: isDark ? const Color(0xFFF2F4F8) : const Color(0xFF0E1116),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF6F7FB),
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.25),
      ),
      appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
      // ✅ Use CardThemeData (not CardTheme) for your Flutter version
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF141821) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        surfaceTintColor: Colors.transparent, // remove M3 overlay tint
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isDark ? const Color(0xFF161B24) : Colors.white,
        iconColor: cs.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161B24) : Colors.white,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(fontSize: 12),
        side: BorderSide(color: Colors.white.withOpacity(.35)),
        backgroundColor: Colors.white.withOpacity(.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);
}
