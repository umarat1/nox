import 'package:flutter/foundation.dart';

import 'api.dart';
import 'mock.dart';

NoxApi createApi() => MockApi();
bool get isDesktop => false;
bool get isWindows => false;
Future<void> initDesktop(
  void Function() onShow,
  Future<void> Function() onQuit,
  Future<void> Function() onToggle, {
  bool hidden = false,
}) async {}
Future<void> updateTray(bool connected, String server) async {}
Future<String?> applySystemProxy(bool on, int port) async => null;
Future<String?> setUserAutostart(bool on) async => null;
Future<String?> readLegacyState() async => null;
bool get isAndroid => false;
Future<bool> prepareVpn() async => true;
Future<bool> isTvDevice() async => const bool.fromEnvironment('NOX_MOCK_TV');
Future<bool> openUrl(String url) async => false;
Future<void> legacyImported() async {}
final windowShown = ValueNotifier<bool>(true);
bool get canFullScreen => const bool.fromEnvironment('NOX_MOCK_DESKTOP');
final fullScreen = ValueNotifier<bool>(false);
Future<void> toggleFullScreen([bool? on]) async =>
    fullScreen.value = on ?? !fullScreen.value;

bool get canCaptcha => false;
Future<String> solveCaptcha(String url) async => 'error:unsupported';
bool get canSplitApps => const bool.fromEnvironment('NOX_MOCK_DESKTOP');

class AppInfo {
  final String pkg, label;
  final Uint8List? icon;
  AppInfo(this.pkg, this.label, this.icon);
}

Future<List<AppInfo>> listApps() async => [
  AppInfo('org.telegram.messenger', 'Telegram', null),
  AppInfo('com.google.android.youtube', 'YouTube', null),
  AppInfo('com.android.chrome', 'Chrome', null),
  AppInfo('ru.sberbankmobile', 'СберБанк', null),
  AppInfo('com.vkontakte.android', 'VK', null),
];
