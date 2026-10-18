import 'package:flutter/material.dart';

import 'controller.dart';
import 'platform.dart';
import 'theme.dart';

String splitDesc(Map<String, dynamic> s) {
  final n = ((s['splitApps'] as List?) ?? []).length;
  return switch (s['splitMode']) {
    'include' when n > 0 => 'Только выбранные: $n',
    'exclude' when n > 0 => 'Все, кроме выбранных: $n',
    _ => 'Все приложения',
  };
}

/// Android per-app split tunnelling: off / only selected apps / all except selected.
class SplitAppsPage extends StatefulWidget {
  final NoxController c;
  const SplitAppsPage({super.key, required this.c});
  @override
  State<SplitAppsPage> createState() => _SplitAppsPageState();
}

class _SplitAppsPageState extends State<SplitAppsPage> {
  List<AppInfo>? apps;
  late String mode;
  late Set<String> sel;
  late final Set<String>
  pinned; // selected when the page opened: listed first, order stays put
  String q = '';
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    final s = widget.c.settings;
    mode = (s['splitMode'] as String?) ?? '';
    sel = {...((s['splitApps'] as List?) ?? []).map((e) => '$e')};
    pinned = {...sel};
    listApps().then((a) {
      if (mounted) setState(() => apps = a);
    });
  }

  Future<void> _save() async {
    if (!dirty) return;
    dirty = false;
    final c = widget.c;
    await c.saveSettings({
      'splitMode': mode,
      'splitApps': sel.toList()..sort(),
    });
    // the app list is fixed when the TUN starts: reconnect to apply
    if (c.connected) {
      await c.call('Disconnect');
      await c.call('Connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = Pal.of(c.settings['theme'] as String?);
    final all = apps;
    final ql = q.toLowerCase();
    final shown = all
        ?.where(
          (a) =>
              ql.isEmpty ||
              a.label.toLowerCase().contains(ql) ||
              a.pkg.toLowerCase().contains(ql),
        )
        .toList();
    // apps selected when the page opened come first (no jumping while ticking boxes)
    shown?.sort((a, b) {
      final x = pinned.contains(a.pkg) ? 0 : 1,
          y = pinned.contains(b.pkg) ? 0 : 1;
      return x != y
          ? x - y
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    Widget modeChip(String k, String t) {
      final on = mode == k;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: ChoiceChip(
          label: Text(t),
          selected: on,
          showCheckmark: false,
          selectedColor: p.acc,
          backgroundColor: p.chip,
          labelStyle: TextStyle(
            color: on ? Colors.white : p.txt,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: on ? p.acc : p.line),
          onSelected: (_) => setState(() {
            mode = k;
            dirty = true;
          }),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.txt,
        title: const Text('Приложения через VPN'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              children: [
                modeChip('', 'Все приложения'),
                modeChip('include', 'Только выбранные'),
                modeChip('exclude', 'Все, кроме выбранных'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(switch (mode) {
              'include' =>
                'Через VPN идут только отмеченные приложения, остальные — напрямую.',
              'exclude' => 'Отмеченные приложения идут напрямую, мимо VPN.',
              _ =>
                'Весь трафик устройства идёт через VPN. Список ниже сохраняется.',
            }, style: TextStyle(color: p.sub, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              style: TextStyle(color: p.txt),
              decoration: InputDecoration(
                hintText: 'Поиск',
                hintStyle: TextStyle(color: p.ter),
                prefixIcon: Icon(Icons.search, color: p.sub),
                filled: true,
                fillColor: p.card,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: shown == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final a = shown[i];
                      final on = sel.contains(a.pkg);
                      return CheckboxListTile(
                        value: on,
                        activeColor: p.acc,
                        checkColor: Colors.white,
                        secondary: SizedBox(
                          width: 36,
                          height: 36,
                          child: a.icon != null
                              ? Image.memory(a.icon!, gaplessPlayback: true)
                              : Icon(Icons.android, color: p.sub),
                        ),
                        title: Text(a.label, style: TextStyle(color: p.txt)),
                        subtitle: Text(
                          a.pkg,
                          style: TextStyle(color: p.ter, fontSize: 11),
                        ),
                        onChanged: (v) => setState(() {
                          v == true ? sel.add(a.pkg) : sel.remove(a.pkg);
                          if (mode == '' && sel.isNotEmpty) mode = 'exclude';
                          dirty = true;
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _save();
    super.dispose();
  }
}
