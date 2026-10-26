import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
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
  String period = 'day';

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
          _banner(context, store),
          const SizedBox(height: 14),
          const NoPlayers(),
        ] else ...[
          _banner(context, store),
          const SizedBox(height: 14),
          _todayCard(context, store),
          const SizedBox(height: 14),
          _quick(context),
          SectionTitle('Последние матчи',
              trailing: Text('${store.players.length} в пати', style: T.small)),
          ..._feed(context, store),
        ],
      ],
    );
  }

  // --- баннер «Держи рейтинг» с играми по месяцам ------------------------------------------------------
  Widget _banner(BuildContext context, Store store) {
    // фон — самый частый герой лидера (или «моего» игрока)
    final List<PlayerSummary> ss = store.players.isEmpty ? <PlayerSummary>[] : store.summaries('month');
    final PlayerSummary? focus = store.me != null ? store.summary(store.me!, 'month') : (ss.isEmpty ? null : ss.first);
    final heroId = focus == null || focus.topHeroes.isEmpty
        ? (focus?.last?.heroId)
        : focus.topHeroes.first.heroId;
    final hero = RefData.I.hero(heroId);

    // игры пати по месяцам (уникальные матчи), последние 6 месяцев
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
    } else if (counts[5] > 0) {
      tag = '${counts[5].toInt()}';
    }

    return Container(
      height: 340,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCard), color: C.surface2),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (hero != null)
          Image.network(hero.image, fit: BoxFit.cover, alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => const SizedBox())
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A3528), Color(0xFF16150F)],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.75)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text('ДЕРЖИ\nРЕЙТИНГ', style: T.display.copyWith(fontSize: 38, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white70),
                ),
                child: Text('Dota Party · ранкед', style: T.tiny.copyWith(color: Colors.white, fontSize: 10)),
              ),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Игры пати по месяцам', style: T.body.copyWith(fontWeight: FontWeight.w700))),
                  CircleBtn(Icons.north_east_rounded,
                      size: 36, color: Colors.black26, onTap: () => push(context, const DigestScreen(period: 'month'))),
                ]),
                const SizedBox(height: 4),
                MiniBars(
                  values: counts,
                  labels: [for (final d in months) monthShort(d.month)],
                  highlight: 5,
                  tag: tag,
                  height: 96,
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  // --- карточка «сегодня / неделя / месяц» -------------------------------------------------------------
  Widget _todayCard(BuildContext context, Store store) {
    final named = store.named(period);
    final ids = <int>{};
    var wins = 0, games = 0;
    for (final n in named) {
      for (final m in n.$2) {
        if (ids.add(m.matchId * 2 + (m.isRadiant ? 1 : 0))) {
          games++;
          if (m.won) wins++;
        }
      }
    }
    final me = store.me;
    final meDelta = me == null ? null : mmrDelta(inPeriod(store.matchesOf(me), period), store.settings.mmrStep);
    final together = togetherSummary(named);
    final title = {'day': 'Сегодня', 'week': 'За неделю', 'month': 'За месяц'}[period]!;

    Widget bigRow(String value, String unit, String sub, {Color? subColor}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: T.big),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(unit, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
                Text(sub, style: T.tiny.copyWith(color: subColor ?? C.lime)),
              ]),
            ),
          ]),
        );

    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.sub),
            const SizedBox(height: 12),
            bigRow('$games', 'игр', games == 0 ? 'никто не играл' : '${pct(games == 0 ? 0 : wins / games)} побед'),
            bigRow('$wins–${games - wins}', 'W–L', together.games > 0 ? '${together.games} вместе' : 'соло',
                subColor: C.muted),
            if (meDelta != null)
              bigRow(signed(meDelta), 'MMR', 'у вас (${me!.name})', subColor: deltaColor(meDelta))
            else
              bigRow('${store.players.length}', 'в пати', 'игроков'),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 118,
          child: Column(children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.all(4),
              child: Column(children: [
                for (final e in const {'day': 'Сегодня', 'week': 'Неделя', 'month': 'Месяц'}.entries)
                  GestureDetector(
                    onTap: () => setState(() => period = e.key),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: period == e.key ? C.bg : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(e.value,
                          style: T.small.copyWith(
                              color: period == e.key ? Colors.white : Colors.black87, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: C.lime,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => push(context, DigestScreen(period: period)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: Text('Сводка', style: T.small.copyWith(color: C.onLime, fontWeight: FontWeight.w800))),
                  ),
                ),
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
            radius: 22,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: lime ? C.onLime : C.lime, size: 22),
              const SizedBox(height: 14),
              Text(title, style: T.body.copyWith(fontWeight: FontWeight.w800, color: lime ? C.onLime : C.text)),
              Text(sub, style: T.tiny.copyWith(color: lime ? C.onLime.withValues(alpha: 0.7) : C.muted)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.campaign_rounded, 'Позвать пати', 'сбор на катку', () => push(context, const GoScreen()), lime: true),
        const SizedBox(width: 10),
        tile(Icons.emoji_events_outlined, 'Соревнование', 'номинации и сезон', () => push(context, const ContestScreen())),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(Icons.workspace_premium_outlined, 'Рекорды', 'лучшие игры', () => push(context, const RecordsScreen())),
        const SizedBox(width: 10),
        tile(Icons.person_add_alt_1_rounded, 'Добавить', 'игрока в пати', () => openAdd(context)),
      ]),
    ]);
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
      for (final g in groups) Padding(padding: const EdgeInsets.only(bottom: 8), child: MatchTile(rows: g, step: store.settings.mmrStep)),
    ];
  }
}
