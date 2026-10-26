import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Игры вместе: сводка, лучшая пара, матрица пар (игры и винрейт).
class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key});
  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  String period = 'all';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final named = store.named(period);
    final sum = togetherSummary(named);
    final pairs = pairStats(named)..sort((a, b) => b.games.compareTo(a.games));
    final duo = bestDuo(pairs);
    final n = named.length;
    final grid = <(int, int), Pair>{for (final p in pairs) (p.a, p.b): p};
    return PageScaffold(
      title: 'Вместе',
      children: [
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 14),
        AppCard(
          child: Row(children: [
            _stat('${sum.games}', 'игр вместе'),
            _stat('${sum.wins}–${sum.losses}', 'W–L'),
            _stat(sum.games == 0 ? '—' : pct(sum.wins / sum.games), 'винрейт', lime: sum.games > 0 && sum.wins / sum.games >= 0.5),
          ]),
        ),
        const SizedBox(height: 12),
        if (duo != null)
          AppCard(
            gradient: LinearGradient(colors: [C.lime.withValues(alpha: 0.22), C.surface]),
            child: Row(children: [
              Avatar(store.byName(named[duo.a].$1)?.avatar, size: 44, fallback: named[duo.a].$1),
              Transform.translate(
                offset: const Offset(-10, 0),
                child: Avatar(store.byName(named[duo.b].$1)?.avatar, size: 44, fallback: named[duo.b].$1),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Лучшая пара', style: T.tiny.copyWith(color: C.lime)),
                  Text('${named[duo.a].$1} + ${named[duo.b].$1}', style: T.sub),
                  Text('${duo.games} ${plural(duo.games, 'игра', 'игры', 'игр').split(' ').last} · ${duo.wins}–${duo.games - duo.wins} · ${pct(duo.winrate)}',
                      style: T.small),
                ]),
              ),
            ]),
          ),
        if (n >= 2) ...[
          const SectionTitle('Матрица пар'),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 84),
                  for (var j = 0; j < n; j++)
                    SizedBox(
                      width: 62,
                      child: Text(named[j].$1, style: T.tiny, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    ),
                ]),
                const SizedBox(height: 6),
                for (var i = 0; i < n; i++)
                  Row(children: [
                    SizedBox(width: 84, child: Text(named[i].$1, style: T.tiny.copyWith(color: C.text), overflow: TextOverflow.ellipsis)),
                    for (var j = 0; j < n; j++) _cell(i == j ? null : grid[(i < j ? i : j, i < j ? j : i)], i == j),
                  ]),
              ]),
            ),
          ),
        ],
        const SectionTitle('Все пары'),
        if (pairs.isEmpty) Text('Совместных игр нет', style: T.small),
        for (final p in pairs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.glass2, borderRadius: BorderRadius.circular(rInner), border: Border.all(color: C.glass)),
              child: Row(children: [
                Expanded(child: Text('${named[p.a].$1} + ${named[p.b].$1}', style: T.body.copyWith(fontWeight: FontWeight.w700))),
                Text('${p.games} · ', style: T.small),
                Text(pct(p.winrate), style: T.small.copyWith(color: p.winrate >= 0.5 ? C.lime : C.red, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Text('Совместная игра — двое ваших игроков на одной стороне и не соло в лобби.', style: T.tiny),
      ],
    );
  }

  Widget _stat(String v, String l, {bool lime = false}) => Expanded(
        child: Column(children: [
          Text(v, style: T.big.copyWith(fontSize: 24, color: lime ? C.lime : C.text)),
          Text(l, style: T.small),
        ]),
      );

  Widget _cell(Pair? p, bool self) {
    final color = self
        ? C.bg
        : p == null
            ? C.surface2
            : Color.lerp(C.red.withValues(alpha: 0.5), C.lime.withValues(alpha: 0.75), p.winrate)!;
    return Container(
      width: 58,
      height: 46,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: self || p == null
          ? Text(self ? '' : '·', style: T.tiny)
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${p.games}', style: T.small.copyWith(color: C.onLime, fontWeight: FontWeight.w800)),
              Text(pct(p.winrate), style: T.tiny.copyWith(color: C.onLime, fontSize: 9)),
            ]),
    );
  }
}
