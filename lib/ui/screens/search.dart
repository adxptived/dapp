import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/ranks.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_player.dart';

/// Поиск по ID: матч — разбор; игрок — карточка любого игрока (не только из пати) + «Добавить в пати».
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ctl = TextEditingController();
  bool busy = false;
  String? error;
  _Lookup? result;

  Future<void> _go() async {
    final store = context.read<Store>();
    final text = ctl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final q = parseLookup(text);
      if (q.kind == LookupKind.match) {
        if (mounted) openMatch(context, q.id);
      } else {
        var id = q.id;
        if (q.vanity != null) id = accountIdFromSteam64(await resolveVanity(q.vanity!));
        final prof = await store.od.profile(id);
        final hasProfile = prof['profile'] is Map;
        if (!hasProfile && q.ambiguous) {
          if (mounted) openMatch(context, id);
        } else if (!hasProfile) {
          throw ApiError('Игрок не найден или профиль скрыт');
        } else {
          final wl = await store.od.winLoss(id);
          final recent = await store.od.recentMatches(id);
          final heroes = await store.od.playerHeroes(id);
          result = _Lookup(id, prof, wl, recent.where((r) => r['lobby_type'] == 7).toList(), heroes.take(5).toList());
        }
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Поиск по ID',
      leading: Icons.search_rounded,
      onLeading: _go,
      trailing: const HeaderAvatar(),
      children: [
        TextField(
          controller: ctl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _go(),
          decoration: InputDecoration(
            hintText: 'ID матча, игрока или ссылка',
            prefixIcon: const Icon(Icons.search_rounded, color: C.muted),
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste_rounded, color: C.muted),
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) {
                  ctl.text = d!.text!.trim();
                  _go();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Число до 2 млрд ищется сначала как игрок, больше — как матч. «матч 123…» / «игрок 123…» снимает неоднозначность.',
          style: T.tiny,
        ),
        const SizedBox(height: 14),
        LimeButton('Найти', busy: busy, icon: Icons.search_rounded, onTap: _go),
        const SizedBox(height: 14),
        if (error != null) Text(error!, style: T.small.copyWith(color: C.red)),
        if (result != null) _card(context, store, result!),
        if (result == null && error == null && !busy) ...[
          const SectionTitle('Пати'),
          for (final p in store.players)
            PlayerLine(
              player: p,
              name: p.name,
              sub: '${rankLabel(p.rankTier, p.leaderboardRank)} · ${p.accountId}',
              onTap: () => openPlayer(context, p),
              trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
            ),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, Store store, _Lookup r) {
    final profile = (r.prof['profile'] as Map?) ?? {};
    final name = (profile['personaname'] ?? 'Игрок ${r.id}').toString();
    final win = (r.wl['win'] as num?)?.toInt() ?? 0, lose = (r.wl['lose'] as num?)?.toInt() ?? 0;
    final inParty = store.byId(r.id);
    final recent = r.recent.take(10).toList();
    double avg(String k) => recent.isEmpty ? 0 : recent.map((m) => (m[k] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / recent.length;
    return Column(children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(profile['avatarfull']?.toString(), size: 64, fallback: name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: T.title.copyWith(fontSize: 20)),
                Text('account_id ${r.id}', style: T.tiny),
                const SizedBox(height: 6),
                RankBadge((r.prof['rank_tier'] as num?)?.toInt(), leaderboard: (r.prof['leaderboard_rank'] as num?)?.toInt()),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          KvTable(rows: [
            ('Ранкед', valueText('$win–$lose · ${win + lose == 0 ? '—' : pct(win / (win + lose))}')),
            ('Баланс побед', valueText(signed(win - lose), color: deltaColor(win - lose))),
            if (recent.isNotEmpty) ...[
              ('K/D/A (посл.)', valueText('${avg('kills').toStringAsFixed(1)} / ${avg('deaths').toStringAsFixed(1)} / ${avg('assists').toStringAsFixed(1)}')),
              ('GPM / урон', valueText('${avg('gold_per_min').round()} / ${kfmt(avg('hero_damage'))}')),
            ],
          ]),
          if (r.heroes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Топ героев', style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in r.heroes)
                Column(children: [
                  HeroIcon(int.tryParse('${h['hero_id']}'), height: 30),
                  Text('${h['games']} · ${(h['games'] as num? ?? 0) == 0 ? '' : pct(((h['win'] as num?) ?? 0) / (h['games'] as num))}',
                      style: T.tiny),
                ]),
            ]),
          ],
          const SizedBox(height: 14),
          if (inParty != null)
            LimeButton('Открыть карточку', onTap: () => openPlayer(context, inParty))
          else
            LimeButton('Добавить в пати',
                icon: Icons.add_rounded,
                onTap: () => push(context, AddPlayerScreen(initialId: '${r.id}', initialName: name))),
        ]),
      ),
      if (recent.isNotEmpty) ...[
        const SectionTitle('Последние ранкед-игры'),
        for (final m in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => openMatch(context, (m['match_id'] as num).toInt(), accountId: r.id),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(rInner)),
                child: Row(children: [
                  HeroIcon((m['hero_id'] as num?)?.toInt(), height: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${RefData.I.heroName((m['hero_id'] as num?)?.toInt())} · ${m['kills']}/${m['deaths']}/${m['assists']}',
                      style: T.small.copyWith(color: C.text),
                    ),
                  ),
                  Builder(builder: (_) {
                    final won = (((m['player_slot'] as num?) ?? 0) < 128) == (m['radiant_win'] == true);
                    return Text(won ? 'W' : 'L', style: T.body.copyWith(color: won ? C.lime : C.red, fontWeight: FontWeight.w800));
                  }),
                ]),
              ),
            ),
          ),
      ],
      const SizedBox(height: 6),
      Text('Данные OpenDota, без оценки MMR.', style: T.tiny),
    ]);
  }
}

class _Lookup {
  final int id;
  final Map<String, dynamic> prof, wl;
  final List<Map<String, dynamic>> recent, heroes;
  _Lookup(this.id, this.prof, this.wl, this.recent, this.heroes);
}
