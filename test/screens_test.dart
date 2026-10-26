// Рендер всех экранов на тестовых данных: ловит исключения и переполнения вёрстки,
// а с --update-goldens сохраняет скриншоты в test/shots/ (их смотрят глазами в CI).
import 'dart:io';
import 'dart:math';

import 'package:dapp/data/models.dart';
import 'package:dapp/data/refdata.dart';
import 'package:dapp/data/store.dart';
import 'package:dapp/logic/stats.dart';
import 'package:dapp/ui/screens/add_player.dart';
import 'package:dapp/ui/screens/compare.dart';
import 'package:dapp/ui/screens/contest.dart';
import 'package:dapp/ui/screens/digest.dart';
import 'package:dapp/ui/screens/duel.dart';
import 'package:dapp/ui/screens/go.dart';
import 'package:dapp/ui/screens/graph.dart';
import 'package:dapp/ui/screens/heroes.dart';
import 'package:dapp/ui/screens/matches_list.dart';
import 'package:dapp/ui/screens/matchups.dart';
import 'package:dapp/ui/screens/player.dart';
import 'package:dapp/ui/screens/records.dart';
import 'package:dapp/ui/screens/roles.dart';
import 'package:dapp/ui/screens/status.dart';
import 'package:dapp/ui/screens/together.dart';
import 'package:dapp/ui/shell.dart';
import 'package:dapp/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const heroes = {
  1: ('npc_dota_hero_antimage', 'Anti-Mage'),
  2: ('npc_dota_hero_axe', 'Axe'),
  5: ('npc_dota_hero_crystal_maiden', 'Crystal Maiden'),
  8: ('npc_dota_hero_juggernaut', 'Juggernaut'),
  11: ('npc_dota_hero_nevermore', 'Shadow Fiend'),
  14: ('npc_dota_hero_pudge', 'Pudge'),
  26: ('npc_dota_hero_lion', 'Lion'),
  35: ('npc_dota_hero_sniper', 'Sniper'),
  41: ('npc_dota_hero_faceless_void', 'Faceless Void'),
  44: ('npc_dota_hero_phantom_assassin', 'Phantom Assassin'),
  74: ('npc_dota_hero_invoker', 'Invoker'),
  86: ('npc_dota_hero_rubick', 'Rubick'),
  104: ('npc_dota_hero_legion_commander', 'Legion Commander'),
  106: ('npc_dota_hero_ember_spirit', 'Ember Spirit'),
  129: ('npc_dota_hero_mars', 'Mars'),
};

Store buildStore() {
  final rnd = Random(7);
  final store = Store.memory(Directory.systemTemp.createTempSync('dapp').path);
  store.settings.autoUpdateCheck = false;
  final now = nowTs();
  final names = ['Вася', 'Петя', 'Kolya228', 'Ann', 'Миша'];
  final skill = [0.58, 0.52, 0.47, 0.55, 0.44];
  final heroIds = heroes.keys.toList();
  // общие игры пати
  final shared = <int>[for (var i = 0; i < 40; i++) 7000000000 + i];
  for (var p = 0; p < names.length; p++) {
    final ms = <M>[];
    for (var i = 0; i < 90 + p * 7; i++) {
      final isShared = i < 40 && rnd.nextDouble() < 0.5;
      final id = isShared ? shared[i] : 7100000000 + p * 1000 + i;
      final start = now - (isShared ? i * 36000 : rnd.nextInt(60 * 86400));
      final radiantSide = isShared ? (i % 2 == 0) : rnd.nextBool();
      final won = isShared ? (i % 3 != 0) : rnd.nextDouble() < skill[p];
      final hero = heroIds[(p * 3 + rnd.nextInt(6)) % heroIds.length];
      final rad = [for (var k = 0; k < 5; k++) heroIds[(i + k) % heroIds.length]];
      final dire = [for (var k = 0; k < 5; k++) heroIds[(i + k + 5) % heroIds.length]];
      (radiantSide ? rad : dire)[0] = hero;
      ms.add(M(
        matchId: id,
        playerSlot: radiantSide ? p % 5 : 128 + p % 5,
        radiantWin: radiantSide == won,
        heroId: hero,
        startTime: start,
        duration: 1500 + rnd.nextInt(1800),
        lobbyType: 7,
        kills: rnd.nextInt(15),
        deaths: rnd.nextInt(10),
        assists: rnd.nextInt(20),
        partySize: isShared ? 2 : 1,
        radiant: rad,
        dire: dire,
        gpm: 300 + rnd.nextInt(450),
        xpm: 350 + rnd.nextInt(450),
        lastHits: 40 + rnd.nextInt(300),
        denies: rnd.nextInt(20),
        heroDamage: 8000 + rnd.nextInt(30000),
        towerDamage: rnd.nextInt(8000),
        heroHealing: rnd.nextInt(3000),
        netWorth: 8000 + rnd.nextInt(25000),
        level: 15 + rnd.nextInt(15),
        perfScore: 0.3 + rnd.nextDouble() * 0.5,
        bench: {'gold_per_min': rnd.nextDouble(), 'hero_damage_per_min': rnd.nextDouble(), 'xp_per_min': rnd.nextDouble()},
        enriched: true,
        position: 1 + rnd.nextInt(5),
        imp: rnd.nextInt(60) - 20,
        wards: rnd.nextInt(15),
        laneResult: rnd.nextInt(5) - 2,
      ));
    }
    store.seed(
      Player(
        accountId: 100000 + p,
        name: names[p],
        createdTs: now - 70 * 86400,
        anchors: [MmrAnchor(now - 70 * 86400, 3000 + p * 400)],
        rankTier: 30 + p * 10 + 3,
        lastRefresh: now,
        lastProfile: now,
        isMe: p == 0,
        goalMmr: p == 0 ? 4500 : null,
      ),
      ms,
    );
  }
  store.seasons.add(Season(number: 2, startTs: now - 10 * 86400, plannedEndTs: now + 20 * 86400, lengthDays: 30));
  store.seasons.insert(
      0,
      Season(number: 1, startTs: now - 50 * 86400, plannedEndTs: now - 20 * 86400, endTs: now - 20 * 86400, lengthDays: 30, champion: 'Вася', table: [
        {'player': 'Вася', 'points': 21, 'golds': 4},
        {'player': 'Ann', 'points': 15, 'golds': 2},
        {'player': 'Петя', 'points': 9, 'golds': 1},
      ]));
  return store;
}

Future<void> loadFonts() async {
  final manrope = File('test/fonts/Manrope.ttf');
  if (manrope.existsSync()) {
    final l = FontLoader('Manrope')..addFont(Future.value(ByteData.sublistView(manrope.readAsBytesSync())));
    await l.load();
    testFontFamily = 'Manrope';
  } else {
    testFontFamily = 'Roboto';
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

void main() {
  late Store store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    RefData.I.seedForTests(heroes);
    Shell.skipStartup = true;
    store = buildStore();
  });

  Future<void> shot(WidgetTester tester, String name, Widget page, {double height = 2340, int? tab}) async {
    tester.view.physicalSize = Size(1080, height);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<Store>.value(
      value: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: page),
    ));
    if (tab != null) {
      Shell.shellKey.currentState!.go(tab);
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
  }

  final tall = 5600.0;

  testWidgets('home', (t) async => shot(t, '01_home', Shell(key: Shell.shellKey), height: tall));
  testWidgets('home_phone', (t) async => shot(t, '00_home_phone', Shell(key: Shell.shellKey)));
  testWidgets('rating', (t) async => shot(t, '02_rating', Shell(key: Shell.shellKey), height: tall, tab: 1));
  testWidgets('analytics', (t) async => shot(t, '03_analytics', Shell(key: Shell.shellKey), height: tall, tab: 2));
  testWidgets('search', (t) async => shot(t, '04_search', Shell(key: Shell.shellKey), tab: 3));
  testWidgets('settings', (t) async => shot(t, '05_settings', Shell(key: Shell.shellKey), height: 7000, tab: 4));
  testWidgets('player', (t) async => shot(t, '06_player', const PlayerScreen(accountId: 100000), height: 9000));
  testWidgets('compare', (t) async => shot(t, '07_compare', const CompareScreen(), height: tall));
  testWidgets('together', (t) async => shot(t, '08_together', const TogetherScreen(), height: tall));
  testWidgets('heroes', (t) async => shot(t, '09_heroes', const HeroesScreen(), height: tall));
  testWidgets('matchups', (t) async => shot(t, '10_matchups', const MatchupsScreen(), height: tall));
  testWidgets('records', (t) async => shot(t, '11_records', const RecordsScreen(), height: tall));
  testWidgets('contest', (t) async => shot(t, '12_contest', const ContestScreen(), height: 7000));
  testWidgets('graph', (t) async => shot(t, '13_graph', const GraphScreen()));
  testWidgets('digest', (t) async => shot(t, '14_digest', const DigestScreen(period: 'week'), height: tall));
  testWidgets('go', (t) async => shot(t, '15_go', const GoScreen(), height: tall));
  testWidgets('matches', (t) async => shot(t, '16_matches', const MatchesListScreen(accountId: 100001), height: tall));
  testWidgets('roles', (t) async => shot(t, '17_roles', const RolesScreen(), height: tall));
  testWidgets('status', (t) async => shot(t, '18_status', const StatusScreen()));
  testWidgets('duel', (t) async => shot(t, '20_duel', const DuelScreen(), height: tall));
  testWidgets('add', (t) async => shot(t, '19_add', const AddPlayerScreen()));

  test('логика: рейтинг, награды, рекорды, матчапы', () {
    final ss = store.summaries('month');
    expect(ss, isNotEmpty);
    expect(ss.first.currentMmr, isNotNull);
    expect(computeStandings(store.named('month')), isNotEmpty);
    expect(computeRecords(store.named('month')).$1, isNotEmpty);
    expect(partyMatchups(store.named('all'), 3).games, greaterThan(0));
    expect(pairStats(store.named('all')), isNotEmpty);
  });
}
