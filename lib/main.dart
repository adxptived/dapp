import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/store.dart';
import 'services/background.dart';
import 'services/notifier.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // больше места под раскодированные иконки героев, предметов и аватарки — чтобы не пропадали при прокрутке
  PaintingBinding.instance.imageCache
    ..maximumSize = 3000
    ..maximumSizeBytes = 256 << 20;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final store = await Store.open();
  // оповещения и сводки, когда приложение открыто
  Store.onEvents = (s, events) async {
    await Notifier.handleEvents(s, events);
    await Notifier.periodic(s);
  };
  await Notifier.init();
  await Background.init();
  await Background.schedule(store.settings.pollMinutes, wifiOnly: store.settings.bgWifiOnly);
  runApp(ChangeNotifierProvider.value(value: store, child: const DotaPartyApp()));
  Future.delayed(const Duration(seconds: 2), Notifier.requestPermission);
}

class DotaPartyApp extends StatelessWidget {
  const DotaPartyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dota Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: Shell(key: Shell.shellKey),
    );
  }
}
