// Фоновая проверка матчей (WorkManager на Android, Background Fetch на iOS).
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/store.dart';
import 'notifier.dart';
import 'updater.dart';

const _taskName = 'dapp-poll';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await runBackgroundPoll();
    } catch (_) {}
    return true;
  });
}

/// Одна итерация фона: обновить игроков, разослать оповещения, сводки, проверить обновление приложения.
Future<void> runBackgroundPoll() async {
  final store = await Store.open();
  if (store.players.isEmpty) return;
  await Notifier.init();
  final events = await store.refreshAll();
  await Notifier.handleEvents(store, events);
  await Notifier.periodic(store);
  if (store.settings.notifyUpdates) {
    try {
      final u = await Updater.check(store);
      if (u != null) {
        await Notifier.show('updates', 3, 'Доступно обновление ${u.version}', 'Откройте Dota Party, чтобы установить.');
      }
    } catch (_) {}
  }
  await store.save();
}

class Background {
  static Future<void> init() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (_) {}
  }

  static Future<void> schedule(int minutes) async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (_) {}
  }
}
