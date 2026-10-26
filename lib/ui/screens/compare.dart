import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';

/// Сравнение игроков: индекс «силы в пати» и место по перфу, винрейту, KDA и GPM.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String? period;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final per = period ?? store.settings.defaultPeriod;
    final ss = store.summaries(per);
    final cmp = buildComparison(ss);
    ss.sort((a, b) => (cmp.powerRank[a.name] ?? 99).compareTo(cmp.powerRank[b.name] ?? 99));
    String fmt(String key, PlayerSummary s) {
      final v = compareMetrics[key]!(s);
      if (v == null) return '—';
      return switch (key) {
        'perf' => (v * 100).toStringAsFixed(0),
        'winrate' => pct(v),
        'kda' => v.toStringAsFixed(1),
        _ => v.toStringAsFixed(0),
      };
    }

    return PageScaffold(
      title: 'Сравнение',
      children: [
        Segments<String>(value: per, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 14),
        if (ss.length < 2)
          const EmptyState(title: 'Нужно минимум двое', text: 'Добавьте ещё игроков, чтобы сравнивать.')
        else ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Сила в пати', style: T.sub),
              Text('среднее места по перфу, винрейту, KDA и GPM', style: T.small),
              const SizedBox(height: 12),
              for (final s in ss)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: GestureDetector(
                    onTap: () => openPlayer(context, s.player),
                    child: Column(children: [
                      Row(children: [
                        placeBadge(cmp.powerRank[s.name] ?? 0),
                        const SizedBox(width: 10),
                        Avatar(s.player.avatar, size: 36, fallback: s.name),
                        const SizedBox(width: 10),
                        Expanded(child: Text(s.name, style: T.body.copyWith(fontWeight: FontWeight.w800))),
                        Text(cmp.power[s.name] == null ? '—' : (cmp.power[s.name]! * 100).toStringAsFixed(0),
                            style: T.title.copyWith(color: cmp.powerRank[s.name] == 1 ? C.gold : C.text)),
                      ]),
                      const SizedBox(height: 8),
                      BarMeter(cmp.power[s.name] ?? 0, bars: 34, height: 16),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (final k in compareLabels.keys)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: cmp.ranks[s.name]?[k] == 1 ? C.lime.withValues(alpha: 0.15) : C.surface2,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(compareLabels[k]!, style: T.tiny.copyWith(fontSize: 9)),
                                Text(fmt(k, s), style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
                                Text(cmp.ranks[s.name]?[k] == null ? '' : '#${cmp.ranks[s.name]![k]}',
                                    style: T.tiny.copyWith(color: cmp.ranks[s.name]?[k] == 1 ? C.lime : C.muted)),
                              ]),
                            ),
                          ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Перф и GPM сравниваются, если посчитаны хотя бы по $minCompareGames играм.', style: T.tiny),
        ],
      ],
    );
  }
}
