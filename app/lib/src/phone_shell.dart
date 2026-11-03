part of 'home.dart';

// 2.3.1 phone shell (Android phone; desktop and TV keep their layouts): compact connect
// card, current-server row, one subscription card with a «⋯» menu, the flat server list
// with country chips, and a bottom navigation Главная / Серверы / Подписки / Настройки.

bool phoneShell(NoxController c) => !desktopUi && !c.isTv;

/// Selected bottom tab (0 Главная, 1 Серверы, 2 Подписки, 3 Настройки).
final phoneTab = ValueNotifier<int>(0);

/// Servers tab search text.
final srvQuery = ValueNotifier<String>('');
final _srvQueryCtl = TextEditingController();

/// Liquid glass surface of the mockups: neutral translucent card (alpha from
/// «Прозрачность стекла»), thin specular edge, soft shadow.
BoxDecoration glassCard(Pal p, {double r = 22, Color? border, Color? tint}) {
  if (winCards) return winCardDeco(p, r: math.min(r, 10), border: border);
  final base =
      tint ??
      (p.light
          ? const Color(0xFFFFFFFF)
          : (p.amoled ? const Color(0xFF120E11) : const Color(0xFF1C161B)));
  return BoxDecoration(
    color: base.withValues(alpha: glassAlpha(p.light ? .92 : 1)),
    borderRadius: BorderRadius.circular(r),
    border: Border.all(
      color:
          border ??
          (p.light
              ? Colors.white.withValues(alpha: .85)
              : Colors.white.withValues(alpha: .10)),
    ),
    boxShadow: [
      BoxShadow(
        color: p.light ? const Color(0x14782832) : const Color(0x59000000),
        blurRadius: 26,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class GlassCard extends StatelessWidget {
  final Pal p;
  final Widget child;
  final double r;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  const GlassCard({
    super.key,
    required this.p,
    required this.child,
    this.r = 22,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    Widget body = Container(
      decoration: glassCard(p, r: r),
      padding: padding,
      child: child,
    );
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: onTap,
          child: body,
        ),
      );
    }
    return Padding(
      padding: margin,
      child: glassBlurred(r: r, child: body),
    );
  }
}

Color pingColor(Pal p, int ping) => ping <= 0
    ? p.ter
    : ping < 200
    ? p.grn
    : ping < 900
    ? p.amb
    : p.red;

/// «● 754 мс»
class _PingDot extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J s;
  const _PingDot({required this.c, required this.p, required this.s});
  @override
  Widget build(BuildContext context) {
    final ping = (s['ping'] ?? 0) as int;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: pingColor(p, ping),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _pingOf(c, s),
          style: TextStyle(
            color: p.txt.withValues(alpha: .82),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Server row inside a country card: flag, short name, «Текущий», ping. Tap selects,
/// long-press opens the server menu.
class _PhoneRow extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J s;
  final bool first, last;
  const _PhoneRow({
    required this.c,
    required this.p,
    required this.s,
    this.first = false,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) {
    final sel = s['id'] == c.selected;
    return Material(
      key: first ? TourKeys.server : null,
      color: sel
          ? p.acc.withValues(alpha: p.light ? .08 : .13)
          : Colors.transparent,
      child: InkWell(
        onTap: () => c.select(s['id']),
        onLongPress: () => serverSheet(context, c, p, s),
        onSecondaryTap: () => serverSheet(context, c, p, s),
        focusColor: p.acc.withValues(alpha: .18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(
                    bottom: BorderSide(
                      color: p.light
                          ? const Color(0x123C1E23)
                          : Colors.white.withValues(alpha: .06),
                    ),
                  ),
          ),
          child: Row(
            children: [
              _flag(p, s, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _shortName(s['name'] ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (sel)
                Container(
                  margin: const EdgeInsets.only(right: 10, left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.acc.withValues(alpha: p.light ? .12 : .18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Текущий',
                    style: TextStyle(
                      color: p.acc,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              _PingDot(c: c, p: p, s: s),
            ],
          ),
        ),
      ),
    );
  }
}

/// Country card: rows separated by hairlines inside one glass card.
Widget _phoneCountryCard(
  NoxController c,
  Pal p,
  List<J> rows,
  bool Function() first,
) => GlassCard(
  p: p,
  r: 20,
  padding: EdgeInsets.zero,
  margin: const EdgeInsets.only(bottom: 8),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Column(
      children: [
        for (final (i, s) in rows.indexed)
          _PhoneRow(
            c: c,
            p: p,
            s: s,
            first: first(),
            last: i == rows.length - 1,
          ),
      ],
    ),
  ),
);

String _connLabel(NoxController c) => c.connected
    ? 'Подключено'
    : c.status == 'connecting'
    ? 'Подключение…'
    : c.status == 'disconnecting'
    ? 'Отключение…'
    : 'Отключено';

class _StatusPill extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _StatusPill({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final on = c.connected, wait = c.busy;
    final col = on ? p.grn : (wait ? p.amb : p.sub);
    return Container(
      key: const Key('status-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: on
            ? p.grn.withValues(alpha: p.light ? .11 : .13)
            : (p.light
                  ? Colors.black.withValues(alpha: .05)
                  : Colors.white.withValues(alpha: .07)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _connLabel(c),
            style: TextStyle(
              color: on ? p.grn : p.sub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _timer(NoxController c) {
  final since = (c.s['since'] ?? 0) as int;
  if (!c.connected || since <= 0) return '00:00:00';
  return _hms(DateTime.now().millisecondsSinceEpoch ~/ 1000 - since);
}

Widget _speed(Pal p, IconData i, num v, {double size = 13}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(i, size: size + 1, color: p.sub),
    const SizedBox(width: 5),
    Text(
      '${fmtBytes(v)}/с',
      style: TextStyle(
        color: p.sub,
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    ),
  ],
);

/// Small red power button of the compact card.
Widget _miniPower(NoxController c, Pal p) {
  final on = c.connected, wait = c.busy;
  return Focus(
    key: TourKeys.power,
    child: Semantics(
      button: true,
      label: on ? 'Отключить' : 'Подключить',
      child: GestureDetector(
        onTap: c.toggle,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.acc.withValues(alpha: on ? .12 : .06),
            border: Border.all(color: p.acc.withValues(alpha: on ? .38 : .2)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: wait && !on
                    ? [p.amb, Color.lerp(p.amb, Colors.black, .25)!]
                    : [
                        const Color(0xFFF0656B),
                        Color.lerp(p.acc, Colors.black, on ? .10 : .18)!,
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: p.acc.withValues(alpha: on ? .45 : .22),
                  blurRadius: on ? 22 : 12,
                ),
              ],
            ),
            child: Icon(
              Icons.power_settings_new_rounded,
              color: Colors.white.withValues(alpha: on ? 1 : .85),
              size: 27,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Connect card. «С кнопкой»: power button | status + timer | speeds.
/// «С ползунком»: no button, centred status, timer and speeds (the slide bar is docked
/// above the bottom navigation).
class _CompactHero extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _CompactHero({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final t = c.traffic;
    final down = (t?['Down'] ?? 0) as num, up = (t?['Up'] ?? 0) as num;
    final timerStyle = TextStyle(
      color: c.connected ? p.txt : p.txt.withValues(alpha: .92),
      fontWeight: FontWeight.w800,
      letterSpacing: .5,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    if (heroStyle == 'timer') {
      return GlassCard(
        key: const Key('hero-compact'),
        p: p,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
        child: Column(
          children: [
            ..._heroUpdate(context, c, p),
            _heroTopRow(context, c, p),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _timer(c),
                style: timerStyle.copyWith(fontSize: 46, height: 1.15),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _speed(p, Icons.south_rounded, down),
                const SizedBox(width: 22),
                _speed(p, Icons.north_rounded, up),
              ],
            ),
            _heroGraph(c, p),
          ],
        ),
      );
    }
    return GlassCard(
      key: const Key('hero-compact'),
      p: p,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 2),
      child: Column(
        children: [
          ..._heroUpdate(context, c, p),
          _heroTopRow(context, c, p),
          const SizedBox(height: 6),
          Row(
            children: [
              _miniPower(c, p),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _timer(c),
                    style: timerStyle.copyWith(fontSize: 30),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _speed(p, Icons.south_rounded, down),
                        const SizedBox(height: 8),
                        _speed(p, Icons.north_rounded, up),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _heroGraph(c, p),
        ],
      ),
    );
  }
}

/// 2.3.2: live speed graph under the connect card's numbers + a small chevron to fold it
/// (folded = the plain compact card; persisted in ui.heroGraphOff).
Widget _heroGraph(NoxController c, Pal p) {
  final off = c.flag('heroGraphOff', false);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!off) ...[
        const SizedBox(height: 10),
        SizedBox(
          key: const Key('hero-graph'),
          height: 56,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LiveGraph(
              series: c.speed,
              p: p,
              active: c.connected && c.animSmooth,
              calm: true,
              span: 60,
            ),
          ),
        ),
      ],
      Tooltip(
        message: off ? 'Показать график скорости' : 'Скрыть график скорости',
        child: InkWell(
          key: const Key('hero-graph-toggle'),
          borderRadius: BorderRadius.circular(99),
          onTap: () => c.setPrefLive('heroGraphOff', off ? '0' : '1'),
          child: SizedBox(
            width: 56,
            height: 22,
            child: Icon(
              off
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 20,
              color: p.sub.withValues(alpha: .8),
            ),
          ),
        ),
      ),
    ],
  );
}

String _srvTitle(J s) {
  final n = (s['name'] ?? '') as String;
  if (NoxController.isBal(s)) return _dispName(n);
  return _dispName(n); // 2.3.3: full original name (minus the leading flag)
}

/// Current server: flag, «Страна · сервер», ping, › — opens the Серверы tab.
class _CurrentServer extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _CurrentServer({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final cur = c.current;
    return GlassCard(
      key: const Key('current-server'),
      p: p,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => phoneTab.value = 1,
      child: Row(
        children: [
          if (cur != null)
            _flag(p, cur, size: 40)
          else
            Icon(Icons.public_rounded, size: 40, color: p.sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cur == null ? 'Сервер не выбран' : _srvTitle(cur),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cur == null ? 'Выберите сервер в списке' : 'Текущий сервер',
                  style: TextStyle(color: p.sub, fontSize: 13),
                ),
              ],
            ),
          ),
          if (cur != null) _PingDot(c: c, p: p, s: cur),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: p.ter, size: 22),
        ],
      ),
    );
  }
}

int _subCount(NoxController c, J b) => c.servers
    .where(
      (s) => s['subId'] == b['id'] && (!_antiOn(c) || NoxController.isQw(s)),
    )
    .length;

/// 2.3.2 «Анти БПЛА»: the phone lists only qWDTT servers (persisted in ui.antiblock).
bool _antiOn(NoxController c) => c.flag('antiblock', false);

/// 2.3.2: the subscription picked in the card switcher (several subscriptions only).
J? _subSel(NoxController c) {
  final subs = c.subs;
  if (subs.length < 2) return null;
  return subs[(int.tryParse(c.pref('subIdx', '0')) ?? 0).clamp(
    0,
    subs.length - 1,
  )];
}

/// Phone list = visible() ∩ selected subscription ∩ «Анти БПЛА».
List<J> phoneFilter(NoxController c, List<J> l) {
  final sub = _subSel(c), anti = _antiOn(c);
  if (sub == null && !anti) return l;
  return [
    for (final s in l)
      // the current server stays listed even when it is from another subscription
      if ((sub == null || s['subId'] == sub['id'] || s['id'] == c.selected) &&
          (!anti || NoxController.isQw(s)))
        s,
  ];
}

Future<void> toggleAntiblock(BuildContext context, NoxController c) async {
  final on = !_antiOn(c);
  // 2.3.3: Анти БПЛА (qWDTT only) and МТС (no qWDTT) together left an empty list —
  // they are mutually exclusive now.
  final offMts = on && c.mtsOn;
  c.setPrefLive('antiblock', on ? '1' : '0');
  if (offMts) await c.setMtsProxy(false);
  if (!context.mounted) return;
  toast(
    context,
    on
        ? 'Анти БПЛА: в списке только серверы qWDTT${offMts ? ' (МТС прокси выключен)' : ''}'
        : 'Анти БПЛА выключен: показаны все серверы',
  );
}

Future<void> toggleMts(BuildContext context, NoxController c) async {
  final on = !c.mtsOn;
  final offAnti = on && _antiOn(c); // 2.3.3: qWDTT cannot go through МТС
  if (offAnti) c.setPrefLive('antiblock', '0');
  await c.setMtsProxy(on);
  if (!context.mounted) return;
  toast(
    context,
    on
        ? 'МТС прокси включён: только AnyTLS, NaiveProxy, mieru, VLESS и прокси${offAnti ? ' (Анти БПЛА выключен)' : ''}'
        : 'МТС прокси выключен',
  );
  if (on) await mtsApnDialog(context);
}

/// Small round glass button in the connect card's top corners.
class _CornerBtn extends StatelessWidget {
  final Pal p;
  final String tip;
  final bool on;
  final Widget child;
  final VoidCallback onTap;
  const _CornerBtn({
    super.key,
    required this.p,
    required this.tip,
    required this.on,
    required this.child,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: Semantics(
      button: true,
      toggled: on,
      label: tip,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? p.acc.withValues(alpha: p.light ? .14 : .22)
                  : (p.light
                        ? Colors.black.withValues(alpha: .045)
                        : Colors.white.withValues(alpha: .07)),
              border: Border.all(
                color: on
                    ? p.acc.withValues(alpha: p.light ? .55 : .65)
                    : (p.light
                          ? Colors.black.withValues(alpha: .08)
                          : Colors.white.withValues(alpha: .12)),
              ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: p.acc.withValues(alpha: .28),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: MediaQuery.withNoTextScaling(child: child),
          ),
        ),
      ),
    ),
  );
}

/// «Анти БПЛА» (left) · status pill · «МТС» (right): the top row of the connect card.
/// 2.3.2: «Обновить до X.Y.Z» above the status pill while the engine reports an app
/// update (latest.json → /api/apps/nox/update.json → iji.by). Tap = the in-app
/// download + install job (engine picks the ABI APK and checks sha256). Own line, so it
/// never touches the corner buttons or the graph.
List<Widget> _heroUpdate(BuildContext context, NoxController c, Pal p) {
  // 2.3.2: «Обновить до X» → (auto-download) «Скачивание 42%» → «Установить X»
  final st = updPill(c);
  if (st == null) return const [];
  final v = st.version, label = st.label;
  final acc = p.light ? p.acc : p.acc2;
  final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.15);
  final j = updJob(c);
  final total = (j?['total'] as num?) ?? -1;
  final frac =
      st.kind == 'progress' && '${j?['stage']}' == 'download' && total > 0
      ? (((j?['done'] as num?) ?? 0) / total).clamp(0.0, 1.0).toDouble()
      : null;
  return [
    Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Tooltip(
          message: switch (st.kind) {
            'progress' =>
              'Обновление $v скачивается — нажмите, чтобы смотреть ход',
            'ready' => 'Версия $v скачана и проверена — установить',
            _ =>
              v.isEmpty
                  ? 'Скачать и установить обновление'
                  : 'Скачать и установить версию $v',
          },
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('hero-update'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => startUpdateFlow(context, c, p),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      acc.withValues(alpha: p.light ? .16 : .26),
                      acc.withValues(alpha: p.light ? .08 : .14),
                    ],
                  ),
                  border: Border.all(color: acc.withValues(alpha: .45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (st.kind == 'progress')
                      SizedBox(
                        key: const Key('hero-update-progress'),
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          value: frac,
                          strokeWidth: 2,
                          color: acc,
                          backgroundColor: acc.withValues(alpha: .2),
                        ),
                      )
                    else
                      Icon(
                        st.kind == 'ready'
                            ? Icons.install_mobile_rounded
                            : Icons.system_update_alt_rounded,
                        size: 15,
                        color: acc,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      textScaler: TextScaler.linear(ts),
                      style: TextStyle(
                        color: acc,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    const SizedBox(height: 6),
  ];
}

Widget _heroTopRow(BuildContext context, NoxController c, Pal p) {
  final anti = _antiOn(c);
  final antiCol = anti ? (p.light ? p.acc : p.acc2) : p.sub;
  // 2.3.4: the shield button carries a small «Анти БПЛА» caption under it. The caption
  // is wider than the 34 px circle, so it overflows sideways (centred, into the card
  // padding) instead of pushing the button inward; the pill and «МТС» stay on the
  // button's line (top-aligned row, each in a 34 px slot).
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CornerBtn(
            key: const Key('hero-antiblock'),
            p: p,
            tip: anti
                ? 'Анти БПЛА: вкл — только qWDTT'
                : 'Анти БПЛА: показать только qWDTT',
            on: anti,
            onTap: () => toggleAntiblock(context, c),
            child: Icon(
              anti ? Icons.shield_rounded : Icons.shield_outlined,
              size: 17,
              color: antiCol,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 34,
            height: 11,
            child: OverflowBox(
              maxWidth: 70,
              child: MediaQuery.withNoTextScaling(
                child: Text(
                  'Анти БПЛА',
                  key: const Key('hero-antiblock-caption'),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                    color: antiCol,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      Expanded(
        child: SizedBox(
          height: 34,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _StatusPill(c: c, p: p),
              ),
            ),
          ),
        ),
      ),
      if (!desktopUi)
        _CornerBtn(
          key: const Key('hero-mts'),
          p: p,
          tip: c.mtsOn ? 'МТС прокси: вкл' : 'МТС прокси: выкл',
          on: c.mtsOn,
          onTap: () => toggleMts(context, c),
          child: Text(
            'МТС',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
              color: c.mtsOn ? (p.light ? p.acc : p.acc2) : p.sub,
            ),
          ),
        )
      else
        const SizedBox(width: 34),
    ],
  );
}

String _subName(J b, int i) {
  final n = '${b['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Подписка ${i + 1}' : n;
}

/// Segmented switcher (subscriptions on the main card, subscription filter on Серверы).
class _Seg extends StatelessWidget {
  final Pal p;
  final List<(String, String)> items; // (label, small count)
  final int on;
  final ValueChanged<int> onTap;
  const _Seg({
    required this.p,
    required this.items,
    required this.on,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: p.light
          ? const Color(0xFFEDE8E6).withValues(alpha: .9)
          : Colors.black.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(14),
    ),
    // 2.3.2: equal-width segments when every label fits; otherwise (small screen,
    // big font, long names) natural-width pills that scroll sideways.
    child: LayoutBuilder(
      builder: (context, box) {
        final ts = MediaQuery.textScalerOf(context);
        double need = 0;
        for (final (i, (t, n)) in items.indexed) {
          need += _w(t, n, i == on, ts) + 12;
        }
        // equal split is fine while every label keeps ≥ 90 px of text (ellipsized
        // tail like «X panel · umara…»); below that, scroll instead of «Се…».
        final slot = box.maxWidth / math.max(1, items.length) - 12;
        if (need <= box.maxWidth || slot >= ts.scale(90)) {
          return Row(
            children: [
              for (final (i, (t, n)) in items.indexed)
                Expanded(child: _pill(i, t, n)),
            ],
          );
        }
        return SingleChildScrollView(
          key: const Key('sub-seg-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, (t, n)) in items.indexed)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * .85),
                  child: i == on
                      ? _SeenOnce(
                          key: ValueKey('seg-on-$i'),
                          child: _pill(i, t, n),
                        )
                      : _pill(i, t, n),
                ),
            ],
          ),
        );
      },
    ),
  );

  static double _w(String t, String n, bool bold, TextScaler ts) {
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: t),
          if (n.isNotEmpty)
            TextSpan(
              text: ' $n',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: ts,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  Widget _pill(int i, String t, String n) => GestureDetector(
    onTap: () => onTap(i),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: i == on
            ? (p.light ? Colors.white : Colors.white.withValues(alpha: .09))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        boxShadow: i == on && p.light
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: t),
            if (n.isNotEmpty)
              TextSpan(
                text: ' $n',
                style: TextStyle(
                  color: p.ter,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: i == on ? p.txt : p.sub,
          fontSize: 13.5,
          fontWeight: i == on ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Scrolls the selected switcher pill into view when it appears.
class _SeenOnce extends StatefulWidget {
  final Widget child;
  const _SeenOnce({super.key, required this.child});
  @override
  State<_SeenOnce> createState() => _SeenOnceState();
}

class _SeenOnceState extends State<_SeenOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // only the switcher's own horizontal scroller — never the page list
        final ro = context.findRenderObject();
        final pos = Scrollable.maybeOf(context)?.position;
        if (ro != null && pos != null && pos.axis == Axis.horizontal) {
          pos.ensureVisible(
            ro,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _dotsBtn(
  Pal p,
  VoidCallback onTap, {
  String tip = 'Действия с подпиской',
}) => Tooltip(
  message: tip,
  child: Material(
    type: MaterialType.transparency,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.light
              ? Colors.white.withValues(alpha: .7)
              : Colors.white.withValues(alpha: .05),
          border: Border.all(
            color: p.light
                ? const Color(0x143C1E23)
                : Colors.white.withValues(alpha: .12),
          ),
        ),
        child: Icon(Icons.more_horiz_rounded, color: p.txt, size: 20),
      ),
    ),
  ),
);

/// 2.3.2: round glass ↻ next to «⋯» — refreshes the shown subscription, spins while
/// updating, then a short «Обновлено» / error toast (same as the ⋯ menu item).
class _SubRefreshBtn extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final J sub;
  const _SubRefreshBtn({
    super.key,
    required this.c,
    required this.p,
    required this.sub,
  });
  @override
  State<_SubRefreshBtn> createState() => _SubRefreshBtnState();
}

class _SubRefreshBtnState extends State<_SubRefreshBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _busy = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    _spin.repeat();
    dynamic r;
    try {
      r = await widget.c.call('RefreshSub', [widget.sub['id']]);
    } catch (e) {
      r = 'Не удалось обновить: $e';
    }
    if (!mounted) return;
    try {
      await finishRefresh(context, widget.c, r);
    } finally {
      if (mounted) {
        _spin.stop();
        _spin.reset();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Tooltip(
      message: _busy ? 'Обновляется…' : 'Обновить подписку',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _go,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.light
                  ? Colors.white.withValues(alpha: .7)
                  : Colors.white.withValues(alpha: .05),
              border: Border.all(
                color: p.light
                    ? const Color(0x143C1E23)
                    : Colors.white.withValues(alpha: .12),
              ),
            ),
            child: RotationTransition(
              turns: _spin,
              child: Icon(
                Icons.refresh_rounded,
                color: _busy ? p.acc : p.txt,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subscription card: switcher (several subscriptions) or title, «⋯», used / remaining,
/// expiry, progress bar, compact announcement.
class _SubCard extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J? fixed; // Подписки tab: one card per subscription, no switcher
  final Widget? footer; // 2.4.0 Windows: the ping check bar under the progress bar
  const _SubCard({required this.c, required this.p, this.fixed, this.footer});
  @override
  Widget build(BuildContext context) {
    final subs = c.subs;
    final idx = fixed != null
        ? subs.indexOf(fixed!)
        : (int.tryParse(c.pref('subIdx', '0')) ?? 0).clamp(0, subs.length - 1);
    final b = fixed ?? subs[idx];
    final n = _subCount(c, b);
    final used = ((b['upload'] ?? 0) as num) + ((b['download'] ?? 0) as num);
    final total = (b['total'] ?? 0) as num;
    final expire = (b['expire'] ?? 0) as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = expire > 0 ? (expire - now) / 86400 : null;
    final dt = expire > 0
        ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
        : null;
    final d = _SubData(n: n, used: used, total: total, left: left, dt: dt);
    final ann = (b['announce'] ?? '') as String;
    final multi = fixed == null && subs.length > 1;
    final expCol = d.forever || d.days > 7
        ? p.grn
        : (d.days > 2 ? p.amb : p.red);
    return GlassCard(
      key: fixed == null ? TourKeys.sub : null,
      p: p,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: multi
                    ? _Seg(
                        p: p,
                        items: [
                          for (final (i, s) in subs.indexed)
                            (_subName(s, i), '${_subCount(c, s)}'),
                        ],
                        on: idx,
                        onTap: (i) => c.setPrefLive('subIdx', '$i'),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: _subName(b, math.max(0, idx))),
                            TextSpan(
                              text: '  ${d.servTxt}',
                              style: TextStyle(
                                color: p.sub,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.txt,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              KeyedSubtree(
                key: fixed == null ? TourKeys.refresh : null,
                child: _SubRefreshBtn(
                  key: Key('sub-refresh-${b['id']}'),
                  c: c,
                  p: p,
                  sub: b,
                ),
              ),
              const SizedBox(width: 8),
              _dotsBtn(p, () => subSheet(context, c, p, b)),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: d.unlimited ? d.usedTxt : fmtBytes(d.trafficLeft),
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                TextSpan(
                  text: d.unlimited
                      ? '  израсходовано'
                      : '  осталось из ${fmtBytes(d.total)}',
                  style: TextStyle(color: p.sub, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: d.forever ? '∞ Бессрочно' : d.expShort,
                  style: TextStyle(color: expCol, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: d.forever
                      ? (d.unlimited ? ' · трафик без лимита' : '')
                      : ' · ${d.dateTxt}',
                ),
                if (!d.unlimited)
                  TextSpan(text: ' · израсходовано ${d.usedTxt}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.sub, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(
                    color: p.light
                        ? const Color(0xFFEDE8E6)
                        : Colors.white.withValues(alpha: .06),
                  ),
                  FractionallySizedBox(
                    widthFactor: d.unlimited ? 1 : d.tFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color.lerp(
                              p.acc,
                              Colors.black,
                              .2,
                            )!.withValues(alpha: .8),
                            p.acc.withValues(alpha: .85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ?footer,
          if (ann.isNotEmpty) _AnnounceLine(c: c, p: p, text: ann),
        ],
      ),
    );
  }
}

/// Compact provider announcement: one or two lines, tap for the full text, × hides it.
class _AnnounceLine extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final String text;
  const _AnnounceLine({required this.c, required this.p, required this.text});
  @override
  Widget build(BuildContext context) {
    final key = '${text.hashCode}';
    if (c.ui['annHide'] == key) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showDialog<void>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Объявление'),
              content: SingleChildScrollView(child: SelectableText(text)),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(d);
                    c.setPref('annHide', key);
                  },
                  child: const Text('Скрыть'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: p.acc.withValues(alpha: p.light ? .06 : .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.campaign_outlined, size: 17, color: p.acc),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text.replaceAll('**', '').replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.txt.withValues(alpha: .85),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => c.setPref('annHide', key),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: p.sub),
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

class _PhoneNav extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final int tab;
  const _PhoneNav({required this.c, required this.p, required this.tab});
  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.language_rounded, Icons.language_rounded, 'Серверы'),
    (Icons.credit_card_outlined, Icons.credit_card_rounded, 'Подписки'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Настройки'),
  ];
  @override
  Widget build(BuildContext context) {
    final upd = c.s['update'] is Map;
    final bar = Container(
      key: const Key('phone-nav'),
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: (p.light ? const Color(0xFFFBF9F8) : const Color(0xFF141115))
            .withValues(alpha: glassBlur ? .82 : .96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
            color: p.light
                ? const Color(0x143C1E23)
                : Colors.white.withValues(alpha: .09),
          ),
        ),
      ),
      child: Row(
        children: [
          for (final (i, (ic, icOn, label)) in _items.indexed)
            Expanded(
              child: Semantics(
                selected: i == tab,
                button: true,
                label: label,
                child: InkWell(
                  key: i == 3
                      ? TourKeys.settings
                      : (i == 2 ? TourKeys.add : null),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => phoneTab.value = i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 58,
                              height: 32,
                              decoration: BoxDecoration(
                                color: i == tab
                                    ? p.acc.withValues(
                                        alpha: p.light ? .10 : .16,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                i == tab ? icOn : ic,
                                size: 22,
                                color: i == tab ? p.acc : p.sub,
                              ),
                            ),
                            if (i == 3 && upd)
                              Positioned(
                                right: 12,
                                top: 2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: p.acc,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: i == tab ? p.acc : p.sub,
                            fontSize: 12,
                            fontWeight: i == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: glassBlur
          ? ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: bar,
              ),
            )
          : bar,
    );
  }
}

/// Page title with an optional round «＋».
Widget _pageTitle(
  Pal p,
  String t, {
  VoidCallback? onAdd,
  String addTip = 'Добавить',
  Widget? extra,
}) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 14, 0, 12),
  child: Row(
    children: [
      Expanded(
        child: Text(
          t,
          style: TextStyle(
            color: p.txt,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
      ),
      ?extra,
      if (extra != null) const SizedBox(width: 6),
      if (onAdd != null)
        Tooltip(
          message: addTip,
          child: Material(
            key: Key('page-add-$t'),
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(p.acc, Colors.white, .1)!,
                    Color.lerp(p.acc, Colors.black, .25)!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: p.acc.withValues(alpha: .35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);

Widget _sectionLabel(Pal p, String t) => Padding(
  padding: const EdgeInsets.fromLTRB(6, 14, 6, 7),
  child: Text(
    t.toUpperCase(),
    style: TextStyle(
      color: p.ter,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  ),
);

/// Glass action button («Проверить пинг», «Обновить»).
Widget _actBtn(Pal p, IconData i, String t, VoidCallback onTap, {Key? key}) =>
    GlassCard(
      key: key,
      p: p,
      r: 16,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(i, size: 18, color: p.txt),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.txt,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

/// Pops [ctx] only when it belongs to a bottom sheet / dialog (the settings list is also
/// shown as the Настройки page, where there is nothing to close).
void popSheet(BuildContext ctx) {
  if (ModalRoute.of(ctx) is PopupRoute) Navigator.pop(ctx);
}

Widget brandLogo({double size = 30}) => Image.asset(
  'assets/brand/logo_server_plus.png',
  width: size,
  height: size,
  filterQuality: FilterQuality.medium,
);

/// Height of the phone's bottom overlay (slide bar + navigation), measured.
final _bottomH = ValueNotifier<double>(0);

class _SizeReport extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;
  const _SizeReport({required this.onSize, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RSize(onSize);
  @override
  void updateRenderObject(BuildContext context, _RSize r) => r.onSize = onSize;
}

class _RSize extends RenderProxyBox {
  _RSize(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final z = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(z));
    }
  }
}

String _emptyText(NoxController c) {
  final sub = _subSel(c);
  final inSub = sub == null
      ? ''
      : ' в подписке «${_subName(sub, c.subs.indexOf(sub))}»';
  if (_antiOn(c)) {
    return c.mtsOn
        ? 'Нет серверов qWDTT$inSub: «МТС прокси» их скрывает. Выключите «МТС» или «Анти БПЛА».'
        : 'Нет серверов qWDTT$inSub. Выключите «Анти БПЛА»${sub != null ? ' или выберите другую подписку' : ''}.';
  }
  if (sub != null) return 'Нет серверов$inSub. Выберите другую подписку.';
  return 'Нет серверов. Нажмите «＋» на вкладке «Серверы» или «Подписки».';
}

/// 2.3.2: Поддержка · sites · Донат as a horizontal row of glass pills (top of Настройки).
Widget _linksRow(BuildContext context, Pal p) {
  final tiles = <(String, String, Widget)>[
    for (final (t, u, _, tg) in _SubLinksBar._items)
      (
        t,
        u,
        tg
            ? Icon(Icons.telegram, size: 18, color: const Color(0xFF2AABEE))
            : _siteBadge(p, t),
      ),
    (
      'Донат',
      _SubLinksBar._donateUrl,
      Icon(Icons.favorite_rounded, size: 16, color: p.light ? p.acc : p.acc2),
    ),
  ];
  return SizedBox(
    height: 44,
    child: SingleChildScrollView(
      key: const Key('settings-links'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (i, (t, u, ic)) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final donate = i == tiles.length - 1;
                return Tooltip(
                  message: donate
                      ? 'Пожертвование'
                      : u.replaceFirst('https://', ''),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('link-$t'),
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => _openSubUrl(context, u),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: donate
                                ? [
                                    p.acc.withValues(
                                      alpha: p.light ? .14 : .26,
                                    ),
                                    p.acc.withValues(
                                      alpha: p.light ? .06 : .10,
                                    ),
                                  ]
                                : p.light
                                ? [
                                    Colors.white.withValues(alpha: .85),
                                    Colors.white.withValues(alpha: .55),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: .10),
                                    Colors.white.withValues(alpha: .04),
                                  ],
                          ),
                          border: Border.all(
                            color: donate
                                ? p.acc.withValues(alpha: .45)
                                : (p.light
                                      ? Colors.black.withValues(alpha: .08)
                                      : Colors.white.withValues(alpha: .12)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.light
                                    ? Colors.black.withValues(alpha: .04)
                                    : Colors.white.withValues(alpha: .07),
                              ),
                              child: ic,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t,
                              maxLines: 1,
                              style: TextStyle(
                                color: donate
                                    ? (p.light ? p.acc : p.acc2)
                                    : p.txt,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}

/// Favicon-style letter badge for a site link.
Widget _siteBadge(Pal p, String host) => MediaQuery.withNoTextScaling(
  child: Stack(
    alignment: Alignment.center,
    children: [
      Icon(Icons.public_rounded, size: 20, color: p.sub.withValues(alpha: .35)),
      Text(
        host.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: p.light ? p.acc : p.acc2,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  ),
);

extension _PhoneShell on _BodyState {
  Widget phoneBody(
    BuildContext context,
    List<J> list,
    List<Widget> banners,
  ) => ValueListenableBuilder<int>(
    valueListenable: phoneTab,
    builder: (context, tab, _) => ValueListenableBuilder<String>(
      valueListenable: srvQuery,
      builder: (context, q, _) {
        final dock = heroStyle == 'timer' && tab <= 1;
        final shown = phoneFilter(c, list);
        return Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _bottomH,
                builder: (context, h, _) {
                  // the last row scrolls fully above the slide bar and the navigation
                  final est =
                      84.0 +
                      MediaQuery.paddingOf(context).bottom +
                      (dock ? 80 : 0);
                  final pad = math.max(est, h) + 16;
                  return switch (tab) {
                    1 => _serversPage(context, shown, q, pad),
                    2 => _subsPage(context, pad),
                    3 => _settingsPage(context, pad),
                    _ => _homePage(context, shown, banners, pad),
                  };
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SizeReport(
                onSize: (z) {
                  if ((z.height - _bottomH.value).abs() > .5) {
                    _bottomH.value = z.height;
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (dock)
                      Padding(
                        key: const Key('slider-dock'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: TapPill(c: c, p: p),
                      ),
                    MediaQuery.removePadding(
                      context: context,
                      removeBottom: false,
                      child: _PhoneNav(c: c, p: p, tab: tab),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  List<Widget> _listOrEmpty(BuildContext context, List<J> list, double pad) {
    if (list.isEmpty) {
      final none = c.subs.isEmpty && c.servers.isEmpty;
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, pad),
          sliver: SliverList.list(
            children: [
              if (none) ...[
                ClipboardAddButton(c: c, p: p),
                const SizedBox(height: 12),
              ],
              Text(
                none
                    ? 'Скопируйте ссылку на подписку или сервер (vless, trojan, ss, hy2, tuic, qwdtt, sstp) и нажмите кнопку выше. Другие способы — «＋» на вкладке «Подписки».'
                    : _emptyText(c),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.sub),
              ),
              if (!none && _antiOn(c)) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    key: const Key('antiblock-off'),
                    onPressed: () => toggleAntiblock(context, c),
                    icon: Icon(Icons.shield_outlined, color: p.acc, size: 18),
                    label: Text(
                      'Выключить Анти БПЛА',
                      style: TextStyle(
                        color: p.acc,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ];
    }
    return [
      ..._accordionSlivers(list, const EdgeInsets.fromLTRB(16, 0, 16, 0)),
      // room under the last row for the slide bar and the navigation (measured)
      SliverToBoxAdapter(
        child: SizedBox(key: const Key('list-end'), height: pad),
      ),
    ];
  }

  Widget _scroll(List<Widget> top, List<Widget> rest) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.list(children: top),
      ),
      ...rest,
    ],
  );

  Widget _homePage(
    BuildContext context,
    List<J> list,
    List<Widget> banners,
    double pad,
  ) {
    return _scroll([
      _CompactHero(c: c, p: p),
      _CurrentServer(c: c, p: p),
      for (final b in banners)
        Padding(padding: const EdgeInsets.only(top: 8), child: b),
      if (c.subs.isNotEmpty) _SubCard(c: c, p: p),
      if (list.isNotEmpty) _CountryChips(c: c, p: p, list: list),
    ], _listOrEmpty(context, list, pad));
  }

  Widget _serversPage(BuildContext context, List<J> all, String q, double pad) {
    final subs = c.subs;
    final sIdx = (int.tryParse(c.pref('subIdx', '0')) ?? 0)
        .clamp(0, math.max(0, subs.length - 1))
        .toInt();
    var list = all;
    final qq = q.trim().toLowerCase();
    if (qq.isNotEmpty) {
      list = [
        for (final s in list)
          if ('${s['name'] ?? ''} ${regionName[region('${s['name'] ?? ''}') ?? ''] ?? ''} ${NoxController.proto(s)}'
              .toLowerCase()
              .contains(qq))
            s,
      ];
    }
    final ids = [for (final s in list) s['id'] as String];
    return _scroll([
      _pageTitle(
        p,
        'Серверы',
        onAdd: () => addSheet(context, c, p),
        addTip: 'Добавить подписку или сервер',
        extra: IconButton(
          key: const Key('srv-list-menu'),
          tooltip: 'Сортировка и фильтры',
          onPressed: () =>
              listSheet(context, c, p, caption: listCaption(c, list.length)),
          icon: Icon(Icons.tune_rounded, color: p.txt),
        ),
      ),
      GlassCard(
        p: p,
        r: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: p.sub, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const Key('srv-search'),
                controller: _srvQueryCtl,
                onChanged: (v) => srvQuery.value = v,
                style: TextStyle(color: p.txt, fontSize: 15),
                cursorColor: p.acc,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Поиск страны или сервера',
                  hintStyle: TextStyle(color: p.ter, fontSize: 15),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            if (q.isNotEmpty)
              InkWell(
                onTap: () {
                  _srvQueryCtl.clear();
                  srvQuery.value = '';
                },
                child: Icon(Icons.close_rounded, color: p.sub, size: 18),
              ),
          ],
        ),
      ),
      if (subs.length > 1) ...[
        const SizedBox(height: 10),
        _Seg(
          p: p,
          items: [
            for (final (i, s) in subs.indexed)
              (_subName(s, i), '${_subCount(c, s)}'),
          ],
          on: sIdx,
          onTap: (i) => c.setPrefLive('subIdx', '$i'),
        ),
      ],
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _actBtn(
              p,
              Icons.bolt_rounded,
              'Проверить пинг',
              () => c.ping(ids),
              key: TourKeys.ping,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actBtn(p, Icons.refresh_rounded, 'Обновить', () async {
              dynamic r;
              for (final b in c.subs) {
                r = await c.call('RefreshSub', [b['id']]);
              }
              if (context.mounted) await finishRefresh(context, c, r);
            }),
          ),
        ],
      ),
      if (list.isNotEmpty) _CountryChips(c: c, p: p, list: list),
    ], _listOrEmpty(context, list, pad));
  }

  Widget _subsPage(BuildContext context, double pad) => ListView(
    padding: EdgeInsets.fromLTRB(16, 8, 16, pad),
    children: [
      _pageTitle(
        p,
        'Подписки',
        onAdd: () => addSheet(context, c, p),
        addTip: 'Добавить подписку',
      ),
      if (c.subs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Подписок пока нет. Скопируйте ссылку на подписку и нажмите «Добавить из буфера» или «＋».',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub),
          ),
        ),
      for (final b in c.subs) _SubCard(c: c, p: p, fixed: b),
      const SizedBox(height: 14),
      ClipboardAddButton(c: c, p: p),
    ],
  );

  Widget _settingsPage(BuildContext context, double pad) {
    final upd = c.s['update'] is Map;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, pad),
      children: [
        _pageTitle(p, 'Настройки'),
        _linksRow(context, p),
        const SizedBox(height: 12),
        GlassCard(
          p: p,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              brandLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Прокси'),
                          TextSpan(
                            text: '+',
                            style: TextStyle(color: p.acc),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        color: p.txt,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Версия ${c.s['version'] ?? ''}',
                      style: TextStyle(color: p.sub, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sectionLabel(p, 'Быстрые'),
        if (!desktopUi || winShell(c))
          item(
            p,
            'МТС прокси',
            desc: c.mtsOn
                ? 'Включён: только AnyTLS, NaiveProxy, mieru, VLESS и прокси'
                : (isWindows || winShellForce)
                ? 'Через 192.168.192.192 (интернет МТС, APN wap.mts.ru)'
                : 'Через APN МТС (нужна SIM МТС)',
            trailing: sw(p, c.mtsOn),
            onTap: () => toggleMts(context, c),
          ),
        KeyedSubtree(
          key: TourKeys.mail,
          child: item(
            p,
            upd ? 'Доступно обновление' : 'Обновления и сообщения',
            desc: upd ? 'Нажмите, чтобы установить' : 'Почта от разработчика',
            color: upd ? p.acc : null,
            arrow: true,
            onTap: () => updateSheet(context, c, p),
          ),
        ),
        _sectionLabel(p, 'Все настройки'),
        Builder(
          builder: (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: settingsItems(context, c, p, ctx),
          ),
        ),
      ],
    );
  }
}
