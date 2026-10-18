import 'package:flutter/material.dart';

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
  runApp(NoxApp(c: c));
  c.start();
}

class NoxApp extends StatelessWidget {
  final NoxController c;
  const NoxApp({super.key, required this.c});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nox',
    debugShowCheckedModeBanner: false,
    theme: materialTheme(Pal.dark),
    locale: const Locale('ru'),
    // D-pad / remote: arrows move focus, centre button activates (Android TV, M2)
    shortcuts: {...WidgetsApp.defaultShortcuts},
    home: Home(c: c),
  );
}
