// Диагностика загрузки картинок с настоящей сетью (запускается в CI отдельно).
import 'dart:io';

import 'package:dapp/ui/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const urls = [
  'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/pudge.png',
  'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/icons/pudge.png',
  'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/items/blink.png',
  'https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_5.png',
  'https://avatars.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg',
];

void main() {
  testWidgets('реальная загрузка', (tester) async {
    HttpOverrides.global = null;
    for (final u in urls) {
      final b = await tester.runAsync(() => ImageCache2.load(u));
      // ignore: avoid_print
      print('LOAD ${b?.length ?? 'NULL'} $u err=${ImageCache2.lastError}');
    }
    await tester.pumpWidget(MaterialApp(home: Column(children: [for (final u in urls) NetImage(u, width: 40, height: 40)])));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final raws = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    // ignore: avoid_print
    print('RAWIMAGES ${raws.length} withImage=${raws.where((r) => r.image != null).length}');
    for (final w in tester.widgetList<Image>(find.byType(Image))) {
      // ignore: avoid_print
      print('IMAGE ${w.image}');
    }
  });
}
