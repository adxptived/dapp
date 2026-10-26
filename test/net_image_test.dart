// Диагностика загрузки картинок с настоящей сетью (запускается в CI отдельно).
import 'dart:io';

import 'package:dapp/ui/net_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const urls = [
  'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/pudge.png',
  'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/items/blink.png',
  'https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_5.png',
];

void main() {
  // ignore: avoid_print
  ImageCache2.debug = (m) => print('DBG ${DateTime.now().toIso8601String().substring(11, 23)} $m');

  test('сырой http', () async {
    for (final u in urls) {
      final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
      // ignore: avoid_print
      print('RAW ${r.statusCode} ${r.bodyBytes.length} $u');
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('загрузчик', () async {
    HttpOverrides.global = null;
    for (final u in urls) {
      final b = await ImageCache2.load(u).timeout(const Duration(seconds: 60), onTimeout: () => null);
      // ignore: avoid_print
      print('LOAD ${b?.length ?? 'NULL'} $u err=${ImageCache2.lastError}');
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
