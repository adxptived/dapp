import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';

/// Рекорды отдельных игр: плитки с героем, значением, игроком и датой + лучшая серия побед.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  String period = 'month';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final (records, streak) = computeRecords(store.named(period));
    final normal = records.where((r) => !r.def.anti).toList();
    final anti = records.where((r) => r.def.anti).toList();
    return PageScaffold(
      title: 'Рекорды',
      children: [
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 14),
        if (records.isEmpty) const EmptyState(title: 'Рекордов пока нет', text: 'За период нет игр.', icon: Icons.workspace_premium_outlined),
        if (streak != null)
          AppCard(
            color: C.lime,
            child: Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Лучшая серия побед', style: T.small.copyWith(color: C.onLime)),
                  Text('${streak.$1} — ${streak.$2} подряд', style: T.title.copyWith(color: C.onLime)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [for (final r in normal) _tile(context, store, r)],
        ),
        if (anti.isNotEmpty) ...[
          const SectionTitle('Антирекорды'),
          for (final r in anti) _tile(context, store, r, wide: true),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, Store store, RecordRow r, {bool wide = false}) {
    final p = store.byName(r.player);
    final body = [
      Row(children: [
        Text(r.def.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Expanded(child: Text(r.def.title, style: T.tiny, maxLines: 2)),
      ]),
      const SizedBox(height: 8),
      Text(r.text, style: T.title.copyWith(color: r.def.anti ? C.red : C.lime)),
      const Spacer(),
      Row(children: [
        HeroIcon(r.match.heroId, height: 22, radius: 5),
        const SizedBox(width: 6),
        Expanded(child: Text(RefData.I.heroName(r.match.heroId), style: T.tiny, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Avatar(p?.avatar, size: 20, fallback: r.player),
        const SizedBox(width: 6),
        Expanded(child: Text(r.player, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        Text(fmtDate(r.match.startTime, time: false), style: T.tiny),
      ]),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: wide ? 8 : 0),
      child: SizedBox(
        height: wide ? 150 : null,
        child: AppCard(
          padding: const EdgeInsets.all(14),
          radius: 22,
          onTap: () => openMatch(context, r.match.matchId, accountId: p?.accountId),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
        ),
      ),
    );
  }
}
