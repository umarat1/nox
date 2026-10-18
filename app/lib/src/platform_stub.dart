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
