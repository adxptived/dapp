// Сетевые клиенты: OpenDota (троттлинг, ретраи, учёт лимита), Stratz GraphQL, Steam (кастомные ссылки).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiError implements Exception {
  final String message;
  final int? status;
  ApiError(this.message, [this.status]);
  @override
  String toString() => message;
}

class ProviderHealth {
  final String name;
  bool? ok;
  String? lastError;
  int? lastOkTs;
  int? lastFailTs;
  ProviderHealth(this.name);
  void success() {
    ok = true;
    lastOkTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  void failure(Object e) {
    ok = false;
    lastError = e.toString();
    lastFailTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }
}

class OpenDota {
  String apiKey;
  String base;
  final http.Client _client = http.Client();
  final health = ProviderHealth('OpenDota');
  int? remainingDay; // остаток суточного лимита
  int? remainingMinute;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _chain = Future.value();
  bool _projectExtended = true;

  OpenDota({this.apiKey = '', String? base}) : base = (base == null || base.isEmpty) ? defaultBase : base;

  static const defaultBase = 'https://api.opendota.com/api';

  Duration get _gap => apiKey.isEmpty ? const Duration(milliseconds: 1100) : const Duration(milliseconds: 120);

  bool get backgroundAllowed => remainingDay == null || remainingDay! > (apiKey.isEmpty ? 300 : 2000);

  Future<void> _throttle() {
    final c = Completer<void>();
    _chain = _chain.then((_) async {
      final wait = _last.add(_gap).difference(DateTime.now());
      if (!wait.isNegative) await Future.delayed(wait);
      _last = DateTime.now();
      c.complete();
    });
    return c.future;
  }

  Uri _uri(String path, [Map<String, dynamic>? params]) {
    final q = <String, dynamic>{...?params};
    if (apiKey.isNotEmpty) q['api_key'] = apiKey;
    final u = Uri.parse('$base$path');
    return u.replace(queryParameters: q.isEmpty ? null : q.map((k, v) => MapEntry(k, v is List ? v.map((e) => '$e').toList() : '$v')));
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? params, int retries = 3}) async {
    Object? lastErr;
    for (var attempt = 0; attempt < retries; attempt++) {
      await _throttle();
      try {
        final resp = await _client.get(_uri(path, params)).timeout(const Duration(seconds: 30));
        final day = int.tryParse(resp.headers['x-rate-limit-remaining-day'] ?? '');
        if (day != null) remainingDay = day;
        final min = int.tryParse(resp.headers['x-rate-limit-remaining-minute'] ?? '');
        if (min != null) remainingMinute = min;
        if (resp.statusCode == 200) {
          health.success();
          return jsonDecode(utf8.decode(resp.bodyBytes));
        }
        if (resp.statusCode == 429) {
          lastErr = ApiError('OpenDota: лимит запросов', 429);
          await Future.delayed(Duration(seconds: 5 * (attempt + 1)));
          continue;
        }
        if (resp.statusCode >= 500) {
          lastErr = ApiError('OpenDota: ошибка сервера ${resp.statusCode}', resp.statusCode);
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        health.success();
        throw ApiError('OpenDota: HTTP ${resp.statusCode}', resp.statusCode);
      } on ApiError {
        rethrow;
      } catch (e) {
        lastErr = e;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    final err = lastErr ?? ApiError('OpenDota не ответил');
    health.failure(err);
    throw err is ApiError ? err : ApiError('OpenDota недоступен: $err');
  }

  Future<void> refreshPlayer(int accountId) async {
    try {
      await _throttle();
      await _client.post(_uri('/players/$accountId/refresh')).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<void> requestParse(int matchId) async {
    try {
      await _throttle();
      await _client.post(_uri('/request/$matchId')).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> profile(int accountId) async {
    final d = await get('/players/$accountId');
    return d is Map<String, dynamic> ? d : {};
  }

  static const _baseColumns = [
    'hero_id', 'start_time', 'duration', 'lobby_type', 'kills', 'deaths', 'assists', //
    'average_rank', 'leaver_status', 'party_size', 'heroes',
  ];
  static const _extColumns = [
    'gold_per_min', 'xp_per_min', 'last_hits', 'denies', 'hero_damage', 'tower_damage', 'hero_healing', 'level',
  ];

  /// Ранкед-матчи игрока. limit == null — вся история постранично.
  Future<List<Map<String, dynamic>>> matches(int accountId, {int? limit = 100, int? lobbyType = 7, int? date}) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    const page = 1000;
    while (true) {
      final params = <String, dynamic>{
        'significant': 0,
        'project': [..._baseColumns, if (_projectExtended) ..._extColumns],
        'limit': limit ?? page,
        if (lobbyType != null) 'lobby_type': lobbyType,
        if (limit == null) 'offset': offset,
        if (date != null) 'date': date,
      };
      dynamic data;
      try {
        data = await get('/players/$accountId/matches', params: params);
      } on ApiError catch (e) {
        if (_projectExtended && (e.status == 400 || (e.status ?? 0) >= 500)) {
          _projectExtended = false;
          return matches(accountId, limit: limit, lobbyType: lobbyType, date: date);
        }
        rethrow;
      }
      if (data is! List) break;
      final rows = data.whereType<Map<String, dynamic>>().toList();
      if (rows.isNotEmpty && !rows.first.containsKey('start_time') && _projectExtended) {
        _projectExtended = false;
        return matches(accountId, limit: limit, lobbyType: lobbyType, date: date);
      }
      out.addAll(rows);
      if (limit != null || rows.length < page) break;
      offset += page;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> recentMatches(int accountId) async {
    final d = await get('/players/$accountId/recentMatches');
    return d is List ? d.whereType<Map<String, dynamic>>().toList() : [];
  }

  final Map<int, (DateTime, Map<String, dynamic>)> _matchCache = {};

  Future<Map<String, dynamic>> match(int matchId) async {
    final hit = _matchCache[matchId];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 10) return hit.$2;
    final d = await get('/matches/$matchId');
    final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
    if ((m['players'] as List?)?.isNotEmpty ?? false) {
      _matchCache[matchId] = (DateTime.now(), m);
      if (_matchCache.length > 40) _matchCache.remove(_matchCache.keys.first);
    }
    return m;
  }

  Future<Map<String, dynamic>> constants(String name) async {
    final d = await get('/constants/$name');
    return d is Map<String, dynamic> ? d : {};
  }

  Future<List<Map<String, dynamic>>> playerHeroes(int accountId) async {
    final d = await get('/players/$accountId/heroes', params: {'lobby_type': 7});
    return d is List ? d.whereType<Map<String, dynamic>>().toList() : [];
  }

  Future<Map<String, dynamic>> winLoss(int accountId) async {
    final d = await get('/players/$accountId/wl', params: {'lobby_type': 7});
    return d is Map<String, dynamic> ? d : {};
  }
}

class Stratz {
  String apiKey;
  final http.Client _client = http.Client();
  final health = ProviderHealth('Stratz');
  Stratz(this.apiKey);
  bool get enabled => apiKey.trim().isNotEmpty;

  static const url = 'https://api.stratz.com/graphql';

  Future<Map<String, dynamic>> query(String q) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await _client
            .post(Uri.parse(url),
                headers: {
                  'Authorization': 'Bearer ${apiKey.trim()}',
                  'User-Agent': 'STRATZ_API',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'query': q}))
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final p = jsonDecode(utf8.decode(resp.bodyBytes));
          health.success();
          if (p is Map && p['errors'] is List && (p['errors'] as List).isNotEmpty && p['data'] == null) {
            throw ApiError('Stratz: ${(p['errors'] as List).first['message']}');
          }
          return (p is Map && p['data'] is Map) ? Map<String, dynamic>.from(p['data']) : {};
        }
        if (resp.statusCode == 429 || resp.statusCode >= 500) {
          lastErr = ApiError('Stratz HTTP ${resp.statusCode}', resp.statusCode);
          await Future.delayed(Duration(milliseconds: 1500 * (attempt + 1)));
          continue;
        }
        throw ApiError('Stratz HTTP ${resp.statusCode}${resp.statusCode == 403 ? ' (проверьте ключ)' : ''}', resp.statusCode);
      } on ApiError catch (e) {
        health.failure(e);
        rethrow;
      } catch (e) {
        lastErr = e;
        await Future.delayed(Duration(milliseconds: 1500 * (attempt + 1)));
      }
    }
    health.failure(lastErr ?? 'нет ответа');
    throw ApiError('Stratz не ответил');
  }

  static const playerFields = '''
    topLaneOutcome midLaneOutcome bottomLaneOutcome
    players {
      steamAccountId isRadiant partyId heroId
      position role lane imp
      goldPerMinute experiencePerMinute networth heroDamage towerDamage heroHealing
      numLastHits numDenies level
      stats { wards { time } }
    }
  ''';

  /// Данные игрока по матчам (пачками по 10 через алиасы): match_id → строка игрока + исходы линий.
  Future<Map<int, Map<String, dynamic>>> matchesFor(int accountId, List<int> ids, Map<int, (bool, int?)> hints) async {
    final result = <int, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final body = [for (var n = 0; n < chunk.length; n++) 'm$n: match(id: ${chunk[n]}) { $playerFields }'].join('\n');
      final data = await query('query {\n$body\n}');
      for (var n = 0; n < chunk.length; n++) {
        final m = data['m$n'];
        if (m is! Map) continue;
        final rows = (m['players'] as List? ?? []).whereType<Map>().toList();
        if (rows.isEmpty) continue;
        Map? row;
        for (final r in rows) {
          if (r['steamAccountId'] == accountId) {
            row = r;
            break;
          }
        }
        final hint = hints[chunk[n]];
        if (row == null && hint != null) {
          final same = rows.where((r) => r['isRadiant'] == hint.$1 && r['heroId'] == hint.$2).toList();
          if (same.length == 1) row = same.first;
        }
        if (row == null) continue;
        final me = row;
        final int party = me['partyId'] == null
            ? 1
            : rows.where((r) => r['isRadiant'] == me['isRadiant'] && r['partyId'] == me['partyId']).length;
        result[chunk[n]] = {
          'party_size': party,
          'position': _position(me['position']),
          'imp': me['imp'],
          'lane_result': laneResult(me['lane'] as String?, me['isRadiant'] as bool?, {
            'top': m['topLaneOutcome'],
            'mid': m['midLaneOutcome'],
            'bottom': m['bottomLaneOutcome'],
          }),
          'wards': (me['stats'] is Map && me['stats']['wards'] is List) ? (me['stats']['wards'] as List).length : null,
          'gpm': me['goldPerMinute'],
          'xpm': me['experiencePerMinute'],
          'net_worth': me['networth'],
          'hero_damage': me['heroDamage'],
          'tower_damage': me['towerDamage'],
          'hero_healing': me['heroHealing'],
          'last_hits': me['numLastHits'],
          'denies': me['numDenies'],
          'level': me['level'],
        };
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> fullMatch(int matchId) async {
    final data = await query('''
query {
  match(id: $matchId) {
    id durationSeconds didRadiantWin startDateTime
    players {
      steamAccountId isRadiant heroId position role lane kills deaths assists imp
      goldPerMinute experiencePerMinute networth heroDamage towerDamage heroHealing
      numLastHits numDenies level
      item0Id item1Id item2Id item3Id item4Id item5Id neutral0Id
      steamAccount { name }
    }
  }
}''');
    final m = data['match'];
    return m is Map<String, dynamic> ? m : null;
  }

  static int? _position(dynamic v) => int.tryParse(v?.toString().split('_').last ?? '');

  static int? laneResult(String? lane, bool? isRadiant, Map<String, dynamic> outcomes) {
    const map = {'SAFE_LANE': ('bottom', 'top'), 'OFF_LANE': ('top', 'bottom'), 'MID_LANE': ('mid', 'mid')};
    const view = {'RADIANT_STOMP': 2, 'RADIANT_VICTORY': 1, 'TIE': 0, 'DIRE_VICTORY': -1, 'DIRE_STOMP': -2};
    final sides = map[lane ?? ''];
    if (sides == null || isRadiant == null) return null;
    final score = view[outcomes[isRadiant ? sides.$1 : sides.$2]?.toString() ?? ''];
    if (score == null) return null;
    return isRadiant ? score : -score;
  }
}

/// Кастомная ссылка Steam /id/<имя> → SteamID64 через публичный XML профиля.
Future<int> resolveVanity(String vanity) async {
  for (var i = 0; i < 3; i++) {
    try {
      final r = await http
          .get(Uri.parse('https://steamcommunity.com/id/$vanity/?xml=1'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final m = RegExp(r'<steamID64>(\d+)</steamID64>').firstMatch(r.body);
        if (m == null) throw ApiError('Не нашёл Steam-профиль «$vanity» (или он скрыт).');
        return int.parse(m.group(1)!);
      }
    } on ApiError {
      rethrow;
    } catch (_) {}
  }
  throw ApiError('Steam не ответил. Пришлите ссылку Dotabuff/OpenDota или числовой ID.');
}
