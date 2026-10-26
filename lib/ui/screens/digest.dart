import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';

/// Сводка за период (то, что бот присылал раз в день / по понедельникам).
class DigestScreen extends StatefulWidget {
  final String period;
  const DigestScreen({super.key, this.period = 'day'});
  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  late String period = widget.period;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final text = buildDigestText(store, period);
    final ss = store.summaries(period).where((s) => s.agg.games > 0).toList()
      ..sort((a, b) => b.periodDelta.compareTo(a.periodDelta));
    final awards = periodAwards(store.named(period), store.settings.mmrStep);
    final all = [for (final n in store.named(period)) ...n.$2];
    final heroTop = heroStats(all, limit: 1);
    return PageScaffold(
      title: 'Сводка',
      trailing: CircleBtn(Icons.ios_share_rounded, onTap: () => _share(text)),
      children: [
        Segments<String>(
          value: period,
          options: const {'day': 'Сутки', 'week': 'Неделя', 'month': 'Месяц'},
          onChanged: (v) => setState(() => period = v),
        ),
        const SizedBox(height: 14),
        if (ss.isEmpty)
          const EmptyState(title: 'За период никто не играл', icon: Icons.bedtime_outlined)
        else ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Итоги ${periodLong[period]}', style: T.sub),
              const SizedBox(height: 10),
              for (var i = 0; i < ss.length; i++)
                PlayerLine(
                  player: ss[i].player,
                  name: ss[i].name,
                  sub: '${ss[i].agg.wins}–${ss[i].agg.losses} · KDA ${ss[i].agg.kda.toStringAsFixed(1)}',
                  lead: placeBadge(i + 1),
                  trailing: DeltaText(ss[i].periodDelta, suffix: ' MMR', style: T.body),
                  onTap: () => openPlayer(context, ss[i].player),
                ),
            ]),
          ),
          if (heroTop.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(children: [
                HeroIcon(heroTop.first.heroId, height: 46, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Герой ${period == 'day' ? 'дня' : period == 'week' ? 'недели' : 'месяца'}', style: T.tiny.copyWith(color: C.lime)),
                    Text(RefData.I.heroName(heroTop.first.heroId), style: T.sub),
                    Text('${heroTop.first.games} игр · ${pct(heroTop.first.winrate)}', style: T.small),
                  ]),
                ),
              ]),
            ),
          ],
          if (awards.isNotEmpty) ...[
            const SectionTitle('Отличия'),
            AppCard(
              child: Column(children: [
                for (final a in awards)
                  PlayerLine(
                    player: store.byName(a.entries.first.player),
                    name: '${a.emoji} ${a.title}',
                    sub: '${a.entries.first.player} — ${a.entries.first.text}',
                  ),
              ]),
            ),
          ],
        ],
        const SizedBox(height: 16),
        LimeButton('Отправить в Telegram', icon: Icons.send_rounded, onTap: () => _share(text)),
        const SizedBox(height: 10),
        LimeButton('Скопировать текстом', dark: true, icon: Icons.copy_rounded, onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          toast(context, 'Скопировано');
        }),
      ],
    );
  }

  void _share(String text) {
    launchUrl(
      Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent('Dota Manager')}&text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// Текст сводки (для уведомления, Telegram и буфера обмена).
String buildDigestText(Store store, String period) {
  final ss = store.summaries(period).where((s) => s.agg.games > 0).toList()
    ..sort((a, b) => b.periodDelta.compareTo(a.periodDelta));
  if (ss.isEmpty) return 'Dota Manager: ${periodLong[period]} никто не играл 😴';
  final b = StringBuffer('📊 Итоги ${periodLong[period]}\n');
  for (var i = 0; i < ss.length; i++) {
    final s = ss[i];
    b.write('${i + 1}. ${s.name} — ${s.agg.wins}–${s.agg.losses}, ${signed(s.periodDelta)} MMR'
        '${s.currentMmr != null ? ' (≈${s.currentMmr})' : ''}\n');
  }
  final awards = periodAwards(store.named(period), store.settings.mmrStep);
  if (awards.isNotEmpty) {
    b.write('\n🏅 Отличия\n');
    for (final a in awards.take(6)) {
      b.write('${a.emoji} ${a.title}: ${a.entries.first.player} — ${a.entries.first.text}\n');
    }
  }
  return b.toString().trim();
}
