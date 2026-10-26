import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/ranks.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../fx.dart';
import '../theme.dart';
import '../widgets.dart';
import 'duel.dart';
import 'graph.dart';
import 'matches_list.dart';
import 'matchups.dart';
import 'roles.dart';

class PlayerScreen extends StatefulWidget {
  final int accountId;
  const PlayerScreen({super.key, required this.accountId});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? period;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final p = store.byId(widget.accountId);
    if (p == null) {
      return const PageScaffold(title: 'Игрок', children: [EmptyState(title: 'Игрок удалён')]);
    }
    final per = period ?? store.settings.defaultPeriod;
    final s = store.summary(p, per);
    final ss = store.summaries(per);
    final cmp = buildComparison(ss);
    final step = store.settings.mmrStep;

    return PageScaffold(
      title: p.name,
      trailing: CircleBtn(Icons.more_horiz_rounded, onTap: () => _menu(context, store, p)),
      onRefresh: () async {
        await store.refreshPlayer(p, full: false);
        await store.save();
      },
      children: [
        _header(context, store, s),
        const SizedBox(height: 14),
        Segments<String>(value: per, options: periodLabels, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 14),
        _actions(context, store, p),
        const SizedBox(height: 14),
        _stats(s),
        if (ss.length >= 2) ...[const SizedBox(height: 14), _power(s, cmp, ss.length)],
        const SizedBox(height: 14),
        _goal(context, store, s),
        const SizedBox(height: 14),
        _activity(s),
        const SizedBox(height: 14),
        _splits(s),
        SectionTitle('Топ героев', trailing: Text('пул: ${heroPool(s.window)}', style: T.small)),
        _heroes(s),
        SectionTitle('Последние игры',
            trailing: GestureDetector(
              onTap: () => push(context, MatchesListScreen(accountId: p.accountId)),
              child: Text('все матчи →', style: T.limeS),
            )),
        for (final m in s.all.reversed.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _gameRow(context, p, m, step),
          ),
        if (s.all.isEmpty)
          EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Матчей нет',
            text: p.privateHistory
                ? 'OpenDota не видит игр. Включите в Dota 2: Настройки → Социальные → «Общедоступная история матчей».'
                : 'Потяните вниз, чтобы обновить.',
          ),
        if (s.window.any((m) => m.bench != null)) ...[
          SectionTitle('Профиль скилла', trailing: Text('перцентиль на своих героях', style: T.small)),
          _skill(s),
        ],
        SectionTitle('Журнал MMR', trailing: GestureDetector(onTap: () => _setMmr(context, store, p), child: Text('задать →', style: T.limeS))),
        _journal(context, store, p, s),
      ],
    );
  }

  Widget _header(BuildContext context, Store store, PlayerSummary s) {
    final p = s.player;
    final mmr = s.currentMmr;
    final mismatch = mmrRankMismatch(mmr, p.rankTier);
    return AppCard(
      child: Column(children: [
        Row(children: [
          Avatar(p.avatar, size: 72, fallback: p.name, ring: s.onStreak && s.streak.$1 == true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(p.name, style: T.title.copyWith(fontSize: 20), overflow: TextOverflow.ellipsis)),
                if (p.plus) ...[const SizedBox(width: 6), const Text('➕', style: TextStyle(fontSize: 12))],
              ]),
              if (p.personaname != null && p.personaname != p.name) Text('Steam: ${p.personaname}', style: T.small),
              const SizedBox(height: 6),
              RankBadge(p.rankTier, leaderboard: p.leaderboardRank, size: 30),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(mmr == null ? '—' : '≈$mmr', style: T.display.copyWith(fontSize: 40)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MMR', style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
              DeltaText(s.periodDelta, suffix: ' ${periodLong[period ?? store.settings.defaultPeriod]}'),
            ]),
          ),
          const Spacer(),
          if (s.todayGames > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('сегодня', style: T.tiny),
              Text('${s.todayWins}–${s.todayGames - s.todayWins}', style: T.body.copyWith(fontWeight: FontWeight.w700)),
              DeltaText(s.todayDelta),
            ]),
        ]),
        if (mmr == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Стартовый MMR не задан — показывается только ±MMR. Нажмите «Задать MMR».', style: T.small),
          ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('⚠️ Оценка разошлась с медалью (${rankLabel(p.rankTier)}). Обновите MMR.', style: T.small.copyWith(color: C.gold)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          FormDots(s.form, size: 12),
          const Spacer(),
          if (s.streak.$2 >= 2)
            Text(s.streak.$1 == true ? '🔥 ${s.streak.$2} побед подряд' : '🧊 ${s.streak.$2} поражений подряд', style: T.small),
        ]),
      ]),
    );
  }

  Widget _actions(BuildContext context, Store store, Player p) {
    Widget a(IconData i, String t, VoidCallback f) => Expanded(
          child: GestureDetector(
            onTap: f,
            child: Column(children: [
              CircleBtn(i, onTap: f, size: 50),
              const SizedBox(height: 6),
              Text(t, style: T.tiny.copyWith(color: C.text), textAlign: TextAlign.center),
            ]),
          ),
        );
    return Row(children: [
      a(Icons.tune_rounded, 'MMR', () => _setMmr(context, store, p)),
      a(Icons.list_alt_rounded, 'Матчи', () => push(context, MatchesListScreen(accountId: p.accountId))),
      a(Icons.sports_kabaddi_outlined, 'Соперники', () => push(context, MatchupsScreen(accountId: p.accountId))),
      a(Icons.view_week_outlined, 'Позиции', () => push(context, RolesScreen(accountId: p.accountId))),
      a(Icons.sports_mma_outlined, 'Дуэль', () => openDuel(context, a: p.accountId)),
      a(Icons.timeline_rounded, 'График', () => push(context, GraphScreen(accountId: p.accountId))),
    ]);
  }

  Widget _stats(PlayerSummary s) {
    String n0(double? v) => v == null ? '—' : v.toStringAsFixed(0);
    final style = inferRoleStyle(s.avgLastHits, s.avgHealing);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Статистика', style: T.sub),
        const SizedBox(height: 12),
        StatGrid(columns: 3, [
          StatItem('Игры', '${s.agg.games}', icon: Icons.sports_esports_outlined),
          StatItem('Победы', '${s.agg.wins}–${s.agg.losses}',
              sub: s.agg.games == 0 ? null : pct(s.agg.winrate), subColor: s.agg.winrate >= 0.5 ? C.lime : C.red),
          StatItem('KDA', s.agg.games == 0 ? '—' : s.agg.kda.toStringAsFixed(2), accent: true),
          StatItem('K / D / A', s.agg.games == 0 ? '—' : '${s.agg.avgK.toStringAsFixed(1)}/${s.agg.avgD.toStringAsFixed(1)}/${s.agg.avgA.toStringAsFixed(1)}'),
          StatItem('GPM', n0(s.avgGpm), sub: s.avgXpm == null ? null : 'XPM ${n0(s.avgXpm)}'),
          StatItem('Урон', s.avgDamage == null ? '—' : kfmt(s.avgDamage!), sub: 'за игру'),
          StatItem('Нетворс', s.avgNetWorth == null ? '—' : kfmt(s.avgNetWorth!)),
          StatItem('Перф', s.avgPerf == null ? '—' : '${(s.avgPerf! * 100).toStringAsFixed(0)}', sub: s.avgPerf == null ? null : 'из 100'),
          StatItem('Серия', s.bestStreak == 0 ? '—' : '${s.bestStreak}', sub: 'лучшая'),
        ]),
        if (style.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [Text('Стиль: ', style: T.small), SmallPill(style)]),
        ],
        if (s.detailGames < s.agg.games && s.agg.games > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('GPM/урон посчитаны по ${s.detailGames} из ${s.agg.games} игр — подробности догружаются фоном.', style: T.tiny),
          ),
      ]),
    );
  }

  /// Цель по MMR: прогресс от стартового значения, сколько осталось и сколько это побед.
  Widget _goal(BuildContext context, Store store, PlayerSummary s) {
    final p = s.player;
    final cur = s.currentMmr;
    final goal = p.goalMmr;
    Future<void> setGoal() async {
      final v = await prompt(context, 'Цель по MMR', initial: goal?.toString(), hint: cur == null ? 'например 4000' : 'сейчас ≈$cur',
          keyboard: TextInputType.number);
      if (v == null) return;
      final n = int.tryParse(v.trim());
      await store.setGoal(p, (n == null || n <= 0) ? null : n);
    }

    if (goal == null || cur == null) {
      return AppCard(
        onTap: cur == null ? () => _setMmr(context, store, p) : setGoal,
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: C.lime.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.flag_rounded, color: C.lime),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Цель по MMR', style: T.sub),
              Text(cur == null ? 'сначала задайте текущий MMR' : 'поставьте цель — покажем прогресс и сколько побед осталось',
                  style: T.small),
            ]),
          ),
          const Icon(Icons.add_rounded, color: C.lime),
        ]),
      );
    }
    final start = s.ledger.start ?? cur;
    final span = (goal - start).abs();
    final done = span == 0 ? 1.0 : ((cur - start) / (goal - start)).clamp(0.0, 1.0);
    final left = goal - cur;
    final step = store.settings.mmrStep;
    final wins = left <= 0 ? 0 : (left / step).ceil();
    return AppCard(
      onTap: setGoal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Цель по MMR', style: T.sub),
              Text('цель: $goal · старт: $start', style: T.small),
            ]),
          ),
          CircleBtn(Icons.edit_rounded, size: 38, onTap: setGoal),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          AnimatedNumber(done * 100, style: T.display, format: (v) => '${v.round()}%'),
        ]),
        const SizedBox(height: 10),
        BarMeter(done, bars: 36),
        const SizedBox(height: 10),
        Text(
          left <= 0
              ? 'Цель достигнута! 🎉 Поставьте новую.'
              : 'Осталось $left MMR — это $wins ${plural(wins, 'чистая победа', 'чистые победы', 'чистых побед').split(' ').skip(1).join(' ')} подряд.',
          style: T.small.copyWith(color: C.text),
        ),
      ]),
    );
  }

  /// Календарь активности за 12 недель: насыщенность — сколько игр, цвет — в плюсе или в минусе день.
  Widget _activity(PlayerSummary s) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: 7 * 12 - 1 + (today.weekday - 1)));
    final days = <int, (int, int)>{};
    for (final m in s.all) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.startTime * 1000);
      if (d.isBefore(start)) continue;
      final k = DateTime(d.year, d.month, d.day).difference(start).inDays;
      final v = days[k] ?? (0, 0);
      days[k] = (v.$1 + 1, v.$2 + (m.won ? 1 : 0));
    }
    final total = days.values.fold<int>(0, (a, v) => a + v.$1);
    final active = days.length;
    final maxG = days.values.fold<int>(1, (a, v) => v.$1 > a ? v.$1 : a);
    final weeks = 12 + (today.weekday == 7 ? 0 : 1);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Активность', style: T.sub)),
          Text('$total игр · $active дн. за 12 недель', style: T.small),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final cell = ((box.maxWidth - 24) / weeks).clamp(8.0, 22.0);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              for (final d in const ['пн', '', 'ср', '', 'пт', '', 'вс'])
                SizedBox(height: cell, width: 22, child: Text(d, style: T.tiny.copyWith(fontSize: 8))),
            ]),
            for (var w = 0; w < weeks; w++)
              Column(children: [
                for (var d = 0; d < 7; d++)
                  Builder(builder: (_) {
                    final k = w * 7 + d;
                    final date = start.add(Duration(days: k));
                    if (date.isAfter(today)) return SizedBox(width: cell, height: cell);
                    final v = days[k];
                    final Color color;
                    if (v == null) {
                      color = C.glass;
                    } else {
                      final t = 0.35 + 0.65 * (v.$1 / maxG);
                      color = (v.$2 * 2 >= v.$1 ? C.lime : C.red).withValues(alpha: t);
                    }
                    return Container(
                      width: cell - 3,
                      height: cell - 3,
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                    );
                  }),
              ]),
          ]);
        }),
        const SizedBox(height: 8),
        Text('Фиолетовый — день в плюсе, красный — в минусе; ярче — больше игр.', style: T.tiny),
      ]),
    );
  }

  Widget _power(PlayerSummary s, Comparison cmp, int size) {
    final power = cmp.power[s.name];
    final ranks = cmp.ranks[s.name] ?? {};
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Сила среди игроков', style: T.sub)),
          Text('#${cmp.powerRank[s.name]} из $size', style: T.title.copyWith(color: C.lime)),
        ]),
        const SizedBox(height: 10),
        BarMeter(power ?? 0, bars: 30, height: 28),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in compareLabels.entries)
            SmallPill('${e.value}: ${ranks[e.key] == null ? '—' : '#${ranks[e.key]}'}', lime: ranks[e.key] == 1),
        ]),
      ]),
    );
  }

  Widget _splits(PlayerSummary s) {
    final sp = soloPartySplit(s.window);
    final hours = bestWorstHour(winrateByHour(s.window));
    String wl((int, int) v) => v.$1 == 0 ? '—' : '${v.$2}–${v.$1 - v.$2} · ${pct(v.$2 / v.$1)}';
    final wins = s.window.where((m) => m.won).toList(), losses = s.window.where((m) => !m.won).toList();
    String avgKda(List<M> l) => l.isEmpty ? '—' : (l.map((m) => m.kda).reduce((a, b) => a + b) / l.length).toStringAsFixed(1);
    String avgD(List<M> l) => l.isEmpty ? '—' : (l.map((m) => m.deaths).reduce((a, b) => a + b) / l.length).toStringAsFixed(1);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Соло и группа', style: T.sub),
        const SizedBox(height: 12),
        StatGrid(columns: 2, [
          StatItem('Соло', wl(sp['solo']!), icon: Icons.person_outline_rounded),
          StatItem('В группе', wl(sp['party']!), icon: Icons.group_outlined),
          StatItem('В победах', 'KDA ${avgKda(wins)}', sub: 'смертей ${avgD(wins)}'),
          StatItem('В поражениях', 'KDA ${avgKda(losses)}', sub: 'смертей ${avgD(losses)}'),
          if (hours.$1 != null) StatItem('Лучший час', '${hours.$1!.$1}:00', sub: pct(hours.$1!.$2), subColor: C.lime),
          if (hours.$2 != null) StatItem('Худший час', '${hours.$2!.$1}:00', sub: pct(hours.$2!.$2), subColor: C.red),
          StatItem(
            'Средняя игра',
            s.window.where((m) => m.duration != null).isEmpty
                ? '—'
                : fmtDuration((mean(s.window.map((m) => m.duration)) ?? 0).round()),
          ),
          if (sp['unknown']!.$1 > 0) StatItem('Размер неизвестен', wl(sp['unknown']!)),
        ]),
      ]),
    );
  }

  Widget _heroes(PlayerSummary s) {
    final hs = heroStats(s.window, limit: 10);
    if (hs.isEmpty) return Text('Нет игр за период', style: T.small);
    final maxG = hs.first.games;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        for (final h in hs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              HeroIcon(h.heroId, height: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(RefData.I.heroName(h.heroId), style: T.body.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: h.games / maxG,
                      minHeight: 4,
                      backgroundColor: C.surface3,
                      color: h.winrate >= 0.5 ? C.lime : C.red,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${h.games} · ${pct(h.winrate)}', style: T.small.copyWith(color: C.text)),
                  Text('KDA ${h.kda.toStringAsFixed(1)}${h.avgImp != null ? ' · IMP ${h.avgImp!.round()}' : ''}', style: T.tiny),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _gameRow(BuildContext context, Player p, M m, int step) {
    final d = matchMmrDelta(m, step);
    return Pressable(
      scale: 0.98,
      onTap: () => openMatch(context, m.matchId, accountId: p.accountId),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: C.glass2, borderRadius: BorderRadius.circular(rInner), border: Border.all(color: C.glass)),
        child: Row(children: [
          Container(width: 4, height: 34, decoration: BoxDecoration(color: m.won ? C.lime : C.red, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          HeroIcon(m.heroId, height: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(RefData.I.heroName(m.heroId), style: T.body.copyWith(fontWeight: FontWeight.w700)),
              Text('${m.kills}/${m.deaths}/${m.assists} · ${fmtDuration(m.duration)} · ${fmtAgo(m.startTime)}', style: T.small),
            ]),
          ),
          DeltaText(d, style: T.body),
        ]),
      ),
    );
  }

  Widget _skill(PlayerSummary s) {
    const labels = {
      'gold_per_min': 'GPM',
      'xp_per_min': 'XPM',
      'kills_per_min': 'Убийства/мин',
      'last_hits_per_min': 'Добивания/мин',
      'hero_damage_per_min': 'Урон/мин',
      'hero_healing_per_min': 'Лечение/мин',
      'tower_damage': 'Урон по башням',
    };
    final skill = aggregateSkill(s.window);
    return AppCard(
      child: Column(children: [
        for (final e in labels.entries)
          if (skill[e.key] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 120, child: Text(e.value, style: T.small.copyWith(color: C.text))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: skill[e.key]!.clamp(0, 1).toDouble(),
                      minHeight: 8,
                      backgroundColor: C.surface3,
                      color: skill[e.key]! >= 0.5 ? C.lime : C.gold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 36, child: Text(pct(skill[e.key]!), style: T.small, textAlign: TextAlign.end)),
              ]),
            ),
        const SizedBox(height: 6),
        Text('50% — средний игрок мира на тех же героях', style: T.tiny),
      ]),
    );
  }

  Widget _journal(BuildContext context, Store store, Player p, PlayerSummary s) {
    final l = s.ledger;
    if (p.anchors.isEmpty) {
      return AppCard(child: Text('MMR не задан. Оценка начнётся с заданного значения.', style: T.small));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatGrid(columns: 2, [
          StatItem('Старт', '${l.start}'),
          StatItem('Сейчас', '≈${l.current}', accent: true),
          StatItem('Игрой', signed(l.earned), color: deltaColor(l.earned), sub: 'за ${gamesWord(l.games)}'),
          StatItem('Правки', signed(l.corrections), sub: 'ручные поправки'),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < p.anchors.length; i++)
          Row(children: [
            Expanded(child: Text('${fmtDate(p.anchors[i].ts)} — ${p.anchors[i].mmr}', style: T.small.copyWith(color: C.text))),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: C.muted),
              onPressed: () async {
                if (await confirm(context, 'Удалить запись?', 'MMR ${p.anchors[i].mmr} от ${fmtDate(p.anchors[i].ts)}')) {
                  await store.removeAnchor(p, i);
                }
              },
            ),
          ]),
      ]),
    );
  }

  Future<void> _setMmr(BuildContext context, Store store, Player p) async {
    final hint = mmrFromRank(p.rankTier);
    final v = await prompt(context, 'Текущий MMR ${p.name}',
        hint: hint == null ? 'например 3200' : 'по медали ≈$hint', keyboard: TextInputType.number);
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return;
    if (n < 0 || n > 20000) {
      if (context.mounted) toast(context, 'MMR должен быть от 0 до 20000');
      return;
    }
    await store.setMmr(p, n);
    if (context.mounted) toast(context, 'MMR ${p.name}: $n');
  }

  void _menu(BuildContext context, Store store, Player p) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          ListTile(
            leading: Icon(p.isMe ? Icons.person_off_outlined : Icons.person_pin_outlined, color: C.lime),
            title: Text(p.isMe ? 'Это не я' : 'Это я'),
            subtitle: const Text('ваши ±MMR на главной и в уведомлениях'),
            onTap: () {
              Navigator.pop(c);
              store.setMe(p.isMe ? null : p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: C.lime),
            title: const Text('Переименовать'),
            onTap: () async {
              Navigator.pop(c);
              final v = await prompt(context, 'Имя игрока', initial: p.name);
              if (v == null) return;
              try {
                await store.renamePlayer(p, v);
              } catch (e) {
                if (context.mounted) toast(context, '$e');
              }
            },
          ),
          for (final l in [
            ('OpenDota', 'https://www.opendota.com/players/${p.accountId}'),
            ('Dotabuff', 'https://www.dotabuff.com/players/${p.accountId}'),
            ('Stratz', 'https://stratz.com/players/${p.accountId}'),
            ('Steam', 'https://steamcommunity.com/profiles/${p.accountId + steamId64Base}'),
          ])
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: C.muted),
              title: Text('Открыть в ${l.$1}'),
              onTap: () {
                Navigator.pop(c);
                launchUrl(Uri.parse(l.$2), mode: LaunchMode.externalApplication);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: C.red),
            title: const Text('Удалить игрока', style: TextStyle(color: C.red)),
            onTap: () async {
              Navigator.pop(c);
              if (await confirm(context, 'Удалить ${p.name}?', 'Игрок и его сохранённые матчи будут удалены.', ok: 'Удалить')) {
                await store.removePlayer(p);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}
