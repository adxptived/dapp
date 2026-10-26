import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/store.dart';
import '../theme.dart';
import '../widgets.dart';

/// «Позвать пати» (аналог /go): собрать сообщение со временем и отметить, кто идёт.
class GoScreen extends StatefulWidget {
  const GoScreen({super.key});
  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> {
  final ctl = TextEditingController(text: 'Го ранкед!');
  String when = 'now';
  final going = <int, String>{}; // account_id → 'yes' | 'later' | 'no'

  String _whenText() {
    final now = DateTime.now();
    switch (when) {
      case '15':
        final t = now.add(const Duration(minutes: 15));
        return 'через 15 минут (в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')})';
      case '30':
        final t = now.add(const Duration(minutes: 30));
        return 'через полчаса (в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')})';
      case 'evening':
        return 'сегодня вечером';
      default:
        return 'прямо сейчас';
    }
  }

  String _message(Store store) {
    final yes = store.players.where((p) => going[p.accountId] == 'yes').map((p) => p.name).toList();
    final later = store.players.where((p) => going[p.accountId] == 'later').map((p) => p.name).toList();
    final b = StringBuffer('🎮 ${ctl.text.trim().isEmpty ? 'Го катку!' : ctl.text.trim()}\n⏰ ${_whenText()}\n');
    b.write('Собрано ${yes.length}/5');
    if (yes.isNotEmpty) b.write(': ${yes.join(', ')}');
    if (later.isNotEmpty) b.write('\n⏱ позже: ${later.join(', ')}');
    final missing = store.players.where((p) => going[p.accountId] == null).map((p) => p.name).toList();
    if (missing.isNotEmpty) b.write('\nЖдём: ${missing.join(', ')}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final yes = going.values.where((v) => v == 'yes').length;
    return PageScaffold(
      title: 'Позвать на катку',
      children: [
        TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Текст приглашения'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Segments<String>(
          value: when,
          options: const {'now': 'Сейчас', '15': '15 мин', '30': '30 мин', 'evening': 'Вечером'},
          onChanged: (v) => setState(() => when = v),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Кто идёт', style: T.sub)),
              Text('Собрано $yes/5', style: T.title.copyWith(color: yes >= 5 ? C.lime : C.text)),
            ]),
            const SizedBox(height: 8),
            BarMeter(yes / 5, bars: 25, height: 22),
            const SizedBox(height: 8),
            for (final p in store.players)
              PlayerLine(
                player: p,
                name: p.name,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final o in const [('yes', '✅'), ('later', '⏱'), ('no', '❌')])
                    GestureDetector(
                      onTap: () => setState(() => going[p.accountId] == o.$1 ? going.remove(p.accountId) : going[p.accountId] = o.$1),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: going[p.accountId] == o.$1 ? C.lime.withValues(alpha: 0.25) : C.surface2,
                          shape: BoxShape.circle,
                        ),
                        child: Text(o.$2, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(color: C.surface2, child: Text(_message(store), style: T.body)),
        const SizedBox(height: 14),
        LimeButton('Отправить в Telegram', icon: Icons.send_rounded, onTap: () {
          launchUrl(
            Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent('🎮')}&text=${Uri.encodeComponent(_message(store))}'),
            mode: LaunchMode.externalApplication,
          );
        }),
        const SizedBox(height: 10),
        LimeButton('Скопировать', dark: true, icon: Icons.copy_rounded, onTap: () {
          Clipboard.setData(ClipboardData(text: _message(store)));
          toast(context, 'Скопировано');
        }),
      ],
    );
  }
}
