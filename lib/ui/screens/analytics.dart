import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare.dart';
import 'contest.dart';
import 'graph.dart';
import 'heroes.dart';
import 'matchups.dart';
import 'records.dart';
import 'roles.dart';
import 'together.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String period = 'month';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Аналитика',
      leading: Icons.refresh_rounded,
      onLeading: () => store.refreshAll(force: true),
      trailing: const HeaderAvatar(),
      onRefresh: () => store.refreshAll(force: true),
      children: [
        Row(children: [
          CircleBtn(Icons.search_rounded, color: C.surface, onTap: () => push(context, const HeroesScreen())),
          const Spacer(),
          PopupMenuButton<String>(
            color: C.surface2,
            onSelected: (v) => setState(() => period = v),
            itemBuilder: (_) => [for (final e in periodLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            child: const IgnorePointer(child: CircleBtn(Icons.calendar_today_outlined, color: C.surface)),
          ),
          const SizedBox(width: 8),
          CircleBtn(Icons.folder_open_outlined, color: C.surface, onTap: () => push(context, const RecordsScreen())),
          const SizedBox(width: 8),
          CircleBtn(Icons.add_rounded, filled: true, onTap: () => openAdd(context)),
        ]),
        const SizedBox(height: 14),
        if (store.players.isEmpty) const NoPlayers() else ...[
          _goal(context, store),
          const SizedBox(height: 14),
          _distribution(context, store),
          const SizedBox(height: 14),
          _graph(context, store),
          SectionTitle('Разделы', trailing: Text(periodLong[period]!, style: T.small)),
          _grid(context),
        ],
      ],
    );
  }

  /// «Цель месяца»: винрейт пати против 50% (как Monthly Sales Goal).
  Widget _goal(BuildContext context, Store store) {
    final named = store.named(period);
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
    // сколько побед подряд нужно, чтобы выйти на 55%
    var need = 0;
    while (games > 0 && (wins + need) / (games + need) < 0.55 && need < 200) {
      need++;
    }
    final msg = games == 0
        ? 'Сыграйте пару ранкед-игр — здесь появится винрейт пати.'
        : wr >= 0.55
            ? 'Отлично! Винрейт пати выше 55%. Так держать.'
            : 'Ещё $need ${plural(need, 'победа', 'победы', 'побед').split(' ').last} подряд до 55%. Каждая катка на счету.';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Винрейт пати', style: T.sub),
              Text('Цель: 55% · ${periodLong[period]}', style: T.small),
            ]),
          ),
          CircleBtn(Icons.more_vert_rounded, size: 40, onTap: () => push(context, const CompareScreen())),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(games == 0 ? '—' : pct(wr), style: T.display),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$wins–${games - wins}', style: T.small.copyWith(color: C.text)),
          ),
        ]),
        const SizedBox(height: 10),
        BarMeter(wr, bars: 36),
        const SizedBox(height: 12),
        Text(msg, style: T.small.copyWith(color: C.text)),
      ]),
    );
  }

  /// Кольцо: распределение игр по игрокам.
  Widget _distribution(BuildContext context, Store store) {
    final named = store.named(period);
    final total = named.fold<int>(0, (a, n) => a + n.$2.length);
    final segs = <(double, Color)>[
      for (var i = 0; i < named.length; i++) (named[i].$2.length.toDouble(), C.seriesOf(i)),
    ];
    return AppCard(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Распределение игр', style: T.sub),
              Text('кто сколько играл ${periodLong[period]}', style: T.small),
            ]),
          ),
          CircleBtn(Icons.north_east_rounded, size: 40, onTap: () => push(context, const TogetherScreen())),
        ]),
        const SizedBox(height: 16),
        Donut(
          size: 210,
          segments: segs,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: T.big.copyWith(fontSize: 34)),
            Text('игр всего', style: T.small),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 14, runSpacing: 8, children: [
          for (var i = 0; i < named.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: C.seriesOf(i), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${named[i].$1} · ${named[i].$2.length}', style: T.small.copyWith(color: C.text)),
            ]),
        ]),
      ]),
    );
  }

  Widget _graph(BuildContext context, Store store) {
    final step = store.settings.mmrStep;
    final since = periodSince(period);
    final series = <(String, Color, List<(double, double)>)>[];
    for (var i = 0; i < store.players.length; i++) {
      final p = store.players[i];
      final tl = mmrTimeline(store.matchesOf(p), p.anchors, step)
          .where((e) => since == null || e.$1 >= since)
          .map((e) => (e.$1.toDouble(), e.$2.toDouble()))
          .toList();
      if (tl.isNotEmpty) series.add((p.name, C.seriesOf(i), tl));
    }
    return AppCard(
      onTap: () => push(context, const GraphScreen()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('График MMR', style: T.sub)),
          const Icon(Icons.north_east_rounded, color: C.muted, size: 18),
        ]),
        const SizedBox(height: 12),
        if (series.isEmpty)
          Text('Нет игр за период', style: T.small)
        else
          LineChart(series: series, height: 180, xLabel: (x) => fmtDate(x.toInt(), time: false)),
      ]),
    );
  }

  Widget _grid(BuildContext context) {
    final items = [
      (Icons.compare_arrows_rounded, 'Сравнение', 'сила в пати', () => push(context, const CompareScreen())),
      (Icons.people_alt_outlined, 'Вместе', 'пары и совместные', () => push(context, const TogetherScreen())),
      (Icons.local_fire_department_outlined, 'Герои', 'любимые и лучшие', () => push(context, const HeroesScreen())),
      (Icons.sports_kabaddi_outlined, 'Соперники', 'тяжёлые и удобные', () => push(context, const MatchupsScreen())),
      (Icons.workspace_premium_outlined, 'Рекорды', 'лучшие игры', () => push(context, const RecordsScreen())),
      (Icons.emoji_events_outlined, 'Соревнование', 'номинации, сезон', () => push(context, const ContestScreen())),
      (Icons.timeline_rounded, 'График MMR', 'по времени и играм', () => push(context, const GraphScreen())),
      (Icons.view_week_outlined, 'Позиции', '1–5 (Stratz)', () => push(context, const RolesScreen())),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (final it in items)
          AppCard(
            onTap: it.$4,
            radius: 22,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: C.surface2, shape: BoxShape.circle),
                child: Icon(it.$1, color: C.lime, size: 20),
              ),
              const Spacer(),
              Text(it.$2, style: T.body.copyWith(fontWeight: FontWeight.w800)),
              Text(it.$3, style: T.tiny),
            ]),
          ),
      ],
    );
  }
}
