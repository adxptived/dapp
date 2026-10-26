// Навигация и общие блоки, которые знают о Store.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/refdata.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'screens/add_player.dart';
import 'screens/match.dart';
import 'screens/player.dart';
import 'fx.dart';
import 'theme.dart';
import 'widgets.dart';

void push(BuildContext context, Widget page) => Navigator.of(context).push(fadeRoute(page));

void openPlayer(BuildContext context, Player p) => push(context, PlayerScreen(accountId: p.accountId));

void openMatch(BuildContext context, int matchId, {int? accountId}) =>
    push(context, MatchScreen(matchId: matchId, focusAccount: accountId));

void openAdd(BuildContext context) => push(context, const AddPlayerScreen());

/// Аватар «Это я» (или первого игрока) в шапке; бейдж — игры сегодня.
class HeaderAvatar extends StatelessWidget {
  const HeaderAvatar({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final p = store.me ?? (store.players.isEmpty ? null : store.players.first);
    if (p == null) {
      return CircleBtn(Icons.person_add_alt_1_rounded, onTap: () => openAdd(context));
    }
    final today = store.matchesOf(p).where((m) => m.startTime >= localDayStart()).length;
    return GestureDetector(
      onTap: () => openPlayer(context, p),
      child: Avatar(p.avatar, size: 38, fallback: p.name, badge: today > 0 ? today : null),
    );
  }
}

/// Строка матча в ленте: герой, игрок(и), исход, K/D/A, ±MMR.
class MatchTile extends StatelessWidget {
  final List<(Player, M)> rows; // один матч, несколько игроков пати
  final int step;
  const MatchTile({super.key, required this.rows, required this.step});

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final m = first.$2;
    final won = m.won;
    return Pressable(
      scale: 0.98,
      onTap: () => openMatch(context, m.matchId, accountId: first.$1.accountId),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.glass2, borderRadius: BorderRadius.circular(rInner), border: Border.all(color: C.glass)),
        child: Row(children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(color: won ? C.lime : C.red, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          HeroIcon(m.heroId, height: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                rows.map((r) => r.$1.name).join(', '),
                style: T.body.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${RefData.I.heroName(m.heroId)} · ${m.kills}/${m.deaths}/${m.assists} · ${fmtDuration(m.duration)}',
                style: T.small,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(won ? 'Победа' : 'Поражение',
                style: T.small.copyWith(color: won ? C.lime : C.red, fontWeight: FontWeight.w700)),
            Text(fmtAgo(m.startTime), style: T.tiny),
          ]),
        ]),
      ),
    );
  }
}

/// Группирует ленту по матчам (совместная игра — одна строка).
List<List<(Player, M)>> groupFeed(List<(Player, M)> feed, {int limit = 10}) {
  final groups = <String, List<(Player, M)>>{};
  for (final r in feed) {
    groups.putIfAbsent('${r.$2.matchId}:${r.$2.isRadiant}', () => []).add(r);
  }
  return groups.values.take(limit).toList();
}

class NoPlayers extends StatelessWidget {
  const NoPlayers({super.key});
  @override
  Widget build(BuildContext context) => EmptyState(
        title: 'Игроков пока нет',
        text:
            'Добавьте игроков по ссылке Dotabuff / OpenDota / Stratz / Steam или по ID. Важно: в Dota 2 должна быть включена опция «Общедоступная история матчей».',
        action: LimeButton('Добавить игрока', icon: Icons.add_rounded, onTap: () => openAdd(context)),
      );
}

/// Плашка-предупреждение о проблемах с данными.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    if (store.refreshing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: Text('Обновляю ${store.progress}', style: T.small)),
        ]),
      );
    }
    if (store.lastError == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: C.surface2,
        padding: const EdgeInsets.all(12),
        radius: rInner,
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: C.gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${store.lastError} — показаны сохранённые данные'
              '${store.dataAge > 0 ? ' (обновлены ${fmtAgo(nowTs() - store.dataAge)})' : ''}.',
              style: T.small,
            ),
          ),
        ]),
      ),
    );
  }
}
