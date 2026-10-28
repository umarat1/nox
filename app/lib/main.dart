import 'src/captcha_win.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/controller.dart';
import 'src/home.dart';
import 'src/platform.dart';
import 'src/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final c = NoxController(createApi());
  await initDesktop(
    () => c.refresh(),
    () async {
      // Quit closes only the window process; the VPN keeps running in the service.
      WidgetsBinding.instance.handleRequestAppExit();
    },
    () => c.toggle(),
    hidden: args.contains('--tray'),
  );
  if (canFullScreen) {
    // F11 toggles fullscreen, Esc leaves it (desktop)
    HardwareKeyboard.instance.addHandler((e) {
      if (e is! KeyDownEvent) return false;
      if (e.logicalKey == LogicalKeyboardKey.f11) {
        toggleFullScreen();
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape && fullScreen.value) {
        toggleFullScreen(false);
        return true;
      }
      return false;
    });
  }
  runApp(NoxApp(c: c));
  c.start();
}

class NoxApp extends StatelessWidget {
  final NoxController c;
  const NoxApp({super.key, required this.c});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (_, _) {
      final pal = Pal.of(
        c.settings['theme'] as String?,
        c.pref('tpl', 'glass'),
      );
      vol3d = vol3dFromUi(c.ui);
      graphStyle = graphFromUi(c.ui);
      return MaterialApp(
        navigatorKey: noxNav,
        title: 'Nox',
        debugShowCheckedModeBanner: false,
        theme: materialTheme(pal),
        locale: const Locale('ru'),
        shortcuts: {...WidgetsApp.defaultShortcuts},
        builder: (ctx, child) {
          SystemChrome.setSystemUIOverlayStyle(systemBars(pal));
          return LayoutBuilder(
            builder: (ctx, box) {
              final mq0 = MediaQuery.of(ctx);
              final mq = box.maxWidth.isFinite && box.maxHeight.isFinite
                  ? mq0.copyWith(size: Size(box.maxWidth, box.maxHeight))
                  : mq0;
              final fs = c.fontScale;
              final us = c.uiScale;
              // Font via textScaler; UI density by scaling the logical viewport (TV defaults larger).
              Widget body = MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(fs)),
                child: child ?? const SizedBox.shrink(),
              );
              if ((us - 1.0).abs() > 0.01) {
                body = OverflowBox(
                  minWidth: mq.size.width / us,
                  maxWidth: mq.size.width / us,
                  minHeight: mq.size.height / us,
                  maxHeight: mq.size.height / us,
                  alignment: Alignment.topCenter,
                  child: Transform.scale(
                    scale: us,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: mq.size.width / us,
                      height: mq.size.height / us,
                      child: MediaQuery(
                        data: mq.copyWith(
                          size: Size(mq.size.width / us, mq.size.height / us),
                          textScaler: TextScaler.linear(fs),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              }
              return body;
            },
          );
        },
        home: Home(c: c),
      );
    },
  );
}
