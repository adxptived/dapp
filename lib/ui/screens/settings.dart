import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/ranks.dart';
import '../../logic/stats.dart';
import '../../services/background.dart';
import '../../services/notifier.dart';
import '../../services/updater.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets.dart';
import 'status.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String version = '';

  @override
  void initState() {
    super.initState();
    Updater.current().then((v) {
      if (mounted) setState(() => version = '${v.$1} (${v.$2})');
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final s = store.settings;
    Future<void> set(void Function() f) => store.updateSettings((_) => f());

    return PageScaffold(
      title: 'Настройки',
      leading: Icons.tune_rounded,
      trailing: const HeaderAvatar(),
      children: [
        // --- пати ---
        SectionTitle('Пати', trailing: GestureDetector(onTap: () => openAdd(context), child: Text('+ добавить', style: T.limeS))),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: store.players.isEmpty
              ? Padding(padding: const EdgeInsets.all(10), child: Text('Игроков нет', style: T.small))
              : ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: store.reorder,
                  children: [
                    for (var i = 0; i < store.players.length; i++)
                      Row(key: ValueKey(store.players[i].accountId), children: [
                        Expanded(
                          child: PlayerLine(
                            player: store.players[i],
                            name: store.players[i].name + (store.players[i].isMe ? ' · я' : ''),
                            sub: '${rankLabel(store.players[i].rankTier, store.players[i].leaderboardRank)} · '
                                '${store.matchesOf(store.players[i]).length} игр',
                            onTap: () => openPlayer(context, store.players[i]),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.drag_indicator_rounded, color: C.muted)),
                        ),
                      ]),
                  ],
                ),
        ),

        // --- рейтинг ---
        const SectionTitle('Рейтинг'),
        _group([
          _tile(
            'Шаг MMR за игру',
            '±${s.mmrStep} за победу/поражение',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleBtn(Icons.remove_rounded, size: 34, onTap: () => set(() => s.mmrStep = (s.mmrStep - 1).clamp(1, 100))),
              SizedBox(width: 40, child: Text('${s.mmrStep}', textAlign: TextAlign.center, style: T.sub)),
              CircleBtn(Icons.add_rounded, size: 34, onTap: () => set(() => s.mmrStep = (s.mmrStep + 1).clamp(1, 100))),
            ]),
          ),
          _tile('Период по умолчанию', periodLabels[s.defaultPeriod]!,
              trailing: DropChip<String>(
                  label: 'Период', value: s.defaultPeriod, options: periodLabels, onChanged: (v) => set(() => s.defaultPeriod = v))),
          _tile('Длительность сезона', '${s.seasonDays} дней',
              onTap: () async {
                final v = await prompt(context, 'Дней в сезоне (7–365)', initial: '${s.seasonDays}', keyboard: TextInputType.number);
                final n = int.tryParse(v ?? '');
                if (n != null) set(() => s.seasonDays = n.clamp(7, 365));
              }),
        ]),

        // --- уведомления ---
        const SectionTitle('Уведомления'),
        _group([
          _switch('Конец матча', 'результат, K/D/A и ±MMR', s.notifyMatches, (v) => set(() => s.notifyMatches = v)),
          _switch('Ежедневная сводка', 'в ${s.digestHour}:00, если кто-то играл', s.dailyDigest, (v) => set(() => s.dailyDigest = v)),
          _tile('Час сводки', '${s.digestHour}:00',
              trailing: DropChip<int>(
                label: 'Час',
                value: s.digestHour,
                options: {for (var h = 0; h < 24; h++) h: '$h:00'},
                onChanged: (v) => set(() => s.digestHour = v),
              )),
          _switch('Итоги недели', 'по понедельникам', s.weeklyDigest, (v) => set(() => s.weeklyDigest = v)),
          _switch('Смена лидера', '«Вася обошёл Петю по GPM» (неделя)', s.leaderChanges, (v) => set(() => s.leaderChanges = v)),
          _switch('Steam-профили', 'смена ника и аватарки', s.steamChanges, (v) => set(() => s.steamChanges = v)),
          _tile('Частота проверки', 'каждые ${s.pollMinutes} мин (минимум Android — 15)',
              trailing: DropChip<int>(
                label: 'Раз в',
                value: s.pollMinutes,
                options: const {15: '15 мин', 30: '30 мин', 60: '1 час', 180: '3 часа'},
                onChanged: (v) async {
                  await set(() => s.pollMinutes = v);
                  await Background.schedule(v);
                },
              )),
          _tile('Разрешить уведомления', 'системный запрос Android 13+', onTap: Notifier.requestPermission),
          _tile('Проверить сейчас', 'обновить и прислать оповещения', onTap: () async {
            final ev = await store.refreshAll(force: true);
            await Notifier.handleEvents(store, ev);
            await Notifier.periodic(store);
            if (context.mounted) toast(context, ev.isEmpty ? 'Новых матчей нет' : 'Новых событий: ${ev.length}');
          }),
        ]),

        // --- источники данных ---
        const SectionTitle('Данные'),
        _group([
          _tile('Ключ OpenDota', s.openDotaKey.isEmpty ? 'не задан — до 2000 запросов в сутки' : 'задан ••••${_tail(s.openDotaKey)}',
              onTap: () => _key(context, 'Ключ OpenDota', s.openDotaKey, (v) => set(() => s.openDotaKey = v))),
          _tile('Ключ Stratz', s.stratzKey.isEmpty ? 'не задан — без позиций, IMP, вижна' : 'задан ••••${_tail(s.stratzKey)}',
              onTap: () => _key(context, 'Ключ Stratz (stratz.com/api)', s.stratzKey, (v) => set(() => s.stratzKey = v))),
          _tile('Адрес OpenDota', s.openDotaBase.isEmpty ? 'по умолчанию (api.opendota.com)' : s.openDotaBase,
              onTap: () => _key(context, 'Адрес API OpenDota (зеркало/прокси)', s.openDotaBase, (v) => set(() => s.openDotaBase = v))),
          _tile('Подробности матчей', 'догружать за последние ${s.enrichDays} дней',
              trailing: DropChip<int>(
                label: 'Дней',
                value: s.enrichDays,
                options: const {30: '30', 90: '90', 180: '180', 365: '365'},
                onChanged: (v) => set(() => s.enrichDays = v),
              )),
          _tile('Состояние API', 'OpenDota, Stratz, лимиты, очередь', onTap: () => push(context, const StatusScreen())),
          _tile('Перезагрузить всю историю', 'полная загрузка матчей всех игроков', onTap: () async {
            for (final p in store.players) {
              try {
                await store.refreshPlayer(p, full: true);
              } catch (_) {}
            }
            await store.save();
            if (context.mounted) toast(context, 'История обновлена');
          }),
          _tile('Обновить справочники', 'герои и предметы (${RefData.I.heroes.length} героев)', onTap: () async {
            try {
              await RefData.I.refreshIfStale(store.od, store.dir, force: true);
              if (context.mounted) toast(context, 'Готово: ${RefData.I.heroes.length} героев');
            } catch (e) {
              if (context.mounted) toast(context, '$e');
            }
          }),
        ]),

        // --- обновления ---
        const SectionTitle('Обновления приложения'),
        _group([
          _tile('Версия', version, onTap: () => Updater.checkAndPrompt(context, store)),
          _tile('Проверить обновления', 'GitHub Releases · ${s.updateRepo}', onTap: () => Updater.checkAndPrompt(context, store)),
          _switch('Проверять при запуске', 'и предлагать установить', s.autoUpdateCheck, (v) => set(() => s.autoUpdateCheck = v)),
          _switch('Уведомлять о новой версии', 'проверка в фоне', s.notifyUpdates, (v) => set(() => s.notifyUpdates = v)),
          _tile('Репозиторий обновлений', s.updateRepo,
              onTap: () => _key(context, 'owner/repo', s.updateRepo, (v) => set(() => s.updateRepo = v.isEmpty ? 'adxptived/dapp' : v))),
          _tile('GitHub-токен', s.githubToken.isEmpty ? 'не нужен для публичного репо' : 'задан',
              onTap: () => _key(context, 'GitHub-токен (для приватного репо)', s.githubToken, (v) => set(() => s.githubToken = v))),
        ]),

        // --- резервные копии ---
        const SectionTitle('Резервные копии'),
        _group([
          _tile('Экспорт', 'сохранить игроков, матчи и настройки в файл', onTap: () => _export(context, store)),
          _tile('Импорт', 'восстановить из файла .json', onTap: () => _import(context, store)),
          _tile('Автокопии', 'раз в день, хранятся 7 штук', onTap: () => _backups(context, store)),
          _tile('Сбросить всё', 'удалить игроков, матчи и настройки', danger: true, onTap: () async {
            if (await confirm(context, 'Сбросить всё?', 'Все данные приложения будут удалены.', ok: 'Сбросить')) {
              await store.resetAll();
            }
          }),
        ]),

        const SectionTitle('О приложении'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dota Party $version', style: T.sub),
            const SizedBox(height: 6),
            Text(
              'Рейтинг, оценка MMR и статистика ранкед-игр вашей пати. Данные — OpenDota (и Stratz по ключу). '
              'Проект не связан с Valve.',
              style: T.small,
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://github.com/${s.updateRepo}'), mode: LaunchMode.externalApplication),
              child: Text('github.com/${s.updateRepo}', style: T.limeS),
            ),
          ]),
        ),
      ],
    );
  }

  String _tail(String k) => k.length <= 4 ? k : k.substring(k.length - 4);

  Widget _group(List<Widget> children) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const Divider(height: 1, indent: 16, endIndent: 16, color: C.stroke),
          ],
        ]),
      );

  Widget _tile(String title, String sub, {Widget? trailing, VoidCallback? onTap, bool danger = false}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: T.body.copyWith(fontWeight: FontWeight.w700, color: danger ? C.red : C.text)),
                const SizedBox(height: 2),
                Text(sub, style: T.small),
              ]),
            ),
            if (trailing != null) trailing else if (onTap != null) const Icon(Icons.chevron_right_rounded, color: C.muted),
          ]),
        ),
      );

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) =>
      _tile(title, sub, trailing: Switch(value: value, onChanged: onChanged), onTap: () => onChanged(!value));

  Future<void> _key(BuildContext context, String title, String current, ValueChanged<String> save) async {
    final v = await prompt(context, title, initial: current, hint: 'пусто — убрать');
    if (v != null) save(v.trim());
  }

  Future<void> _export(BuildContext context, Store store) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(store.exportJson())));
      final d = DateTime.now();
      final name = 'dota-party-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
      final r = await FilePicker.saveFile(dialogTitle: 'Сохранить копию', fileName: name, bytes: bytes);
      if (context.mounted) toast(context, r == null ? 'Отменено' : 'Сохранено');
    } catch (e) {
      if (context.mounted) toast(context, 'Не удалось: $e');
    }
  }

  Future<void> _import(BuildContext context, Store store) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;
      final data = await File(path).readAsBytes();
      final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      if (!context.mounted) return;
      if (!await confirm(context, 'Восстановить?', 'Текущие данные будут заменены данными из файла.', ok: 'Восстановить')) return;
      await store.importJson(j);
      if (context.mounted) toast(context, 'Восстановлено: ${store.players.length} игроков');
    } catch (e) {
      if (context.mounted) toast(context, 'Не удалось: $e');
    }
  }

  Future<void> _backups(BuildContext context, Store store) async {
    final files = await store.backups();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          Text('Автокопии', style: T.title),
          if (files.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Пока нет', style: T.small)),
          for (final f in files)
            ListTile(
              leading: const Icon(Icons.history_rounded, color: C.lime),
              title: Text(f.uri.pathSegments.last),
              subtitle: Text('${(f.lengthSync() / 1024).round()} КБ'),
              onTap: () async {
                Navigator.pop(c);
                if (!await confirm(context, 'Восстановить копию?', 'Текущие данные будут заменены.', ok: 'Восстановить')) return;
                await store.importJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
                if (context.mounted) toast(context, 'Восстановлено');
              },
            ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}
