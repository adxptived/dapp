// Чистые расчёты статистики (порт stats.py, awards.py, records.py, party.py, matchups.py, сравнения из tracker.py).
import 'dart:math' as math;

import '../data/models.dart';
import 'ranks.dart';

const rankedLobby = 7;

double? mean(Iterable<num?> values) {
  final v = values.whereType<num>().toList();
  if (v.isEmpty) return null;
  return v.fold<double>(0, (a, b) => a + b) / v.length;
}

String plural(int n, String one, String few, String many) {
  final n10 = n % 10, n100 = n % 100;
  final w = (n10 == 1 && n100 != 11)
      ? one
      : (n10 >= 2 && n10 <= 4 && !(n100 >= 12 && n100 <= 14))
          ? few
          : many;
  return '$n $w';
}

String gamesWord(int n) => plural(n, 'игра', 'игры', 'игр');

// --- периоды --------------------------------------------------------------------------------------------------

const periods = ['day', 'week', 'month', 'year', 'all'];
const periodLabels = {
  'day': 'Сутки',
  'week': 'Неделя',
  'month': 'Месяц',
  'year': 'Год',
  'all': 'Всё',
};
const periodLong = {
  'day': 'за сутки',
  'week': 'за неделю',
  'month': 'за месяц',
  'year': 'за год',
  'all': 'за всё время',
};
const _periodSeconds = {'day': 86400, 'week': 7 * 86400, 'month': 30 * 86400, 'year': 365 * 86400};

int nowTs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

int? periodSince(String period, [int? now]) {
  final s = _periodSeconds[period];
  return s == null ? null : (now ?? nowTs()) - s;
}

int localDayStart([int? now]) {
  final d = DateTime.fromMillisecondsSinceEpoch((now ?? nowTs()) * 1000);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;
}

List<M> inPeriod(List<M> ms, String period) {
  final since = periodSince(period);
  return since == null ? ms : ms.where((m) => m.startTime >= since).toList();
}

// --- MMR ------------------------------------------------------------------------------------------------------

int matchMmrDelta(M m, int step) => m.won ? step : -step;

int mmrDelta(Iterable<M> ms, int step) => ms.fold(0, (a, m) => a + matchMmrDelta(m, step));

bool countsAfter(M m, int ts) {
  final d = m.duration;
  if (d != null && d > 0) return m.startTime + d > ts;
  return m.startTime >= ts;
}

List<MmrAnchor> effectiveAnchors(List<M> ms, List<MmrAnchor> anchors) {
  final result = <MmrAnchor>[];
  for (final a in anchors) {
    if (result.isNotEmpty) {
      final prevTs = result.last.ts;
      final played = ms.any((m) => countsAfter(m, prevTs) && !countsAfter(m, a.ts));
      if (!played) {
        result[result.length - 1] = MmrAnchor(prevTs, a.mmr);
        continue;
      }
    }
    result.add(a);
  }
  return result;
}

class Ledger {
  final int? start;
  final int? current;
  final int earned;
  final int games;
  final int corrections;
  final List<Map<String, dynamic>> entries;
  Ledger(this.start, this.current, this.earned, this.games, this.corrections, this.entries);
}

Ledger mmrLedger(List<M> ms, List<MmrAnchor> rawAnchors, int step, {int sinceTs = 0}) {
  final anchors = effectiveAnchors(ms, rawAnchors);
  final firstTs = anchors.isNotEmpty ? anchors.first.ts : sinceTs;
  final counted = ms.where((m) => countsAfter(m, firstTs)).toList();
  final earned = mmrDelta(counted, step);
  if (anchors.isEmpty) return Ledger(null, null, earned, counted.length, 0, []);
  final entries = <Map<String, dynamic>>[
    {'ts': anchors.first.ts, 'mmr': anchors.first.mmr, 'drift': null, 'games': 0}
  ];
  for (var i = 1; i < anchors.length; i++) {
    final prev = anchors[i - 1], cur = anchors[i];
    final between = counted.where((m) => countsAfter(m, prev.ts) && !countsAfter(m, cur.ts)).toList();
    entries.add({
      'ts': cur.ts,
      'mmr': cur.mmr,
      'drift': cur.mmr - (prev.mmr + mmrDelta(between, step)),
      'games': between.length,
    });
  }
  final last = anchors.last;
  final current = last.mmr + mmrDelta(counted.where((m) => countsAfter(m, last.ts)), step);
  final start = anchors.first.mmr;
  return Ledger(start, current, earned, counted.length, current - start - earned, entries);
}

/// Оценка MMR после каждой игры: [(время, MMR)]. Без журнала — накопленное ±MMR от нуля.
List<(int, int)> mmrTimeline(List<M> sorted, List<MmrAnchor> rawAnchors, int step) {
  final anchors = effectiveAnchors(sorted, rawAnchors);
  if (anchors.isEmpty) {
    var total = 0;
    return [
      for (final m in sorted) (m.startTime, total += matchMmrDelta(m, step)),
    ];
  }
  final first = anchors.first;
  final before = sorted.where((m) => !countsAfter(m, first.ts)).toList();
  final after = sorted.where((m) => countsAfter(m, first.ts)).toList();
  final points = <(int, int)>[];
  var value = first.mmr - mmrDelta(before, step);
  for (final m in before) {
    value += matchMmrDelta(m, step);
    points.add((m.startTime, value));
  }
  var index = 0;
  value = first.mmr;
  for (final m in after) {
    while (index + 1 < anchors.length && countsAfter(m, anchors[index + 1].ts)) {
      index++;
      value = anchors[index].mmr;
    }
    value += matchMmrDelta(m, step);
    points.add((m.startTime, value));
  }
  return points;
}

// --- агрегаты -------------------------------------------------------------------------------------------------

class Agg {
  final int games, wins, kills, deaths, assists;
  const Agg(this.games, this.wins, this.kills, this.deaths, this.assists);
  int get losses => games - wins;
  double get winrate => games == 0 ? 0 : wins / games;
  double get kda => games == 0 ? 0 : (kills + assists) / math.max(deaths, 1);
  double get avgK => games == 0 ? 0 : kills / games;
  double get avgD => games == 0 ? 0 : deaths / games;
  double get avgA => games == 0 ? 0 : assists / games;
}

Agg aggregate(Iterable<M> ms) {
  var g = 0, w = 0, k = 0, d = 0, a = 0;
  for (final m in ms) {
    g++;
    if (m.won) w++;
    k += m.kills;
    d += m.deaths;
    a += m.assists;
  }
  return Agg(g, w, k, d, a);
}

(bool?, int) currentStreak(List<M> sorted) {
  if (sorted.isEmpty) return (null, 0);
  final last = sorted.last.won;
  var n = 0;
  for (final m in sorted.reversed) {
    if (m.won == last) {
      n++;
    } else {
      break;
    }
  }
  return (last, n);
}

int longestWinStreak(List<M> sorted) {
  var longest = 0, cur = 0;
  for (final m in sorted) {
    if (m.won) {
      cur++;
      longest = math.max(longest, cur);
    } else {
      cur = 0;
    }
  }
  return longest;
}

int longestLossStreak(List<M> sorted) {
  var longest = 0, cur = 0;
  for (final m in sorted) {
    if (!m.won) {
      cur++;
      longest = math.max(longest, cur);
    } else {
      cur = 0;
    }
  }
  return longest;
}

class HeroStat {
  final int heroId;
  final int games, wins;
  final double kda;
  final double? avgImp, avgGpm;
  HeroStat(this.heroId, this.games, this.wins, this.kda, this.avgImp, this.avgGpm);
  int get losses => games - wins;
  double get winrate => games == 0 ? 0 : wins / games;
}

HeroStat _group(int key, List<M> g) {
  final a = aggregate(g);
  return HeroStat(key, a.games, a.wins, a.kda, mean(g.map((m) => m.imp)), mean(g.map((m) => m.gpm)));
}

List<HeroStat> heroStats(Iterable<M> ms, {int? limit, int? heroId}) {
  final by = <int, List<M>>{};
  for (final m in ms) {
    final h = m.heroId;
    if (h == null || h == 0 || (heroId != null && h != heroId)) continue;
    by.putIfAbsent(h, () => []).add(m);
  }
  final res = by.entries.map((e) => _group(e.key, e.value)).toList();
  res.sort((a, b) {
    final c = b.games.compareTo(a.games);
    if (c != 0) return c;
    final w = b.winrate.compareTo(a.winrate);
    if (w != 0) return w;
    return a.heroId.compareTo(b.heroId);
  });
  return limit != null && res.length > limit ? res.sublist(0, limit) : res;
}

List<HeroStat> roleStats(Iterable<M> ms) {
  final by = <int, List<M>>{};
  for (final m in ms) {
    final p = m.position;
    if (p == null || p == 0) continue;
    by.putIfAbsent(p, () => []).add(m);
  }
  final keys = by.keys.toList()..sort();
  return [for (final k in keys) _group(k, by[k]!)];
}

int heroPool(Iterable<M> ms) => ms.map((m) => m.heroId).whereType<int>().where((h) => h > 0).toSet().length;

/// Соло / пати / неизвестно: (игр, побед).
Map<String, (int, int)> soloPartySplit(Iterable<M> ms) {
  final b = {'solo': [0, 0], 'party': [0, 0], 'unknown': [0, 0]};
  for (final m in ms) {
    final ps = m.partySize;
    final key = (ps == null || ps == 0) ? 'unknown' : (ps > 1 ? 'party' : 'solo');
    b[key]![0]++;
    if (m.won) b[key]![1]++;
  }
  return b.map((k, v) => MapEntry(k, (v[0], v[1])));
}

Map<int, (int, int)> winrateByHour(Iterable<M> ms) {
  final by = <int, List<int>>{};
  for (final m in ms) {
    final h = DateTime.fromMillisecondsSinceEpoch(m.startTime * 1000).hour;
    final s = by.putIfAbsent(h, () => [0, 0]);
    s[0]++;
    if (m.won) s[1]++;
  }
  return by.map((k, v) => MapEntry(k, (v[0], v[1])));
}

((int, double)?, (int, double)?) bestWorstHour(Map<int, (int, int)> byHour, {int minGames = 3}) {
  final q = [
    for (final e in byHour.entries)
      if (e.value.$1 >= minGames) (e.key, e.value.$2 / e.value.$1)
  ];
  if (q.length < 2) return (null, null);
  q.sort((a, b) => b.$2.compareTo(a.$2));
  if (q.first.$2 == q.last.$2) return (null, null);
  return (q.first, q.last);
}

M? bestGame(Iterable<M> ms) {
  M? best;
  var bk = -1.0;
  for (final m in ms) {
    if (m.kills + m.assists < 10) continue;
    if (m.kda > bk) {
      bk = m.kda;
      best = m;
    }
  }
  return best;
}

Map<String, double> aggregateSkill(Iterable<M> ms) {
  final sums = <String, double>{}, counts = <String, int>{};
  for (final m in ms) {
    for (final e in (m.bench ?? const <String, double>{}).entries) {
      sums[e.key] = (sums[e.key] ?? 0) + e.value;
      counts[e.key] = (counts[e.key] ?? 0) + 1;
    }
  }
  return sums.map((k, v) => MapEntry(k, v / counts[k]!));
}

String inferRoleStyle(double? avgLastHits, double? avgHealing) {
  if (avgLastHits == null) return '';
  if ((avgHealing ?? 0) > 4000) return 'саппорт (хилер)';
  if (avgLastHits >= 180) return 'кор (фарм)';
  if (avgLastHits < 90) return 'саппорт / роумер';
  return 'универсал';
}

const _positiveBench = {
  'gold_per_min',
  'xp_per_min',
  'kills_per_min',
  'assists_per_min',
  'last_hits_per_min',
  'hero_damage_per_min',
  'hero_healing_per_min',
  'tower_damage',
};

double? perfScore(Map<String, double> bench) {
  final p = bench.entries.where((e) => _positiveBench.contains(e.key)).map((e) => e.value).toList();
  if (p.isEmpty) return null;
  return p.reduce((a, b) => a + b) / p.length;
}

// --- сводка по игроку -------------------------------------------------------------------------------------

class PlayerSummary {
  final Player player;
  final List<M> all; // все ранкед-матчи по времени
  final List<M> window; // матчи периода
  final int step;
  late final Agg agg;
  late final Ledger ledger;
  late final (bool?, int) streak;
  late final List<bool> form;
  late final List<HeroStat> topHeroes;
  late final int todayGames, todayWins, todayDelta;
  late final int periodDelta;
  late final double? avgPerf;
  late final int enrichedGames;
  late final int detailGames;
  late final double? avgGpm, avgXpm, avgDamage, avgNetWorth, avgLastHits, avgHealing;
  late final int bestStreak;

  PlayerSummary(this.player, this.all, this.window, this.step) {
    agg = aggregate(window);
    ledger = mmrLedger(all, player.anchors, step, sinceTs: player.createdTs);
    streak = currentStreak(all);
    form = all.length <= 5 ? all.map((m) => m.won).toList() : all.sublist(all.length - 5).map((m) => m.won).toList();
    topHeroes = heroStats(window, limit: 3);
    final today = all.where((m) => m.startTime >= localDayStart()).toList();
    todayGames = today.length;
    todayWins = today.where((m) => m.won).length;
    todayDelta = mmrDelta(today, step);
    periodDelta = mmrDelta(window, step);
    final perf = window.map((m) => m.perfScore).whereType<double>().toList();
    enrichedGames = perf.length;
    avgPerf = mean(perf);
    final det = window.where((m) => m.hasDetail).toList();
    detailGames = det.length;
    avgGpm = mean(det.map((m) => m.gpm));
    avgXpm = mean(det.map((m) => m.xpm));
    avgDamage = mean(det.map((m) => m.heroDamage));
    avgNetWorth = mean(det.map((m) => m.netWorth));
    avgLastHits = mean(det.map((m) => m.lastHits));
    avgHealing = mean(det.map((m) => m.heroHealing));
    bestStreak = longestWinStreak(window);
  }

  String get name => player.name;
  int? get currentMmr => ledger.current;
  String get rank => rankLabel(player.rankTier, player.leaderboardRank);
  bool get onStreak => streak.$2 >= 2;
  M? get last => all.isEmpty ? null : all.last;
}

// --- сравнение «сила в чате» -----------------------------------------------------------------------------

const minCompareGames = 5;

class Comparison {
  final Map<String, Map<String, int>> ranks; // имя → метрика → место
  final Map<String, double?> power;
  final Map<String, int> powerRank;
  final Map<String, List<String>> leads;
  final Map<String, double?> averages;
  Comparison(this.ranks, this.power, this.powerRank, this.leads, this.averages);
}

final Map<String, double? Function(PlayerSummary)> compareMetrics = {
  'perf': (s) => s.enrichedGames >= minCompareGames ? s.avgPerf : null,
  'winrate': (s) => s.agg.games > 0 ? s.agg.winrate : null,
  'kda': (s) => s.agg.games > 0 ? s.agg.kda : null,
  'gpm': (s) => s.detailGames >= minCompareGames ? s.avgGpm : null,
};

const compareLabels = {'perf': 'Перф', 'winrate': 'Винрейт', 'kda': 'KDA', 'gpm': 'GPM'};

Comparison buildComparison(List<PlayerSummary> ss) {
  final ranks = {for (final s in ss) s.name: <String, int>{}};
  final pos = {for (final s in ss) s.name: <double>[]};
  final leads = {for (final s in ss) s.name: <String>[]};
  final averages = <String, double?>{};
  compareMetrics.forEach((key, getter) {
    final valued = [
      for (final s in ss)
        if (getter(s) != null) (s.name, getter(s)!)
    ];
    averages[key] = mean(valued.map((v) => v.$2));
    valued.sort((a, b) => b.$2.compareTo(a.$2));
    final n = valued.length;
    for (var i = 0; i < n; i++) {
      final name = valued[i].$1;
      ranks[name]![key] = i + 1;
      if (i == 0 && n > 1) leads[name]!.add(key);
      pos[name]!.add(n > 1 ? (n - 1 - i) / (n - 1) : 1.0);
    }
  });
  final power = {for (final s in ss) s.name: mean(pos[s.name]!)};
  final order = ss.map((s) => s.name).toList()
    ..sort((a, b) {
      final pa = power[a], pb = power[b];
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pb.compareTo(pa);
    });
  final powerRank = {for (var i = 0; i < order.length; i++) order[i]: i + 1};
  return Comparison(ranks, power, powerRank, leads, averages);
}

// --- совместные игры ------------------------------------------------------------------------------------

Map<int, bool> _winMap(List<M> ms) => {
      for (final m in ms)
        if (m.partySize != 1) m.matchId: m.won
    };

class TogetherSummary {
  final int games, wins;
  TogetherSummary(this.games, this.wins);
  int get losses => games - wins;
}

TogetherSummary togetherSummary(List<(String, List<M>)> players) {
  final byMatch = <int, List<bool>>{};
  for (final p in players) {
    _winMap(p.$2).forEach((id, won) => byMatch.putIfAbsent(id, () => []).add(won));
  }
  var games = 0, wins = 0;
  for (final o in byMatch.values) {
    final w = o.where((x) => x).length, l = o.length - w;
    if (math.max(w, l) < 2 || w == l) continue;
    games++;
    if (w > l) wins++;
  }
  return TogetherSummary(games, wins);
}

class Pair {
  final int a, b, games, wins;
  Pair(this.a, this.b, this.games, this.wins);
  double get winrate => games == 0 ? 0 : wins / games;
}

List<Pair> pairStats(List<(String, List<M>)> players) {
  final maps = players.map((p) => _winMap(p.$2)).toList();
  final res = <Pair>[];
  for (var a = 0; a < maps.length; a++) {
    for (var b = a + 1; b < maps.length; b++) {
      var g = 0, w = 0;
      for (final id in maps[a].keys) {
        final wb = maps[b][id];
        if (wb == null || wb != maps[a][id]) continue;
        g++;
        if (wb) w++;
      }
      if (g > 0) res.add(Pair(a, b, g, w));
    }
  }
  return res;
}

Pair? bestDuo(List<Pair> pairs) {
  Pair? best;
  for (final p in pairs) {
    if (best == null || p.games > best.games || (p.games == best.games && p.winrate > best.winrate)) best = p;
  }
  return best;
}

// --- соревнование / номинации -------------------------------------------------------------------------

class StandingEntry {
  final String player;
  final int place;
  final double value;
  final String text;
  StandingEntry(this.player, this.place, this.value, this.text);
}

class Standing {
  final String key, emoji, title;
  final bool anti;
  final List<StandingEntry> entries;
  Standing(this.key, this.emoji, this.title, this.anti, this.entries);
}

double? matchBench(M m, String metric) => m.bench?[metric];

List<Standing> computeStandings(List<(String, List<M>)> named, {int step = 25, int minGames = 3, int top = 3}) {
  final players = <String, List<M>>{
    for (final p in named)
      if (p.$2.isNotEmpty) p.$1: ([...p.$2]..sort((a, b) => a.startTime.compareTo(b.startTime)))
  };
  final out = <Standing>[];

  void add(String key, String emoji, String title, Map<String, double> values, String Function(String) detail,
      {bool lowest = false, double floor = 0, bool anti = false, bool Function(double)? keep}) {
    if (values.length < 2) return;
    final vs = values.values;
    if (vs.reduce(math.max) == vs.reduce(math.min)) return;
    final ordered = values.entries.toList()..sort((a, b) => lowest ? a.value.compareTo(b.value) : b.value.compareTo(a.value));
    final shown = ordered.where((e) => (e.value >= floor || lowest) && (keep == null || keep(e.value))).toList();
    if (shown.isEmpty) return;
    final entries = <StandingEntry>[];
    var place = 1;
    for (var i = 0; i < shown.length && i < top; i++) {
      if (i > 0 && shown[i].value != shown[i - 1].value) place = i + 1;
      entries.add(StandingEntry(shown[i].key, place, shown[i].value, detail(shown[i].key)));
    }
    out.add(Standing(key, emoji, title, anti, entries));
  }

  final played = players;
  final regular = {
    for (final e in played.entries)
      if (e.value.length >= minGames) e.key: e.value
  };

  final deltas = played.map((n, ms) => MapEntry(n, mmrDelta(ms, step).toDouble()));
  String sgn(double v) => v >= 0 ? '+${v.toInt()}' : '${v.toInt()}';
  add('climb', '🚀', 'Больше всех поднялся', deltas, (n) => '${sgn(deltas[n]!)} MMR', keep: (v) => v > 0);
  add('drop', '📉', 'Больше всех просел', deltas, (n) => '${sgn(deltas[n]!)} MMR', lowest: true, anti: true, keep: (v) => v < 0);
  add('games', '🕹️', 'Больше всех играл', played.map((n, ms) => MapEntry(n, ms.length.toDouble())),
      (n) => gamesWord(played[n]!.length));

  final winrates = regular.map((n, ms) => MapEntry(n, ms.where((m) => m.won).length / ms.length));
  add('winrate', '👑', 'Лучший винрейт', winrates,
      (n) => '${(winrates[n]! * 100).toStringAsFixed(0)}% за ${gamesWord(regular[n]!.length)}');

  Map<String, double> averages(num? Function(M) f) {
    final r = <String, double>{};
    regular.forEach((n, ms) {
      final v = mean(ms.map(f));
      if (v != null) r[n] = v;
    });
    return r;
  }

  final perf = averages((m) => m.perfScore);
  add('perf', '⭐', 'Лучший перф', perf, (n) => '${(perf[n]! * 100).toStringAsFixed(0)}/100');

  final samples = math.min(2, minGames);
  Map<String, List<num>> sampled(num? Function(M) f, [bool Function(num)? known]) {
    final r = <String, List<num>>{};
    regular.forEach((n, ms) {
      final v = ms.map(f).whereType<num>().where((x) => known == null || known(x)).toList();
      if (v.length >= samples) r[n] = v;
    });
    return r;
  }

  Map<String, (double, double)> heroRelative(num? Function(M) f, String metric) {
    final r = <String, (double, double)>{};
    regular.forEach((n, ms) {
      final pcts = ms.map((m) => matchBench(m, metric)).whereType<double>().toList();
      final raws = ms.map(f).whereType<num>().toList();
      if (pcts.length >= samples && raws.isNotEmpty) r[n] = (mean(pcts)!, mean(raws)!);
    });
    return r;
  }

  final gpmRel = heroRelative((m) => m.gpm, 'gold_per_min');
  if (gpmRel.length >= 2) {
    add('gpm', '💰', 'GPM для своего героя', gpmRel.map((k, v) => MapEntry(k, v.$1)),
        (n) => '${gpmRel[n]!.$2.toStringAsFixed(0)} GPM · лучше ${(gpmRel[n]!.$1 * 100).toStringAsFixed(0)}%');
  } else {
    final gpm = averages((m) => m.gpm);
    add('gpm', '💰', 'Наибольший GPM', gpm, (n) => '${gpm[n]!.toStringAsFixed(0)} GPM в среднем');
  }
  final dmgRel = heroRelative((m) => m.heroDamage, 'hero_damage_per_min');
  if (dmgRel.length >= 2) {
    add('damage', '💥', 'Урон для своего героя', dmgRel.map((k, v) => MapEntry(k, v.$1)),
        (n) => '${(dmgRel[n]!.$2 / 1000).toStringAsFixed(1)}k · лучше ${(dmgRel[n]!.$1 * 100).toStringAsFixed(0)}%');
  } else {
    final dmg = averages((m) => m.heroDamage);
    add('damage', '💥', 'Наибольший урон по героям', dmg, (n) => '${(dmg[n]! / 1000).toStringAsFixed(1)}k урона/игра');
  }
  final assists = averages((m) => m.assists);
  add('assists', '🤝', 'Больше всего ассистов', assists, (n) => '${assists[n]!.toStringAsFixed(1)} ассистов/игра');

  final wards = sampled((m) => m.wards).map((k, v) => MapEntry(k, mean(v)!));
  add('wards', '👁️', 'Лучший вижн', wards, (n) => '${wards[n]!.toStringAsFixed(1)} вардов/игра', floor: 1);
  final stacks = sampled((m) => m.stacks).map((k, v) => MapEntry(k, mean(v)!));
  add('stacks', '🏕️', 'Мастер стаков', stacks, (n) => '${stacks[n]!.toStringAsFixed(1)} стаков/игра', floor: 0.5);
  final lanes = sampled((m) => m.laneResult);
  final laneShare = lanes.map((k, v) => MapEntry(k, v.where((x) => x > 0).length / v.length));
  add('lane', '🛣️', 'Победитель линии', laneShare, (n) => 'выиграл ${(laneShare[n]! * 100).toStringAsFixed(0)}% линий');
  final shard = sampled((m) => m.shardTime, (t) => t > 0).map((k, v) => MapEntry(k, mean(v)!));
  add('fast_shard', '⚡', 'Самый быстрый шард', shard, (n) {
    final s = shard[n]!.round();
    return 'шард в среднем на ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }, lowest: true);

  final best = <String, M>{};
  played.forEach((n, ms) {
    final b = bestGame(ms);
    if (b != null) best[n] = b;
  });
  add('best_game', '🎯', 'Лучшая игра', best.map((k, v) => MapEntry(k, v.kda)),
      (n) => '${best[n]!.kills}/${best[n]!.deaths}/${best[n]!.assists} (KDA ${best[n]!.kda.toStringAsFixed(1)})');

  final streaks = played.map((n, ms) => MapEntry(n, longestWinStreak(ms).toDouble()));
  add('win_streak', '🔥', 'Лучшая серия побед', streaks, (n) => '${streaks[n]!.toInt()} подряд', floor: 2);
  final deaths = averages((m) => m.deaths);
  add('deaths', '💀', 'Больше всего смертей', deaths, (n) => '${deaths[n]!.toStringAsFixed(1)} смертей/игра', anti: true);
  final loss = played.map((n, ms) => MapEntry(n, longestLossStreak(ms).toDouble()));
  add('loss_streak', '🧊', 'Серия поражений', loss, (n) => '${loss[n]!.toInt()} подряд', floor: 3, anti: true);
  return out;
}

class PointsRow {
  final String player;
  int points = 0;
  int golds = 0;
  PointsRow(this.player);
  Map<String, dynamic> toJson() => {'player': player, 'points': points, 'golds': golds};
}

List<PointsRow> contestPoints(List<Standing> standings) {
  const byPlace = {1: 3, 2: 2, 3: 1};
  final table = <String, PointsRow>{};
  for (final s in standings) {
    for (final e in s.entries) {
      final row = table.putIfAbsent(e.player, () => PointsRow(e.player));
      if (s.anti) continue;
      row.points += byPlace[e.place] ?? 0;
      if (e.place == 1) row.golds++;
    }
  }
  final rows = table.values.toList()
    ..sort((a, b) {
      final c = b.points.compareTo(a.points);
      if (c != 0) return c;
      final g = b.golds.compareTo(a.golds);
      if (g != 0) return g;
      return a.player.compareTo(b.player);
    });
  return rows;
}

/// Награды за период: единственный лидер каждой номинации.
List<Standing> periodAwards(List<(String, List<M>)> named, int step) {
  final res = <Standing>[];
  for (final s in computeStandings(named, step: step, top: 2)) {
    if (s.entries.length > 1 && s.entries[1].place == 1) continue;
    res.add(Standing(s.key, s.emoji, s.title, s.anti, [s.entries.first]));
  }
  return res;
}

Map<String, String> currentLeaders(List<Standing> standings) {
  final r = <String, String>{};
  for (final s in standings) {
    if (s.anti) continue;
    final firsts = s.entries.where((e) => e.place == 1).toList();
    if (firsts.length == 1) r[s.key] = firsts.first.player;
  }
  return r;
}

// --- рекорды ------------------------------------------------------------------------------------------------

class RecordDef {
  final String key, emoji, title;
  final num? Function(M) getter;
  final String Function(num) fmt;
  final bool anti;
  const RecordDef(this.key, this.emoji, this.title, this.getter, this.fmt, {this.anti = false});
}

String kfmt(num v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

final recordDefs = <RecordDef>[
  RecordDef('gpm', '💰', 'Макс. GPM', (m) => m.gpm, (v) => '${v.toStringAsFixed(0)} GPM'),
  RecordDef('kills', '⚔️', 'Больше всего убийств', (m) => m.kills, (v) => plural(v.toInt(), 'убийство', 'убийства', 'убийств')),
  RecordDef('assists', '🤝', 'Больше всего ассистов', (m) => m.assists, (v) => plural(v.toInt(), 'ассист', 'ассиста', 'ассистов')),
  RecordDef('kda', '🎯', 'Лучший KDA', (m) => m.kills + m.assists < 10 ? null : m.kda, (v) => 'KDA ${v.toStringAsFixed(1)}'),
  RecordDef('hero_damage', '💥', 'Макс. урон по героям', (m) => m.heroDamage, (v) => '${kfmt(v)} урона'),
  RecordDef('tower_damage', '🏰', 'Макс. урон по строениям', (m) => m.towerDamage, (v) => '${kfmt(v)} урона'),
  RecordDef('hero_healing', '💚', 'Макс. лечение', (m) => (m.heroHealing ?? 0) == 0 ? null : m.heroHealing, (v) => '${kfmt(v)} лечения'),
  RecordDef('last_hits', '🌾', 'Больше всего добиваний', (m) => m.lastHits, (v) => plural(v.toInt(), 'добивание', 'добивания', 'добиваний')),
  RecordDef('net_worth', '💎', 'Макс. нетворс', (m) => m.netWorth, (v) => '${kfmt(v)} золота'),
  RecordDef('imp', '📊', 'Лучший IMP', (m) => m.imp, (v) => 'IMP ${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}'),
  RecordDef('duration', '⏳', 'Самая долгая игра', (m) => m.duration, (v) => '${(v / 60).toStringAsFixed(0)} мин'),
  RecordDef('deaths', '💀', 'Больше всего смертей', (m) => m.deaths, (v) => plural(v.toInt(), 'смерть', 'смерти', 'смертей'), anti: true),
];

class RecordRow {
  final RecordDef def;
  final String player;
  final num value;
  final M match;
  RecordRow(this.def, this.player, this.value, this.match);
  String get text => def.fmt(value);
}

(List<RecordRow>, (String, int)?) computeRecords(List<(String, List<M>)> named) {
  final out = <RecordRow>[];
  for (final def in recordDefs) {
    RecordRow? best;
    for (final p in named) {
      for (final m in p.$2) {
        final v = def.getter(m);
        if (v == null) continue;
        if (best == null || v > best.value || (v == best.value && m.startTime < best.match.startTime)) {
          best = RecordRow(def, p.$1, v, m);
        }
      }
    }
    if (best != null && (best.value > 0 || def.key == 'imp')) out.add(best);
  }
  (String, int)? streak;
  for (final p in named) {
    final s = longestWinStreak([...p.$2]..sort((a, b) => a.startTime.compareTo(b.startTime)));
    if (s >= 2 && (streak == null || s > streak.$2)) streak = (p.$1, s);
  }
  return (out, streak);
}

// --- матчапы -------------------------------------------------------------------------------------------------

const matchupPrior = 10.0;

class MatchupRow {
  final int heroId, games, wins;
  final double score;
  MatchupRow(this.heroId, this.games, this.wins, this.score);
  int get losses => games - wins;
  double get winrate => games == 0 ? 0 : wins / games;
}

class MatchupReport {
  final int total, games, wins, minGames;
  final List<MatchupRow> hard, easy, goodAllies, badAllies;
  MatchupReport(this.total, this.games, this.wins, this.minGames, this.hard, this.easy, this.goodAllies, this.badAllies);
  double get winrate => games == 0 ? 0.5 : wins / games;
  bool get isEmpty => hard.isEmpty && easy.isEmpty && goodAllies.isEmpty && badAllies.isEmpty;
}

int matchupThreshold(String period) => const {'day': 2, 'week': 2, 'month': 3}[period] ?? 4;

void _tally(Map<int, List<int>> b, int hero, bool won) {
  final s = b.putIfAbsent(hero, () => [0, 0]);
  s[0]++;
  if (won) s[1]++;
}

MatchupReport _report(Map<int, List<int>> against, Map<int, List<int>> allies, int counted, int wins, int total, int minGames,
    {int top = 5}) {
  final base = counted > 0 ? wins / counted : 0.5;
  List<MatchupRow> rows(Map<int, List<int>> b) => [
        for (final e in b.entries)
          if (e.value[0] >= minGames)
            MatchupRow(e.key, e.value[0], e.value[1], (e.value[1] + matchupPrior * base) / (e.value[0] + matchupPrior))
      ];
  (List<MatchupRow>, List<MatchupRow>) split(List<MatchupRow> r) {
    final best = r.where((x) => x.score > base).toList()..sort((a, b) => b.score.compareTo(a.score));
    final worst = r.where((x) => x.score < base).toList()..sort((a, b) => a.score.compareTo(b.score));
    return (best.take(top).toList(), worst.take(top).toList());
  }

  final a = split(rows(against)), l = split(rows(allies));
  return MatchupReport(total, counted, wins, minGames, a.$2, a.$1, l.$1, l.$2);
}

MatchupReport playerMatchups(List<M> ms, int minGames) {
  final against = <int, List<int>>{}, allies = <int, List<int>>{};
  var counted = 0, wins = 0;
  for (final m in ms) {
    if (m.radiant == null || m.dire == null || m.radiant!.isEmpty || m.dire!.isEmpty) continue;
    counted++;
    if (m.won) wins++;
    final mine = m.isRadiant ? m.radiant! : m.dire!;
    final theirs = m.isRadiant ? m.dire! : m.radiant!;
    var skipped = false;
    for (final h in mine) {
      if (h == m.heroId && !skipped) {
        skipped = true;
        continue;
      }
      _tally(allies, h, m.won);
    }
    for (final h in theirs) {
      _tally(against, h, m.won);
    }
  }
  return _report(against, allies, counted, wins, ms.length, minGames);
}

MatchupReport partyMatchups(List<(String, List<M>)> named, int minGames) {
  final sides = <(int, bool), (bool, List<int>, M)>{};
  final ids = <int>{};
  for (final p in named) {
    for (final m in p.$2) {
      ids.add(m.matchId);
      final key = (m.matchId, m.isRadiant);
      final e = sides.putIfAbsent(key, () => (m.won, <int>[], m));
      if (m.heroId != null) e.$2.add(m.heroId!);
    }
  }
  final against = <int, List<int>>{}, allies = <int, List<int>>{};
  var counted = 0, wins = 0;
  sides.forEach((key, e) {
    final m = e.$3;
    if (m.radiant == null || m.dire == null || m.radiant!.isEmpty || m.dire!.isEmpty) return;
    counted++;
    if (e.$1) wins++;
    final mine = key.$2 ? m.radiant! : m.dire!;
    final theirs = key.$2 ? m.dire! : m.radiant!;
    final own = [...e.$2];
    for (final h in mine) {
      if (own.remove(h)) continue;
      _tally(allies, h, e.$1);
    }
    for (final h in theirs) {
      _tally(against, h, e.$1);
    }
  });
  return _report(against, allies, counted, wins, ids.length, minGames);
}

// --- сезоны -------------------------------------------------------------------------------------------------

bool seasonDue(Season s, int now) => s.endTs == null && now >= s.plannedEndTs;
int seasonDaysLeft(Season s, int now) {
  final left = s.plannedEndTs - now;
  if (left <= 0) return 0;
  return (left + 86399) ~/ 86400;
}

List<int> _seasonRanks(List<Map<String, dynamic>> table) {
  final ranks = <int>[];
  for (var i = 0; i < table.length; i++) {
    final same = i > 0 && table[i]['points'] == table[i - 1]['points'] && table[i]['golds'] == table[i - 1]['golds'];
    ranks.add(same ? ranks.last : i + 1);
  }
  return ranks;
}

class HallRow {
  final String player;
  int titles = 0, silver = 0, bronze = 0;
  HallRow(this.player);
}

List<HallRow> hallRows(List<Season> finished) {
  final stats = <String, HallRow>{};
  HallRow row(String n) => stats.putIfAbsent(n, () => HallRow(n));
  for (final s in finished) {
    final r = _seasonRanks(s.table);
    for (var i = 0; i < s.table.length; i++) {
      final name = s.table[i]['player'].toString();
      if (r[i] == 1) {
        if (s.champion == name) row(name).titles++;
      } else if (r[i] == 2) {
        row(name).silver++;
      } else if (r[i] == 3) {
        row(name).bronze++;
      }
    }
  }
  final rows = stats.values.toList()
    ..sort((a, b) {
      for (final c in [b.titles - a.titles, b.silver - a.silver, b.bronze - a.bronze]) {
        if (c != 0) return c;
      }
      return a.player.compareTo(b.player);
    });
  return rows;
}

/// Чемпион по таблице очков: единственный лидер (иначе null).
String? championOf(List<PointsRow> table) {
  if (table.isEmpty || table.first.points == 0) return null;
  if (table.length > 1 && table[1].points == table[0].points && table[1].golds == table[0].golds) return null;
  return table.first.player;
}
