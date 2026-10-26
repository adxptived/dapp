import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../fx.dart';
import '../theme.dart';
import '../widgets.dart';

/// Дуэль: два игрока лицом к лицу — игры вместе, друг против друга и показатели рядом.
class DuelScreen extends StatefulWidget {
  final int? a, b;
  const DuelScreen({super.key, this.a, this.b});
  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  int? a, b;
  String period = 'all';

  @override
  void initState() {
    super.initState();
    a = widget.a;
    b = widget.b;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final ps = store.players;
    if (ps.length < 2) {
      return const PageScaffold(title: 'Дуэль', children: [
        EmptyState(title: 'Нужно минимум двое', text: 'Добавьте ещё игрока, чтобы сравнить.', icon: Icons.sports_mma_outlined),
      ]);
    }
    final pa = store.byId(a ?? -1) ?? ps[0];
    var pb = store.byId(b ?? -1) ?? ps.firstWhere((p) => p != pa);
    if (pb == pa) pb = ps.firstWhere((p) => p != pa);
    final sa = store.summary(pa, period), sb = store.summary(pb, period);

    // общие матчи
    final mb = {for (final m in sb.window) m.matchId: m};
    var withG = 0, withW = 0, vsG = 0, vsA = 0;
    for (final m in sa.window) {
      final o = mb[m.matchId];
      if (o == null) continue;
      if (o.isRadiant == m.isRadiant) {
        withG++;
        if (m.won) withW++;
      } else {
        vsG++;
        if (m.won) vsA++;
      }
    }

    return PageScaffold(
      title: 'Дуэль',
      children: [
        Segments<String>(value: period, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _pick(context, store, pa, (id) => setState(() => a = id))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
              child: Center(child: Text('VS', style: T.small.copyWith(color: C.onLime, fontWeight: FontWeight.w900))),
            ),
          ),
          Expanded(child: _pick(context, store, pb, (id) => setState(() => b = id))),
        ]),
        const SizedBox(height: 14),
        AppCard(
          child: Row(children: [
            _box('Вместе', withG == 0 ? '—' : '$withW–${withG - withW}', withG == 0 ? 'нет общих игр' : pct(withW / withG)),
            Container(width: 1, height: 50, color: C.glass),
            _box('Друг против друга', vsG == 0 ? '—' : '$vsA : ${vsG - vsA}', vsG == 0 ? 'не встречались' : '${pa.name} : ${pb.name}'),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(children: [
            _bar('≈MMR', sa.currentMmr?.toDouble(), sb.currentMmr?.toDouble(), (v) => '${v.round()}'),
            _bar('±MMR', sa.periodDelta.toDouble(), sb.periodDelta.toDouble(), (v) => signed(v)),
            _bar('Игры', sa.agg.games.toDouble(), sb.agg.games.toDouble(), (v) => '${v.round()}'),
            _bar('Винрейт', sa.agg.games > 0 ? sa.agg.winrate : null, sb.agg.games > 0 ? sb.agg.winrate : null, (v) => pct(v)),
            _bar('KDA', sa.agg.games > 0 ? sa.agg.kda : null, sb.agg.games > 0 ? sb.agg.kda : null, (v) => v.toStringAsFixed(2)),
            _bar('GPM', sa.avgGpm, sb.avgGpm, (v) => '${v.round()}'),
            _bar('Урон', sa.avgDamage, sb.avgDamage, (v) => kfmt(v)),
            _bar('Перф', sa.avgPerf, sb.avgPerf, (v) => '${(v * 100).round()}'),
            _bar('Смерти', sa.agg.games > 0 ? sa.agg.avgD : null, sb.agg.games > 0 ? sb.agg.avgD : null,
                (v) => v.toStringAsFixed(1), lowerBetter: true),
            _bar('Лучшая серия', sa.bestStreak.toDouble(), sb.bestStreak.toDouble(), (v) => '${v.round()}'),
            _bar('Пул героев', heroPool(sa.window).toDouble(), heroPool(sb.window).toDouble(), (v) => '${v.round()}'),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Лаймовым — кто впереди по показателю.', style: T.tiny),
      ],
    );
  }

  Widget _pick(BuildContext context, Store store, Player p, ValueChanged<int> onPick) => AppCard(
        padding: const EdgeInsets.all(12),
        onTap: () async {
          final v = await pickOption<int>(context, 'Игрок', {for (final x in store.players) x.accountId: x.name}, p.accountId);
          if (v != null) onPick(v);
        },
        child: Column(children: [
          Avatar(p.avatar, size: 54, fallback: p.name),
          const SizedBox(height: 8),
          Text(p.name, style: T.body.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
          RankBadge(p.rankTier, leaderboard: p.leaderboardRank, size: 18),
        ]),
      );

  Widget _box(String title, String value, String sub) => Expanded(
        child: Column(children: [
          Text(title, style: T.tiny),
          const SizedBox(height: 4),
          Text(value, style: T.big.copyWith(fontSize: 24)),
          Text(sub, style: T.tiny, overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _bar(String label, double? va, double? vb, String Function(double) fmt, {bool lowerBetter = false}) {
    final both = va != null && vb != null;
    final aWins = both && (lowerBetter ? va < vb : va > vb);
    final bWins = both && (lowerBetter ? vb < va : vb > va);
    final total = both ? (va.abs() + vb.abs()) : 0.0;
    final fa = total == 0 ? 0.5 : va!.abs() / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(children: [
        Row(children: [
          Text(va == null ? '—' : fmt(va), style: T.small.copyWith(color: aWins ? C.lime : C.text, fontWeight: FontWeight.w800)),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: T.tiny)),
          Text(vb == null ? '—' : fmt(vb), style: T.small.copyWith(color: bWins ? C.lime : C.text, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 5),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: fa),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, f, __) => Row(children: [
            Expanded(
              flex: (f * 1000).round().clamp(1, 999),
              child: Container(height: 6, decoration: BoxDecoration(color: aWins ? C.lime : C.faint, borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: ((1 - f) * 1000).round().clamp(1, 999),
              child: Container(height: 6, decoration: BoxDecoration(color: bWins ? C.lime : C.faint, borderRadius: BorderRadius.circular(3))),
            ),
          ]),
        ),
      ]),
    );
  }
}

// для навигации из других экранов
void openDuel(BuildContext context, {int? a, int? b}) => push(context, DuelScreen(a: a, b: b));
