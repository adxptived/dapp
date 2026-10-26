// Состояние приложения: игроки, матчи, настройки, сезоны. Хранение — JSON-файлы в папке приложения.
// Работает и в UI, и в фоновой задаче (отдельный экземпляр).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/ranks.dart';
import '../logic/stats.dart';
import 'api.dart';
import 'models.dart';
import 'refdata.dart';

/// Событие для оповещений: новый матч, смена ника/аватара и т. п.
class StoreEvent {
  final String kind; // match | steam
  final Player player;
  final M? match;
  final String? text;
  StoreEvent(this.kind, this.player, {this.match, this.text});
}

class Store extends ChangeNotifier {
  /// Обработчик событий обновления (оповещения), задаётся в main для открытого приложения.
  static Future<void> Function(Store, List<StoreEvent>)? onEvents;

  late String dir;
  final List<Player> players = [];
  final Map<int, List<M>> _matches = {};
  Settings settings = Settings();
  final List<Season> seasons = [];
  late OpenDota od;
  late Stratz stratz;
  bool loaded = false;
  bool refreshing = false;
  String? lastError;
  int lastFullRefresh = 0;
  String progress = '';

  static Future<Store> open() async {
    final s = Store();
    await s.init();
    return s;
  }

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    dir = '${docs.path}/dapp';
    await Directory('$dir/matches').create(recursive: true);
    await _loadState();
    od = OpenDota(apiKey: settings.openDotaKey, base: settings.openDotaBase);
    stratz = Stratz(settings.stratzKey);
    await RefData.I.load(dir);
    for (final p in players) {
      _matches[p.accountId] = await _loadMatches(p.accountId);
    }
    loaded = true;
    notifyListeners();
  }

  /// Перечитать с диска (после фоновой задачи).
  Future<void> reload() async {
    if (refreshing) return;
    players.clear();
    seasons.clear();
    _matches.clear();
    await _loadState();
    applyKeys();
    for (final p in players) {
      _matches[p.accountId] = await _loadMatches(p.accountId);
    }
    notifyListeners();
  }

  void applyKeys() {
    od.apiKey = settings.openDotaKey.trim();
    od.base = settings.openDotaBase.trim().isEmpty ? OpenDota.defaultBase : settings.openDotaBase.trim();
    stratz.apiKey = settings.stratzKey.trim();
  }

  // --- файлы --------------------------------------------------------------------------------------------

  File get _stateFile => File('$dir/state.json');
  File _matchFile(int id) => File('$dir/matches/$id.json');

  Future<void> _loadState() async {
    try {
      if (await _stateFile.exists()) {
        final j = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
        _applyState(j);
      }
    } catch (e) {
      lastError = 'Не удалось прочитать данные: $e';
    }
  }

  void _applyState(Map<String, dynamic> j) {
    players
      ..clear()
      ..addAll((j['players'] as List? ?? []).whereType<Map>().map((e) => Player.fromJson(Map<String, dynamic>.from(e))));
    settings = j['settings'] is Map ? Settings.fromJson(Map<String, dynamic>.from(j['settings'])) : Settings();
    seasons
      ..clear()
      ..addAll((j['seasons'] as List? ?? []).whereType<Map>().map((e) => Season.fromJson(Map<String, dynamic>.from(e))));
    lastFullRefresh = (j['last_full_refresh'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _stateJson() => {
        'version': 1,
        'players': players.map((p) => p.toJson()).toList(),
        'settings': settings.toJson(),
        'seasons': seasons.map((s) => s.toJson()).toList(),
        'last_full_refresh': lastFullRefresh,
      };

  Future<void> save() async {
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(_stateJson()));
    await tmp.rename(_stateFile.path);
  }

  Future<List<M>> _loadMatches(int id) async {
    try {
      final f = _matchFile(id);
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      final ms = list.whereType<Map>().map((e) => M.fromJson(Map<String, dynamic>.from(e))).toList();
      ms.sort((a, b) => a.startTime.compareTo(b.startTime));
      return ms;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveMatches(int id) async {
    final f = _matchFile(id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode((_matches[id] ?? []).map((m) => m.toJson()).toList()));
    await tmp.rename(f.path);
  }

  // --- выборки ----------------------------------------------------------------------------------------

  List<M> matchesOf(Player p) => _matches[p.accountId] ?? const [];

  Player? byName(String name) {
    final n = name.trim().replaceFirst('@', '').toLowerCase();
    for (final p in players) {
      if (p.name.toLowerCase() == n) return p;
    }
    return null;
  }

  Player? byId(int accountId) {
    for (final p in players) {
      if (p.accountId == accountId) return p;
    }
    return null;
  }

  Player? get me {
    for (final p in players) {
      if (p.isMe) return p;
    }
    return null;
  }

  List<(String, List<M>)> named(String period, {int? since, int? until}) => [
        for (final p in players)
          (
            p.name,
            inPeriod(matchesOf(p), period)
                .where((m) => (since == null || m.startTime >= since) && (until == null || m.startTime < until))
                .toList()
          )
      ];

  PlayerSummary summary(Player p, String period) =>
      PlayerSummary(p, matchesOf(p), inPeriod(matchesOf(p), period), settings.mmrStep);

  /// Рейтинг: по оценке MMR (у кого её нет — по ±MMR за период), затем по винрейту.
  List<PlayerSummary> summaries(String period) {
    final list = players.map((p) => summary(p, period)).toList();
    list.sort((a, b) {
      final am = a.currentMmr, bm = b.currentMmr;
      if (am != null && bm != null && am != bm) return bm.compareTo(am);
      if (am != null && bm == null) return -1;
      if (am == null && bm != null) return 1;
      final d = b.periodDelta.compareTo(a.periodDelta);
      if (d != 0) return d;
      return b.agg.winrate.compareTo(a.agg.winrate);
    });
    return list;
  }

  /// Все матчи пати (уникальные по match_id) — для ленты.
  List<(Player, M)> feed({int limit = 50}) {
    final all = <(Player, M)>[];
    for (final p in players) {
      for (final m in matchesOf(p)) {
        all.add((p, m));
      }
    }
    all.sort((a, b) => b.$2.startTime.compareTo(a.$2.startTime));
    return all.take(limit).toList();
  }

  int get dataAge {
    final ts = players.map((p) => p.lastRefresh).fold<int>(0, (a, b) => a == 0 ? b : (b < a ? b : a));
    return ts == 0 ? 0 : nowTs() - ts;
  }

  int get enrichQueue {
    final since = nowTs() - settings.enrichDays * 86400;
    var n = 0;
    for (final p in players) {
      n += matchesOf(p).where((m) => !m.enriched && m.startTime >= since).length;
    }
    return n;
  }

  // --- игроки -----------------------------------------------------------------------------------------

  Future<int> resolveAccount(String input) async {
    final vanity = extractVanity(input);
    if (vanity != null) return accountIdFromSteam64(await resolveVanity(vanity));
    return parseAccountId(input);
  }

  Future<Player> addPlayer(String input, {String? name, int? mmr, void Function(String)? onProgress}) async {
    if (players.length >= 32) throw ApiError('Слишком много игроков (максимум 32).');
    final id = await resolveAccount(input);
    if (byId(id) != null) throw ApiError('Этот игрок уже в пати: ${byId(id)!.name}');
    onProgress?.call('Профиль…');
    final prof = await od.profile(id);
    final profile = (prof['profile'] as Map?) ?? {};
    var display = (name ?? '').trim();
    if (display.isEmpty) display = (profile['personaname'] ?? 'Игрок $id').toString();
    var unique = display;
    var k = 2;
    while (byName(unique) != null) {
      unique = '$display $k';
      k++;
    }
    final now = nowTs();
    final p = Player(
      accountId: id,
      name: unique,
      createdTs: now,
      anchors: mmr != null ? [MmrAnchor(now, mmr)] : [],
      personaname: profile['personaname']?.toString(),
      avatar: profile['avatarfull']?.toString(),
      rankTier: (prof['rank_tier'] as num?)?.toInt(),
      leaderboardRank: (prof['leaderboard_rank'] as num?)?.toInt(),
      plus: profile['plus'] == true,
      lastProfile: now,
      isMe: players.isEmpty,
    );
    players.add(p);
    _matches[id] = [];
    await save();
    notifyListeners();
    onProgress?.call('История матчей…');
    await refreshPlayer(p, full: true);
    final last = matchesOf(p).isEmpty ? null : matchesOf(p).last.matchId;
    p.lastNotifiedMatch = last;
    await save();
    notifyListeners();
    return p;
  }

  Future<void> removePlayer(Player p) async {
    players.remove(p);
    _matches.remove(p.accountId);
    try {
      await _matchFile(p.accountId).delete();
    } catch (_) {}
    await save();
    notifyListeners();
  }

  Future<void> renamePlayer(Player p, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final other = byName(n);
    if (other != null && other != p) throw ApiError('Ник «$n» уже занят');
    p.name = n;
    await save();
    notifyListeners();
  }

  Future<void> setMmr(Player p, int mmr) async {
    p.anchors.add(MmrAnchor(nowTs(), mmr));
    await save();
    notifyListeners();
  }

  Future<void> removeAnchor(Player p, int index) async {
    if (index >= 0 && index < p.anchors.length) p.anchors.removeAt(index);
    await save();
    notifyListeners();
  }

  Future<void> setMe(Player? p) async {
    for (final x in players) {
      x.isMe = identical(x, p);
    }
    await save();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final p = players.removeAt(oldIndex);
    players.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, p);
    await save();
    notifyListeners();
  }

  Future<void> updateSettings(void Function(Settings) change) async {
    change(settings);
    applyKeys();
    await save();
    notifyListeners();
  }

  // --- обновление ------------------------------------------------------------------------------------

  static M _fromListRow(Map<String, dynamic> r) {
    List<int>? rad, dire;
    final heroes = r['heroes'];
    if (heroes is Map) {
      rad = [];
      dire = [];
      heroes.forEach((slot, v) {
        final s = int.tryParse(slot.toString());
        final h = v is Map ? (v['hero_id'] as num?)?.toInt() : null;
        if (s == null || h == null || h == 0) return;
        (s < 128 ? rad! : dire!).add(h);
      });
      if (rad.isEmpty || dire.isEmpty) {
        rad = null;
        dire = null;
      }
    }
    int? i(String k) => (r[k] as num?)?.toInt();
    return M(
      matchId: i('match_id')!,
      playerSlot: i('player_slot') ?? 0,
      radiantWin: r['radiant_win'] == true,
      heroId: i('hero_id'),
      startTime: i('start_time') ?? 0,
      duration: i('duration'),
      lobbyType: i('lobby_type'),
      kills: i('kills') ?? 0,
      deaths: i('deaths') ?? 0,
      assists: i('assists') ?? 0,
      partySize: i('party_size'),
      averageRank: i('average_rank'),
      radiant: rad,
      dire: dire,
      gpm: i('gold_per_min'),
      xpm: i('xp_per_min'),
      lastHits: i('last_hits'),
      denies: i('denies'),
      heroDamage: i('hero_damage'),
      towerDamage: i('tower_damage'),
      heroHealing: i('hero_healing'),
      level: i('level'),
    );
  }

  void _merge(M into, M from) {
    into.radiantWin = from.radiantWin;
    into.playerSlot = from.playerSlot;
    into.heroId ??= from.heroId;
    into.duration ??= from.duration;
    into.kills = from.kills;
    into.deaths = from.deaths;
    into.assists = from.assists;
    into.partySize ??= from.partySize;
    into.averageRank ??= from.averageRank;
    into.radiant ??= from.radiant;
    into.dire ??= from.dire;
    into.gpm ??= from.gpm;
    into.xpm ??= from.xpm;
    into.lastHits ??= from.lastHits;
    into.denies ??= from.denies;
    into.heroDamage ??= from.heroDamage;
    into.towerDamage ??= from.towerDamage;
    into.heroHealing ??= from.heroHealing;
    into.level ??= from.level;
  }

  /// Обновить одного игрока. Возвращает новые матчи.
  Future<List<M>> refreshPlayer(Player p, {bool full = false, bool enrich = true, List<StoreEvent>? events}) async {
    final now = nowTs();
    final list = _matches.putIfAbsent(p.accountId, () => []);
    final known = {for (final m in list) m.matchId: m};
    // профиль: ранг, ник, аватар — не чаще раза в 30 минут
    if (full || now - p.lastProfile > 1800) {
      try {
        final prof = await od.profile(p.accountId);
        final profile = (prof['profile'] as Map?) ?? {};
        final newName = profile['personaname']?.toString();
        final newAvatar = profile['avatarfull']?.toString();
        if (events != null && p.personaname != null && newName != null && newName != p.personaname) {
          events.add(StoreEvent('steam', p, text: '${p.name}: ник в Steam «${p.personaname}» → «$newName»'));
        }
        if (events != null && p.avatar != null && newAvatar != null && newAvatar != p.avatar) {
          events.add(StoreEvent('steam', p, text: '${p.name} сменил аватарку в Steam'));
        }
        p.personaname = newName ?? p.personaname;
        p.avatar = newAvatar ?? p.avatar;
        p.rankTier = (prof['rank_tier'] as num?)?.toInt() ?? p.rankTier;
        p.leaderboardRank = (prof['leaderboard_rank'] as num?)?.toInt();
        p.plus = profile['plus'] == true;
        p.lastProfile = now;
      } catch (_) {}
    }
    final rows = await od.matches(p.accountId, limit: (full || list.isEmpty) ? null : 60);
    final added = <M>[];
    for (final r in rows) {
      if (r['match_id'] == null) continue;
      final m = _fromListRow(r);
      if (m.lobbyType != null && m.lobbyType != rankedLobby) continue;
      final old = known[m.matchId];
      if (old == null) {
        list.add(m);
        known[m.matchId] = m;
        added.add(m);
      } else {
        _merge(old, m);
      }
    }
    p.privateHistory = list.isEmpty && rows.isEmpty;
    // последние ~20 игр с GPM/уроном одним запросом
    try {
      final recent = await od.recentMatches(p.accountId);
      for (final r in recent) {
        if ((r['lobby_type'] as num?)?.toInt() != rankedLobby) continue;
        final m = _fromListRow(r);
        final old = known[m.matchId];
        if (old == null) {
          list.add(m);
          known[m.matchId] = m;
          added.add(m);
        } else {
          _merge(old, m);
        }
      }
    } catch (_) {}
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    p.lastRefresh = now;
    if (enrich) {
      await _enrich(p, budget: od.apiKey.isEmpty ? 6 : 25);
      await _enrichStratz(p);
    }
    await _saveMatches(p.accountId);
    if (events != null) {
      for (final m in added) {
        events.add(StoreEvent('match', p, match: m));
      }
    }
    return added;
  }

  /// Догрузка подробностей /matches/{id}: нетворс, бенчмарки → перф, предметы, стаки, шард.
  Future<void> _enrich(Player p, {int budget = 6}) async {
    final since = nowTs() - settings.enrichDays * 86400;
    final queue = matchesOf(p).where((m) => !m.enriched && m.startTime >= since).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final m in queue.take(budget)) {
      if (!od.backgroundAllowed) break;
      try {
        final raw = await od.match(m.matchId);
        applyMatchDetail(m, raw, p.accountId);
      } catch (_) {
        break;
      }
    }
  }

  static void applyMatchDetail(M m, Map<String, dynamic> raw, int accountId) {
    final players = (raw['players'] as List? ?? []).whereType<Map>().toList();
    if (players.isEmpty) return;
    Map? found;
    for (final x in players) {
      if (x['account_id'] == accountId) found = x;
    }
    if (found == null) {
      for (final x in players) {
        if (x['player_slot'] == m.playerSlot) found = x;
      }
    }
    if (found == null) return;
    final Map me = found;
    int? i(String k) => (me[k] as num?)?.toInt();
    m.gpm = i('gold_per_min') ?? m.gpm;
    m.xpm = i('xp_per_min') ?? m.xpm;
    m.lastHits = i('last_hits') ?? m.lastHits;
    m.denies = i('denies') ?? m.denies;
    m.heroDamage = i('hero_damage') ?? m.heroDamage;
    m.towerDamage = i('tower_damage') ?? m.towerDamage;
    m.heroHealing = i('hero_healing') ?? m.heroHealing;
    m.netWorth = i('net_worth') ?? m.netWorth;
    m.level = i('level') ?? m.level;
    m.duration ??= (raw['duration'] as num?)?.toInt();
    final items = [for (final s in ['item_0', 'item_1', 'item_2', 'item_3', 'item_4', 'item_5']) i(s)]
        .whereType<int>()
        .where((x) => x > 0)
        .toList();
    if (items.isNotEmpty) m.items = items;
    m.neutralItem = i('item_neutral') ?? m.neutralItem;
    final bench = <String, double>{};
    final b = me['benchmarks'];
    if (b is Map) {
      b.forEach((k, v) {
        final pct = v is Map ? v['pct'] : v;
        if (pct is num) bench[k.toString()] = pct.toDouble();
      });
    }
    if (bench.isNotEmpty) {
      m.bench = bench;
      m.perfScore = perfScore(bench);
    }
    if (raw['version'] != null) m.stacks = i('camps_stacked');
    final log = me['purchase_log'];
    if (log is List) {
      for (final e in log) {
        if (e is Map && e['key'] == 'aghanims_shard' && e['time'] is num) m.shardTime = (e['time'] as num).toInt();
      }
    }
    // состав и размер пати
    final rad = <int>[], dire = <int>[];
    for (final x in players) {
      final h = (x['hero_id'] as num?)?.toInt();
      final s = (x['player_slot'] as num?)?.toInt();
      if (h == null || s == null) continue;
      (s < 128 ? rad : dire).add(h);
    }
    if (rad.isNotEmpty && dire.isNotEmpty) {
      m.radiant = rad;
      m.dire = dire;
    }
    final ps = (me['party_size'] as num?)?.toInt();
    if (ps != null && ps > 0) {
      m.partySize = ps;
    } else if (me['party_id'] != null && me['party_id'] != 0) {
      final side = m.playerSlot < 128;
      m.partySize = players
          .where((x) => x['party_id'] == me['party_id'] && ((x['player_slot'] as num? ?? 0) < 128) == side)
          .length;
    }
    m.averageRank = averageRankTier(players.map((x) => (x['rank_tier'] as num?)?.toInt())) ?? m.averageRank;
    m.enriched = true;
  }

  Future<void> _enrichStratz(Player p) async {
    if (!stratz.enabled) return;
    final since = nowTs() - settings.enrichDays * 86400;
    final queue = matchesOf(p).where((m) => !m.stratzDone && m.startTime >= since).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final ids = queue.take(30).map((m) => m.matchId).toList();
    if (ids.isEmpty) return;
    try {
      final hints = {for (final m in queue) m.matchId: (m.isRadiant, m.heroId)};
      final data = await stratz.matchesFor(p.accountId, ids, hints);
      final byId = {for (final m in queue) m.matchId: m};
      data.forEach((id, row) {
        final m = byId[id];
        if (m == null) return;
        int? i(String k) => (row[k] as num?)?.toInt();
        m.position = i('position') ?? m.position;
        m.imp = i('imp') ?? m.imp;
        m.laneResult = i('lane_result') ?? m.laneResult;
        m.wards = i('wards') ?? m.wards;
        m.partySize ??= i('party_size');
        m.gpm ??= i('gpm');
        m.xpm ??= i('xpm');
        m.netWorth ??= i('net_worth');
        m.heroDamage ??= i('hero_damage');
        m.towerDamage ??= i('tower_damage');
        m.heroHealing ??= i('hero_healing');
        m.lastHits ??= i('last_hits');
        m.denies ??= i('denies');
        m.stratzDone = true;
      });
      // матчи старше суток, которых Stratz не знает, больше не спрашиваем
      for (final m in queue.take(30)) {
        if (!data.containsKey(m.matchId) && nowTs() - m.startTime > 86400) m.stratzDone = true;
      }
    } catch (_) {}
  }

  /// Обновить всех. Возвращает события (новые матчи, смены профилей).
  Future<List<StoreEvent>> refreshAll({bool force = false}) async {
    if (refreshing) return [];
    refreshing = true;
    lastError = null;
    notifyListeners();
    final events = <StoreEvent>[];
    try {
      unawaited(RefData.I.refreshIfStale(od, dir).catchError((_) {}));
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        if (!force && nowTs() - p.lastRefresh < 180) continue; // свежее 3 минут — не дёргаем
        progress = '${p.name} (${i + 1}/${players.length})';
        notifyListeners();
        try {
          await refreshPlayer(p, events: events);
        } catch (e) {
          lastError = e.toString();
        }
      }
      lastFullRefresh = nowTs();
      if (onEvents != null) {
        try {
          await onEvents!(this, events);
        } catch (_) {}
      } else {
        await checkSeasons();
      }
      await save();
    } finally {
      refreshing = false;
      progress = '';
      notifyListeners();
    }
    return events;
  }

  /// Подробный матч для экрана матча.
  Future<Map<String, dynamic>> fetchMatch(int matchId) => od.match(matchId);

  // --- сезоны -----------------------------------------------------------------------------------------

  Season? get currentSeason {
    for (final s in seasons) {
      if (!s.finished) return s;
    }
    return null;
  }

  List<Season> get finishedSeasons => seasons.where((s) => s.finished).toList();

  Future<Season> startSeason(int days) async {
    final now = nowTs();
    final number = seasons.isEmpty ? 1 : seasons.map((s) => s.number).reduce((a, b) => a > b ? a : b) + 1;
    final s = Season(number: number, startTs: now, plannedEndTs: now + days * 86400, lengthDays: days);
    seasons.add(s);
    await save();
    notifyListeners();
    return s;
  }

  List<PointsRow> seasonTable(Season s) {
    final named = this.named('all', since: s.startTs, until: s.endTs ?? s.plannedEndTs);
    return contestPoints(computeStandings(named, step: settings.mmrStep));
  }

  /// Закрыть сезон; next — сразу начать следующий.
  Future<(Season, String?)> endSeason(Season s, {bool next = false}) async {
    final table = seasonTable(s);
    s.endTs = nowTs() < s.plannedEndTs ? nowTs() : s.plannedEndTs;
    s.champion = championOf(table);
    s.table = table.take(8).map((r) => r.toJson()).toList();
    if (next) {
      await startSeason(s.lengthDays);
    } else {
      await save();
      notifyListeners();
    }
    return (s, s.champion);
  }

  /// Закрывает просроченный сезон и начинает следующий. Возвращает закрытый сезон.
  Future<Season?> checkSeasons() async {
    final s = currentSeason;
    if (s != null && seasonDue(s, nowTs())) {
      await endSeason(s, next: true);
      return s;
    }
    return null;
  }

  // --- резервные копии ----------------------------------------------------------------------------

  Map<String, dynamic> exportJson() => {
        ..._stateJson(),
        'matches': {for (final p in players) '${p.accountId}': matchesOf(p).map((m) => m.toJson()).toList()},
        'exported': nowTs(),
        'app': 'dapp',
      };

  Future<void> importJson(Map<String, dynamic> j) async {
    if (j['players'] is! List) throw ApiError('Это не резервная копия Dota Party');
    _applyState(j);
    applyKeys();
    _matches.clear();
    final ms = j['matches'];
    for (final p in players) {
      final list = ms is Map ? (ms['${p.accountId}'] as List? ?? []) : [];
      _matches[p.accountId] = list.whereType<Map>().map((e) => M.fromJson(Map<String, dynamic>.from(e))).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      await _saveMatches(p.accountId);
    }
    await save();
    notifyListeners();
  }

  /// Ежедневная автокопия (хранится 7 штук).
  Future<void> autoBackup() async {
    try {
      final bdir = Directory('$dir/backups');
      await bdir.create(recursive: true);
      final d = DateTime.now();
      final name = 'backup_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
      final f = File('${bdir.path}/$name');
      if (await f.exists()) return;
      await f.writeAsString(jsonEncode(exportJson()));
      final files = (await bdir.list().toList()).whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
      for (final old in files.skip(7)) {
        await old.delete();
      }
    } catch (_) {}
  }

  Future<List<File>> backups() async {
    final bdir = Directory('$dir/backups');
    if (!await bdir.exists()) return [];
    return (await bdir.list().toList()).whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
  }

  Future<void> resetAll() async {
    for (final p in [...players]) {
      try {
        await _matchFile(p.accountId).delete();
      } catch (_) {}
    }
    players.clear();
    _matches.clear();
    seasons.clear();
    settings = Settings();
    applyKeys();
    await save();
    notifyListeners();
  }
}
