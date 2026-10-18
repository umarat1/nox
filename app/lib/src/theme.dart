import 'package:flutter/material.dart';

/// Android Nox palettes: AMOLED (black), dark, light — same keys as Android (Theme.KEYS).
class Pal {
  final Color bg,
      hero,
      card,
      line,
      chip,
      txt,
      sub,
      ter,
      acc,
      acc2,
      grn,
      amb,
      red,
      sel;
  final bool light;
  const Pal({
    required this.bg,
    required this.hero,
    required this.card,
    required this.line,
    required this.chip,
    required this.txt,
    required this.sub,
    required this.ter,
    required this.acc,
    required this.acc2,
    required this.grn,
    required this.amb,
    required this.red,
    required this.sel,
    this.light = false,
  });

  /// Ping text: white on dark/AMOLED, normal ink on light (white would be unreadable there).
  Color get pingFg => light ? txt : Colors.white;
  Color get pingBg => light ? const Color(0x0F15171C) : const Color(0x14FFFFFF);

  static const dark = Pal(
    bg: Color(0xFF0D1020),
    hero: Color(0xFF181C3A),
    card: Color(0xFF1A1E3D),
    line: Color(0xFF2A3060),
    chip: Color(0xFF22274A),
    txt: Color(0xFFE9EDF5),
    sub: Color(0xFF8A93A6),
    ter: Color(0xFF5B6475),
    acc: Color(0xFF7C5CFF),
    acc2: Color(0xFF8B6CFF),
    grn: Color(0xFF22C55E),
    amb: Color(0xFFF5A524),
    red: Color(0xFFFF5C5C),
    sel: Color(0xFF2A2366),
  );
  static const black = Pal(
    bg: Color(0xFF000000),
    hero: Color(0xFF0A0A10),
    card: Color(0xFF0C0C13),
    line: Color(0xFF1D1D2B),
    chip: Color(0xFF16161F),
    txt: Color(0xFFE9EDF5),
    sub: Color(0xFF8A93A6),
    ter: Color(0xFF5B6475),
    acc: Color(0xFF7C5CFF),
    acc2: Color(0xFF8B6CFF),
    grn: Color(0xFF22C55E),
    amb: Color(0xFFF5A524),
    red: Color(0xFFFF5C5C),
    sel: Color(0xFF1E1948),
  );
  static const lightP = Pal(
    bg: Color(0xFFF3F4F7),
    hero: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE3E5EA),
    chip: Color(0xFFF0F1F4),
    txt: Color(0xFF15171C),
    sub: Color(0xFF5E6470),
    ter: Color(0xFF8A90A0),
    acc: Color(0xFF6C4CF1),
    acc2: Color(0xFF6C4CF1),
    grn: Color(0xFF1F9D55),
    amb: Color(0xFFB7791F),
    red: Color(0xFFD33A3A),
    sel: Color(0xFFECE8FD),
    light: true,
  );

  static Pal of(String? key) => switch (key) {
    'black' => black,
    'light' => lightP,
    _ => dark,
  };
}

const themeNames = [
  ('black', 'AMOLED (чёрная)'),
  ('dark', 'Тёмная'),
  ('light', 'Светлая'),
];
String themeName(String? k) =>
    themeNames.firstWhere((e) => e.$1 == k, orElse: () => themeNames[1]).$2;

ThemeData materialTheme(Pal p) => ThemeData(
  brightness: p.light ? Brightness.light : Brightness.dark,
  scaffoldBackgroundColor: p.bg,
  colorScheme: ColorScheme.fromSeed(
    seedColor: p.acc,
    brightness: p.light ? Brightness.light : Brightness.dark,
    surface: p.hero,
  ),
  fontFamily: 'Segoe UI',
  focusColor: p.acc.withValues(alpha: .35),
  useMaterial3: true,
);
