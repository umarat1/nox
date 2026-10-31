// 2.2.3: dedicated Android TV screen (10-foot UI, D-pad, Netflix-like dark/red).
// Phone / desktop keep Home's layouts; Home switches here only when c.isTv.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'fmt.dart';
import 'home.dart' show settingsSheet, toast, countryBadge;
import 'pair.dart';
import 'regions.dart';
import 'theme.dart';
import 'update_ui.dart';

const _bg = Color(0xFF0B0B0D);
const _card = Color(0xFF17171B);
const _card2 = Color(0xFF222228);
const _red = Color(0xFFE50914);
const _txt = Colors.white;
const _sub = Color(0xFFB3B3B3);
const _grn = Color(0xFF2ECC71);

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String _ping(int p) => (p == 0 || p == -3) ? 'не измерен' : pingText(p);

/// Last-resort guard: a failing action shows a toast instead of a grey screen.
void _safe(dynamic Function() f) {
  try {
    final r = f();
    if (r is Future) r.catchError((Object e) { debugPrint('tv action: $e'); return null; });
  } catch (e) {
    debugPrint('tv action: $e');
  }
}

String _emoji(String? iso) {
  if (iso == null || iso.length != 2) return '';
  final u = iso.toUpperCase();
  return String.fromCharCodes(u.codeUnits.map((e) => 0x1F1E6 + e - 65));
}

/// Focusable tile: red ring + slight scale when focused; OK/Enter/tap activates.
class TvTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final double radius;
  final Color color;
  final FocusNode? node;
  final bool selected;
  const TvTile({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.radius = 18,
    this.color = _card,
    this.node,
    this.selected = false,
  });
  @override
  State<TvTile> createState() => _TvTileState();
}

class _TvTileState extends State<TvTile> {
  bool f = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.node,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        setState(() => f = v);
        if (v) {
          Scrollable.ensureVisible(
            context,
            alignment: .5,
            duration: const Duration(milliseconds: 180),
          );
        }
      },
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.numpadEnter ||
                e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: f ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: f ? _card2 : widget.color,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: f
                    ? _red
                    : widget.selected
                    ? _red.withValues(alpha: .45)
                    : Colors.transparent,
                width: f ? 2.5 : 1.5,
              ),
              boxShadow: f
                  ? [BoxShadow(color: _red.withValues(alpha: .45), blurRadius: 12)]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class TvHome extends StatefulWidget {
  final NoxController c;
  const TvHome({super.key, required this.c});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  final power = FocusNode(debugLabel: 'power');
  NoxController get c => widget.c;

  @override
  void dispose() {
    power.dispose();
    super.dispose();
  }

  String _label(J? s) {
    if (s == null) return 'Сервер не выбран';
    if (NoxController.isBal(s)) return '⚡ Автовыбор';
    final name = '${s['name'] ?? ''}';
    final iso = region(name);
    final country = iso == null ? dispName(name) : (regionName[iso] ?? dispName(name));
    final pr = NoxController.proto(s);
    return [
      '${_emoji(iso)} $country'.trim(),
      if (pr.isNotEmpty) pr,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    tvRed = true;
    final p = Pal.of(c.settings['theme'] as String?, c.pref('tpl', 'glass'));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (did) return;
        // Back: first return focus to the connect button, then leave the app.
        if (!power.hasFocus) {
          power.requestFocus();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-.8, -.9),
              radius: 1.3,
              colors: [Color(0xFF1E0305), _bg],
            ),
          ),
          // 2.2.4: 5% overscan-safe area (48 × 27 dp on the 960 × 540 canvas)
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
            child: Padding(
              padding: EdgeInsets.zero,
              child: FocusTraversalGroup(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 240, child: _left(context, p)),
                    const SizedBox(width: 24),
                    Expanded(child: _right(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _left(BuildContext context, Pal p) {
    final st = c.status;
    final on = c.connected;
    final label = on
        ? 'Подключено'
        : st == 'connecting'
        ? 'Подключение…'
        : st == 'disconnecting'
        ? 'Отключение…'
        : 'Не подключено';
    return FocusTraversalGroup(
      child: ListView(
        children: [
          Row(
            children: [
              const Text(
                'NOX',
                style: TextStyle(
                  color: _red,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(width: 10),
              Text('VPN', style: TextStyle(color: _sub, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: TvTile(
              node: power,
              autofocus: true,
              radius: 100,
              color: on ? _red : _card,
              onTap: c.busy ? null : () => c.toggle(),
              child: SizedBox(
                width: 88,
                height: 88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.power_settings_new_rounded,
                      size: 32,
                      color: on ? Colors.white : _red,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      on ? 'Отключить' : 'Подключить',
                      style: const TextStyle(
                        color: _txt,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              label,
              style: TextStyle(
                color: on ? _grn : _sub,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _label(c.current),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _txt,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (c.current != null)
            Center(
              child: Text(
                'Пинг ${_ping(_int(c.current!['ping']))}',
                style: const TextStyle(color: _sub, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          for (final b in c.subs) _subCard(b),
            _action(Icons.system_update_rounded, 'Обновление', () => openUpdate(context, c, p)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _subCard(J b) {
    final expire = _int(b['expire']);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final days = expire > 0 ? ((expire - now) / 86400).floor() : null;
    final used = _int(b['upload']) + _int(b['download']);
    final total = _int(b['total']);
    final ok = days == null || days >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: ok ? _red : _sub, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${b['name'] ?? 'Подписка'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _txt,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              days == null
                  ? 'Бессрочно'
                  : days < 0
                  ? 'Подписка истекла'
                  : 'Активна · до ${fmtDate(expire)} · $days ${plural(days, 'день', 'дня', 'дней')}',
              style: TextStyle(color: ok ? _grn : _red, fontSize: 12),
            ),
            Text(
              total > 0
                  ? 'Трафик ${fmtBytes(used)} из ${fmtBytes(total)}'
                  : 'Трафик ${fmtBytes(used)} · безлимит',
              style: const TextStyle(color: _sub, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData i, String t, VoidCallback on) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TvTile(
      onTap: on,
      radius: 14,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(i, color: _red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t,
                style: const TextStyle(color: _txt, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Pal get _pal => Pal.of(c.settings['theme'] as String?, c.pref('tpl', 'glass'));

  Widget _icon(IconData i, String t, VoidCallback on) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TvTile(
      onTap: on,
      radius: 17,
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(i, color: _red, size: 16),
              const SizedBox(width: 6),
              Text(t, maxLines: 1, style: const TextStyle(color: _txt, fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _right(BuildContext context) {
    final list = c.visible();
    final chips = c.chips();
    final cat = c.category;
    if (c.servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, color: _red, size: 90),
            const SizedBox(height: 12),
            const Text(
              'Нет серверов',
              style: TextStyle(color: _txt, fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте подписку: отсканируйте QR телефоном\nили введите ссылку вручную',
              textAlign: TextAlign.center,
              style: TextStyle(color: _sub, fontSize: 20),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 360,
              child: _action(Icons.qr_code_2_rounded, 'Показать QR-код',
                  () => openReceive(context, c)),
            ),
            SizedBox(
              width: 360,
              child: _action(Icons.keyboard_rounded, 'Ввести ссылку вручную',
                  () => _manual(context)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FocusTraversalGroup(
          child: Row(
            children: [
              _icon(Icons.qr_code_2_rounded, 'QR', () => _safe(() => openReceive(context, c))),
              _icon(Icons.keyboard_rounded, 'Ссылка', () => _safe(() => _manual(context))),
              _icon(Icons.speed_rounded, 'Пинг', () => _safe(() => c.ping([]))),
              _icon(Icons.refresh_rounded, 'Подписки', () => _safe(() => c.call('RefreshSubs'))),
              _icon(Icons.settings_rounded, 'Опции', () => _safe(() => settingsSheet(context, c, _pal))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: FocusTraversalGroup(
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.only(left: 4),
              children: [
                for (final ch in chips)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
                    child: TvTile(
                      radius: 16,
                      selected: ch.$1 == cat,
                      color: ch.$1 == cat ? const Color(0xFF3A0B0E) : _card,
                      onTap: () => _safe(() => c.setPref('cat', ch.$1)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          child: Text(
                            '${ch.$3 != null ? '${_emoji(ch.$3)} ' : ''}${ch.$2}',
                            style: const TextStyle(color: _txt, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: FocusTraversalGroup(
            child: LayoutBuilder(builder: (_, box) => GridView.builder(
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: box.maxWidth >= 480 ? 3 : 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 48,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _server(list[i]),
            )),
          ),
        ),
      ],
    );
  }

  Widget _server(J s) {
    final sel = s['id'] == c.selected;
    final name = '${s['name'] ?? ''}';
    final iso = region(name);
    final pr = NoxController.proto(s);
    final ping = _int(s['ping']);
    final pc = ping <= 0
        ? _sub
        : ping < 300
        ? _grn
        : ping < 900
        ? const Color(0xFFF5A623)
        : _red;
    final p = Pal.of(c.settings['theme'] as String?, c.pref('tpl', 'glass'));
    return TvTile(
      selected: sel,
      color: sel ? const Color(0xFF2A0A0D) : _card,
      onTap: () => _safe(() => c.select('${s['id']}')),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (NoxController.isBal(s))
              const Icon(Icons.bolt_rounded, color: _red, size: 24)
            else if (iso != null)
              countryBadge(p, iso, 24)
            else
              const Icon(Icons.public_rounded, color: _sub, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    NoxController.isBal(s) ? 'Автовыбор' : dispName(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _txt,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (pr.isNotEmpty) TextSpan(text: '$pr  ·  '),
                        TextSpan(
                          text: _ping(ping),
                          style: TextStyle(color: pc, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _sub, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            if (sel) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle_rounded, color: _red, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _manual(BuildContext context) async {
    final tc = TextEditingController();
    final addNode = FocusNode(debugLabel: 'add');
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ссылка на подписку',
                  style: TextStyle(color: _txt, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Введите ссылку пультом и нажмите «Готово», затем ↓ и «Добавить»',
                  style: TextStyle(color: _sub, fontSize: 15),
                ),
                const SizedBox(height: 14),
                // D-pad ↓ leaves the text field (Flutter keeps arrows inside it by default)
                Focus(
                  skipTraversal: true,
                  onKeyEvent: (_, e) {
                    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      addNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: tc,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: _txt, fontSize: 22),
                    cursorColor: _red,
                    decoration: const InputDecoration(
                      hintText: 'https://… , vless://… , trojan://…',
                      hintStyle: TextStyle(color: _sub),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _sub)),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _red, width: 3),
                      ),
                    ),
                    onSubmitted: (_) => addNode.requestFocus(),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TvTile(
                      radius: 14,
                      onTap: () => Navigator.pop(ctx),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        child: Text('Отмена', style: TextStyle(color: _sub, fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    TvTile(
                      node: addNode,
                      radius: 14,
                      color: _red,
                      onTap: () => _doImport(ctx, tc.text),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                        child: Text(
                          'Добавить',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    addNode.dispose();
  }

  Future<void> _doImport(BuildContext ctx, String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    final r = await c.call('Import', [text]);
    await c.refresh();
    if (!ctx.mounted) return;
    Navigator.pop(ctx);
    if (r is Map && mounted) {
      final errs = (r['errors'] as List?)?.length ?? 0;
      toast(context, '${r['msg']}${errs > 0 ? ' · ошибок: $errs' : ''}');
    }
  }
}
