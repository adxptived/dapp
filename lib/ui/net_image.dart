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
  static const _maxMem = 400;
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
    if (f != null && DateTime.now().difference(f).inSeconds < 20) return Future.value(null);
    return _inflight.putIfAbsent(url, () => _load(url).whenComplete(() => _inflight.remove(url)));
  }

  static Future<Uint8List?> _load(String url) async {
    final dir = await _cacheDir();
    final file = dir == null ? null : File('${dir.path}/${_name(url)}');
    try {
      if (file != null && await file.exists()) {
        final b = await file.readAsBytes();
        if (b.isNotEmpty) {
          _remember(url, b);
          return b;
        }
      }
    } catch (_) {}
    await _slot();
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _failed[url] = DateTime.now();
        return null;
      }
      final b = r.bodyBytes;
      Traffic.add(b.length);
      _remember(url, b);
      if (file != null) {
        try {
          await file.writeAsBytes(b, flush: false);
        } catch (_) {}
      }
      return b;
    } catch (_) {
      _failed[url] = DateTime.now();
      return null;
    } finally {
      _release();
    }
  }

  /// Скачать заранее на диск (иконки всех героев): уже скачанные файлы не трогаем и в память не читаем.
  static Future<int> prefetch(Iterable<String> urls) async {
    final dir = await _cacheDir();
    var n = 0;
    // по одной: фоновая докачка занимает максимум один поток, видимые картинки грузятся без очереди
    for (final u in urls) {
      if (dir != null && await File('${dir.path}/${_name(u)}').exists()) {
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
class NetImage extends StatelessWidget {
  final String? url;
  final double? width, height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  const NetImage(this.url,
      {super.key, this.width, this.height, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? SizedBox(width: width, height: height);
    final u = url;
    if (u == null || u.isEmpty) return ph;
    return Image(
      image: CachedNetImage(u),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => ph,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return Stack(fit: StackFit.passthrough, children: [
          if (frame == null) ph,
          AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
        ]);
      },
    );
  }
}
