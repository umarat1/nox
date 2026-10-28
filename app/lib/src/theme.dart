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

  /// Monochrome: black/white/greys only, country flags replaced by letter badges.
  final bool mono;
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
    this.mono = false,
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

  static const monoP = Pal(
    bg: Color(0xFF0A0A0B),
    hero: Color(0xFF141415),
    card: Color(0xFF161617),
    line: Color(0xFF2E2E31),
    chip: Color(0xFF1F1F21),
    txt: Color(0xFFF2F2F2),
    sub: Color(0xFF9C9CA0),
    ter: Color(0xFF68686C),
    acc: Color(0xFF8E8E93),
    acc2: Color(0xFFD8D8DA),
    grn: Color(0xFFEDEDED),
    amb: Color(0xFFB4B4B8),
    red: Color(0xFF8A8A8E),
    sel: Color(0xFF2B2B2E),
    mono: true,
  );

  static const monoBlack = Pal(
    bg: Color(0xFF000000),
    hero: Color(0xFF000000),
    card: Color(0xFF000000),
    line: Color(0xFF242426),
    chip: Color(0xFF000000),
    txt: Color(0xFFF2F2F2),
    sub: Color(0xFF9C9CA0),
    ter: Color(0xFF68686C),
    acc: Color(0xFF8E8E93),
    acc2: Color(0xFFD8D8DA),
    grn: Color(0xFFEDEDED),
    amb: Color(0xFFB4B4B8),
    red: Color(0xFF8A8A8E),
    sel: Color(0xFF1C1C1E),
    amoled: true,
    mono: true,
  );
  static const monoLight = Pal(
    bg: Color(0xFFF2F2F3),
    hero: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE0E0E2),
    chip: Color(0xFFEFEFF0),
    txt: Color(0xFF121212),
    sub: Color(0xFF5E5E62),
    ter: Color(0xFF8C8C90),
    acc: Color(0xFF3A3A3C),
    acc2: Color(0xFF1F1F21),
    grn: Color(0xFF2A2A2C),
    amb: Color(0xFF6B6B6E),
    red: Color(0xFF4A4A4C),
    sel: Color(0xFFE6E6E8),
    light: true,
    mono: true,
  );

  Pal copyWith({
    Color? bg,
    Color? hero,
    Color? card,
    Color? line,
    Color? chip,
    Color? acc,
    Color? acc2,
    Color? sel,
  }) => Pal(
    bg: bg ?? this.bg,
    hero: hero ?? this.hero,
    card: card ?? this.card,
    line: line ?? this.line,
    chip: chip ?? this.chip,
    txt: txt,
    sub: sub,
    ter: ter,
    acc: acc ?? this.acc,
    acc2: acc2 ?? this.acc2,
    grn: grn,
    amb: amb,
    red: red,
    sel: sel ?? this.sel,
    light: light,
    amoled: amoled,
    mono: mono,
  );

  /// [key] = base theme (black/dark/light), [tpl] = design template (glass/ocean/…/mono).
  static Pal of(String? key, [String? tpl]) {
    if (key == 'mono') return of('dark', 'mono'); // pre-release 2.1.4 builds
    final base = switch (key) {
      'black' => black,
      'light' => lightP,
      _ => dark,
    };
    final t = templateOf(tpl);
    if (t.key == 'mono') {
      return base.light ? monoLight : (base.amoled ? monoBlack : monoP);
    }
    if (t.key == 'glass') return base;
    if (base.light)
      return base.copyWith(acc: t.lAcc, acc2: t.lAcc2, sel: t.lSel);
    if (base.amoled)
      return base.copyWith(acc: t.acc, acc2: t.acc2, sel: t.oSel);
    return base.copyWith(
      bg: t.bg,
      hero: t.hero,
      card: t.card,
      line: t.line,
      chip: t.chip,
      acc: t.acc,
      acc2: t.acc2,
      sel: t.sel,
    );
  }
}

/// Design template: accent pair + tinted dark surfaces; light/AMOLED bases take the accents only.
class Tpl {
  final String key, name;
  final Color acc,
      acc2,
      bg,
      hero,
      card,
      line,
      chip,
      sel,
      oSel,
      lAcc,
      lAcc2,
      lSel;
  const Tpl(
    this.key,
    this.name, {
    required this.acc,
    required this.acc2,
    required this.bg,
    required this.hero,
    required this.card,
    required this.line,
    required this.chip,
    required this.sel,
    required this.oSel,
    required this.lAcc,
    required this.lAcc2,
    required this.lSel,
  });
}

const templates = <Tpl>[
  Tpl(
    'glass',
    'Стекло',
    acc: Color(0xFF7C5CFF),
    acc2: Color(0xFF8B6CFF),
    bg: Color(0xFF0D1020),
    hero: Color(0xFF181C3A),
    card: Color(0xFF1A1E3D),
    line: Color(0xFF2A3060),
    chip: Color(0xFF22274A),
    sel: Color(0xFF2A2366),
    oSel: Color(0xFF15113A),
    lAcc: Color(0xFF6C4CF1),
    lAcc2: Color(0xFF6C4CF1),
    lSel: Color(0xFFECE8FD),
  ),
  Tpl(
    'ocean',
    'Океан',
    acc: Color(0xFF0EA5E9),
    acc2: Color(0xFF22D3EE),
    bg: Color(0xFF08121E),
    hero: Color(0xFF0F1D30),
    card: Color(0xFF102236),
    line: Color(0xFF1E3B57),
    chip: Color(0xFF162C45),
    sel: Color(0xFF0C3550),
    oSel: Color(0xFF06222F),
    lAcc: Color(0xFF0284C7),
    lAcc2: Color(0xFF0891B2),
    lSel: Color(0xFFE0F2FE),
  ),
  Tpl(
    'emerald',
    'Изумруд',
    acc: Color(0xFF10B981),
    acc2: Color(0xFF34D399),
    bg: Color(0xFF07120E),
    hero: Color(0xFF0E1F18),
    card: Color(0xFF0F221A),
    line: Color(0xFF1E3D30),
    chip: Color(0xFF152C22),
    sel: Color(0xFF0D3B2B),
    oSel: Color(0xFF062419),
    lAcc: Color(0xFF059669),
    lAcc2: Color(0xFF047857),
    lSel: Color(0xFFD1FAE5),
  ),
  Tpl(
    'sunset',
    'Закат',
    acc: Color(0xFFF97316),
    acc2: Color(0xFFF472B6),
    bg: Color(0xFF140B12),
    hero: Color(0xFF22121E),
    card: Color(0xFF24131F),
    line: Color(0xFF40213A),
    chip: Color(0xFF2D1828),
    sel: Color(0xFF4A1D35),
    oSel: Color(0xFF2A0E1C),
    lAcc: Color(0xFFEA580C),
    lAcc2: Color(0xFFDB2777),
    lSel: Color(0xFFFFEDD5),
  ),
  Tpl(
    'mono',
    'Монохром',
    acc: Color(0xFF8E8E93),
    acc2: Color(0xFFD8D8DA),
    bg: Color(0xFF0A0A0B),
    hero: Color(0xFF141415),
    card: Color(0xFF161617),
    line: Color(0xFF2E2E31),
    chip: Color(0xFF1F1F21),
    sel: Color(0xFF2B2B2E),
    oSel: Color(0xFF1C1C1E),
    lAcc: Color(0xFF3A3A3C),
    lAcc2: Color(0xFF1F1F21),
    lSel: Color(0xFFE6E6E8),
  ),
];

Tpl templateOf(String? k) =>
    templates.firstWhere((t) => t.key == k, orElse: () => templates[0]);

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
    dynamicSchemeVariant: p.mono
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
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
        side: p.amoled || vol3d
            ? BorderSide(color: vol3d ? p.acc.withValues(alpha: .35) : p.line)
            : BorderSide.none,
      ),
      elevation: vol3d ? 12 : 0,
      shadowColor: vol3d ? p.acc.withValues(alpha: .35) : null,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.hero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: p.amoled || vol3d
            ? BorderSide(color: vol3d ? p.acc.withValues(alpha: .35) : p.line)
            : BorderSide.none,
      ),
      elevation: vol3d ? 16 : 0,
      shadowColor: vol3d ? p.acc.withValues(alpha: .35) : null,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: p.bg),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.bg,
      elevation: vol3d ? 16 : 0,
      shadowColor: vol3d ? p.acc.withValues(alpha: .3) : null,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.hero,
      surfaceTintColor: Colors.transparent,
      elevation: vol3d ? 12 : 2,
      shadowColor: vol3d ? p.acc.withValues(alpha: .4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: vol3d ? p.acc.withValues(alpha: .3) : p.line),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.hero),
        elevation: WidgetStatePropertyAll(vol3d ? 12 : 2),
        shadowColor: WidgetStatePropertyAll(
          vol3d ? p.acc.withValues(alpha: .4) : null,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: vol3d ? p.acc.withValues(alpha: .3) : p.line,
            ),
          ),
        ),
      ),
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

/// Speed graph style: '' classic, 'smooth', 'matrix' (settings.ui['graph']).
String graphStyle = '';
String graphFromUi(Map<String, String> ui) => ui['graph'] ?? '';
const graphStyles = [
  ('', 'Классический'),
  ('smooth', 'Плавный'),
  ('matrix', 'Матрица'),
];

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
