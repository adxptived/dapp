// Справочники героев и предметов (с OpenDota, кэш в файле, обновление раз в неделю).
import 'dart:convert';
import 'dart:io';

import 'api.dart';

const steamCdn = 'https://cdn.cloudflare.steamstatic.com';

class HeroInfo {
  final int id;
  final String name; // npc_dota_hero_xxx
  final String localized;
  HeroInfo(this.id, this.name, this.localized);
  String get short => name.replaceFirst('npc_dota_hero_', '');
  String get image => '$steamCdn/apps/dota2/images/dota_react/heroes/$short.png';
  String get icon => '$steamCdn/apps/dota2/images/dota_react/heroes/icons/$short.png';
}

class ItemInfo {
  final int id;
  final String key;
  final String name;
  ItemInfo(this.id, this.key, this.name);
  String get image => '$steamCdn/apps/dota2/images/dota_react/items/$key.png';
}

class RefData {
  static final RefData I = RefData._();
  RefData._();

  final Map<int, HeroInfo> heroes = {};
  final Map<int, ItemInfo> items = {};
  int updated = 0;
  bool lowData = false; // экономия трафика: маленькие иконки вместо портретов

  String heroName(int? id) => id == null ? '—' : (heroes[id]?.localized ?? 'Герой #$id');
  HeroInfo? hero(int? id) => id == null ? null : heroes[id];
  ItemInfo? item(int? id) => id == null ? null : items[id];

  /// Поиск героя по имени (без учёта регистра, по началу и подстроке, плюс частые сокращения).
  HeroInfo? findHero(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return null;
    const aliases = {
      'am': 'anti-mage', 'пудж': 'pudge', 'инвокер': 'invoker', 'кунка': 'kunkka', 'сф': 'shadow fiend',
      'sf': 'shadow fiend', 'пл': 'phantom lancer', 'wk': 'wraith king', 'вк': 'wraith king', 'qop': 'queen of pain',
      'cm': 'crystal maiden', 'цмка': 'crystal maiden', 'es': 'earthshaker', 'шейкер': 'earthshaker', 'ta': 'templar assassin',
      'od': 'outworld destroyer', 'wr': 'windranger', 'pa': 'phantom assassin', 'фантомка': 'phantom assassin',
      'ck': 'chaos knight', 'dk': 'dragon knight', 'aa': 'ancient apparition', 'bh': 'bounty hunter', 'ns': 'night stalker',
      'sk': 'sand king', 'ss': 'shadow shaman', 'шаман': 'shadow shaman', 'lc': 'legion commander', 'ls': 'lifestealer',
      'wd': 'witch doctor', 'ember': 'ember spirit', 'storm': 'storm spirit', 'void': 'faceless void', 'войд': 'faceless void',
      'спектра': 'spectre', 'снайпер': 'sniper', 'инвок': 'invoker', 'зевс': 'zeus', 'лина': 'lina', 'лион': 'lion',
      'акс': 'axe', 'джагер': 'juggernaut', 'джаг': 'juggernaut', 'мипо': 'meepo', 'тинкер': 'tinker', 'рики': 'riki',
    };
    final target = aliases[s] ?? s;
    for (final h in heroes.values) {
      if (h.localized.toLowerCase() == target) return h;
    }
    for (final h in heroes.values) {
      if (h.localized.toLowerCase().startsWith(target)) return h;
    }
    for (final h in heroes.values) {
      if (h.localized.toLowerCase().contains(target)) return h;
    }
    return null;
  }

  void seedForTests(Map<int, (String, String)> hs) {
    heroes.clear();
    hs.forEach((id, v) => heroes[id] = HeroInfo(id, v.$1, v.$2));
    updated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  Future<File> _file(String dir) async => File('$dir/refdata.json');

  Future<void> load(String dir) async {
    try {
      final f = await _file(dir);
      if (await f.exists()) _apply(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> j) {
    updated = (j['updated'] as num?)?.toInt() ?? 0;
    heroes.clear();
    for (final h in (j['heroes'] as List? ?? [])) {
      heroes[h[0] as int] = HeroInfo(h[0] as int, h[1] as String, h[2] as String);
    }
    items.clear();
    for (final i in (j['items'] as List? ?? [])) {
      items[i[0] as int] = ItemInfo(i[0] as int, i[1] as String, i[2] as String);
    }
  }

  Future<void> refreshIfStale(OpenDota od, String dir, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!force && heroes.isNotEmpty && items.isNotEmpty && now - updated < 14 * 86400) return;
    final hs = await od.constants('heroes');
    final its = await od.constants('items');
    final heroRows = <List<dynamic>>[];
    hs.forEach((k, v) {
      if (v is Map && v['id'] is int) heroRows.add([v['id'], v['name'] ?? '', v['localized_name'] ?? '']);
    });
    final itemRows = <List<dynamic>>[];
    its.forEach((k, v) {
      if (v is Map && v['id'] is int) itemRows.add([v['id'], k, (v['dname'] ?? k).toString()]);
    });
    if (heroRows.isEmpty) return;
    final j = {'updated': now, 'heroes': heroRows, 'items': itemRows};
    _apply(j);
    try {
      await (await _file(dir)).writeAsString(jsonEncode(j));
    } catch (_) {}
  }
}
