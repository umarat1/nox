// «Принять с телефона» (receiver, usually the TV) and «Передать на ТВ» (sender, the phone):
// profiles over the local network. Transport and crypto live in the engine (go/engine/pair.go);
// these screens only drive PairStart / PairStatus / PairStop / PairSend.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import 'api.dart';
import 'controller.dart';
import 'fmt.dart';
import 'platform.dart';
import 'theme.dart';

Future<void> openReceive(BuildContext context, NoxController c) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => PairReceivePage(c: c)));

Future<void> openSend(BuildContext context, NoxController c, {String? uri}) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PairSendPage(c: c, uri: uri),
      ),
    );

Pal _pal(NoxController c) => Pal.of(c.settings['theme'] as String?);

// ------------------------------------------------------------------ shared bits

/// Flat page frame: back button, title, theme of the app.
class _Frame extends StatelessWidget {
  final NoxController c;
  final String title;
  final Widget child;
  const _Frame({required this.c, required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = _pal(c);
    return Theme(
      data: materialTheme(p),
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Назад',
                      icon: Icon(Icons.arrow_back, color: p.txt),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.txt,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button with a visible D-pad focus ring (TV).
class PairBtn extends StatefulWidget {
  final Pal p;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, autofocus;
  const PairBtn({
    super.key,
    required this.p,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = false,
    this.autofocus = false,
  });
  @override
  State<PairBtn> createState() => _PairBtnState();
}

class _PairBtnState extends State<PairBtn> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final on = widget.onTap != null;
    final fg = widget.primary ? Colors.white : p.txt;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _f ? p.acc2 : Colors.transparent, width: 2),
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: widget.primary
            ? (on ? p.acc : p.acc.withValues(alpha: .4))
            : p.chip,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(13),
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => _f = v),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// QR from the pure-Dart `qr` package, drawn dark-on-white with a quiet zone.
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView({super.key, required this.data, required this.size});
  @override
  Widget build(BuildContext context) {
    final img = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return Semantics(
      label: 'QR-код для телефона',
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .06),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: CustomPaint(painter: _QrPainter(img)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage img;
  _QrPainter(this.img);
  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final m = size.shortestSide / n;
    final paint = Paint()..color = const Color(0xFF0D1020);
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) {
          // tiny overlap avoids hairlines between modules on fractional scales
          path.addRect(Rect.fromLTWH(x * m, y * m, m + .4, m + .4));
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter o) => o.img != img;
}

// ------------------------------------------------------------------ receiver

class PairReceivePage extends StatefulWidget {
  final NoxController c;
  const PairReceivePage({super.key, required this.c});
  @override
  State<PairReceivePage> createState() => _PairReceivePageState();
}

class _PairReceivePageState extends State<PairReceivePage> {
  J? info;
  String? err;
  Timer? _t;
  bool _starting = true;

  NoxController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _start();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    if (info?['result'] == null) c.api.call('PairStop').catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      err = null;
    });
    try {
      final r = await c.api.call('PairStart');
      if (!mounted) return;
      setState(() => info = (r as Map).cast<String, dynamic>());
    } on NoxError catch (e) {
      if (mounted) setState(() => err = e.message);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _poll() async {
    if (_starting || info == null || info!['active'] != true) {
      if (mounted) setState(() {}); // countdown
      return;
    }
    try {
      final r = await c.api.call('PairStatus');
      if (!mounted || r is! Map) return;
      final n = r.cast<String, dynamic>();
      setState(() => info = n);
      if (n['result'] != null) c.refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _pal(c);
    return _Frame(
      c: c,
      title: 'Принять с телефона',
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 680;
          final res = (info?['result'] as Map?)?.cast<String, dynamic>();
          final e = err ?? (info?['error'] as String? ?? '');
          final active = info?['active'] == true;
          Widget body;
          if (res != null) {
            body = _done(p, res);
          } else if (_starting && info == null) {
            body = const Center(child: CircularProgressIndicator());
          } else if (e.isNotEmpty && (!active || (info?['host'] ?? '') == '')) {
            body = _failed(p, e);
          } else {
            final qrSize =
                (wide
                        ? (box.maxHeight - 40).clamp(160.0, 340.0)
                        : (box.maxWidth - 64).clamp(160.0, 300.0))
                    .toDouble();
            final qr = QrView(data: '${info?['uri'] ?? ''}', size: qrSize);
            final txt = _waiting(p);
            body = wide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      qr,
                      const SizedBox(width: 40),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: txt,
                        ),
                      ),
                    ],
                  )
                : Column(children: [qr, const SizedBox(height: 22), txt]);
          }
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 32),
              child: Center(child: body),
            ),
          );
        },
      ),
    );
  }

  String _left() {
    final exp = (info?['expires'] ?? 0) as int;
    final s = exp - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (s <= 0) return '0:00';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _kv(Pal p, String k, String v, {double size = 26}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 72,
          child: Text(k, style: TextStyle(color: p.sub, fontSize: 14)),
        ),
        Flexible(
          child: SelectableText(
            v,
            style: TextStyle(
              color: p.txt,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _waiting(Pal p) {
    final i = info ?? const {};
    final code = '${i['code'] ?? ''}';
    final hosts = ((i['hosts'] as List?) ?? const []).cast<Object>();
    final others = hosts.skip(1).map((h) => '$h:${i['port']}').join(', ');
    final st = TextStyle(color: p.txt, fontSize: 15, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('1. На телефоне: Nox → «+» → «Передать на ТВ»', style: st),
        const SizedBox(height: 6),
        Text('2. Отсканируйте QR-код или введите вручную:', style: st),
        const SizedBox(height: 14),
        _kv(p, 'Адрес', '${i['host']}:${i['port']}'),
        _kv(
          p,
          'Код',
          code.length == 6
              ? '${code.substring(0, 3)} ${code.substring(3)}'
              : code,
          size: 32,
        ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Другие адреса: $others',
              style: TextStyle(color: p.sub, fontSize: 12),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.acc2),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Ожидание телефона · осталось ${_left()}',
                style: TextStyle(color: p.sub, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Телефон и ТВ должны быть в одной Wi‑Fi сети.',
          style: TextStyle(color: p.ter, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            PairBtn(
              p: p,
              label: 'Закрыть',
              autofocus: true,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            PairBtn(
              p: p,
              label: 'Новый код',
              icon: Icons.refresh,
              onTap: _start,
            ),
          ],
        ),
      ],
    );
  }

  Widget _done(Pal p, J r) {
    final subs = (r['subs'] ?? 0) as int, srv = (r['servers'] ?? 0) as int;
    final dups = (r['dups'] ?? 0) as int;
    final msg =
        'Получено: $subs ${plural(subs, 'подписка', 'подписки', 'подписок')}, '
        '$srv ${plural(srv, 'сервер', 'сервера', 'серверов')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, color: p.grn, size: 72),
        const SizedBox(height: 14),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.txt,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (dups > 0 || r['selected'] == true || r['settings'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                if (dups > 0) 'уже были: $dups',
                if (r['selected'] == true) 'выбран сервер с телефона',
                if (r['settings'] == true) 'настройки применены',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub, fontSize: 14),
            ),
          ),
        const SizedBox(height: 24),
        PairBtn(
          p: p,
          label: 'Готово',
          primary: true,
          autofocus: true,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _failed(Pal p, String e) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.wifi_off_rounded, color: p.amb, size: 56),
      const SizedBox(height: 14),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          e,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.txt, fontSize: 16, height: 1.35),
        ),
      ),
      const SizedBox(height: 22),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          PairBtn(
            p: p,
            label: 'Попробовать снова',
            primary: true,
            autofocus: true,
            onTap: _start,
          ),
          PairBtn(
            p: p,
            label: 'Закрыть',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    ],
  );
}

// ------------------------------------------------------------------ sender

class PairSendPage extends StatefulWidget {
  final NoxController c;
  final String? uri;

  /// Test hooks; default to the platform camera / scanner.
  final Future<bool> Function()? camera;
  final Future<String?> Function()? scan;
  const PairSendPage({
    super.key,
    required this.c,
    this.uri,
    this.camera,
    this.scan,
  });
  @override
  State<PairSendPage> createState() => _PairSendPageState();
}

class _PairSendPageState extends State<PairSendPage> {
  String? uri; // scanned nox://pair?…
  final addr = TextEditingController(), code = TextEditingController();
  late Set<String> subs;
  bool manual = true, sel = true, sets = false, cam = false, sending = false;
  String? err;
  J? done;

  NoxController get c => widget.c;
  List<J> get _manual =>
      c.servers.where((s) => (s['subId'] ?? '') == '').toList();

  @override
  void initState() {
    super.initState();
    subs = {for (final b in c.subs) '${b['id']}'};
    manual = _manual.isNotEmpty;
    _setUri(widget.uri);
    (widget.camera ?? hasCamera)().then((v) {
      if (mounted) setState(() => cam = v);
    });
  }

  @override
  void dispose() {
    addr.dispose();
    code.dispose();
    super.dispose();
  }

  String? _host(String u) => Uri.tryParse(u)?.queryParameters['h'];

  void _setUri(String? u) {
    if (u == null || !u.toLowerCase().startsWith('nox://pair')) return;
    uri = u;
    err = null;
  }

  Future<void> _scan() async {
    final r = await (widget.scan ?? scanQr)();
    if (!mounted || r == null) return;
    setState(() {
      if (r == 'error:denied') {
        err =
            'Нет доступа к камере. Разрешите камеру или введите адрес и код вручную.';
      } else if (r.startsWith('error:')) {
        err = 'Камера недоступна. Введите адрес и код с экрана ТВ вручную.';
      } else if (!r.toLowerCase().startsWith('nox://pair')) {
        err = 'Это не QR-код Nox. На ТВ откройте «+» → «Принять с телефона».';
      } else {
        _setUri(r);
      }
    });
  }

  Future<void> _send() async {
    setState(() {
      sending = true;
      err = null;
    });
    try {
      final all = subs.length == c.subs.length;
      final r = await c.api.call('PairSend', [
        uri ?? addr.text,
        uri != null ? '' : code.text,
        {
          'subIds': all ? null : subs.toList(),
          'manual': manual,
          'selected': sel,
          'settings': sets,
        },
      ]);
      if (!mounted) return;
      setState(() => done = (r as Map).cast<String, dynamic>());
    } on NoxError catch (e) {
      if (mounted) setState(() => err = e.message);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => sending = false);
  }

  bool get _ready =>
      (subs.isNotEmpty || (manual && _manual.isNotEmpty) || sets) &&
      (uri != null ||
          (addr.text.trim().isNotEmpty &&
              code.text.replaceAll(' ', '').length == 6));

  @override
  Widget build(BuildContext context) {
    final p = _pal(c);
    return _Frame(
      c: c,
      title: 'Передать на ТВ',
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: done != null ? _sent(p) : _form(p),
        ),
      ),
    );
  }

  Widget _h(Pal p, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      t,
      style: TextStyle(color: p.sub, fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  InputDecoration _dec(Pal p, String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(color: p.sub),
    hintStyle: TextStyle(color: p.ter),
    filled: true,
    fillColor: p.chip,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.line),
    ),
  );

  Widget _check(
    Pal p,
    String title,
    String? sub,
    bool v,
    ValueChanged<bool> on,
  ) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => setState(() => on(!v)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: Row(
        children: [
          Icon(
            v ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: v ? p.acc2 : p.sub,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.txt, fontSize: 15),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _form(Pal p) {
    final man = _manual;
    final cur = c.current;
    final h = uri != null ? _host(uri!) : null;
    String count(String id) {
      final n = c.servers.where((s) => s['subId'] == id).length;
      return '$n ${plural(n, 'сервер', 'сервера', 'серверов')}';
    }

    // not a lazy ListView: every control exists, so D-pad traversal reaches «Отправить»
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'На ТВ откройте Nox → «+» → «Принять с телефона». Телефон и ТВ — в одной Wi‑Fi сети.',
            style: TextStyle(color: p.sub, fontSize: 13, height: 1.35),
          ),
          _h(p, '1. ТВ'),
          if (uri != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.tv_rounded, color: p.grn),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ТВ: ${h ?? '?'}',
                      style: TextStyle(
                        color: p.txt,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => uri = null),
                    child: const Text('Изменить'),
                  ),
                ],
              ),
            )
          else ...[
            if (cam)
              PairBtn(
                p: p,
                primary: true,
                icon: Icons.qr_code_scanner_rounded,
                label: 'Сканировать QR-код',
                onTap: _scan,
              ),
            if (cam)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Text(
                  'или введите вручную:',
                  style: TextStyle(color: p.sub, fontSize: 13),
                ),
              ),
            TextField(
              controller: addr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: p.txt),
              onChanged: (_) => setState(() {}),
              decoration: _dec(p, 'Адрес ТВ', '192.168.1.20:41234'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 7,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              ],
              style: TextStyle(color: p.txt, letterSpacing: 2),
              onChanged: (_) => setState(() {}),
              decoration: _dec(
                p,
                'Код',
                '6 цифр с экрана ТВ',
              ).copyWith(counterText: ''),
            ),
          ],
          _h(p, '2. Что передать'),
          if (c.subs.isEmpty && man.isEmpty)
            Text(
              'Нет подписок и серверов — сначала добавьте их через «+».',
              style: TextStyle(color: p.sub),
            ),
          for (final b in c.subs)
            _check(
              p,
              '${(b['name'] ?? '').toString().isEmpty ? 'Подписка' : b['name']}',
              count('${b['id']}'),
              subs.contains('${b['id']}'),
              (v) => v ? subs.add('${b['id']}') : subs.remove('${b['id']}'),
            ),
          if (man.isNotEmpty)
            _check(
              p,
              'Добавленные вручную',
              '${man.length} ${plural(man.length, 'сервер', 'сервера', 'серверов')}',
              manual,
              (v) => manual = v,
            ),
          if (cur != null)
            _check(
              p,
              'Выбранный сервер',
              '${cur['name'] ?? ''}',
              sel,
              (v) => sel = v,
            ),
          _check(
            p,
            'Настройки',
            'DNS, режим, обход РФ, тема',
            sets,
            (v) => sets = v,
          ),
          if (err != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.red.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.red.withValues(alpha: .5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: p.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      err!,
                      style: TextStyle(color: p.txt, fontSize: 14, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          PairBtn(
            p: p,
            primary: true,
            icon: sending ? null : Icons.send_rounded,
            label: sending ? 'Отправка…' : 'Отправить',
            onTap: _ready && !sending ? _send : null,
          ),
        ],
      ),
    );
  }

  Widget _sent(Pal p) {
    final r = done!;
    final subs = (r['subs'] ?? 0) as int, srv = (r['servers'] ?? 0) as int;
    final dups = (r['dups'] ?? 0) as int;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: p.grn, size: 72),
            const SizedBox(height: 14),
            Text(
              'Отправлено на ТВ',
              style: TextStyle(
                color: p.txt,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Получено: $subs ${plural(subs, 'подписка', 'подписки', 'подписок')}, '
              '$srv ${plural(srv, 'сервер', 'сервера', 'серверов')}'
              '${dups > 0 ? ' · уже были: $dups' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub, fontSize: 15),
            ),
            const SizedBox(height: 24),
            PairBtn(
              p: p,
              primary: true,
              label: 'Готово',
              autofocus: true,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ glue in Home

/// Opens the send screen for nox://pair links (system camera app) and, on a TV without
/// any profiles, suggests «Принять с телефона» once per launch (after the tour).
class PairGlue extends StatefulWidget {
  final NoxController c;
  final Widget child;
  const PairGlue({super.key, required this.c, required this.child});
  static bool suggested = false;
  @override
  State<PairGlue> createState() => _PairGlueState();
}

class _PairGlueState extends State<PairGlue> {
  @override
  void initState() {
    super.initState();
    pairLinks.addListener(_link);
    WidgetsBinding.instance.addPostFrameCallback((_) => _link());
  }

  @override
  void dispose() {
    pairLinks.removeListener(_link);
    super.dispose();
  }

  void _link() {
    final u = pairLinks.value;
    if (u == null || !mounted) return;
    pairLinks.value = null;
    openSend(context, widget.c, uri: u);
  }

  void _suggest() {
    final c = widget.c;
    if (PairGlue.suggested || !c.isTv || c.state == null || c.fatal != null) {
      return;
    }
    if (c.tourOn || c.subs.isNotEmpty || c.servers.isNotEmpty) return;
    PairGlue.suggested = true;
    openReceive(context, c);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suggest();
    });
    return widget.child;
  }
}
