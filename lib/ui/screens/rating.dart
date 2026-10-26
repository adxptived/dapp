import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  String? period;
  String sort = 'mmr';

  static const sorts = {'mmr': '≈MMR', 'delta': '±MMR', 'winrate': 'Винрейт', 'kda': 'KDA', 'games': 'Игры', 'perf': 'Перф'};

  List<PlayerSummary> _sorted(List<PlayerSummary> ss) {
    final list = [...ss];
    int cmpNum(num? a, num? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (sort) {
      case 'delta':
        list.sort((a, b) => b.periodDelta.compareTo(a.periodDelta));
      case 'winrate':
        list.sort((a, b) => cmpNum(a.agg.games > 0 ? a.agg.winrate : null, b.agg.games > 0 ? b.agg.winrate : null));
      case 'kda':
        list.sort((a, b) => cmpNum(a.agg.games > 0 ? a.agg.kda : null, b.agg.games > 0 ? b.agg.kda : null));
      case 'games':
        list.sort((a, b) => b.agg.games.compareTo(a.agg.games));
      case 'perf':
        list.sort((a, b) => cmpNum(a.avgPerf, b.avgPerf));
      default:
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final p = period ?? store.settings.defaultPeriod;
    final ss = _sorted(store.summaries(p));
    final now = DateTime.now();
    return PageScaffold(
      title: 'Рейтинг',
      leading: Icons.refresh_rounded,
      onLeading: () => store.refreshAll(force: true),
      trailing: const HeaderAvatar(),
      onRefresh: () => store.refreshAll(force: true),
      children: [
        const StaleBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
          child: Text('Отчёт · ${monthsFull[now.month - 1]}', style: T.h1.copyWith(fontSize: 24)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            DropChip<String>(label: 'Период', value: p, options: periodLabels, onChanged: (v) => setState(() => period = v)),
            const SizedBox(width: 8),
            DropChip<String>(label: 'Сортировка', value: sort, options: sorts, onChanged: (v) => setState(() => sort = v)),
          ]),
        ),
        const SizedBox(height: 14),
        if (store.players.isEmpty) const NoPlayers() else ...[
          _overview(context, store, p, ss),
          const SizedBox(height: 14),
          for (var i = 0; i < ss.length; i++) ...[_playerCard(context, store, ss[i], i + 1), const SizedBox(height: 10)],
          const SizedBox(height: 6),
          LimeButton('Сравнение игроков', icon: Icons.compare_arrows_rounded, onTap: () => push(context, const CompareScreen())),
        ],
      ],
    );
  }

  Widget _overview(BuildContext context, Store store, String p, List<PlayerSummary> ss) {
    final named = store.named(p);
    final together = togetherSummary(named);
    final ids = <int>{};
    var games = 0, wins = 0;
    for (final n in named) {
      for (final m in n.$2) {
        if (ids.add(m.matchId * 2 + (m.isRadiant ? 1 : 0))) {
          games++;
          if (m.won) wins++;
        }
      }
    }
    final wr = games == 0 ? 0.0 : wins / games;
    final mmrs = ss.map((s) => s.currentMmr).whereType<int>().toList();
    final avgMmr = mmrs.isEmpty ? null : mmrs.reduce((a, b) => a + b) / mmrs.length;
    final totalDelta = ss.fold<int>(0, (a, s) => a + s.periodDelta);
    final pairs = pairStats(named);
    final duo = bestDuo(pairs);

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Обзор', style: T.sub),
              Text(periodLong[p]!, style: T.small),
            ]),
          ),
          CircleBtn(Icons.info_outline_rounded, size: 42, onTap: () => _info(context, store)),
          const SizedBox(width: 8),
          CircleBtn(Icons.ios_share_rounded, size: 42, onTap: () => _share(store, p, ss)),
        ]),
        const SizedBox(height: 14),
        KvTable(headLeft: 'Метрика', headRight: 'Все игры', rows: [
          ('Текущее', valueText('$games')),
          ('Победы', valueText('$wins–${games - wins}', color: C.lime)),
          ('Винрейт', valueText(pct(wr), color: wr >= 0.5 ? C.lime : C.red)),
          ('Статус', valueText(games == 0 ? 'Тишина' : wr >= 0.55 ? 'Разнос' : wr >= 0.5 ? 'В плюсе' : 'В минусе')),
        ]),
        const SizedBox(height: 10),
        KvTable(headLeft: 'Метрика', headRight: 'Рейтинг', rows: [
          ('Средний MMR', valueText(avgMmr == null ? '—' : '≈${avgMmr.round()}')),
          ('Изменение', valueText('${signed(totalDelta)} MMR', color: deltaColor(totalDelta))),
          ('Вместе', valueText(together.games == 0 ? 'нет игр' : '${together.wins}–${together.losses}')),
          (
            'Лучшая пара',
            valueText(duo == null ? '—' : '${named[duo.a].$1} + ${named[duo.b].$1} (${duo.games})'),
          ),
        ]),
      ]),
    );
  }

  Widget _playerCard(BuildContext context, Store store, PlayerSummary s, int place) {
    final mmr = s.currentMmr;
    final streak = s.streak;
    return AppCard(
      onTap: () => openPlayer(context, s.player),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          placeBadge(place),
          const SizedBox(width: 10),
          Avatar(s.player.avatar, size: 44, fallback: s.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.name, style: T.sub, overflow: TextOverflow.ellipsis)),
                if (s.player.isMe) ...[const SizedBox(width: 6), const SmallPill('я', lime: true)],
                if (s.player.privateHistory) ...[const SizedBox(width: 6), const Icon(Icons.lock_outline, size: 14, color: C.muted)],
              ]),
              const SizedBox(height: 3),
              RankBadge(s.player.rankTier, leaderboard: s.player.leaderboardRank, size: 20),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(mmr == null ? '—' : '≈$mmr', style: T.title.copyWith(fontSize: 20)),
            DeltaText(s.periodDelta, suffix: ' MMR'),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _mini('Игры', '${s.agg.games}'),
          _mini('W–L', '${s.agg.wins}–${s.agg.losses}'),
          _mini('Винрейт', s.agg.games == 0 ? '—' : pct(s.agg.winrate)),
          _mini('KDA', s.agg.games == 0 ? '—' : s.agg.kda.toStringAsFixed(1)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          FormDots(s.form),
          const SizedBox(width: 8),
          if (streak.$2 >= 2)
            Text(streak.$1 == true ? '🔥 ${streak.$2} побед подряд' : '🧊 ${streak.$2} поражений подряд', style: T.tiny),
          const Spacer(),
          for (final h in s.topHeroes.take(3)) Padding(padding: const EdgeInsets.only(left: 4), child: HeroIcon(h.heroId, height: 20, radius: 4)),
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: T.tiny),
            Text(value, style: T.body.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  void _info(BuildContext context, Store store) {
    showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 40),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Про MMR', style: T.title),
          const SizedBox(height: 10),
          Text(
            'Точный MMR не отдаёт ни один публичный API, поэтому он оценивается:\n\n'
            'MMR ≈ заданный MMR + (победы − поражения) × ${store.settings.mmrStep}\n\n'
            'Стартовый MMR задаётся при добавлении игрока или в его карточке («Задать MMR»). '
            'Ранг, игры, KDA, винрейт, герои и GPM — настоящие данные OpenDota. '
            'Считаются только ранкед-игры. Матчи видны, если в Dota 2 включена «Общедоступная история матчей».',
            style: T.body.copyWith(color: C.muted, height: 1.4),
          ),
        ]),
      ),
    );
  }

  void _share(Store store, String p, List<PlayerSummary> ss) {
    final b = StringBuffer('🏆 Рейтинг ${periodLong[p]}\n');
    for (var i = 0; i < ss.length; i++) {
      final s = ss[i];
      b.write('${i + 1}. ${s.name} — ${s.currentMmr == null ? '' : '≈${s.currentMmr} '}'
          '(${signed(s.periodDelta)}) · ${s.agg.wins}–${s.agg.losses}\n');
    }
    final uri = Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent('Dota Manager')}&text=${Uri.encodeComponent(b.toString())}');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
