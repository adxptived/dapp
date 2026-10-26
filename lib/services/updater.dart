// Обновления: последняя сборка из GitHub Releases → скачать APK → установить поверх.
// APK всегда подписан одним ключом, а номер сборки растёт, поэтому Android ставит обновление без удаления.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class UpdateInfo {
  final String version;
  final int build;
  final String notes;
  final String? apkUrl;
  final String? apiAssetUrl;
  final int size;
  final String pageUrl;
  UpdateInfo(this.version, this.build, this.notes, this.apkUrl, this.apiAssetUrl, this.size, this.pageUrl);
}

class Updater {
  static int _lastCheck = 0;

  static Future<(String, int)> current() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return (info.version, int.tryParse(info.buildNumber) ?? 0);
    } catch (_) {
      return ('?', 0);
    }
  }

  static Map<String, String> _headers(Store store, {bool binary = false}) => {
        'Accept': binary ? 'application/octet-stream' : 'application/vnd.github+json',
        'User-Agent': 'dapp-updater',
        if (store.settings.githubToken.trim().isNotEmpty) 'Authorization': 'Bearer ${store.settings.githubToken.trim()}',
      };

  /// Последний релиз; null — обновлений нет. Бросает исключение при сетевой ошибке.
  static Future<UpdateInfo?> check(Store store, {bool force = false}) async {
    final repo = store.settings.updateRepo.trim().isEmpty ? 'adxptived/dapp' : store.settings.updateRepo.trim();
    final r = await http
        .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: _headers(store))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) throw Exception('Релизов пока нет (или репозиторий приватный — укажите GitHub-токен)');
    if (r.statusCode != 200) throw Exception('GitHub ответил ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '').toString();
    final m = RegExp(r'(\d+)$').firstMatch(tag);
    final build = m == null ? 0 : int.parse(m.group(1)!);
    final (_, cur) = await current();
    if (!force && build <= cur) return null;
    String? apk, api;
    var size = 0;
    for (final a in (j['assets'] as List? ?? []).whereType<Map>()) {
      final name = (a['name'] ?? '').toString();
      if (name.endsWith('.apk')) {
        apk = a['browser_download_url']?.toString();
        api = a['url']?.toString();
        size = (a['size'] as num?)?.toInt() ?? 0;
        break;
      }
    }
    return UpdateInfo(
      (j['name'] ?? tag).toString(),
      build,
      (j['body'] ?? '').toString(),
      apk,
      api,
      size,
      (j['html_url'] ?? 'https://github.com/$repo/releases').toString(),
    );
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/updates');
    await d.create(recursive: true);
    return d;
  }

  /// Готовый скачанный APK этой версии (если уже скачан целиком) — ставится без повторной загрузки.
  static Future<File?> downloaded(UpdateInfo u) async {
    try {
      final f = File('${(await _dir()).path}/dapp-${u.build}.apk');
      if (await f.exists() && (u.size == 0 || await f.length() == u.size)) return f;
    } catch (_) {}
    return null;
  }

  /// Скачать APK с докачкой: обрыв связи не начинает загрузку заново — продолжаем с места обрыва,
  /// автоматически до 8 попыток. Уже скачанный файл не качается повторно.
  static Future<File> download(Store store, UpdateInfo u, void Function(double) onProgress) async {
    final ready = await downloaded(u);
    if (ready != null) {
      onProgress(1);
      return ready;
    }
    final dir = await _dir();
    // старые версии больше не нужны
    try {
      await for (final f in dir.list()) {
        if (f is File && !f.path.contains('dapp-${u.build}.')) await f.delete();
      }
    } catch (_) {}
    final part = File('${dir.path}/dapp-${u.build}.apk.part');
    final useApi = store.settings.githubToken.trim().isNotEmpty && u.apiAssetUrl != null;
    final url = useApi ? u.apiAssetUrl! : u.apkUrl!;
    Object? lastErr;
    for (var attempt = 0; attempt < 8; attempt++) {
      var have = await part.exists() ? await part.length() : 0;
      if (u.size > 0 && have >= u.size) break;
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url))..headers.addAll(_headers(store, binary: true));
        if (have > 0) req.headers['Range'] = 'bytes=$have-';
        final resp = await client.send(req).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200 && have > 0) {
          have = 0; // сервер не умеет докачку — начинаем заново
          await part.writeAsBytes(const [], flush: true);
        } else if (resp.statusCode == 416) {
          break; // уже всё скачано
        } else if (resp.statusCode != 200 && resp.statusCode != 206) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        final total = u.size > 0 ? u.size : have + (resp.contentLength ?? 0);
        final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
        var got = have;
        try {
          await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
            sink.add(chunk);
            got += chunk.length;
            Traffic.add(chunk.length);
            if (total > 0) onProgress(got / total);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        if (u.size == 0 || got >= u.size) break;
      } catch (e) {
        lastErr = e;
        await Future.delayed(Duration(seconds: 1 + attempt * 2));
      } finally {
        client.close();
      }
    }
    final size = await part.exists() ? await part.length() : 0;
    if (size == 0 || (u.size > 0 && size < u.size)) {
      final pctDone = u.size > 0 ? (size * 100 ~/ u.size) : 0;
      throw Exception('Связь обрывается (скачано $pctDone%). Нажмите ещё раз — загрузка продолжится с места обрыва.'
          '');
    }
    final apk = File('${dir.path}/dapp-${u.build}.apk');
    if (await apk.exists()) await apk.delete();
    return part.rename(apk.path);
  }

  static Future<void> install(File apk) async {
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) throw Exception(r.message);
  }

  /// Проверить и предложить обновиться. silent — не показывать «обновлений нет» и ошибки.
  static Future<void> checkAndPrompt(BuildContext context, Store store, {bool silent = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (silent && now - _lastCheck < 3 * 3600) return;
    _lastCheck = now;
    UpdateInfo? u;
    try {
      u = await check(store);
    } catch (e) {
      if (!silent && context.mounted) toast(context, '$e'.replaceFirst('Exception: ', ''));
      return;
    }
    if (!context.mounted) return;
    if (u == null) {
      if (!silent) toast(context, 'У вас последняя версия');
      return;
    }
    await showUpdateDialog(context, store, u);
  }

  static Future<void> showUpdateDialog(BuildContext context, Store store, UpdateInfo u) async {
    final (ver, build) = await current();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => _UpdateSheet(store: store, info: u, currentVersion: '$ver ($build)'),
    );
  }
}

class _UpdateSheet extends StatefulWidget {
  final Store store;
  final UpdateInfo info;
  final String currentVersion;
  const _UpdateSheet({required this.store, required this.info, required this.currentVersion});
  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  double? progress;
  String? error;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    Updater.downloaded(widget.info).then((f) {
      if (mounted && f != null) setState(() => ready = true);
    });
  }

  Future<void> _go() async {
    final u = widget.info;
    if (!Platform.isAndroid || u.apkUrl == null) {
      await launchUrl(Uri.parse(u.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      progress = 0;
      error = null;
    });
    try {
      final f = await Updater.download(widget.store, u, (p) {
        if (mounted) setState(() => progress = p);
      });
      await Updater.install(f);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          progress = null;
          error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.info;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
              child: const Icon(Icons.system_update_rounded, color: C.onLime),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Доступно обновление', style: T.title),
                Text('${u.version} · у вас ${widget.currentVersion}', style: T.small),
              ]),
            ),
          ]),
          if (u.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(child: Text(u.notes.trim(), style: T.small.copyWith(color: C.text))),
            ),
          ],
          const SizedBox(height: 18),
          if (progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 8, backgroundColor: C.surface3),
            ),
            const SizedBox(height: 8),
            Text('Скачиваю… ${((progress ?? 0) * 100).toStringAsFixed(0)}%', style: T.small),
          ] else
            LimeButton(
                !Platform.isAndroid
                    ? 'Открыть страницу релиза'
                    : ready
                        ? 'Установить (уже скачано)'
                        : 'Скачать и установить',
                icon: ready ? Icons.install_mobile_rounded : Icons.download_rounded,
                onTap: _go),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: T.small.copyWith(color: C.red)),
          ],
          const SizedBox(height: 10),
          Text('Установится поверх текущей версии — данные сохранятся. Android может попросить разрешить установку из этого приложения.',
              style: T.tiny),
        ]),
      ),
    );
  }
}
