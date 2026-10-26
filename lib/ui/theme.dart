import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFF110F16);
  static const surface = Color(0xFF1D1A24);
  static const surface2 = Color(0xFF27242F);
  static const surface3 = Color(0xFF322E3B);
  static const stroke = Color(0xFF34303F);
  static const lime = Color(0xFFA48BF4); // акцент: фиолетовый (чуть темнее сиреневого)
  static const limeDim = Color(0xFF6E5BB0);
  static const onLime = Color(0xFF16112A);
  static const text = Color(0xFFF4F4F4);
  static const muted = Color(0xFF8E89A0);
  static const faint = Color(0xFF4A4558);
  static const red = Color(0xFFFF6B7A);
  static const glass = Color(0x14FFFFFF); // полупрозрачная заливка строк на стекле
  static const glass2 = Color(0x0CFFFFFF);
  static const win = Color(0xFF7EE0A1); // победа на графиках/плашках
  static const glow = Color(0xFF3B2D6B); // фиолетовое свечение сверху
  static const gold = Color(0xFFFFC94D);
  static const silver = Color(0xFFC9D1D9);
  static const bronze = Color(0xFFE09A5B);
  static const radiant = Color(0xFF7BD389);
  static const dire = Color(0xFFFF7A6B);

  /// Цвета игроков на графиках.
  static const series = [
    Color(0xFFA48BF4),
    Color(0xFF6FD3FF),
    Color(0xFFFF8A65),
    Color(0xFFB39DFF),
    Color(0xFFFFD54F),
    Color(0xFF4DD0A1),
    Color(0xFFFF6FAE),
    Color(0xFF9FB4C7),
  ];
  static Color seriesOf(int i) => series[i % series.length];
}

const double rCard = 28;
const double rInner = 16;

/// В тестах шрифт подгружается из файла, без сети.
String? testFontFamily;

TextStyle _base() {
  if (testFontFamily != null) return TextStyle(fontFamily: testFontFamily);
  try {
    return GoogleFonts.manrope();
  } catch (_) {
    return const TextStyle();
  }
}

class T {
  static TextStyle get base => _base().copyWith(color: C.text);
  static TextStyle h1 = base.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.5);
  static TextStyle display = base.copyWith(fontSize: 46, fontWeight: FontWeight.w600, height: 1.0, letterSpacing: -1.5);
  static TextStyle big = base.copyWith(fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.5);
  static TextStyle title = base.copyWith(fontSize: 17, fontWeight: FontWeight.w600);
  static TextStyle sub = base.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle body = base.copyWith(fontSize: 14, fontWeight: FontWeight.w500);
  static TextStyle small = base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: C.muted);
  static TextStyle tiny = base.copyWith(fontSize: 10.5, fontWeight: FontWeight.w600, color: C.muted);
  static TextStyle limeS = base.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: C.lime);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  String? family = testFontFamily;
  if (family == null) {
    try {
      family = GoogleFonts.manrope().fontFamily;
    } catch (_) {}
  }
  final tt = base.textTheme.apply(fontFamily: family);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.lime,
      onPrimary: C.onLime,
      secondary: C.lime,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
    textTheme: tt.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0, scrolledUnderElevation: 0),
    dividerColor: C.stroke,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x12FFFFFF),
      hintStyle: const TextStyle(color: C.muted),
      labelStyle: const TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(rInner), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rInner), borderSide: const BorderSide(color: Color(0x1FFFFFFF))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rInner), borderSide: const BorderSide(color: C.lime)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.onLime : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.lime : C.surface3),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.surface3,
      contentTextStyle: const TextStyle(color: C.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rInner)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rCard)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rCard))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.lime),
  );
}
