import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Соревнование: общий зачёт (3/2/1 очка), номинации с топ-3, антирекорды; сезоны и зал славы.
class ContestScreen extends StatefulWidget {
  const ContestScreen({super.key});
  @override
  State<ContestScreen> createState() => _ContestScreenState();
}

class _ContestScreenState extends State<ContestScreen> {
  String tab = 'contest';
  String period = 'week';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Соревнование',
      children: [
        Segments<String>(
          value: tab,
          options: const {'contest': 'Зачёт', 'season': 'Сезон', 'hall': 'Зал славы'},
          onChanged: (v) => setState(() => tab = v),
        ),
        const SizedBox(height: 14),
        ...switch (tab) {
          'season' => _season(context, store),
          'hall' => _hall(store),
          _ => _contest(store),
        },
      ],
    );
  }

  List<Widget> _contest(Store store) {
    final standings = computeStandings(store.named(period), step: store.settings.mmrStep);
    final points = contestPoints(standings);
    return [
      Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
      const SizedBox(height: 14),
      if (standings.isEmpty)
        const EmptyState(
            title: 'Пока не с кем соревноваться',
            text: 'Нужно минимум двое игроков с играми за период.',
            icon: Icons.emoji_events_outlined)
      else ...[
        _podium(store, points),
        const SizedBox(height: 14),
        for (final s in standings.where((s) => !s.anti)) _standing(store, s),
        if (standings.any((s) => s.anti)) ...[
          const SectionTitle('Антирекорды'),
          for (final s in standings.where((s) => s.anti)) _standing(store, s),
        ],
        const SizedBox(height: 6),
        Text('3/2/1 очка за места; GPM и урон — перцентиль на своём герое, если есть бенчмарки.', style: T.tiny),
      ],
    ];
  }

  Widget _podium(Store store, List<PointsRow> points) {
    final top = points.take(3).toList();
    Widget col(int i, double h) {
      if (i >= top.length) return const Expanded(child: SizedBox());
      final r = top[i];
      final p = store.byName(r.player);
      final color = [C.gold, C.silver, C.bronze][i];
      return Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Avatar(p?.avatar, size: i == 0 ? 56 : 46, fallback: r.player, ring: i == 0),
          const SizedBox(height: 6),
          Text(r.player, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          Text('${r.points} очк.', style: T.tiny),
          const SizedBox(height: 6),
          Container(
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, color.withValues(alpha: 0.2)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            child: Text('${i + 1}', style: T.big.copyWith(color: C.onLime)),
          ),
        ]),
      );
    }

    return AppCard(
      child: Column(children: [
        SizedBox(
          height: 230,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [col(1, 80), col(0, 110), col(2, 60)]),
        ),
        if (points.length > 3) ...[
          const SizedBox(height: 10),
          for (var i = 3; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                placeBadge(i + 1),
                const SizedBox(width: 10),
                Expanded(child: Text(points[i].player, style: T.small.copyWith(color: C.text))),
                Text('${points[i].points} очк.', style: T.small),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _standing(Store store, Standing s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(s.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(s.title, style: T.sub)),
            ]),
            const SizedBox(height: 8),
            for (final e in s.entries)
              PlayerLine(
                player: store.byName(e.player),
                name: e.player,
                sub: e.text,
                lead: placeBadge(e.place),
              ),
          ]),
        ),
      );

  List<Widget> _season(BuildContext context, Store store) {
    final s = store.currentSeason;
    final now = nowTs();
    if (s == null) {
      return [
        EmptyState(
          icon: Icons.flag_outlined,
          title: 'Сезон не идёт',
          text: 'Сезон — окно, в котором считаются очки соревнования. По окончании объявляется чемпион, итог уходит в зал славы.',
          action: LimeButton('Начать сезон на ${store.settings.seasonDays} дн.', onTap: () async {
            final v = await prompt(context, 'Длительность сезона (7–365 дней)',
                initial: '${store.settings.seasonDays}', keyboard: TextInputType.number);
            final d = int.tryParse(v ?? '');
            if (d == null) return;
            await store.startSeason(d.clamp(7, 365));
          }),
        ),
      ];
    }
    final table = store.seasonTable(s);
    final left = seasonDaysLeft(s, now);
    final elapsed = ((now - s.startTs) / (s.plannedEndTs - s.startTs)).clamp(0.0, 1.0);
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Сезон ${s.number}', style: T.title.copyWith(fontSize: 22)),
          Text('${fmtDate(s.startTs, time: false)} – ${fmtDate(s.plannedEndTs, time: false)}', style: T.small),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$left', style: T.display),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('дн. осталось', style: T.small)),
          ]),
          const SizedBox(height: 10),
          BarMeter(elapsed, bars: 36, height: 30),
        ]),
      ),
      const SectionTitle('Зачёт сезона'),
      if (table.isEmpty) Text('Пока не с кем соревноваться', style: T.small),
      for (var i = 0; i < table.length; i++)
        PlayerLine(
          player: store.byName(table[i].player),
          name: table[i].player,
          sub: '${table[i].points} очк. · 🥇 ${table[i].golds}',
          lead: placeBadge(i + 1),
        ),
      const SizedBox(height: 16),
      LimeButton('Завершить сезон досрочно', dark: true, onTap: () async {
        if (!await confirm(context, 'Завершить сезон ${s.number}?', 'Будет объявлен чемпион, новый сезон не начнётся.')) return;
        final (_, champ) = await store.endSeason(s);
        if (context.mounted) toast(context, champ == null ? 'Сезон завершён, чемпиона нет' : 'Чемпион сезона: $champ 🏆');
      }),
    ];
  }

  List<Widget> _hall(Store store) {
    final finished = store.finishedSeasons;
    if (finished.isEmpty) {
      return [const EmptyState(icon: Icons.account_balance_outlined, title: 'Зал славы пуст', text: 'Ни один сезон ещё не завершён.')];
    }
    final rows = hallRows(finished);
    return [
      AppCard(
        child: Column(children: [
          for (final r in rows)
            PlayerLine(
              player: store.byName(r.player),
              name: r.player,
              trailing: Text(
                [if (r.titles > 0) '🏆 ${r.titles}', if (r.silver > 0) '🥈 ${r.silver}', if (r.bronze > 0) '🥉 ${r.bronze}'].join('  '),
                style: T.body,
              ),
            ),
        ]),
      ),
      const SectionTitle('Сезоны'),
      for (final Season s in finished.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Text('🏆', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Сезон ${s.number}', style: T.sub),
                  Text('${fmtDate(s.startTs, time: false)} – ${fmtDate(s.endTs ?? s.plannedEndTs, time: false)}', style: T.tiny),
                ]),
              ),
              Text(
                s.champion == null
                    ? 'без чемпиона'
                    : '${s.champion} (${s.table.isEmpty ? '' : s.table.first['points']} очк.)',
                style: T.small.copyWith(color: s.champion == null ? C.muted : C.lime),
              ),
            ]),
          ),
        ),
    ];
  }
}
