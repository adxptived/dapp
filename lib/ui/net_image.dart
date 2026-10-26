// Картинки из сети с кэшем: память (LRU) + файлы в папке приложения. Иконки героев качаются один раз.
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/api.dart';

class ImageCache2 {
  static final _mem = LinkedHashMap<String, Uint8List>();
  static final _inflight = <String, Future<Uint8List?>>{};
  static final _failed = <String, DateTime>{};
  static Directory? _dir;
  static bool _dirFailed = false;
  static int _active = 0;
  static final _queue = Queue<Completer<void>>();
  static const _maxMem = 150;
  static final _onDisk = <String>{}; // имена уже скачанных файлов — без проверок диска на каждую картинку
  static Future<void>? _init;

  /// Один раз при запуске: папка кэша и список скачанного.
  static Future<void> init() => _init ??= () async {
        final d = await _cacheDir();
        if (d == null) return;
        try {
          await for (final f in d.list()) {
            if (f is File) _onDisk.add(f.uri.pathSegments.last);
          }
        } catch (_) {}
      }();
  static const _maxParallel = 6;

  static Future<Directory?> _cacheDir() async {
    if (_dir != null || _dirFailed) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/img');
      await d.create(recursive: true);
      _dir = d;
    } catch (_) {
      _dirFailed = true;
    }
    return _dir;
  }

  static String _name(String url) => url.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static Uint8List? peek(String url) {
    final v = _mem.remove(url);
    if (v != null) _mem[url] = v; // наверх LRU
    return v;
  }

  static void _remember(String url, Uint8List bytes) {
    _mem[url] = bytes;
    while (_mem.length > _maxMem) {
      _mem.remove(_mem.keys.first);
    }
  }

  static Future<void> _slot() async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _active++;
  }

  static void _release() {
    _active--;
    if (_queue.isNotEmpty) _queue.removeFirst().complete();
  }

  static Future<Uint8List?> load(String url) {
    final hit = peek(url);
    if (hit != null) return Future.value(hit);
    final f = _failed[url];
    if (f != null && DateTime.now().difference(f).inSeconds < 8) return Future.value(null);
    return _inflight.putIfAbsent(url, () => _load(url).whenComplete(() => _inflight.remove(url)));
  }

  static Future<Uint8List?> _load(String url) async {
    await init();
    final dir = _dir;
    final name = _name(url);
    final file = dir == null ? null : File('${dir.path}/$name');
    try {
      if (file != null && _onDisk.contains(name)) {
        final b = await file.readAsBytes();
        if (b.isNotEmpty) {
          _remember(url, b);
          return b;
        }
      }
    } catch (_) {}
    if (offline) return null;
    await _slot();
    try {
      // несколько попыток и запасные адреса Steam CDN: если один домен режется сетью/VPN, берём другой
      for (var attempt = 0; attempt < 3; attempt++) {
        for (final u in _mirrors(url)) {
          try {
            final r = await _client.get(Uri.parse(u), headers: const {'User-Agent': 'Mozilla/5.0 dapp'}).timeout(const Duration(seconds: 15));
            if (r.statusCode == 404) continue;
            if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
              lastError = 'HTTP ${r.statusCode} · ${Uri.parse(u).host}';
              continue;
            }
            final b = r.bodyBytes;
            Traffic.add(b.length);
            _remember(url, b);
            if (file != null) {
              try {
                await file.writeAsBytes(b, flush: false);
                _onDisk.add(name);
              } catch (_) {}
            }
            okCount++;
            return b;
          } catch (e) {
            lastError = '${e.runtimeType}: ${'$e'.split('\n').first} · ${Uri.parse(u).host}';
            _resetClient();
          }
        }
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
      _failed[url] = DateTime.now();
      failCount++;
      return null;
    } finally {
      _release();
    }
  }

  static http.Client _client = http.Client();
  static void _resetClient() {
    try {
      _client.close();
    } catch (_) {}
    _client = http.Client();
  }

  static String? lastError;
  static bool offline = false; // тесты: без сети
  static int okCount = 0, failCount = 0;

  static const _steamHosts = [
    'cdn.cloudflare.steamstatic.com',
    'cdn.akamai.steamstatic.com',
    'cdn.steamstatic.com',
    'steamcdn-a.akamaihd.net',
  ];
  static const _avatarHosts = [
    'avatars.steamstatic.com',
    'avatars.akamai.steamstatic.com',
    'avatars.cloudflare.steamstatic.com',
    'steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars',
  ];

  /// Тот же файл на запасных доменах Steam.
  static List<String> _mirrors(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return [url];
    final host = uri.host;
    if (_steamHosts.contains(host)) {
      return [url, for (final h in _steamHosts) if (h != host) uri.replace(host: h).toString()];
    }
    if (host.startsWith('avatars.')) {
      final path = uri.path; // /ab/abcd..._full.jpg
      return [
        url,
        for (final h in _avatarHosts)
          if (!h.startsWith(host)) 'https://$h${h.contains('/') ? (path.startsWith('/') ? path : '/$path') : path}',
      ];
    }
    return [url];
  }

  /// Скачать заранее на диск (иконки всех героев): уже скачанные файлы не трогаем и в память не читаем.
  static Future<int> prefetch(Iterable<String> urls) async {
    final dir = await _cacheDir();
    var n = 0;
    // по одной: фоновая докачка занимает максимум один поток, видимые картинки грузятся без очереди
    for (final u in urls) {
      await init();
      if (dir != null && _onDisk.contains(_name(u))) {
        n++;
        continue;
      }
      if (await load(u) != null) n++;
    }
    return n;
  }

  static Future<(int, int)> diskUsage() async {
    final dir = await _cacheDir();
    if (dir == null) return (0, 0);
    var files = 0, bytes = 0;
    await for (final f in dir.list()) {
      if (f is File) {
        files++;
        bytes += await f.length();
      }
    }
    return (files, bytes);
  }

  static Future<void> clear() async {
    _mem.clear();
    _failed.clear();
    final dir = await _cacheDir();
    _onDisk.clear();
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }
}

/// Провайдер картинки с диска/сети через наш кэш. Раскодированная картинка остаётся в кэше Flutter по URL,
/// поэтому при перерисовке, прокрутке и смене вкладок она показывается мгновенно и не мигает.
class CachedNetImage extends ImageProvider<CachedNetImage> {
  final String url;
  const CachedNetImage(this.url);

  @override
  Future<CachedNetImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<CachedNetImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedNetImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await ImageCache2.load(url);
    if (bytes == null || bytes.isEmpty) {
      // не держим «битую» картинку в кэше Flutter — при следующем показе попробуем снова
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      throw StateError('нет картинки: $url');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is CachedNetImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Картинка из кэша: мгновенно, если уже загружалась; первый раз — плавно проявляется.
/// Если загрузка сорвалась (обрыв сети), пробует ещё раз сама — через 3, 10 и 30 секунд.
class NetImage extends StatefulWidget {
  final String? url;
  final double? width, height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  const NetImage(this.url,
      {super.key, this.width, this.height, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.placeholder});
  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  int attempt = 0;
  Timer? retry;

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      attempt = 0;
      retry?.cancel();
    }
  }

  @override
  void dispose() {
    retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    if (retry != null || attempt >= 3) return;
    const delays = [3, 10, 30];
    retry = Timer(Duration(seconds: delays[attempt]), () {
      if (!mounted) return;
      PaintingBinding.instance.imageCache.evict(CachedNetImage(widget.url!));
      setState(() {
        attempt++;
        retry = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ph = widget.placeholder ?? SizedBox(width: widget.width, height: widget.height);
    final u = widget.url;
    if (u == null || u.isEmpty) return ph;
    return Image(
      key: ValueKey('$u#$attempt'),
      image: CachedNetImage(u),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRetry());
        return ph;
      },
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return Stack(fit: StackFit.passthrough, children: [
          if (frame == null) ph,
          AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 140), child: child),
        ]);
      },
    );
  }
}
