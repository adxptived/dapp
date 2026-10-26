import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Любимые герои пати / топ героев игрока / кто из пати как играет на герое.
class HeroesScreen extends StatefulWidget {
  final int? accountId;
  const HeroesScreen({super.key, this.accountId});
  @override
  State<HeroesScreen> createState() => _HeroesScreenState();
}

class _HeroesScreenState extends State<HeroesScreen> {
  String period = 'month';
  int who = 0; // 0 — вся пати, иначе account_id
  final ctl = TextEditingController();
  HeroInfo? hero;

  @override
  void initState() {
    super.initState();
    who = widget.accountId ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Герои',
      children: [
        TextField(
          controller: ctl,
          decoration: InputDecoration(
            hintText: 'Герой: pudge, инвокер, sf…',
            prefixIcon: const Icon(Icons.search_rounded, color: C.muted),
            suffixIcon: hero == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      hero = null;
                      ctl.clear();
                    }),
                  ),
          ),
          onChanged: (v) => setState(() => hero = v.trim().length < 2 ? null : RefData.I.findHero(v)),
        ),
        const SizedBox(height: 12),
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 12),
        if (hero == null)
          DropChip<int>(
            label: 'Кто',
            value: who,
            options: {0: 'Вся пати', for (final p in store.players) p.accountId: p.name},
            onChanged: (v) => setState(() => who = v),
          ),
        const SizedBox(height: 12),
        if (hero != null) ..._byHero(store, hero!) else if (who == 0) ..._party(store) else ..._player(store),
      ],
    );
  }

  Widget _heroRow(HeroStat h, int maxGames, {String? sub, Widget? lead}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(rInner)),
          child: Row(children: [
            lead ?? HeroIcon(h.heroId, height: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sub ?? RefData.I.heroName(h.heroId), style: T.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: maxGames == 0 ? 0 : h.games / maxGames,
                    minHeight: 4,
                    backgroundColor: C.surface3,
                    color: h.winrate >= 0.5 ? C.lime : C.red,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${h.games} · ${pct(h.winrate)}', style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
              Text('KDA ${h.kda.toStringAsFixed(1)}${h.avgGpm != null ? ' · ${h.avgGpm!.round()} GPM' : ''}', style: T.tiny),
            ]),
          ]),
        ),
      );

  List<Widget> _party(Store store) {
    final all = <M>[for (final n in store.named(period)) ...n.$2];
    final hs = heroStats(all, limit: 20);
    if (hs.isEmpty) return [Text('Нет игр за период', style: T.small)];
    return [
      Text('Любимые герои пати ${periodLong[period]}', style: T.small),
      const SizedBox(height: 8),
      for (final h in hs) _heroRow(h, hs.first.games),
    ];
  }

  List<Widget> _player(Store store) {
    final p = store.byId(who);
    if (p == null) return [];
    final ms = inPeriod(store.matchesOf(p), period);
    final hs = heroStats(ms, limit: 10);
    final roles = roleStats(ms);
    return [
      if (hs.isEmpty) Text('Нет игр за период', style: T.small),
      for (final h in hs) _heroRow(h, hs.isEmpty ? 0 : hs.first.games),
      if (roles.isNotEmpty) ...[
        const SectionTitle('Позиции'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in roles) SmallPill('поз. ${r.heroId}: ${r.games} · ${pct(r.winrate)}', lime: r.winrate >= 0.5),
        ]),
      ],
    ];
  }

  List<Widget> _byHero(Store store, HeroInfo h) {
    final rows = <(Player, HeroStat)>[];
    for (final p in store.players) {
      final hs = heroStats(inPeriod(store.matchesOf(p), period), heroId: h.id);
      if (hs.isNotEmpty) rows.add((p, hs.first));
    }
    rows.sort((a, b) => b.$2.games.compareTo(a.$2.games));
    return [
      Row(children: [
        HeroIcon(h.id, height: 48, radius: 12),
        const SizedBox(width: 12),
        Expanded(child: Text(h.localized, style: T.title.copyWith(fontSize: 20))),
      ]),
      const SizedBox(height: 12),
      if (rows.isEmpty) Text('Никто из пати не играл на ${h.localized} ${periodLong[period]}', style: T.small),
      for (final r in rows) _heroRow(r.$2, rows.first.$2.games, sub: r.$1.name, lead: Avatar(r.$1.avatar, size: 34, fallback: r.$1.name)),
    ];
  }
}
