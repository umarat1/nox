import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api.dart';
import 'mock.dart';

const _mock = bool.fromEnvironment('NOX_MOCK');

bool get isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
bool get isWindows => Platform.isWindows;
bool get isAndroid => Platform.isAndroid;

/// False while the desktop window is hidden (tray), minimized; animations pause on it.
final windowShown = ValueNotifier<bool>(true);

/// Desktop fullscreen (F11 / button); a no-op elsewhere.
bool get canFullScreen => isDesktop && !_mock;
final fullScreen = ValueNotifier<bool>(false);
Future<void> toggleFullScreen([bool? on]) async {
  if (!canFullScreen) return;
  final v = on ?? !await windowManager.isFullScreen();
  await windowManager.setFullScreen(v);
  fullScreen.value = v;
}

NoxApi createApi() =>
    _mock ? MockApi() : (Platform.isAndroid ? AndroidApi() : ServiceApi());

// ---------------------------------------------------------------- Android

const _ch = MethodChannel('nox/core');

class AppInfo {
  final String pkg, label;
  final Uint8List? icon;
  AppInfo(this.pkg, this.label, this.icon);
}

/// Android: the engine runs in this process (gomobile AAR); Kotlin forwards the calls.
class AndroidApi implements NoxApi {
  @override
  String get transport => 'встроенное ядро';

  @override
  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    final r = await _ch.invokeMethod<String>('call', {
      'm': method,
      'a': jsonEncode(args),
    });
    final j = jsonDecode(r ?? '{}') as Map<String, dynamic>;
    if (j['e'] != null) throw NoxError(j['e'].toString());
    return j['r'];
  }
}

/// VPN permission (VpnService.prepare) and, on Android 13+, the notification permission.
/// Prefer the display's highest refresh rate (Flutter ticker / graph then run at panel Hz).
Future<void> requestHighRefreshRate() async {
  if (!Platform.isAndroid || _mock) return;
  try {
    await _ch.invokeMethod('setHighRefresh');
  } catch (_) {}
}

Future<bool> prepareVpn() async {
  if (!Platform.isAndroid || _mock) return true;
  return await _ch.invokeMethod<bool>('prepareVpn') ?? false;
}

/// Android TV / Google TV (leanback): two-pane layout, D-pad focus, autofocus on power.
Future<bool> isTvDevice() async {
  if (!Platform.isAndroid || _mock) return false;
  return await _ch.invokeMethod<bool>('isTv') ?? false;
}

/// Android: VK captcha page for qWDTT in a WebView; success_token or "error:…".
bool get canCaptcha => Platform.isAndroid && !_mock;
Future<String> solveCaptcha(String url) async {
  if (!canCaptcha) return 'error:unsupported';
  try {
    return await _ch.invokeMethod<String>('solveCaptcha', {'url': url}) ??
        'error:cancelled';
  } catch (_) {
    return 'error:webview';
  }
}

/// Android: launchable apps for per-app split tunnelling.
bool get canSplitApps => Platform.isAndroid && !_mock;
Future<List<AppInfo>> listApps() async {
  if (!canSplitApps) return [];
  final r = await _ch.invokeMethod<List>('listApps') ?? [];
  return [
    for (final m in r.cast<Map>())
      AppInfo('${m['pkg']}', '${m['label']}', m['icon'] as Uint8List?),
  ];
}

Future<bool> openUrl(String url) async {
  try {
    if (Platform.isAndroid) {
      return await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    }
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return true;
    }
    await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [url]);
    return true;
  } catch (_) {
    return false;
  }
}

/// After a successful import the old 0.7.x file is renamed so it is not imported again.
Future<void> legacyImported() async {
  if (Platform.isAndroid && !_mock) await _ch.invokeMethod('legacyDone');
}

/// Talks to the noxd service. ipc.json (port + token) is written by the service into its data
/// directory; on Windows %ProgramData%\Nox with an ACL that lets local users read it.
class ServiceApi implements NoxApi {
  int? _port;
  String? _token;
  final _client = http.Client();

  static String ipcPath() {
    if (Platform.isWindows) {
      final pd = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
      return '$pd\\Nox\\ipc.json';
    }
    final home = Platform.environment['HOME'] ?? '.';
    if (Platform.isMacOS)
      return '$home/Library/Application Support/Nox/ipc.json';
    return '$home/.config/Nox/ipc.json';
  }

  Future<void> _load() async {
    final f = File(ipcPath());
    if (!await f.exists()) {
      throw NoxError(
        'Служба Nox не запущена. Переустановите Nox или запустите службу «Nox VPN».',
      );
    }
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    _port = j['port'] as int;
    _token = j['token'] as String;
  }

  @override
  String get transport => 'служба noxd';

  @override
  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_port == null || attempt > 0) await _load();
      try {
        final r = await _client
            .post(
              Uri.parse('http://127.0.0.1:$_port/rpc'),
              headers: {
                'X-Nox-Token': _token!,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'m': method, 'a': args}),
            )
            .timeout(const Duration(seconds: 60));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (r.statusCode == 403 && attempt == 0)
          continue; // service restarted: new token
        if (j['e'] != null) throw NoxError(j['e'].toString());
        return j['r'];
      } on SocketException {
        if (attempt == 1) throw NoxError('Нет связи со службой Nox');
      }
    }
    throw NoxError('Нет связи со службой Nox');
  }
}

// ---------------------------------------------------------------- desktop shell

class _TrayHandler with TrayListener, WindowListener {
  final void Function() onShow;
  final Future<void> Function() onQuit, onToggle;
  _TrayHandler(this.onShow, this.onQuit, this.onToggle);
  @override
  void onTrayIconMouseDown() => onShow();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'show':
        onShow();
      case 'toggle':
        onToggle();
      case 'quit':
        onQuit();
    }
  }

  /// Closing the window only hides it: the VPN lives in the service and keeps running.
  @override
  void onWindowClose() {
    windowShown.value = false;
    windowManager.hide();
  }

  @override
  void onWindowMinimize() => windowShown.value = false;
  @override
  void onWindowRestore() => windowShown.value = true;
  @override
  void onWindowFocus() => windowShown.value = true;
  @override
  void onWindowEnterFullScreen() => fullScreen.value = true;
  @override
  void onWindowLeaveFullScreen() => fullScreen.value = false;
}

_TrayHandler? _tray;

Future<void> initDesktop(
  void Function() onShow,
  Future<void> Function() onQuit,
  Future<void> Function() onToggle, {
  bool hidden = false,
}) async {
  if (!isDesktop || _mock) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(460, 860),
      minimumSize: Size(400, 620),
      title: 'Nox',
      center: true,
    ),
    () async {
      if (hidden) {
        windowShown.value = false;
        return; // autostart: tray only
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await windowManager.setPreventClose(true);
  _tray = _TrayHandler(
    () async {
      windowShown.value = true;
      await windowManager.show();
      await windowManager.focus();
      onShow();
    },
    onQuit,
    onToggle,
  );
  trayManager.addListener(_tray!);
  windowManager.addListener(_tray!);
  try {
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icon.ico' : 'assets/icon.png',
    );
  } catch (e) {
    debugPrint('tray: $e');
  }
  await updateTray(false, '');
}

Future<void> updateTray(bool connected, String server) async {
  if (_tray == null) return;
  await trayManager.setToolTip(
    connected ? 'Nox — подключено: $server' : 'Nox — отключено',
  );
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: 'Открыть Nox'),
        MenuItem(key: 'toggle', label: connected ? 'Отключить' : 'Подключить'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Выход (VPN остаётся включённым)'),
      ],
    ),
  );
}

Future<String?> _reg(List<String> args) async {
  final r = await Process.run('reg', args);
  return r.exitCode == 0 ? null : (r.stderr.toString().trim());
}

/// Proxy mode: the system proxy is per user, so the UI (in the user's session) sets it.
Future<String?> applySystemProxy(bool on, int port) async {
  if (!Platform.isWindows) return null;
  const k = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  if (on) {
    return await _reg([
          'add',
          k,
          '/v',
          'ProxyServer',
          '/t',
          'REG_SZ',
          '/d',
          '127.0.0.1:$port',
          '/f',
        ]) ??
        await _reg([
          'add',
          k,
          '/v',
          'ProxyOverride',
          '/t',
          'REG_SZ',
          '/d',
          'localhost;127.*;10.*;172.16.*;192.168.*;<local>',
          '/f',
        ]) ??
        await _reg([
          'add',
          k,
          '/v',
          'ProxyEnable',
          '/t',
          'REG_DWORD',
          '/d',
          '1',
          '/f',
        ]);
  }
  return _reg([
    'add',
    k,
    '/v',
    'ProxyEnable',
    '/t',
    'REG_DWORD',
    '/d',
    '0',
    '/f',
  ]);
}

/// «Запуск вместе с Windows»: the UI starts at logon (no elevation needed — the core is a service).
Future<String?> setUserAutostart(bool on) async {
  if (!Platform.isWindows) return null;
  const k = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  if (on) {
    return _reg([
      'add',
      k,
      '/v',
      'Nox',
      '/t',
      'REG_SZ',
      '/d',
      '"${Platform.resolvedExecutable}" --tray',
      '/f',
    ]);
  }
  await _reg(['delete', k, '/v', 'Nox', '/f']);
  return null;
}

/// Subscriptions of Nox 0.8 / VPS from the user's profile, for the first start of 1.0.
Future<String?> readLegacyState() async {
  if (Platform.isAndroid) {
    return _mock ? null : _ch.invokeMethod<String>('legacyState');
  }
  final base = Platform.environment['LOCALAPPDATA'];
  if (base == null) return null;
  for (final d in ['Nox', 'VPS']) {
    final f = File('$base\\$d\\state.json');
    if (await f.exists()) return f.readAsString();
  }
  return null;
}

/// Android phones: a camera for scanning the TV's pairing QR (TVs usually have none).
Future<bool> hasCamera() async {
  if (!Platform.isAndroid || _mock) return false;
  try {
    return await _ch.invokeMethod<bool>('hasCamera') ?? false;
  } catch (_) {
    return false;
  }
}

/// Scans a QR (camera permission is asked right here, only when scanning).
/// Returns the text, null when cancelled, or "error:denied" / "error:nocamera".
Future<String?> scanQr() async {
  if (!Platform.isAndroid || _mock) return 'error:nocamera';
  try {
    return await _ch.invokeMethod<String>('scanQr');
  } catch (_) {
    return 'error:nocamera';
  }
}

/// nox://pair links opened from outside (the TV QR scanned with the system camera app).
final pairLinks = ValueNotifier<String?>(null);
bool _pairInit = false;
Future<void> initPairLinks() async {
  if (!Platform.isAndroid || _mock || _pairInit) return;
  _pairInit = true;
  _ch.setMethodCallHandler((call) async {
    if (call.method == 'pair') {
      pairLinks.value = '${call.arguments}';
      await _ch.invokeMethod('takePair');
    }
    return null;
  });
  try {
    final p = await _ch.invokeMethod<String>('takePair');
    if (p != null) pairLinks.value = p;
  } catch (_) {}
}

/// Android: mirror the update progress in a notification (pct < 0 = indeterminate,
/// state: download | verify | install | done | error | canceled | clear).
Future<void> updNotify(String state, int pct, String text) async {
  if (!Platform.isAndroid || _mock) return;
  try {
    await _ch.invokeMethod('updNotify', {
      'state': state,
      'pct': pct,
      'text': text,
    });
  } catch (_) {}
}
