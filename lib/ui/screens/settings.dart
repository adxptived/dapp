import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/refdata.dart';
import '../../data/store.dart';
import '../../logic/ranks.dart';
import '../../logic/stats.dart';
import '../../services/background.dart';
import '../../services/notifier.dart';
import '../../services/updater.dart';
import '../common.dart';
import '../fx.dart';
import '../net_image.dart';
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
  (int, int) cache = (0, 0);
  bool prefetching = false;

  @override
  void initState() {
    super.initState();
    Updater.current().then((v) {
      if (mounted) setState(() => version = '${v.$1} (${v.$2})');
    });
    _cacheInfo();
  }

  Future<void> _cacheInfo() async {
    try {
      final c = await ImageCache2.diskUsage();
      if (mounted) setState(() => cache = c);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final s = store.settings;
    Future<void> set(void Function() f) => store.updateSettings((_) => f());

    return PageScaffold(
      title: 'Настройки',
      trailing: const HeaderAvatar(),
      children: [
        _profile(context, store),

        // --- ключи API ---
        const SectionTitle('Ключи API'),
        _group([
          _keyTile(
            icon: Icons.bolt_rounded,
            title: 'OpenDota',
            value: s.openDotaKey,
            emptyText: 'без ключа — до 2000 запросов в сутки',
            onTap: () => _editKey(
              context,
              title: 'Ключ OpenDota',
              help: 'С ключом приложение опрашивает чаще и не упирается в суточный лимит. Ключ — на opendota.com → API Keys.',
              link: 'https://www.opendota.com/api-keys',
              current: s.openDotaKey,
              test: (k) => _testOpenDota(store, k, s.openDotaBase),
              save: (v) => set(() => s.openDotaKey = v),
            ),
          ),
          _keyTile(
            icon: Icons.insights_rounded,
            title: 'Stratz',
            value: s.stratzKey,
            emptyText: 'нет позиций, IMP, вижна и линий',
            onTap: () => _editKey(
              context,
              title: 'Ключ Stratz',
              help: 'Бесплатный токен: войдите на stratz.com через Steam → API → скопируйте токен. Даёт позиции 1–5, IMP, варды, исход линии.',
              link: 'https://stratz.com/api',
              current: s.stratzKey,
              test: (k) => _testStratz(k),
              save: (v) => set(() => s.stratzKey = v),
            ),
          ),
          _keyTile(
            icon: Icons.dns_rounded,
            title: 'Адрес OpenDota',
            value: s.openDotaBase,
            secret: false,
            emptyText: 'по умолчанию — api.opendota.com',
            onTap: () => _editKey(
              context,
              title: 'Адрес API OpenDota',
              help: 'Если api.opendota.com недоступен из вашей сети — укажите зеркало или прокси, например https://my-proxy.example/api',
              current: s.openDotaBase,
              secret: false,
              hint: 'https://…/api',
              test: (k) => _testOpenDota(store, s.openDotaKey, k),
              save: (v) => set(() => s.openDotaBase = v),
            ),
          ),
          _tile(Icons.monitor_heart_outlined, 'Состояние API', 'OpenDota, Stratz, лимиты, очередь',
              onTap: () => push(context, const StatusScreen())),
        ]),

        // --- рейтинг ---
        const SectionTitle('Рейтинг'),
        _group([
          _tile(
            Icons.trending_up_rounded,
            'Шаг MMR за игру',
            '±${s.mmrStep} за победу/поражение',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleBtn(Icons.remove_rounded, size: 34, onTap: () => set(() => s.mmrStep = (s.mmrStep - 1).clamp(1, 100))),
              SizedBox(
                width: 40,
                child: Center(child: Text('${s.mmrStep}', style: T.sub)),
              ),
              CircleBtn(Icons.add_rounded, size: 34, onTap: () => set(() => s.mmrStep = (s.mmrStep + 1).clamp(1, 100))),
            ]),
          ),
          _pick<String>(Icons.date_range_rounded, 'Период по умолчанию', s.defaultPeriod, periodLabels,
              (v) => set(() => s.defaultPeriod = v)),
          _pick<int>(Icons.flag_outlined, 'Длительность сезона', s.seasonDays,
              const {7: '7 дней', 14: '14 дней', 30: '30 дней', 60: '60 дней', 90: '90 дней'}, (v) => set(() => s.seasonDays = v)),
        ]),

        // --- уведомления ---
        const SectionTitle('Уведомления'),
        _group([
          _switch(Icons.sports_esports_outlined, 'Конец матча', 'результат, K/D/A и ±MMR', s.notifyMatches,
              (v) => set(() => s.notifyMatches = v)),
          _switch(Icons.today_outlined, 'Ежедневная сводка', 'в ${s.digestHour}:00, если кто-то играл', s.dailyDigest,
              (v) => set(() => s.dailyDigest = v)),
          _pick<int>(Icons.schedule_rounded, 'Час сводки', s.digestHour, {for (var h = 0; h < 24; h++) h: '$h:00'},
              (v) => set(() => s.digestHour = v)),
          _switch(Icons.calendar_view_week_outlined, 'Итоги недели', 'по понедельникам', s.weeklyDigest,
              (v) => set(() => s.weeklyDigest = v)),
          _switch(Icons.swap_vert_rounded, 'Смена лидера', '«Вася обошёл Петю по GPM»', s.leaderChanges,
              (v) => set(() => s.leaderChanges = v)),
          _switch(Icons.badge_outlined, 'Steam-профили', 'смена ника и аватарки', s.steamChanges,
              (v) => set(() => s.steamChanges = v)),
          _pick<int>(Icons.timer_outlined, 'Проверять матчи', s.pollMinutes,
              const {15: 'каждые 15 мин', 30: 'каждые 30 мин', 60: 'раз в час', 180: 'раз в 3 часа'}, (v) async {
            await set(() => s.pollMinutes = v);
            await Background.schedule(v, wifiOnly: s.bgWifiOnly);
          }),
          _tile(Icons.notifications_active_outlined, 'Разрешить уведомления', 'системный запрос Android 13+',
              onTap: Notifier.requestPermission),
          _tile(Icons.sync_rounded, 'Проверить сейчас', 'обновить и прислать оповещения', onTap: () async {
            final ev = await store.refreshAll(force: true);
            if (context.mounted) toast(context, ev.isEmpty ? 'Новых матчей нет' : 'Новых событий: ${ev.length}');
          }),
        ]),

        // --- данные и кэш ---
        const SectionTitle('Данные и трафик'),
        _group([
          _switch(Icons.data_saver_on_rounded, 'Экономия трафика',
              'меньше запросов, маленькие иконки, подробности — только для новых игр', s.dataSaver, (v) => set(() => s.dataSaver = v)),
          _switch(Icons.wifi_rounded, 'Фоновая проверка только по Wi-Fi', 'на мобильном интернете — только в приложении', s.bgWifiOnly,
              (v) async {
            await set(() => s.bgWifiOnly = v);
            await Background.schedule(s.pollMinutes, wifiOnly: v);
          }),
          _tile(Icons.swap_vert_circle_outlined, 'Трафик',
              'сегодня ${_mb(Traffic.today)} · за 7 дней ${_mb(Traffic.lastDays(7))} · за 30 дней ${_mb(Traffic.lastDays(30))}'),
          _pick<int>(Icons.manage_history_rounded, 'Подробности матчей', s.enrichDays,
              const {30: 'за 30 дней', 90: 'за 90 дней', 180: 'за 180 дней', 365: 'за год'}, (v) => set(() => s.enrichDays = v)),
          _tile(
            Icons.image_outlined,
            'Иконки героев',
            prefetching ? 'скачиваю…' : 'в кэше ${cache.$1} файлов · ${(cache.$2 / 1024 / 1024).toStringAsFixed(1)} МБ',
            trailing: prefetching
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded, color: C.muted),
            onTap: prefetching
                ? null
                : () async {
                    setState(() => prefetching = true);
                    try {
                      await RefData.I.refreshIfStale(store.od, store.dir);
                      final n = await ImageCache2.prefetch(
                          RefData.I.heroes.values.expand((h) => s.dataSaver ? [h.icon] : [h.image, h.icon]));
                      if (context.mounted) toast(context, 'Иконки героев в кэше: $n');
                    } catch (e) {
                      if (context.mounted) toast(context, '$e');
                    }
                    if (mounted) setState(() => prefetching = false);
                    _cacheInfo();
                  },
          ),
          _tile(Icons.cleaning_services_outlined, 'Очистить кэш картинок', 'скачаются заново при просмотре', onTap: () async {
            await ImageCache2.clear();
            _cacheInfo();
            if (context.mounted) toast(context, 'Кэш очищен');
          }),
          _tile(Icons.menu_book_outlined, 'Обновить справочники', 'герои и предметы (${RefData.I.heroes.length} героев)',
              onTap: () async {
            try {
              await RefData.I.refreshIfStale(store.od, store.dir, force: true);
              if (context.mounted) toast(context, 'Готово: ${RefData.I.heroes.length} героев, ${RefData.I.items.length} предметов');
            } catch (e) {
              if (context.mounted) toast(context, '$e');
            }
          }),
          _tile(Icons.cloud_download_outlined, 'Перезагрузить всю историю', 'полная загрузка матчей всех игроков',
              onTap: () async {
            toast(context, 'Загружаю историю…');
            for (final p in store.players) {
              try {
                await store.refreshPlayer(p, full: true);
              } catch (_) {}
            }
            await store.save();
            if (context.mounted) toast(context, 'История обновлена');
          }),
        ]),

        // --- пати ---
        SectionTitle('Игроки', trailing: Pressable(onTap: () => openAdd(context), child: Text('+ добавить', style: T.limeS))),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: store.players.isEmpty
              ? Padding(padding: const EdgeInsets.all(10), child: Text('Игроков нет', style: T.small))
              : ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, __) => Material(color: Colors.transparent, child: child),
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

        // --- обновления ---
        const SectionTitle('Обновления приложения'),
        _group([
          _tile(Icons.system_update_rounded, 'Проверить обновления', 'GitHub Releases · ${s.updateRepo}',
              onTap: () => Updater.checkAndPrompt(context, store)),
          _switch(Icons.rocket_launch_outlined, 'Проверять при запуске', 'и предлагать установить', s.autoUpdateCheck,
              (v) => set(() => s.autoUpdateCheck = v)),
          _switch(Icons.notifications_none_rounded, 'Уведомлять о новой версии', 'проверка в фоне', s.notifyUpdates,
              (v) => set(() => s.notifyUpdates = v)),
          _keyTile(
            icon: Icons.source_outlined,
            title: 'Репозиторий',
            value: s.updateRepo,
            secret: false,
            emptyText: 'adxptived/dapp',
            onTap: () => _editKey(context,
                title: 'Репозиторий обновлений',
                help: 'owner/repo на GitHub, откуда брать APK.',
                current: s.updateRepo,
                secret: false,
                hint: 'adxptived/dapp',
                save: (v) => set(() => s.updateRepo = v.isEmpty ? 'adxptived/dapp' : v)),
          ),
          _keyTile(
            icon: Icons.key_rounded,
            title: 'GitHub-токен',
            value: s.githubToken,
            emptyText: 'не нужен для публичного репо',
            onTap: () => _editKey(context,
                title: 'GitHub-токен',
                help: 'Нужен, только если репозиторий с релизами приватный (права: Contents → Read).',
                link: 'https://github.com/settings/personal-access-tokens',
                current: s.githubToken,
                test: (k) => _testGithub(k),
                save: (v) => set(() => s.githubToken = v)),
          ),
        ]),

        // --- резервные копии ---
        const SectionTitle('Резервные копии'),
        _group([
          _tile(Icons.upload_file_rounded, 'Экспорт', 'игроки, матчи и настройки в файл', onTap: () => _export(context, store)),
          _tile(Icons.download_for_offline_outlined, 'Импорт', 'восстановить из файла .json', onTap: () => _import(context, store)),
          _tile(Icons.history_rounded, 'Автокопии', 'раз в день, хранятся 7 штук', onTap: () => _backups(context, store)),
          _tile(Icons.delete_forever_outlined, 'Сбросить всё', 'удалить игроков, матчи и настройки', danger: true, onTap: () async {
            if (await confirm(context, 'Сбросить всё?', 'Все данные приложения будут удалены.', ok: 'Сбросить')) {
              await store.resetAll();
            }
          }),
        ]),

        const SizedBox(height: 18),
        Center(
          child: Pressable(
            onTap: () => launchUrl(Uri.parse('https://github.com/${s.updateRepo}'), mode: LaunchMode.externalApplication),
            child: Text('Dota Manager $version · github.com/${s.updateRepo}', style: T.tiny),
          ),
        ),
        const SizedBox(height: 4),
        Center(child: Text('Данные — OpenDota и Stratz. Проект не связан с Valve.', style: T.tiny)),
      ],
    );
  }

  // --- блоки ---------------------------------------------------------------------------------------

  Widget _profile(BuildContext context, Store store) {
    final me = store.me ?? (store.players.isEmpty ? null : store.players.first);
    final total = store.players.fold<int>(0, (a, p) => a + store.matchesOf(p).length);
    return AppCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [C.lime.withValues(alpha: 0.16), C.surface, C.surface],
      ),
      onTap: me == null ? () => openAdd(context) : () => openPlayer(context, me),
      child: Row(children: [
        Avatar(me?.avatar, size: 58, fallback: me?.name ?? '+', ring: me != null),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me?.name ?? 'Добавьте себя', style: T.title.copyWith(fontSize: 19)),
            const SizedBox(height: 4),
            if (me != null) RankBadge(me.rankTier, leaderboard: me.leaderboardRank, size: 20),
            const SizedBox(height: 6),
            Text('${store.players.length} игроков · $total матчей', style: T.small),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
          child: Text(version.isEmpty ? 'v…' : 'v${version.split(' ').first}', style: T.tiny.copyWith(color: C.text)),
        ),
      ]),
    );
  }

  Widget _group(List<Widget> children) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) Divider(height: 1, indent: 62, endIndent: 16, color: Colors.white.withValues(alpha: 0.05)),
          ],
        ]),
      );

  Widget _icon(IconData icon, {bool danger = false}) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: danger ? C.red.withValues(alpha: 0.14) : C.lime.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 18, color: danger ? C.red : C.lime),
      );

  Widget _tile(IconData icon, String title, String sub, {Widget? trailing, VoidCallback? onTap, bool danger = false}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        _icon(icon, danger: danger),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.body.copyWith(fontWeight: FontWeight.w700, color: danger ? C.red : C.text)),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(sub, key: ValueKey(sub), style: T.small),
            ),
          ]),
        ),
        if (trailing != null) trailing else if (onTap != null) const Icon(Icons.chevron_right_rounded, color: C.muted),
      ]),
    );
    return onTap == null ? row : Pressable(scale: 0.985, onTap: onTap, child: row);
  }

  Widget _switch(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) =>
      _tile(icon, title, sub, trailing: Switch(value: value, onChanged: onChanged), onTap: () => onChanged(!value));

  Widget _pick<V>(IconData icon, String title, V value, Map<V, String> options, ValueChanged<V> onChanged) => _tile(
        icon,
        title,
        options[value] ?? '$value',
        trailing: const Icon(Icons.unfold_more_rounded, color: C.muted, size: 20),
        onTap: () async {
          final v = await pickOption<V>(context, title, options, value);
          if (v != null) onChanged(v);
        },
      );

  Widget _keyTile(
      {required IconData icon,
      required String title,
      required String value,
      required String emptyText,
      required VoidCallback onTap,
      bool secret = true}) {
    final isSet = value.trim().isNotEmpty;
    final shown = !isSet ? emptyText : (secret ? '••••••${_tail(value)}' : value);
    return _tile(
      icon,
      title,
      shown,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSet ? C.lime.withValues(alpha: 0.16) : C.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(isSet ? 'задан' : 'нет', style: T.tiny.copyWith(color: isSet ? C.lime : C.muted)),
        ),
        const Icon(Icons.chevron_right_rounded, color: C.muted),
      ]),
    );
  }

  String _mb(int b) => b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(0)} КБ' : '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';

  String _tail(String k) => k.length <= 4 ? k : k.substring(k.length - 4);

  // --- проверки ключей ------------------------------------------------------------------------------

  Future<String> _testOpenDota(Store store, String key, String base) async {
    final od = OpenDota(apiKey: key.trim(), base: base.trim());
    final id = store.players.isEmpty ? 87278757 : store.players.first.accountId;
    await od.get('/players/$id', retries: 1);
    return 'OpenDota отвечает${od.remainingDay != null ? ' · осталось ${od.remainingDay} запросов на сегодня' : ''}';
  }

  Future<String> _testStratz(String key) async {
    final st = Stratz(key.trim());
    await st.query('query { constants { gameVersions { id } } }');
    return 'Ключ Stratz работает';
  }

  Future<String> _testGithub(String key) async {
    final r = await http.get(Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'Bearer ${key.trim()}', 'Accept': 'application/vnd.github+json', 'User-Agent': 'dapp'});
    if (r.statusCode != 200) throw ApiError('GitHub ответил ${r.statusCode}');
    final login = (jsonDecode(r.body) as Map)['login'];
    return 'Токен работает · $login';
  }

  Future<void> _editKey(BuildContext context,
      {required String title,
      required String help,
      required String current,
      required ValueChanged<String> save,
      String? link,
      String? hint,
      bool secret = true,
      Future<String> Function(String)? test}) async {
    await showGlassSheet<void>(
      context,
      (c) => _KeySheet(
        title: title,
        help: help,
        current: current,
        link: link,
        hint: hint,
        secret: secret,
        test: test,
        onSave: (v) {
          save(v);
          Navigator.of(c).pop();
          toast(context, v.isEmpty ? '$title: убран' : '$title: сохранён');
        },
      ),
    );
  }

  // --- резервные копии ------------------------------------------------------------------------------

  Future<void> _export(BuildContext context, Store store) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(store.exportJson())));
      final d = DateTime.now();
      final name = 'dota-manager-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
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
    await showGlassSheet<void>(
      context,
      (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 10), child: Text('Автокопии', style: T.title)),
          if (files.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('Пока нет', style: T.small)),
          for (final f in files)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Pressable(
                onTap: () async {
                  Navigator.pop(c);
                  if (!await confirm(context, 'Восстановить копию?', 'Текущие данные будут заменены.', ok: 'Восстановить')) return;
                  await store.importJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
                  if (context.mounted) toast(context, 'Восстановлено');
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    const Icon(Icons.history_rounded, color: C.lime),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f.uri.pathSegments.last, style: T.body)),
                    Text('${(f.lengthSync() / 1024).round()} КБ', style: T.small),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Шторка ввода ключа: вставка из буфера, показать/скрыть, проверка, ссылка «где взять».
class _KeySheet extends StatefulWidget {
  final String title, help, current;
  final String? link, hint;
  final bool secret;
  final Future<String> Function(String)? test;
  final ValueChanged<String> onSave;
  const _KeySheet(
      {required this.title,
      required this.help,
      required this.current,
      required this.onSave,
      this.link,
      this.hint,
      this.secret = true,
      this.test});
  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late final ctl = TextEditingController(text: widget.current);
  late bool hidden = widget.secret;
  bool testing = false;
  String? result;
  bool ok = false;

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final t = d?.text?.trim();
    if (t == null || t.isEmpty) {
      if (mounted) toast(context, 'Буфер обмена пуст');
      return;
    }
    setState(() {
      ctl.text = t;
      result = null;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _test() async {
    if (widget.test == null) return;
    setState(() {
      testing = true;
      result = null;
    });
    try {
      result = await widget.test!(ctl.text);
      ok = true;
    } catch (e) {
      result = '$e'.replaceFirst('Exception: ', '');
      ok = false;
    }
    if (mounted) setState(() => testing = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: T.title),
        const SizedBox(height: 6),
        Text(widget.help, style: T.small),
        const SizedBox(height: 14),
        TextField(
          controller: ctl,
          obscureText: hidden,
          autocorrect: false,
          enableSuggestions: false,
          style: T.body.copyWith(fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: widget.hint ?? 'вставьте ключ',
            suffixIcon: widget.secret
                ? IconButton(
                    icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                    onPressed: () => setState(() => hidden = !hidden),
                  )
                : null,
          ),
          onChanged: (_) => setState(() => result = null),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: LimeButton('Вставить', dark: true, icon: Icons.content_paste_rounded, onTap: _paste)),
          if (widget.test != null) ...[
            const SizedBox(width: 10),
            Expanded(child: LimeButton('Проверить', dark: true, icon: Icons.wifi_tethering_rounded, busy: testing, onTap: _test)),
          ],
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: result == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ok ? C.lime : C.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(result!, style: T.small.copyWith(color: ok ? C.lime : C.red))),
                  ]),
                ),
        ),
        if (widget.link != null) ...[
          const SizedBox(height: 12),
          Pressable(
            onTap: () => launchUrl(Uri.parse(widget.link!), mode: LaunchMode.externalApplication),
            child: Row(children: [
              const Icon(Icons.open_in_new_rounded, size: 16, color: C.lime),
              const SizedBox(width: 6),
              Text('Где взять ключ', style: T.limeS),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          if (widget.current.isNotEmpty) ...[
            Expanded(child: LimeButton('Убрать', dark: true, onTap: () => widget.onSave(''))),
            const SizedBox(width: 10),
          ],
          Expanded(child: LimeButton('Сохранить', icon: Icons.check_rounded, onTap: () => widget.onSave(ctl.text.trim()))),
        ]),
      ]),
    );
  }
}
