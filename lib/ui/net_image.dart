// Картинки из сети с кэшем: память (LRU) + файлы в папке приложения. Иконки героев качаются один раз.
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

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
    if (f != null && DateTime.now().difference(f).inMinutes < 10) return Future.value(null);
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
    await Future.wait(urls.map((u) async {
      if (dir != null && await File('${dir.path}/${_name(u)}').exists()) {
        n++;
        return;
      }
      if (await load(u) != null) n++;
    }));
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

/// Картинка из кэша: мгновенно, если уже в памяти; иначе плавно проявляется.
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
  Uint8List? bytes;
  bool fromMemory = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  void _start() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      bytes = null;
      return;
    }
    final hit = ImageCache2.peek(url);
    if (hit != null) {
      bytes = hit;
      fromMemory = true;
      return;
    }
    bytes = null;
    fromMemory = false;
    ImageCache2.load(url).then((b) {
      if (mounted && widget.url == url && b != null) setState(() => bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ph = widget.placeholder ?? SizedBox(width: widget.width, height: widget.height);
    final b = bytes;
    final img = b == null
        ? ph
        : Image.memory(b,
            key: ValueKey(widget.url),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ph);
    if (fromMemory) return img;
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: img);
  }
}
