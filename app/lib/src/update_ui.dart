import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'api.dart';
import 'controller.dart';
import 'platform.dart';
import 'theme.dart';

/// «Обновить»: starts (or re-attaches to) the engine's update job and shows its progress.
/// Closing the dialog does not stop the download; the notification keeps showing it.
Future<void> openUpdate(BuildContext context, NoxController c, Pal p) =>
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(c: c, p: p),
    );

String mb(num b) {
  final v = b / (1024 * 1024);
  return v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

String speedText(num bps) {
  if (bps <= 0) return '';
  if (bps >= 1024 * 1024) return '${(bps / 1048576).toStringAsFixed(1)} МБ/с';
  return '${(bps / 1024).toStringAsFixed(0)} КБ/с';
}

String etaText(num left, num bps) {
  if (bps <= 0 || left <= 0) return '';
  final s = (left / bps).round();
  if (s < 60) return 'ещё $s с';
  return 'ещё ${(s / 60).ceil()} мин';
}

class UpdateDialog extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final Duration poll;
  const UpdateDialog({
    super.key,
    required this.c,
    required this.p,
    this.poll = const Duration(milliseconds: 400),
  });
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  Map<String, dynamic> u = {'stage': 'download', 'total': -1, 'done': 0};
  Timer? _t;
  String _lastNote = '';

  NoxApi get api => widget.c.api;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final r = await api.call('UpdateStart');
      if (r is Map) _set(r.cast<String, dynamic>());
    } on NoxError catch (e) {
      _set({'stage': 'error', 'error': e.message});
    }
    _t?.cancel();
    _t = Timer.periodic(widget.poll, (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final r = await api.call('UpdateProgress');
      if (r is Map) _set(r.cast<String, dynamic>());
    } catch (_) {}
  }

  String get stage => '${u['stage'] ?? ''}';
  int get done => (u['done'] as num?)?.toInt() ?? 0;
  int get total => (u['total'] as num?)?.toInt() ?? -1;
  double? get frac => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  void _set(Map<String, dynamic> m) {
    if (!mounted) return;
    setState(() => u = m);
    if (u['active'] != true) _t?.cancel();
    _notify();
  }

  void _notify() {
    final pct = frac == null ? -1 : (frac! * 100).floor();
    final String text;
    switch (stage) {
      case 'download':
        text = total > 0
            ? '${mb(done)} из ${mb(total)} МБ · ${speedText(u['speed'] ?? 0)}'
            : '${mb(done)} МБ';
      case 'verify':
        text = 'Проверка файла…';
      case 'install':
      case 'done':
        text = 'Подтвердите установку';
      case 'error':
        text = '${u['error']}';
      default:
        text = '';
    }
    final key = '$stage|$pct|$text';
    if (key == _lastNote) return;
    _lastNote = key;
    updNotify(stage.isEmpty ? 'clear' : stage, pct, text);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _steps(Pal p) {
    const names = [
      ('download', 'Загрузка'),
      ('verify', 'Проверка'),
      ('install', 'Установка'),
    ];
    final at = switch (stage) {
      'verify' => 1,
      'install' || 'done' => 2,
      _ => 0,
    };
    final failed = stage == 'error' || stage == 'canceled';
    // fixed connectors + scaleDown: fits a 360 dp phone at font 1.3 and a TV alike
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (_, n)) in names.indexed) ...[
            if (i > 0)
              Container(
                width: 28,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= at ? p.acc : p.line,
              ),
            Icon(
              i < at || stage == 'done'
                  ? Icons.check_circle
                  : (i == at && failed ? Icons.error : Icons.circle_outlined),
              size: 18,
              color: i == at && failed ? p.red : (i <= at ? p.acc2 : p.sub),
            ),
            const SizedBox(width: 4),
            Text(
              n,
              style: TextStyle(
                color: i == at ? p.txt : p.sub,
                fontSize: 12,
                fontWeight: i == at ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _btn(
    Pal p,
    String t,
    VoidCallback f, {
    bool main = false,
    bool af = false,
  }) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: main
        ? FilledButton(
            autofocus: af,
            style: FilledButton.styleFrom(backgroundColor: p.acc),
            onPressed: f,
            child: Text(t),
          )
        : OutlinedButton(
            autofocus: af,
            onPressed: f,
            child: Text(t, style: TextStyle(color: p.txt)),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final v = '${u['version'] ?? ''}';
    final speed = (u['speed'] as num?) ?? 0;
    final String head;
    final String sub;
    switch (stage) {
      case 'verify':
        head = 'Проверка…';
        sub = 'Сверяем контрольную сумму и подпись';
      case 'install':
        head = 'Установка…';
        sub = 'Открываем системный установщик';
      case 'done':
        head = 'Подтвердите установку';
        sub = Platform.isMacOS
            ? 'В открывшемся окне перетащите Nox в «Программы» и замените старую версию, затем перезапустите Nox.'
            : 'В системном окне нажмите «Обновить». Если окна нет — разрешите установку из этого источника и нажмите «Повторить».';
      case 'error':
        head = 'Не удалось обновить';
        sub = '${u['error'] ?? ''}';
      case 'canceled':
        head = 'Загрузка остановлена';
        sub = done > 0
            ? 'Скачано ${mb(done)} МБ — «Повторить» продолжит с этого места.'
            : '';
      default:
        head = 'Загрузка${u['resumed'] == true ? ' (продолжение)' : ''}';
        sub = total > 0
            ? '${mb(done)} из ${mb(total)} МБ'
            : (done > 0 ? '${mb(done)} МБ' : 'Подключение…');
    }
    final busy = stage == 'download' || stage == 'verify' || stage == 'install';
    final pct = frac == null ? null : (frac! * 100).floor();
    return Dialog(
      backgroundColor: p.hero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                v.isEmpty ? 'Обновление Nox' : 'Обновление до $v',
                style: TextStyle(
                  color: p.txt,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _steps(p),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      head,
                      style: TextStyle(
                        color: p.txt,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (stage == 'download' && pct != null)
                    Text(
                      '$pct%',
                      key: const Key('upd-pct'),
                      style: TextStyle(
                        color: p.acc2,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: switch (stage) {
                    'download' => frac,
                    'verify' || 'install' => null,
                    'done' => 1.0,
                    _ => frac ?? 0.0,
                  },
                  color: stage == 'error' ? p.red : p.acc,
                  backgroundColor: p.line,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                sub,
                style: TextStyle(
                  color: stage == 'error' ? p.red : p.sub,
                  fontSize: 12,
                ),
              ),
              if (stage == 'download' && speed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${speedText(speed)} · ${etaText(total - done, speed)}',
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  if (stage == 'download')
                    _btn(p, 'Отмена', () async {
                      try {
                        await api.call('UpdateCancel');
                      } catch (_) {}
                      _poll();
                    }, af: true),
                  if (stage == 'error' ||
                      stage == 'canceled' ||
                      stage == 'done') ...[
                    _btn(p, 'Закрыть', () {
                      updNotify('clear', 0, '');
                      Navigator.pop(context);
                    }),
                    _btn(p, 'Повторить', _start, main: true, af: true),
                  ],
                  if (busy && stage != 'download')
                    _btn(p, 'Скрыть', () => Navigator.pop(context), af: true),
                  if (stage == 'download')
                    _btn(p, 'Скрыть', () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2.1.7: «Доступна версия X» with the changelog (latest.json `changelog` → `notes`).
/// Shown once per version on launch (and from the envelope / settings). When the install
/// is below latest.json `minSupported` the engine marks the update `mandatory`: no «Позже»,
/// back / tap outside do nothing, and it comes back until the update is installed.
bool _offerOpen = false;
final Set<String> _offered = {};

bool get updateOfferOpen => _offerOpen;

Future<void> offerUpdate(BuildContext context, NoxController c, Pal p) async {
  final u = c.s['update'];
  if (u is! Map || _offerOpen) return;
  final m = u.cast<String, dynamic>();
  final v = '${m['versionName'] ?? ''}';
  final mandatory = m['mandatory'] == true;
  _offered.add(v);
  _offerOpen = true;
  try {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: !mandatory,
      builder: (_) => UpdateOfferDialog(
        p: p,
        version: v,
        current: '${c.s['version'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        mandatory: mandatory,
      ),
    );
    if (!context.mounted) return;
    if (go == true) {
      await openUpdate(context, c, p);
    } else if (!mandatory) {
      await c.call('HideUpdate', [v]);
      await c.refresh();
    }
  } finally {
    _offerOpen = false;
  }
  // A mandatory update re-offers itself after the progress dialog closes.
  if (mandatory && context.mounted) {
    await c.refresh();
    if (context.mounted && c.s['update'] is Map) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) offerUpdate(context, c, p);
      });
    }
  }
}

/// Launch: offer each new version once per app run (mandatory ones always).
void maybeOfferUpdate(BuildContext context, NoxController c, Pal p) {
  final u = c.s['update'];
  if (u is! Map || _offerOpen) return;
  final v = '${u['versionName'] ?? ''}';
  // once per version per run; a mandatory one re-offers itself from offerUpdate()
  if (_offered.contains(v)) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) offerUpdate(context, c, p);
  });
}

@visibleForTesting
void resetUpdateOffers() {
  _offered.clear();
  _offerOpen = false;
}

class UpdateOfferDialog extends StatelessWidget {
  final Pal p;
  final String version, current, notes;
  final bool mandatory;
  const UpdateOfferDialog({
    super.key,
    required this.p,
    required this.version,
    required this.current,
    required this.notes,
    this.mandatory = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !mandatory,
      child: Dialog(
        backgroundColor: p.hero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded, color: p.acc2, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Доступна версия $version',
                        style: TextStyle(
                          color: p.txt,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mandatory
                      ? 'Версия $current больше не поддерживается — обновите приложение, чтобы продолжить.'
                      : 'Установлена $current',
                  style: TextStyle(
                    color: mandatory ? p.amb : p.sub,
                    fontSize: 12.5,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Что нового',
                    style: TextStyle(
                      color: p.txt,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: TextStyle(
                          color: p.sub,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!mandatory)
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Позже', style: TextStyle(color: p.txt)),
                      ),
                    FilledButton(
                      autofocus: true,
                      style: FilledButton.styleFrom(backgroundColor: p.acc),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Обновить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
