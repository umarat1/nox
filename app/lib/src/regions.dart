/// Country detection for chips and flags (same table as the Android app / PC 0.8).
const _rg = <List<String>>[
  ['RU', 'Россия', 'russia', 'рф'],
  ['BY', 'Беларусь', 'belarus', 'белоруссия'],
  ['UA', 'Украина', 'ukraine'],
  ['KZ', 'Казахстан', 'kazakhstan'],
  ['DE', 'Германия', 'germany'],
  ['NL', 'Нидерланды', 'netherlands', 'голландия'],
  ['FR', 'Франция', 'france'],
  [
    'GB',
    'Британия',
    'united kingdom',
    'uk',
    'великобритания',
    'england',
    'англия',
    'лондон',
    'london',
  ],
  ['US', 'США', 'usa', 'united states', 'america'],
  ['CA', 'Канада', 'canada'],
  ['FI', 'Финляндия', 'finland'],
  ['SE', 'Швеция', 'sweden'],
  ['NO', 'Норвегия', 'norway'],
  ['PL', 'Польша', 'poland'],
  ['LV', 'Латвия', 'latvia'],
  ['LT', 'Литва', 'lithuania'],
  ['EE', 'Эстония', 'estonia'],
  ['TR', 'Турция', 'turkey', 'türkiye'],
  ['AL', 'Албания', 'albania'],
  ['AM', 'Армения', 'armenia'],
  ['GE', 'Грузия', 'georgia'],
  ['AZ', 'Азербайджан', 'azerbaijan'],
  ['CH', 'Швейцария', 'switzerland'],
  ['AT', 'Австрия', 'austria'],
  ['CZ', 'Чехия', 'czech', 'czechia'],
  ['IT', 'Италия', 'italy'],
  ['ES', 'Испания', 'spain'],
  ['PT', 'Португалия', 'portugal'],
  ['RO', 'Румыния', 'romania'],
  ['BG', 'Болгария', 'bulgaria'],
  ['RS', 'Сербия', 'serbia'],
  ['MD', 'Молдова', 'moldova'],
  ['HU', 'Венгрия', 'hungary'],
  ['IL', 'Израиль', 'israel'],
  ['AE', 'ОАЭ', 'uae', 'emirates'],
  ['JP', 'Япония', 'japan'],
  ['SG', 'Сингапур', 'singapore'],
  ['HK', 'Гонконг', 'hong kong'],
  ['IN', 'Индия', 'india'],
  ['CN', 'Китай', 'china'],
  ['KR', 'Корея', 'korea'],
  ['UZ', 'Узбекистан', 'uzbekistan'],
  ['KG', 'Киргизия', 'kyrgyzstan'],
  ['CY', 'Кипр', 'cyprus'],
  ['GR', 'Греция', 'greece'],
  ['IE', 'Ирландия', 'ireland'],
  ['DK', 'Дания', 'denmark'],
  ['BE', 'Бельгия', 'belgium'],
  ['LU', 'Люксембург', 'luxembourg'],
  ['IS', 'Исландия', 'iceland'],
  ['BR', 'Бразилия', 'brazil'],
  ['AU', 'Австралия', 'australia'],
];

final Map<String, String> regionName = {for (final r in _rg) r[0]: r[1]};
final List<(String, String)> _byName = [
  for (final r in _rg)
    for (final n in r.sublist(1)) (n.toLowerCase(), r[0]),
];
const _flagSvgs = {
  'ae',
  'al',
  'am',
  'at',
  'au',
  'az',
  'be',
  'bg',
  'br',
  'by',
  'ca',
  'ch',
  'cn',
  'cy',
  'cz',
  'de',
  'dk',
  'ee',
  'es',
  'fi',
  'fr',
  'gb',
  'ge',
  'gr',
  'hk',
  'hu',
  'ie',
  'il',
  'in',
  'is',
  'it',
  'jp',
  'kg',
  'kr',
  'kz',
  'lt',
  'lu',
  'lv',
  'md',
  'nl',
  'no',
  'pl',
  'pt',
  'ro',
  'rs',
  'ru',
  'se',
  'sg',
  'tr',
  'ua',
  'us',
  'uz',
};
bool hasFlag(String iso) => _flagSvgs.contains(iso.toLowerCase());

/// ISO code from a flag emoji or a leading country name; null if unknown.
String? region(String name) {
  final cp = name.runes.toList();
  for (var i = 0; i + 1 < cp.length; i++) {
    final a = cp[i], b = cp[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      return String.fromCharCodes([65 + a - 0x1F1E6, 65 + b - 0x1F1E6]);
    }
  }
  final t = name
      .replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), '')
      .toLowerCase();
  for (final (k, iso) in _byName) {
    if (t.startsWith(k) &&
        (t.length == k.length ||
            !RegExp(r'\p{L}', unicode: true).hasMatch(t[k.length]))) {
      return iso;
    }
  }
  return null;
}

/// Name without the leading flag emoji.
String dispName(String n) {
  final s = n
      .replaceFirst(RegExp(r'^[\s\u{1F1E6}-\u{1F1FF}]+', unicode: true), '')
      .trim();
  return s.isEmpty ? n : s;
}

/// ISO code for a single word/alias («лондон» → GB); null if unknown.
String? aliasIso(String word) {
  final w = word.toLowerCase();
  for (final (k, iso) in _byName) {
    if (k == w) return iso;
  }
  return null;
}

/// Country named anywhere in [name] as a whole word («qWDTT Турция 2» → TR); null if none.
String? regionAnywhere(String name) {
  final t =
      ' ${name.toLowerCase().replaceAll(RegExp(r'[^\p{L}]+', unicode: true), ' ')} ';
  for (final (k, iso) in _byName) {
    if (k.length >= 3 && t.contains(' $k ')) return iso;
  }
  return null;
}

/// Name inside a country card: no flag, no leading country word
/// («🇹🇷 Турция vless tcp tls 443» → «vless tcp tls 443»); unchanged if nothing is left.
String shortName(String n) {
  final d = dispName(n);
  final m = RegExp(r'^(\p{L}+)[\s·|,:\-–—]+', unicode: true).firstMatch(d);
  if (m == null || aliasIso(m.group(1)!) == null) return d;
  final r = d.substring(m.end).trim();
  return r.isEmpty ? d : r;
}
