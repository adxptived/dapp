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

  static Future<File> download(Store store, UpdateInfo u, void Function(double) onProgress) async {
    final useApi = store.settings.githubToken.trim().isNotEmpty && u.apiAssetUrl != null;
    final url = useApi ? u.apiAssetUrl! : u.apkUrl!;
    final req = http.Request('GET', Uri.parse(url))..headers.addAll(_headers(store, binary: true));
    final client = http.Client();
    try {
      final resp = await client.send(req);
      if (resp.statusCode != 200) throw Exception('Скачивание: HTTP ${resp.statusCode}');
      final total = resp.contentLength ?? u.size;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/dapp-update-${u.build}.apk');
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
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
            LimeButton(Platform.isAndroid ? 'Скачать и установить' : 'Открыть страницу релиза',
                icon: Icons.download_rounded, onTap: _go),
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
