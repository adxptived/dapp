import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../theme.dart';
import '../widgets.dart';

class AddPlayerScreen extends StatefulWidget {
  final String? initialId;
  final String? initialName;
  const AddPlayerScreen({super.key, this.initialId, this.initialName});
  @override
  State<AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends State<AddPlayerScreen> {
  late final idCtl = TextEditingController(text: widget.initialId);
  late final nameCtl = TextEditingController(text: widget.initialName);
  final mmrCtl = TextEditingController();
  bool busy = false;
  String? status;
  String? error;

  Future<void> _add() async {
    final store = context.read<Store>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final mmr = int.tryParse(mmrCtl.text.trim());
      if (mmrCtl.text.trim().isNotEmpty && (mmr == null || mmr < 0 || mmr > 20000)) {
        throw Exception('MMR — число от 0 до 20000');
      }
      final p = await store.addPlayer(idCtl.text, name: nameCtl.text, mmr: mmr, onProgress: (s) {
        if (mounted) setState(() => status = s);
      });
      if (!mounted) return;
      toast(context, '${p.name} добавлен · ${store.matchesOf(p).length} ранкед-игр');
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Добавить игрока',
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ссылка или ID', style: T.sub),
            const SizedBox(height: 4),
            Text('Dotabuff, OpenDota, Stratz, Steam (/profiles/… или /id/…), SteamID64 или account_id', style: T.small),
            const SizedBox(height: 12),
            TextField(
              controller: idCtl,
              decoration: InputDecoration(
                hintText: 'dotabuff.com/players/123456789',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded, color: C.muted),
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    if (d?.text != null) idCtl.text = d!.text!.trim();
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: nameCtl, decoration: const InputDecoration(hintText: 'Имя (необязательно)')),
            const SizedBox(height: 12),
            TextField(
              controller: mmrCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Текущий MMR (необязательно)'),
            ),
            const SizedBox(height: 8),
            Text('Без MMR будет считаться только ±MMR. Задать его можно позже в карточке игрока.', style: T.tiny),
          ]),
        ),
        const SizedBox(height: 14),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: T.small.copyWith(color: C.red)),
          ),
        LimeButton(busy ? (status ?? 'Добавляю…') : 'Добавить игрока', busy: busy, icon: Icons.add_rounded, onTap: _add),
        if (busy && status != null) ...[
          const SizedBox(height: 10),
          Center(child: Text(status!, style: T.small)),
        ],
        const SizedBox(height: 18),
        AppCard(
          color: C.surface2,
          child: Text(
            'Матчи видны, только если в Dota 2 включена опция «Общедоступная история матчей» '
            '(Настройки → Социальные). Игры до включения не подтянутся. '
            'Первая загрузка всей истории занимает до минуты.',
            style: T.small,
          ),
        ),
      ],
    );
  }
}
