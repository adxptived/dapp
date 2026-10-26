import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../fx.dart';
import '../theme.dart';
import '../widgets.dart';

/// Все матчи игрока по 20 на страницу (номер, герой, исход, K/D/A, ±MMR, длительность, крипы).
class MatchesListScreen extends StatefulWidget {
  final int accountId;
  const MatchesListScreen({super.key, required this.accountId});
  @override
  State<MatchesListScreen> createState() => _MatchesListScreenState();
}

class _MatchesListScreenState extends State<MatchesListScreen> {
  int page = 0;
  int? heroFilter;
  bool? winFilter;
  static const per = 20;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final p = store.byId(widget.accountId);
    if (p == null) return const PageScaffold(title: 'Матчи', children: []);
    var all = store.matchesOf(p).reversed.toList();
    if (heroFilter != null) all = all.where((m) => m.heroId == heroFilter).toList();
    if (winFilter != null) all = all.where((m) => m.won == winFilter).toList();
    final pages = (all.length / per).ceil().clamp(1, 1 << 30);
    if (page >= pages) page = pages - 1;
    final slice = all.skip(page * per).take(per).toList();
    final heroes = heroStats(store.matchesOf(p));
    final step = store.settings.mmrStep;
    return PageScaffold(
      title: 'Матчи · ${p.name}',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            DropChip<String>(
              label: 'Исход',
              value: winFilter == null ? 'all' : (winFilter! ? 'w' : 'l'),
              options: const {'all': 'Все', 'w': 'Победы', 'l': 'Поражения'},
              onChanged: (v) => setState(() {
                winFilter = v == 'all' ? null : v == 'w';
                page = 0;
              }),
            ),
            const SizedBox(width: 8),
            DropChip<int>(
              label: 'Герой',
              value: heroFilter ?? 0,
              options: {0: 'Все', for (final h in heroes.take(40)) h.heroId: RefData.I.heroName(h.heroId)},
              onChanged: (v) => setState(() {
                heroFilter = v == 0 ? null : v;
                page = 0;
              }),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text('${all.length} ${plural(all.length, 'матч', 'матча', 'матчей').split(' ').last} · страница ${page + 1} из $pages',
            style: T.small),
        const SizedBox(height: 10),
        for (var i = 0; i < slice.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Pressable(
              scale: 0.98,
              onTap: () => openMatch(context, slice[i].matchId, accountId: p.accountId),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(rInner)),
                child: Row(children: [
                  SizedBox(width: 30, child: Text('${all.length - page * per - i}', style: T.tiny)),
                  HeroIcon(slice[i].heroId, height: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(RefData.I.heroName(slice[i].heroId), style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
                      Text(
                        '${slice[i].kills}/${slice[i].deaths}/${slice[i].assists} · ${fmtDuration(slice[i].duration)}'
                        '${slice[i].lastHits != null ? ' · ${slice[i].lastHits} крипов' : ''} · ${fmtDate(slice[i].startTime, time: false)}',
                        style: T.tiny,
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(slice[i].won ? 'W' : 'L',
                        style: T.body.copyWith(color: slice[i].won ? C.lime : C.red, fontWeight: FontWeight.w800)),
                    DeltaText(matchMmrDelta(slice[i], step), style: T.tiny),
                  ]),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: LimeButton('◀ Назад', dark: true, onTap: page > 0 ? () => setState(() => page--) : null)),
          const SizedBox(width: 10),
          Expanded(child: LimeButton('Дальше ▶', onTap: page < pages - 1 ? () => setState(() => page++) : null)),
        ]),
      ],
    );
  }
}
