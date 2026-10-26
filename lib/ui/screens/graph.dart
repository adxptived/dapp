import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// График MMR: по времени или по номеру игры; цвет закреплён за игроком.
class GraphScreen extends StatefulWidget {
  final int? accountId;
  const GraphScreen({super.key, this.accountId});
  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  String period = 'month';
  bool byGame = false;
  final hidden = <int>{};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final step = store.settings.mmrStep;
    final since = periodSince(period);
    final series = <(String, Color, List<(double, double)>)>[];
    for (var i = 0; i < store.players.length; i++) {
      final p = store.players[i];
      if (widget.accountId != null && p.accountId != widget.accountId) continue;
      if (hidden.contains(p.accountId)) continue;
      final tl = mmrTimeline(store.matchesOf(p), p.anchors, step).where((e) => since == null || e.$1 >= since).toList();
      final pts = <(double, double)>[
        for (var k = 0; k < tl.length; k++) (byGame ? (k + 1).toDouble() : tl[k].$1.toDouble(), tl[k].$2.toDouble())
      ];
      if (pts.isNotEmpty) series.add((p.name, C.seriesOf(i), pts));
    }
    final anyAnchors = store.players.any((p) => p.anchors.isNotEmpty);
    return PageScaffold(
      title: 'График MMR',
      children: [
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 10),
        Segments<bool>(value: byGame, options: const {false: 'По времени', true: 'По номеру игры'}, onChanged: (v) => setState(() => byGame = v)),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 14, 12),
          child: series.isEmpty
              ? Padding(padding: const EdgeInsets.all(20), child: Text('Нет игр за период', style: T.small))
              : LineChart(
                  series: series,
                  height: 300,
                  xLabel: byGame ? (x) => '#${x.round()}' : (x) => fmtDate(x.toInt(), time: false),
                ),
        ),
        const SizedBox(height: 12),
        if (widget.accountId == null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < store.players.length; i++)
              GestureDetector(
                onTap: () => setState(() {
                  final id = store.players[i].accountId;
                  hidden.contains(id) ? hidden.remove(id) : hidden.add(id);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: hidden.contains(store.players[i].accountId) ? C.stroke : C.seriesOf(i)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: C.seriesOf(i), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(store.players[i].name,
                        style: T.small.copyWith(color: hidden.contains(store.players[i].accountId) ? C.muted : C.text)),
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: 10),
        Text(anyAnchors ? 'MMR — оценка от заданного значения; на правках линия «прыгает».' : 'MMR не задан — показано накопленное ±MMR.',
            style: T.tiny),
      ],
    );
  }
}
