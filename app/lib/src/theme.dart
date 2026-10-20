import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// AMOLED: every surface is pure #000000; depth comes from edges and glow, not grey fills.
  final bool amoled;
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
    this.amoled = false,
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
    hero: Color(0xFF000000),
    card: Color(0xFF000000),
    line: Color(0xFF1A1A26),
    chip: Color(0xFF000000),
    txt: Color(0xFFE9EDF5),
    sub: Color(0xFF8A93A6),
    ter: Color(0xFF5B6475),
    acc: Color(0xFF7C5CFF),
    acc2: Color(0xFF8B6CFF),
    grn: Color(0xFF22C55E),
    amb: Color(0xFFF5A524),
    red: Color(0xFFFF5C5C),
    sel: Color(0xFF15113A),
    amoled: true,
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

ThemeData materialTheme(Pal p) {
  final b = p.light ? Brightness.light : Brightness.dark;
  var cs = ColorScheme.fromSeed(
    seedColor: p.acc,
    brightness: b,
    surface: p.hero,
  );
  if (p.amoled) {
    const k = Color(0xFF000000);
    cs = cs.copyWith(
      surface: k,
      surfaceDim: k,
      surfaceBright: k,
      surfaceContainerLowest: k,
      surfaceContainerLow: k,
      surfaceContainer: k,
      surfaceContainerHigh: k,
      surfaceContainerHighest: k,
      surfaceTint: Colors.transparent,
    );
  }
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: cs,
    fontFamily: 'Segoe UI',
    focusColor: p.acc.withValues(alpha: .35),
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.hero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: p.amoled ? BorderSide(color: p.line) : BorderSide.none,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.hero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: p.amoled ? BorderSide(color: p.line) : BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: p.bg),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.hero,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.amoled ? const Color(0xFF0B0B12) : null,
    ),
  );
}

/// System bars follow the palette (AMOLED: black status + navigation bar, no scrim).
SystemUiOverlayStyle systemBars(Pal p) => SystemUiOverlayStyle(
  statusBarColor: p.amoled ? const Color(0xFF000000) : Colors.transparent,
  systemNavigationBarColor: p.bg,
  systemNavigationBarDividerColor: p.bg,
  systemNavigationBarContrastEnforced: false,
  statusBarIconBrightness: p.light ? Brightness.dark : Brightness.light,
  statusBarBrightness: p.light ? Brightness.light : Brightness.dark,
  systemNavigationBarIconBrightness: p.light
      ? Brightness.dark
      : Brightness.light,
);

/// Volumetric 3D look on/off (settings «Объёмный 3D-дизайн», ui pref `vol3d`, default on).
/// When off everything is flat: no shadows, no gradients; palette (incl. pure-black AMOLED) unchanged.
bool vol3d = true;
bool vol3dFromUi(Map<String, String> ui) => ui['vol3d'] != '0';

/// Green → amber → red as [left] (0..1 of remaining) runs low.
Color levelColor(Pal p, double left) => left > .5
    ? Color.lerp(p.amb, p.grn, ((left - .5) / .5).clamp(0, 1))!
    : Color.lerp(p.red, p.amb, (left / .5).clamp(0, 1))!;

// ---- Volumetric look: a soft top-left light, raised surfaces and accent glow. ----

/// Top-lit sheen over a surface: a faint highlight that fades out, so cards read as raised.
/// On AMOLED the base stays #000000 at the bottom-right; only the lit edge is lifted.
Gradient raisedGradient(Pal p, Color base) {
  if (!vol3d) return LinearGradient(colors: [base, base]);
  final hi = p.light
      ? Color.alphaBlend(const Color(0x66FFFFFF), base)
      : Color.alphaBlend(
          Colors.white.withValues(alpha: p.amoled ? .045 : .06),
          base,
        );
  final lo = p.light ? Color.alphaBlend(const Color(0x06000000), base) : base;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [hi, base, lo],
    stops: const [0, .55, 1],
  );
}

/// Soft depth shadows. Black shadows vanish on AMOLED, so there a faint accent halo is used.
List<BoxShadow> raisedShadow(Pal p, {double e = 1}) => !vol3d
    ? const []
    : p.light
    ? [
        BoxShadow(
          color: const Color(0x14141A33),
          blurRadius: 18 * e,
          offset: Offset(0, 6 * e),
        ),
        BoxShadow(
          color: const Color(0x0A141A33),
          blurRadius: 3 * e,
          offset: Offset(0, 1 * e),
        ),
      ]
    : p.amoled
    ? [
        BoxShadow(
          color: p.acc.withValues(alpha: .07 * e),
          blurRadius: 18 * e,
          spreadRadius: -2,
        ),
      ]
    : [
        BoxShadow(
          color: const Color(0x73000000),
          blurRadius: 20 * e,
          offset: Offset(0, 8 * e),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: .025),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ];

/// Accent button fill: a lit top over a deeper bottom.
Gradient accentGradient(Pal p) => !vol3d
    ? LinearGradient(colors: [p.acc, p.acc])
    : LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(p.acc2, Colors.white, .12)!,
          p.acc,
          Color.lerp(p.acc, Colors.black, .18)!,
        ],
      );
