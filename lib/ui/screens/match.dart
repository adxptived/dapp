import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/ranks.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

class MatchScreen extends StatefulWidget {
  final int matchId;
  final int? focusAccount;
  const MatchScreen({super.key, required this.matchId, this.focusAccount});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  Map<String, dynamic>? data;
  Map<int, Map<String, dynamic>> stratzRows = {}; // hero_id → строка Stratz (IMP, позиция)
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<Store>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await store.fetchMatch(widget.matchId);
      if ((d['players'] as List?)?.isEmpty ?? true) throw Exception('OpenDota не знает этот матч (или он ещё не доехал).');
      data = d;
      // обогатить сохранённые матчи игроков пати
      for (final p in store.players) {
        for (final m in store.matchesOf(p)) {
          if (m.matchId == widget.matchId && !m.enriched) Store.applyMatchDetail(m, d, p.accountId);
        }
      }
      if (store.stratz.enabled) {
        try {
          final s = await store.stratz.fullMatch(widget.matchId);
          for (final r in (s?['players'] as List? ?? []).whereType<Map>()) {
            final h = (r['heroId'] as num?)?.toInt();
            if (h != null) stratzRows[h] = Map<String, dynamic>.from(r);
          }
        } catch (_) {}
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return PageScaffold(
      title: 'Матч ${widget.matchId}',
      trailing: CircleBtn(Icons.more_horiz_rounded, onTap: () => _menu(context, store)),
      onRefresh: _load,
      children: [
        if (loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (error != null)
          EmptyState(icon: Icons.error_outline_rounded, title: 'Не получилось', text: error, action: LimeButton('Повторить', onTap: _load))
        else
          ..._content(context, store),
      ],
    );
  }

  List<Widget> _content(BuildContext context, Store store) {
    final d = data!;
    final players = (d['players'] as List).whereType<Map>().toList();
    final radiantWin = d['radiant_win'] == true;
    final partyIds = {for (final p in store.players) p.accountId: p.name};
    final radiant = players.where((p) => ((p['player_slot'] as num?) ?? 0) < 128).toList();
    final dire = players.where((p) => ((p['player_slot'] as num?) ?? 0) >= 128).toList();
    final rk = (d['radiant_score'] as num?)?.toInt() ?? radiant.fold<int>(0, (a, p) => a + ((p['kills'] as num?)?.toInt() ?? 0));
    final dk = (d['dire_score'] as num?)?.toInt() ?? dire.fold<int>(0, (a, p) => a + ((p['kills'] as num?)?.toInt() ?? 0));
    final avgRank = averageRankTier(players.map((p) => (p['rank_tier'] as num?)?.toInt()));
    final start = (d['start_time'] as num?)?.toInt() ?? 0;
    int nw(List<Map> t) => t.fold<int>(0, (a, p) => a + ((p['net_worth'] as num?)?.toInt() ?? 0));
    final parsed = d['version'] != null;

    // за кого играла пати
    bool? partySide;
    for (final p in players) {
      if (partyIds.containsKey(p['account_id'])) partySide = ((p['player_slot'] as num?) ?? 0) < 128;
    }
    final partyWon = partySide == null ? null : partySide == radiantWin;

    return [
      AppCard(
        child: Column(children: [
          if (partyWon != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: partyWon ? C.lime : C.red, borderRadius: BorderRadius.circular(20)),
              child: Text(partyWon ? 'ПОБЕДА ПАТИ' : 'ПОРАЖЕНИЕ ПАТИ',
                  style: T.tiny.copyWith(color: C.onLime, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(children: [
                Text('Силы Света', style: T.small.copyWith(color: C.radiant)),
                if (radiantWin) Text('победа', style: T.tiny.copyWith(color: C.lime)),
              ]),
            ),
            Text('$rk : $dk', style: T.display.copyWith(fontSize: 40)),
            Expanded(
              child: Column(children: [
                Text('Силы Тьмы', style: T.small.copyWith(color: C.dire)),
                if (!radiantWin) Text('победа', style: T.tiny.copyWith(color: C.lime)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            SmallPill(fmtDuration((d['duration'] as num?)?.toInt())),
            if (start > 0) SmallPill(fmtDate(start)),
            if (avgRank != null) SmallPill('лобби: ${rankLabel(avgRank)}'),
            SmallPill(d['lobby_type'] == 7 ? 'Рейтинг' : 'Обычная'),
            if (nw(radiant) > 0 && nw(dire) > 0) SmallPill('золото ${kfmt(nw(radiant))} / ${kfmt(nw(dire))}'),
          ]),
          if (!parsed) ...[
            const SizedBox(height: 10),
            Text('Матч не разобран: нет таймингов предметов и стаков.', style: T.tiny),
          ],
        ]),
      ),
      SectionTitle('Силы Света', trailing: Text(radiantWin ? 'победа' : '', style: T.limeS)),
      ..._team(context, radiant, partyIds),
      SectionTitle('Силы Тьмы', trailing: Text(!radiantWin ? 'победа' : '', style: T.limeS)),
      ..._team(context, dire, partyIds),
    ];
  }

  List<Widget> _team(BuildContext context, List<Map> team, Map<int, String> party) {
    return [
      for (final p in team)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _row(p, party),
        ),
    ];
  }

  Widget _row(Map p, Map<int, String> party) {
    int i(String k) => (p[k] as num?)?.toInt() ?? 0;
    final heroId = (p['hero_id'] as num?)?.toInt();
    final acc = (p['account_id'] as num?)?.toInt();
    final inParty = party[acc];
    final name = inParty ?? (p['personaname'] ?? p['name'] ?? 'Аноним').toString();
    final focus = acc != null && acc == widget.focusAccount;
    final st = stratzRows[heroId];
    final items = [for (final s in ['item_0', 'item_1', 'item_2', 'item_3', 'item_4', 'item_5']) i(s)];
    final neutral = i('item_neutral');
    final pos = int.tryParse(st?['position']?.toString().split('_').last ?? '');
    final imp = (st?['imp'] as num?)?.toInt();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(color: focus ? C.lime : (inParty != null ? C.limeDim.withValues(alpha: 0.5) : C.stroke)),
      ),
      child: Column(children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            HeroIcon(heroId, height: 38),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(6)),
                child: Text('${i('level')}', style: T.tiny.copyWith(color: C.text, fontSize: 9)),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      style: T.body.copyWith(fontWeight: FontWeight.w800, color: inParty != null ? C.lime : C.text),
                      overflow: TextOverflow.ellipsis),
                ),
                if (pos != null) ...[const SizedBox(width: 6), SmallPill('поз. $pos')],
              ]),
              Text(
                '${RefData.I.heroName(heroId)} · ${rankLabel((p['rank_tier'] as num?)?.toInt())}',
                style: T.tiny,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${i('kills')}/${i('deaths')}/${i('assists')}', style: T.body.copyWith(fontWeight: FontWeight.w800)),
            if (imp != null) Text('IMP ${imp >= 0 ? '+' : ''}$imp', style: T.tiny.copyWith(color: imp >= 0 ? C.lime : C.red)),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _cell('NW', kfmt(i('net_worth'))),
          _cell('LH/DN', '${i('last_hits')}/${i('denies')}'),
          _cell('GPM/XPM', '${i('gold_per_min')}/${i('xp_per_min')}'),
          _cell('Урон', kfmt(i('hero_damage'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: it == 0 ? Container(width: 33, height: 24, decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(4))) : ItemIcon(it),
            ),
          const SizedBox(width: 6),
          if (neutral > 0) ClipOval(child: SizedBox(width: 24, height: 24, child: ItemIcon(neutral))),
          const Spacer(),
          if (p['aghanims_scepter'] == 1) const Text('🔮', style: TextStyle(fontSize: 13)),
          if (p['aghanims_shard'] == 1) const Text('💠', style: TextStyle(fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _cell(String l, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: T.tiny.copyWith(fontSize: 9)),
            Text(v, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  void _menu(BuildContext context, Store store) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_rounded, color: C.lime),
            title: const Text('Запросить разбор OpenDota'),
            subtitle: const Text('появятся тайминги предметов и стаки'),
            onTap: () async {
              Navigator.pop(c);
              await store.od.requestParse(widget.matchId);
              if (context.mounted) toast(context, 'Разбор запрошен — обновите через пару минут');
            },
          ),
          for (final l in [
            ('OpenDota', 'https://www.opendota.com/matches/${widget.matchId}'),
            ('Dotabuff', 'https://www.dotabuff.com/matches/${widget.matchId}'),
            ('Stratz', 'https://stratz.com/matches/${widget.matchId}'),
          ])
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: C.muted),
              title: Text('Открыть в ${l.$1}'),
              onTap: () {
                Navigator.pop(c);
                launchUrl(Uri.parse(l.$2), mode: LaunchMode.externalApplication);
              },
            ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}
