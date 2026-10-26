// rank_tier OpenDota → медаль; парсинг ID игрока/матча (порт ranks.py и ids.py).

const medals = {
  1: 'Herald',
  2: 'Guardian',
  3: 'Crusader',
  4: 'Archon',
  5: 'Legend',
  6: 'Ancient',
  7: 'Divine',
  8: 'Immortal',
};

const uncalibrated = 'Без ранга';

String rankLabel(int? rankTier, [int? leaderboardRank]) {
  if (rankTier == null || rankTier == 0) return uncalibrated;
  final medal = rankTier ~/ 10, star = rankTier % 10;
  final name = medals[medal];
  if (name == null) return uncalibrated;
  if (medal == 8) return leaderboardRank != null && leaderboardRank > 0 ? 'Immortal #$leaderboardRank' : 'Immortal';
  return star > 0 ? '$name $star' : name;
}

/// Картинка медали со Steam CDN.
String? rankIconUrl(int? rankTier) {
  if (rankTier == null || rankTier == 0) return null;
  final medal = rankTier ~/ 10;
  if (medal < 1 || medal > 8) return null;
  return 'https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_$medal.png';
}

int? rankStarsOf(int? rankTier) {
  if (rankTier == null || rankTier == 0) return null;
  final medal = rankTier ~/ 10, star = rankTier % 10;
  if (medal >= 8 || star == 0) return null;
  return star;
}

String? rankStarsUrl(int? rankTier) {
  final s = rankStarsOf(rankTier);
  return s == null ? null : 'https://www.opendota.com/assets/images/dota2/rank_icons/rank_star_$s.png';
}

int? averageRankTier(Iterable<int?> tiers) {
  final ordinals = <int>[];
  for (final t in tiers) {
    if (t == null || t == 0) continue;
    final medal = t ~/ 10, star = t % 10;
    if (medal >= 8) {
      ordinals.add(35);
    } else if (medal >= 1 && medal <= 7) {
      ordinals.add((medal - 1) * 5 + (star < 1 ? 1 : star) - 1);
    }
  }
  if (ordinals.isEmpty) return null;
  final mean = (ordinals.reduce((a, b) => a + b) / ordinals.length).round();
  if (mean >= 35) return 80;
  return (mean ~/ 5 + 1) * 10 + mean % 5 + 1;
}

const medalStep = 770;
const starStep = 154;
const mmrDriftTolerance = 350;

(int, int?)? rankMmrRange(int? rankTier) {
  if (rankTier == null || rankTier == 0) return null;
  final medal = rankTier ~/ 10, star = rankTier % 10;
  if (medal == 8) return (5620, null);
  if (medal < 1 || medal > 7) return null;
  final low = (medal - 1) * medalStep + (star - 1 < 0 ? 0 : star - 1) * starStep;
  return (low, low + starStep);
}

bool mmrRankMismatch(int? currentMmr, int? rankTier) {
  final span = rankMmrRange(rankTier);
  if (currentMmr == null || span == null) return false;
  if (currentMmr < span.$1 - mmrDriftTolerance) return true;
  return span.$2 != null && currentMmr > span.$2! + mmrDriftTolerance;
}

/// Примерный MMR по медали (середина звезды) — подсказка для стартового MMR.
int? mmrFromRank(int? rankTier) {
  final span = rankMmrRange(rankTier);
  if (span == null) return null;
  return span.$2 == null ? span.$1 : (span.$1 + span.$2!) ~/ 2;
}

// --- ID ----------------------------------------------------------------------------------------------------

const steamId64Base = 76561197960265728;
const accountIdMax = 0xFFFFFFFF;

class IdError implements Exception {
  final String message;
  IdError(this.message);
  @override
  String toString() => message;
}

int _toAccountId(int number) {
  if (number > steamId64Base) number -= steamId64Base;
  if (number <= 0 || number > accountIdMax) {
    throw IdError('Это не похоже на ID игрока. Нужна ссылка Dotabuff/OpenDota, account_id или SteamID64.');
  }
  return number;
}

String? extractVanity(String text) {
  final m = RegExp(r'steamcommunity\.com/id/([^/?#\s]+)', caseSensitive: false).firstMatch(text);
  return m?.group(1);
}

/// Ссылка Dotabuff/OpenDota/Stratz/Steam или число → account_id. Кастомную Steam-ссылку разрешает вызывающий код.
int parseAccountId(String text) {
  final raw = text.trim();
  if (raw.isEmpty) throw IdError('Нужна ссылка Dotabuff/OpenDota или числовой ID.');
  if (extractVanity(raw) != null) {
    throw IdError('Кастомная Steam-ссылка: нужен запрос к Steam.');
  }
  var m = RegExp(r'/players/(\d+)').firstMatch(raw);
  if (m != null) return _toAccountId(int.parse(m.group(1)!));
  m = RegExp(r'/profiles/(\d+)').firstMatch(raw);
  if (m != null) return _toAccountId(int.parse(m.group(1)!));
  if (RegExp(r'^\d+$').hasMatch(raw)) return _toAccountId(int.parse(raw));
  throw IdError('Не понял. Нужна ссылка Dotabuff/OpenDota (.../players/<id>), account_id или SteamID64.');
}

int accountIdFromSteam64(int steam64) => _toAccountId(steam64);

/// Что ищем по ID: матч или игрока. Голое число до 2 млрд — сначала игрок, больше — матч.
enum LookupKind { player, match }

class LookupQuery {
  final LookupKind kind;
  final int id;
  final String? vanity;
  final bool ambiguous;
  LookupQuery(this.kind, this.id, {this.vanity, this.ambiguous = false});
}

LookupQuery parseLookup(String text) {
  final raw = text.trim();
  final lower = raw.toLowerCase();
  final vanity = extractVanity(raw);
  if (vanity != null) return LookupQuery(LookupKind.player, 0, vanity: vanity);
  var m = RegExp(r'/matches?/(\d+)').firstMatch(raw);
  if (m != null) return LookupQuery(LookupKind.match, int.parse(m.group(1)!));
  final digits = RegExp(r'(\d{3,})').firstMatch(raw);
  if (lower.startsWith('матч') || lower.startsWith('match')) {
    if (digits != null) return LookupQuery(LookupKind.match, int.parse(digits.group(1)!));
  }
  if (lower.startsWith('игрок') || lower.startsWith('player')) {
    if (digits != null) return LookupQuery(LookupKind.player, _toAccountId(int.parse(digits.group(1)!)));
  }
  if (raw.contains('/players/') || raw.contains('/profiles/')) {
    return LookupQuery(LookupKind.player, parseAccountId(raw));
  }
  if (RegExp(r'^\d+$').hasMatch(raw)) {
    final n = int.parse(raw);
    if (n > steamId64Base) return LookupQuery(LookupKind.player, _toAccountId(n));
    if (n < 2000000000) return LookupQuery(LookupKind.player, n, ambiguous: true);
    return LookupQuery(LookupKind.match, n);
  }
  throw IdError('Нужен ID матча или игрока, либо ссылка Dotabuff/OpenDota/Stratz/Steam.');
}
