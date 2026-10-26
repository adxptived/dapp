import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/store.dart';
import '../../logic/stats.dart';
import '../theme.dart';
import '../widgets.dart';

/// Состояние источников данных (аналог /status).
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool checking = false;

  Future<void> _ping() async {
    final store = context.read<Store>();
    setState(() => checking = true);
    try {
      await store.od.get('/health');
    } catch (_) {
      try {
        await store.od.constants('game_mode');
      } catch (_) {}
    }
    if (store.stratz.enabled) {
      try {
        await store.stratz.query('query { constants { gameVersions { id } } }');
      } catch (_) {}
    }
    if (mounted) setState(() => checking = false);
  }

  Widget _health(ProviderHealth h, {bool enabled = true}) {
    final ok = h.ok;
    final (label, color) = !enabled
        ? ('не настроен', C.muted)
        : ok == null
            ? ('не проверялся', C.muted)
            : ok
                ? ('работает', C.lime)
                : ('недоступен', C.red);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: T.small.copyWith(color: color, fontWeight: FontWeight.w700)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final od = store.od;
    return PageScaffold(
      title: 'Состояние',
      children: [
        AppCard(
          child: KvTable(rows: [
            ('OpenDota', _health(od.health)),
            if (od.health.lastError != null && od.health.ok == false) ('Ошибка', valueText(od.health.lastError!)),
            ('Ключ OpenDota', valueText(od.apiKey.isEmpty ? 'нет (лимит ~2000/сутки)' : 'есть')),
            ('Остаток за сутки', valueText(od.remainingDay?.toString() ?? '—')),
            ('Остаток в минуту', valueText(od.remainingMinute?.toString() ?? '—')),
            ('Фоновая догрузка', valueText(od.backgroundAllowed ? 'идёт' : 'на паузе (бережём лимит)')),
            ('Stratz', _health(store.stratz.health, enabled: store.stratz.enabled)),
            ('Очередь подробностей', valueText('${store.enrichQueue} матчей')),
            ('Данные обновлены', valueText(store.lastFullRefresh == 0 ? '—' : fmtAgo(store.lastFullRefresh))),
            ('Игроков', valueText('${store.players.length}')),
            (
              'Матчей в базе',
              valueText('${store.players.fold<int>(0, (a, p) => a + store.matchesOf(p).length)}'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        LimeButton('Проверить сейчас', busy: checking, onTap: _ping),
        const SizedBox(height: 10),
        Text(
          'Без ключа OpenDota комфортно до 6–8 игроков. Если api.opendota.com недоступен из вашей сети, '
          'укажите зеркало в «Адрес OpenDota».',
          style: T.tiny,
        ),
        const SizedBox(height: 4),
        Text('Сейчас: ${fmtDate(nowTs())}', style: T.tiny),
      ],
    );
  }
}
