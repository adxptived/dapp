import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Позиции 1–5: игры, винрейт, KDA, IMP (нужен ключ Stratz).
class RolesScreen extends StatefulWidget {
  final int? accountId;
  const RolesScreen({super.key, this.accountId});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  String period = 'month';
  int who = 0;
  static const names = {1: 'Керри', 2: 'Мид', 3: 'Хард', 4: 'Роумер', 5: 'Саппорт'};

  @override
  void initState() {
    super.initState();
    who = widget.accountId ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final players = who == 0 ? store.players : [if (store.byId(who) != null) store.byId(who)!];
    return PageScaffold(
      title: 'Позиции',
      children: [
        if (!store.stratz.enabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: EmptyState(
              icon: Icons.key_rounded,
              title: 'Нужен ключ Stratz',
              text: 'Позиции, IMP, вижн и исход линии приходят из Stratz. Бесплатный ключ: stratz.com/api → вставьте в Настройках.',
            ),
          ),
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 12),
        DropChip<int>(
          label: 'Кто',
          value: who,
          options: {0: 'Все игроки', for (final x in store.players) x.accountId: x.name},
          onChanged: (v) => setState(() => who = v),
        ),
        const SizedBox(height: 12),
        for (final p in players) _player(store, p),
      ],
    );
  }

  Widget _player(Store store, Player p) {
    final rs = roleStats(inPeriod(store.matchesOf(p), period));
    final total = rs.fold<int>(0, (a, r) => a + r.games);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(p.avatar, size: 32, fallback: p.name),
            const SizedBox(width: 10),
            Expanded(child: Text(p.name, style: T.sub)),
            Text('$total ${plural(total, 'игра', 'игры', 'игр').split(' ').last}', style: T.small),
          ]),
          const SizedBox(height: 10),
          if (rs.isEmpty) Text('Нет данных о позициях', style: T.small),
          for (final r in rs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: C.surface2, shape: BoxShape.circle),
                  child: Text('${r.heroId}', style: T.body.copyWith(color: C.lime, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(names[r.heroId] ?? '', style: T.body.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : r.games / total,
                        minHeight: 4,
                        backgroundColor: C.surface3,
                        color: r.winrate >= 0.5 ? C.lime : C.red,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${r.games} · ${pct(r.winrate)}', style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
                  Text('KDA ${r.kda.toStringAsFixed(1)}${r.avgImp != null ? ' · IMP ${r.avgImp!.round()}' : ''}', style: T.tiny),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}
