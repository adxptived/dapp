// Локальные уведомления: конец матча, сводки, смена лидера, Steam, сезоны, обновления.
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/refdata.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import '../ui/screens/digest.dart';

class Notifier {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (_) {}
  }

  static Future<void> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  static const _channels = {
    'matches': 'Конец матча',
    'digest': 'Сводки',
    'contest': 'Соревнование и сезоны',
    'steam': 'Steam-профили',
    'updates': 'Обновления приложения',
  };

  static Future<void> show(String channel, int id, String title, String body) async {
    await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'dapp_$channel',
            _channels[channel] ?? channel,
            importance: channel == 'matches' ? Importance.high : Importance.defaultImportance,
            priority: channel == 'matches' ? Priority.high : Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body),
            color: const Color(0xFFD6F84C),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  /// Обработать события обновления: оповещения о матчах и смене Steam-профиля.
  static Future<void> handleEvents(Store store, List<StoreEvent> events) async {
    final s = store.settings;
    final now = nowTs();
    // матчи: группируем по match_id + сторона (совместная игра — одно уведомление)
    final byMatch = <String, List<StoreEvent>>{};
    for (final e in events.where((e) => e.kind == 'match' && e.match != null)) {
      final m = e.match!;
      final last = e.player.lastNotifiedMatch;
      if (last != null && m.matchId <= last) continue;
      if (now - m.endTime > 6 * 3600) continue; // старые игры (догрузка истории) не объявляем
      byMatch.putIfAbsent('${m.matchId}:${m.isRadiant}', () => []).add(e);
    }
    for (final group in byMatch.values) {
      final m = group.first.match!;
      final won = m.won;
      final lines = <String>[];
      for (final e in group) {
        final pm = e.match!;
        final mmr = store.summary(e.player, 'day').currentMmr;
        lines.add('${e.player.name} — ${RefData.I.heroName(pm.heroId)} ${pm.kills}/${pm.deaths}/${pm.assists}'
            ' · ${matchMmrDelta(pm, s.mmrStep) > 0 ? '+' : ''}${matchMmrDelta(pm, s.mmrStep)}${mmr != null ? ' (≈$mmr)' : ''}');
      }
      final who = group.length > 1 ? 'Пати' : group.first.player.name;
      if (s.notifyMatches) {
        await show('matches', m.matchId % 1000000000, '${won ? '✅ Победа' : '❌ Поражение'} · $who',
            '${lines.join('\n')}\n⏱ ${(m.duration ?? 0) ~/ 60} мин');
      }
    }
    // запоминаем последние матчи, чтобы не повторяться
    for (final p in store.players) {
      final ms = store.matchesOf(p);
      if (ms.isNotEmpty && (p.lastNotifiedMatch == null || ms.last.matchId > p.lastNotifiedMatch!)) {
        p.lastNotifiedMatch = ms.last.matchId;
      }
    }
    if (s.steamChanges) {
      var k = 0;
      for (final e in events.where((e) => e.kind == 'steam')) {
        await show('steam', 900000 + k++, '👤 Steam', e.text ?? '');
      }
    }
  }

  /// Сводки, лидеры номинаций и сезоны — вызывается после обновления (в фоне и в приложении).
  static Future<void> periodic(Store store) async {
    final s = store.settings;
    final d = DateTime.now();
    final today = d.year * 10000 + d.month * 100 + d.day;
    if (s.dailyDigest && d.hour >= s.digestHour && s.lastDigestDay != today) {
      s.lastDigestDay = today;
      final played = store.players.any((p) => store.matchesOf(p).any((m) => m.startTime >= nowTs() - 86400));
      if (played) await show('digest', 1, '📊 Сводка за сутки', buildDigestText(store, 'day'));
    }
    if (s.weeklyDigest && d.weekday == DateTime.monday && d.hour >= s.digestHour && s.lastWeeklyDay != today) {
      s.lastWeeklyDay = today;
      final played = store.players.any((p) => store.matchesOf(p).any((m) => m.startTime >= nowTs() - 7 * 86400));
      if (played) await show('digest', 2, '🗓 Итоги недели', buildDigestText(store, 'week'));
    }
    if (s.leaderChanges) {
      final standings = computeStandings(store.named('week'), step: s.mmrStep);
      final now = currentLeaders(standings);
      if (s.leaders.isNotEmpty) {
        var k = 0;
        for (final st in standings) {
          final leader = now[st.key];
          final old = s.leaders[st.key];
          if (leader == null || old == null || old == leader) continue;
          await show('contest', 500 + k++, '${st.emoji} ${st.title}', '$leader обошёл $old — ${st.entries.first.text}');
        }
      }
      s.leaders = now;
    }
    final closed = await store.checkSeasons();
    if (closed != null) {
      await show('contest', 700 + closed.number,
          '🏁 Сезон ${closed.number} завершён',
          closed.champion == null ? 'Чемпиона нет. Начался следующий сезон.' : '🏆 Чемпион: ${closed.champion}. Начался следующий сезон.');
    }
    await store.save();
  }
}
