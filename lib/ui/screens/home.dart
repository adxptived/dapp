import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../fx.dart';
import '../net_image.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contest.dart';
import 'digest.dart';
import 'go.dart';
import 'records.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String period = 'week';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Главная',
      leading: Icons.refresh_rounded,
      onLeading: () => store.refreshAll(force: true),
      trailing: const HeaderAvatar(),
      onRefresh: () => store.refreshAll(force: true),
      children: [
        const StaleBanner(),
        if (store.players.isEmpty) ...[
          const NoPlayers(),
        ] else ...[
          _banner(context, store),
          const SizedBox(height: 14),
          _periodCard(context, store),
          const SizedBox(height: 14),
          _quick(context),
          const SizedBox(height: 14),
          _months(context, store),
          SectionTitle('Последние матчи', trailing: Text('${store.players.length} игроков', style: T.small)),
          ..._feed(context, store),
        ],
      ],
    );
  }

  /// Счёт за сегодня: уникальные игры пати (совместная — одна), победы/поражения, ±MMR «моего» игрока.
  (int, int) _todayScore(Store store) {
    final since = localDayStart();
    final seen = <String>{};
    var w = 0, l = 0;
    for (final p in store.players) {
      for (final m in store.matchesOf(p)) {
        if (m.startTime < since || !seen.add('${m.matchId}:${m.isRadiant}')) continue;
        m.won ? w++ : l++;
      }
    }
    return (w, l);
  }

  // --- баннер: счёт дня и последний матч ---------------------------------------------------------------
  Widget _banner(BuildContext context, Store store) {
    final (w, l) = _todayScore(store);
    final feed = store.feed(limit: 12);
    final last = feed.isEmpty ? null : groupFeed(feed, limit: 1).first;
    final lastM = last?.first.$2;
    final hero = RefData.I.hero(lastM?.heroId);
    final me = store.me;
    final meToday = me == null
        ? null
        : mmrDelta(store.matchesOf(me).where((m) => m.startTime >= localDayStart()), store.settings.mmrStep);
    final d = DateTime.now();

    return Container(
      height: 360,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCard), color: C.surface2),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (hero != null && !RefData.I.lowData)
          NetImage(hero.image, fit: BoxFit.cover, alignment: Alignment.topCenter)
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B2D6B), Color(0xFF15111F)],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.7)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Glass(
                radius: BorderRadius.circular(20),
                tint: 0.3,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('Сегодня · ${d.day} ${monthShort(d.month)}', style: T.tiny.copyWith(color: Colors.white, fontSize: 11)),
              ),
              const Spacer(),
              if (meToday != null && (w + l) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: deltaColor(meToday) == C.muted ? Colors.white24 : deltaColor(meToday), borderRadius: BorderRadius.circular(20)),
                  child: Text('${signed(meToday)} MMR', style: T.tiny.copyWith(color: C.onLime, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _score('W', w, C.lime),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(':', style: T.display.copyWith(fontSize: 56, color: Colors.white54)),
              ),
              _score('L', l, w + l == 0 ? Colors.white : C.red),
            ]),
            Text(
              w + l == 0 ? 'Сегодня ещё не играли' : '${w + l} ${plural(w + l, 'игра', 'игры', 'игр').split(' ').last} · ${pct(w / (w + l))} побед',
              style: T.small.copyWith(color: Colors.white70),
            ),
            const Spacer(),
            if (last != null) _lastMatch(context, store, last),
          ]),
        ),
      ]),
    );
  }

  Widget _score(String label, int v, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.tiny.copyWith(color: Colors.white60, letterSpacing: 2)),
        AnimatedNumber(v, style: T.display.copyWith(fontSize: 64, color: color, height: 1)),
      ]);

  Widget _lastMatch(BuildContext context, Store store, List<(Player, M)> g) {
    final m = g.first.$2;
    final step = store.settings.mmrStep;
    return Pressable(
      scale: 0.97,
      onTap: () => openMatch(context, m.matchId, accountId: g.first.$1.accountId),
      child: Glass(
        radius: BorderRadius.circular(22),
        tint: 0.4,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(children: [
          HeroIcon(m.heroId, height: 44, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Последний матч · ${fmtAgo(m.startTime)}', style: T.tiny.copyWith(color: Colors.white60)),
              const SizedBox(height: 2),
              Text(g.map((r) => r.$1.name).join(', '),
                  style: T.body.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
              Text('${RefData.I.heroName(m.heroId)} · ${m.kills}/${m.deaths}/${m.assists} · ${fmtDuration(m.duration)}',
                  style: T.small.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: m.won ? C.lime : C.red, borderRadius: BorderRadius.circular(12)),
              child: Text(m.won ? 'WIN' : 'LOSE', style: T.tiny.copyWith(color: C.onLime, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            DeltaText(matchMmrDelta(m, step), suffix: ' MMR', style: T.tiny),
          ]),
        ]),
      ),
    );
  }

  // --- неделя / месяц / год ---------------------------------------------------------------------------
  Widget _periodCard(BuildContext context, Store store) {
    final named = store.named(period);
    final ids = <String>{};
    var wins = 0, games = 0;
    for (final n in named) {
      for (final m in n.$2) {
        if (ids.add('${m.matchId}:${m.isRadiant}')) {
          games++;
          if (m.won) wins++;
        }
      }
    }
    final me = store.me;
    final meDelta = me == null ? null : mmrDelta(inPeriod(store.matchesOf(me), period), store.settings.mmrStep);
    final together = togetherSummary(named);
    const opts = {'week': 'Неделя', 'month': 'Месяц', 'year': 'Год'};

    Widget bigRow(num value, String Function(num) fmt, String unit, String sub, {Color? subColor}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            AnimatedNumber(value, style: T.big, format: fmt),
            const SizedBox(width: 6),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(unit, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
                  Text(sub, style: T.tiny.copyWith(color: subColor ?? C.lime), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ]),
        );

    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(periodLong[period]!.replaceFirst('за', 'За'), key: ValueKey(period), style: T.sub),
            ),
            const SizedBox(height: 12),
            bigRow(games, (v) => '${v.round()}', 'игр', games == 0 ? 'никто не играл' : '${pct(wins / games)} побед'),
            bigRow(wins, (v) => '${v.round()}–${games - wins}', 'W–L', together.games > 0 ? '${together.games} вместе' : 'соло',
                subColor: C.muted),
            if (meDelta != null)
              bigRow(meDelta, (v) => signed(v), 'MMR', 'у вас (${me!.name})', subColor: deltaColor(meDelta))
            else
              bigRow(store.players.length, (v) => '${v.round()}', 'игроков', 'отслеживается'),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 118,
          child: Column(children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(builder: (context, box) {
                final keys = opts.keys.toList();
                final i = keys.indexOf(period);
                return SizedBox(
                  height: 132,
                  child: Stack(children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      top: i * 44.0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: Container(decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16))),
                    ),
                    Column(children: [
                      for (var k = 0; k < keys.length; k++)
                        Pressable(
                          scale: 0.93,
                          onTap: () => setState(() => period = keys[k]),
                          child: SizedBox(
                            height: 44,
                            width: double.infinity,
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                style: T.small.copyWith(color: k == i ? Colors.white : Colors.black87, fontWeight: FontWeight.w700),
                                child: Text(opts[keys[k]]!),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ]),
                );
              }),
            ),
            const SizedBox(height: 10),
            Pressable(
              onTap: () => push(context, DigestScreen(period: period)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: C.lime,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: C.lime.withValues(alpha: 0.3), blurRadius: 18, spreadRadius: -6)],
                ),
                child: Center(child: Text('Сводка', style: T.small.copyWith(color: C.onLime, fontWeight: FontWeight.w800))),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _quick(BuildContext context) {
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {bool lime = false}) => Expanded(
          child: AppCard(
            onTap: onTap,
            color: lime ? C.lime : C.surface,
            padding: const EdgeInsets.all(14),
            radius: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: lime ? Colors.black12 : C.surface2, shape: BoxShape.circle),
                child: Icon(icon, color: lime ? C.onLime : C.lime, size: 20),
              ),
              const SizedBox(height: 14),
              Text(title, style: T.body.copyWith(fontWeight: FontWeight.w800, color: lime ? C.onLime : C.text)),
              Text(sub, style: T.tiny.copyWith(color: lime ? C.onLime.withValues(alpha: 0.7) : C.muted)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.campaign_rounded, 'Позвать на катку', 'собрать стак', () => push(context, const GoScreen()), lime: true),
        const SizedBox(width: 10),
        tile(Icons.emoji_events_outlined, 'Соревнование', 'номинации и сезон', () => push(context, const ContestScreen())),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(Icons.workspace_premium_outlined, 'Рекорды', 'лучшие игры', () => push(context, const RecordsScreen())),
        const SizedBox(width: 10),
        tile(Icons.person_add_alt_1_rounded, 'Добавить', 'нового игрока', () => openAdd(context)),
      ]),
    ]);
  }

  /// Игры пати по месяцам (уникальные матчи), последние 6 месяцев.
  Widget _months(BuildContext context, Store store) {
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1)];
    final counts = List<double>.filled(6, 0);
    final seen = <int>{};
    for (final p in store.players) {
      for (final m in store.matchesOf(p)) {
        if (!seen.add(m.matchId)) continue;
        final d = DateTime.fromMillisecondsSinceEpoch(m.startTime * 1000);
        for (var i = 0; i < 6; i++) {
          if (d.year == months[i].year && d.month == months[i].month) counts[i]++;
        }
      }
    }
    String? tag;
    if (counts[4] > 0) {
      final ch = (counts[5] - counts[4]) / counts[4] * 100;
      tag = '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(0)}%';
    }
    return AppCard(
      onTap: () => push(context, const DigestScreen(period: 'month')),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Игры по месяцам', style: T.sub),
              Text('в этом месяце ${counts[5].toInt()}', style: T.small),
            ]),
          ),
          const Icon(Icons.north_east_rounded, color: C.muted, size: 18),
        ]),
        const SizedBox(height: 8),
        MiniBars(values: counts, labels: [for (final d in months) monthShort(d.month)], highlight: 5, tag: tag, height: 100),
      ]),
    );
  }

  List<Widget> _feed(BuildContext context, Store store) {
    final groups = groupFeed(store.feed(limit: 60), limit: 12);
    if (groups.isEmpty) {
      return [
        const EmptyState(
          icon: Icons.hourglass_empty_rounded,
          title: 'Матчей пока нет',
          text: 'Ранкед-игры появятся после обновления. Потяните экран вниз.',
        )
      ];
    }
    return [
      for (var i = 0; i < groups.length; i++)
        FadeSlideIn(
          index: i,
          child: Padding(padding: const EdgeInsets.only(bottom: 8), child: MatchTile(rows: groups[i], step: store.settings.mmrStep)),
        ),
    ];
  }
}
