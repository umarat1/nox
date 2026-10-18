String fmtBytes(num b) {
  const u = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var i = 0;
  var v = b.toDouble();
  while (v >= 1024 && i < 4) {
    v /= 1024;
    i++;
  }
  return '${i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v < 10 ? 1 : 0)} ${u[i]}';
}

String plural(int n, String one, String few, String many) {
  final m100 = n.abs() % 100, m = m100 % 10;
  if (m100 > 10 && m100 < 20) return many;
  if (m == 1) return one;
  if (m > 1 && m < 5) return few;
  return many;
}

String ago(int t) {
  if (t == 0) return 'не обновлялась';
  final d = DateTime.now().millisecondsSinceEpoch ~/ 1000 - t;
  if (d < 60) return 'только что';
  if (d < 3600) return '${d ~/ 60} мин назад';
  if (d < 86400) return '${d ~/ 3600} ч назад';
  return fmtDate(t);
}

String fmtDate(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String fmtDur(int s) {
  if (s < 0) s = 0;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(x)}' : '${two(m)}:${two(x)}';
}

/// Monochrome ping (Murad, 0.8.1): the state is text only, never colour.
String pingText(int? p) {
  if (p == null || p == 0) return '—';
  if (p == -1) return 'таймаут';
  if (p == -2) return 'UDP';
  return '$p мс';
}
