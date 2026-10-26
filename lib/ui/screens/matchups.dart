import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Против каких героев тяжело и с кем в команде лучше (по игроку или по всей пати).
class MatchupsScreen extends StatefulWidget {
  final int? accountId;
  const MatchupsScreen({super.key, this.accountId});
  @override
  State<MatchupsScreen> createState() => _MatchupsScreenState();
}

class _MatchupsScreenState extends State<MatchupsScreen> {
  String period = 'month';
  int who = 0;

  @override
  void initState() {
    super.initState();
    who = widget.accountId ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final minGames = matchupThreshold(period);
    final p = who == 0 ? null : store.byId(who);
    final MatchupReport r = p == null
        ? partyMatchups(store.named(period), minGames)
        : playerMatchups(inPeriod(store.matchesOf(p), period), minGames);
    return PageScaffold(
      title: 'Соперники и союзники',
      children: [
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 12),
        DropChip<int>(
          label: 'Кто',
          value: who,
          options: {0: 'Все игроки', for (final x in store.players) x.accountId: x.name},
          onChanged: (v) => setState(() => who = v),
        ),
        const SizedBox(height: 12),
        if (r.total == 0)
          const EmptyState(title: 'За период игр нет', icon: Icons.hourglass_empty_rounded)
        else if (r.games == 0)
          const EmptyState(
              title: 'Составов пока нет',
              text: 'Составы команд подтягиваются вместе с историей матчей. Загляните позже.',
              icon: Icons.hourglass_top_rounded)
        else ...[
          Text('по ${r.games} из ${r.total} игр · обычный винрейт ${pct(r.winrate)}', style: T.small),
          if (r.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Пока мало повторов: нужен герой, встреченный хотя бы ${r.minGames} раза.', style: T.small),
            ),
          _section('😰 Тяжёлые соперники', r.hard),
          _section('😎 Удобные соперники', r.easy),
          _section('📉 С ними в команде хуже', r.badAllies),
          _section('📈 С ними в команде лучше', r.goodAllies),
          const SizedBox(height: 8),
          Text('Герой — в списке от ${r.minGames} встреч; порядок учитывает число игр.', style: T.tiny),
        ],
      ],
    );
  }

  Widget _section(String title, List<MatchupRow> rows) {
    if (rows.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(title),
      AppCard(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                HeroIcon(row.heroId, height: 30),
                const SizedBox(width: 10),
                Expanded(child: Text(RefData.I.heroName(row.heroId), style: T.body.copyWith(fontWeight: FontWeight.w700))),
                Text('${row.wins}–${row.losses}  ', style: T.small),
                Text(pct(row.winrate),
                    style: T.small.copyWith(color: row.winrate >= 0.5 ? C.lime : C.red, fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
