// Модели данных: игрок пати, матч игрока, настройки, сезон.

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
double? _dbl(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
bool? _bool(dynamic v) => v is bool ? v : (v is num ? v != 0 : null);
List<int> _ints(dynamic v) => v is List ? v.map(_int).whereType<int>().toList() : <int>[];

/// Запись журнала заданного MMR: когда и какое значение ввели.
class MmrAnchor {
  final int ts;
  final int mmr;
  const MmrAnchor(this.ts, this.mmr);
  Map<String, dynamic> toJson() => {'ts': ts, 'mmr': mmr};
  factory MmrAnchor.fromJson(Map<String, dynamic> j) => MmrAnchor(_int(j['ts']) ?? 0, _int(j['mmr']) ?? 0);
}

class Player {
  final int accountId;
  String name;
  int createdTs;
  List<MmrAnchor> anchors;
  String? personaname;
  String? avatar;
  int? rankTier;
  int? leaderboardRank;
  bool plus;
  bool isMe;
  int lastRefresh; // unix, последнее обновление матчей
  int lastProfile; // unix, последнее обновление профиля
  int? lastNotifiedMatch; // последний матч, о котором уже сообщили
  bool privateHistory; // OpenDota не видит матчи

  Player({
    required this.accountId,
    required this.name,
    required this.createdTs,
    List<MmrAnchor>? anchors,
    this.personaname,
    this.avatar,
    this.rankTier,
    this.leaderboardRank,
    this.plus = false,
    this.isMe = false,
    this.lastRefresh = 0,
    this.lastProfile = 0,
    this.lastNotifiedMatch,
    this.privateHistory = false,
  }) : anchors = anchors ?? [];

  Map<String, dynamic> toJson() => {
        'account_id': accountId,
        'name': name,
        'created_ts': createdTs,
        'anchors': anchors.map((a) => a.toJson()).toList(),
        'personaname': personaname,
        'avatar': avatar,
        'rank_tier': rankTier,
        'leaderboard_rank': leaderboardRank,
        'plus': plus,
        'is_me': isMe,
        'last_refresh': lastRefresh,
        'last_profile': lastProfile,
        'last_notified_match': lastNotifiedMatch,
        'private_history': privateHistory,
      };

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        accountId: _int(j['account_id']) ?? 0,
        name: (j['name'] ?? '').toString(),
        createdTs: _int(j['created_ts']) ?? 0,
        anchors: (j['anchors'] as List? ?? [])
            .whereType<Map>()
            .map((e) => MmrAnchor.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        personaname: j['personaname'] as String?,
        avatar: j['avatar'] as String?,
        rankTier: _int(j['rank_tier']),
        leaderboardRank: _int(j['leaderboard_rank']),
        plus: _bool(j['plus']) ?? false,
        isMe: _bool(j['is_me']) ?? false,
        lastRefresh: _int(j['last_refresh']) ?? 0,
        lastProfile: _int(j['last_profile']) ?? 0,
        lastNotifiedMatch: _int(j['last_notified_match']),
        privateHistory: _bool(j['private_history']) ?? false,
      );
}

/// Матч глазами одного игрока (строка истории). Подробности (GPM, перф, предметы) догружаются позже.
class M {
  final int matchId;
  int playerSlot;
  bool radiantWin;
  int? heroId;
  int startTime;
  int? duration;
  int? lobbyType;
  int kills, deaths, assists;
  int? partySize;
  int? averageRank;
  List<int>? radiant; // герои света
  List<int>? dire; // герои тьмы
  // подробности
  int? gpm, xpm, lastHits, denies, heroDamage, towerDamage, heroHealing, netWorth, level;
  double? perfScore; // 0..1, среднее перцентилей
  Map<String, double>? bench; // перцентили benchmark-метрик
  List<int>? items;
  int? neutralItem;
  int? shardTime;
  int? stacks;
  bool enriched; // /matches/{id} уже загружен
  // Stratz
  int? position;
  int? imp;
  int? laneResult;
  int? wards;
  bool stratzDone;

  M({
    required this.matchId,
    required this.playerSlot,
    required this.radiantWin,
    this.heroId,
    required this.startTime,
    this.duration,
    this.lobbyType,
    this.kills = 0,
    this.deaths = 0,
    this.assists = 0,
    this.partySize,
    this.averageRank,
    this.radiant,
    this.dire,
    this.gpm,
    this.xpm,
    this.lastHits,
    this.denies,
    this.heroDamage,
    this.towerDamage,
    this.heroHealing,
    this.netWorth,
    this.level,
    this.perfScore,
    this.bench,
    this.items,
    this.neutralItem,
    this.shardTime,
    this.stacks,
    this.enriched = false,
    this.position,
    this.imp,
    this.laneResult,
    this.wards,
    this.stratzDone = false,
  });

  bool get isRadiant => playerSlot < 128;
  bool get won => isRadiant == radiantWin;
  int get endTime => startTime + (duration ?? 0);
  double get kda => (kills + assists) / (deaths < 1 ? 1 : deaths);
  bool get hasDetail => gpm != null || netWorth != null || heroDamage != null;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': matchId,
      'ps': playerSlot,
      'rw': radiantWin,
      'h': heroId,
      'st': startTime,
      'du': duration,
      'lt': lobbyType,
      'k': kills,
      'd': deaths,
      'a': assists,
      'pz': partySize,
      'ar': averageRank,
      'r': radiant,
      'di': dire,
      'gpm': gpm,
      'xpm': xpm,
      'lh': lastHits,
      'dn': denies,
      'hd': heroDamage,
      'td': towerDamage,
      'hh': heroHealing,
      'nw': netWorth,
      'lv': level,
      'pf': perfScore,
      'b': bench,
      'it': items,
      'ni': neutralItem,
      'sh': shardTime,
      'sk': stacks,
      'en': enriched,
      'pos': position,
      'imp': imp,
      'lr': laneResult,
      'w': wards,
      'sd': stratzDone,
    };
    m.removeWhere((k, v) => v == null);
    return m;
  }

  factory M.fromJson(Map<String, dynamic> j) => M(
        matchId: _int(j['id']) ?? 0,
        playerSlot: _int(j['ps']) ?? 0,
        radiantWin: _bool(j['rw']) ?? false,
        heroId: _int(j['h']),
        startTime: _int(j['st']) ?? 0,
        duration: _int(j['du']),
        lobbyType: _int(j['lt']),
        kills: _int(j['k']) ?? 0,
        deaths: _int(j['d']) ?? 0,
        assists: _int(j['a']) ?? 0,
        partySize: _int(j['pz']),
        averageRank: _int(j['ar']),
        radiant: j['r'] == null ? null : _ints(j['r']),
        dire: j['di'] == null ? null : _ints(j['di']),
        gpm: _int(j['gpm']),
        xpm: _int(j['xpm']),
        lastHits: _int(j['lh']),
        denies: _int(j['dn']),
        heroDamage: _int(j['hd']),
        towerDamage: _int(j['td']),
        heroHealing: _int(j['hh']),
        netWorth: _int(j['nw']),
        level: _int(j['lv']),
        perfScore: _dbl(j['pf']),
        bench: j['b'] is Map
            ? Map<String, double>.fromEntries((j['b'] as Map)
                .entries
                .where((e) => e.value is num)
                .map((e) => MapEntry(e.key.toString(), (e.value as num).toDouble())))
            : null,
        items: j['it'] == null ? null : _ints(j['it']),
        neutralItem: _int(j['ni']),
        shardTime: _int(j['sh']),
        stacks: _int(j['sk']),
        enriched: _bool(j['en']) ?? false,
        position: _int(j['pos']),
        imp: _int(j['imp']),
        laneResult: _int(j['lr']),
        wards: _int(j['w']),
        stratzDone: _bool(j['sd']) ?? false,
      );
}

class Settings {
  int mmrStep;
  bool notifyMatches;
  bool dailyDigest;
  int digestHour;
  bool weeklyDigest;
  bool leaderChanges;
  bool steamChanges;
  bool autoUpdateCheck;
  bool notifyUpdates;
  int pollMinutes;
  int enrichDays;
  int seasonDays;
  String openDotaKey;
  String stratzKey;
  String openDotaBase;
  String githubToken;
  String updateRepo;
  String defaultPeriod; // day/week/month/year/all
  int lastDigestDay; // yyyymmdd
  int lastWeeklyDay;
  Map<String, String> leaders; // номинация → лидер (для объявлений о смене лидера)

  Settings({
    this.mmrStep = 25,
    this.notifyMatches = true,
    this.dailyDigest = true,
    this.digestHour = 10,
    this.weeklyDigest = true,
    this.leaderChanges = false,
    this.steamChanges = true,
    this.autoUpdateCheck = true,
    this.notifyUpdates = true,
    this.pollMinutes = 15,
    this.enrichDays = 90,
    this.seasonDays = 30,
    this.openDotaKey = '',
    this.stratzKey = '',
    this.openDotaBase = '',
    this.githubToken = '',
    this.updateRepo = 'adxptived/dotapp',
    this.defaultPeriod = 'week',
    this.lastDigestDay = 0,
    this.lastWeeklyDay = 0,
    Map<String, String>? leaders,
  }) : leaders = leaders ?? {};

  Map<String, dynamic> toJson() => {
        'mmr_step': mmrStep,
        'notify_matches': notifyMatches,
        'daily_digest': dailyDigest,
        'digest_hour': digestHour,
        'weekly_digest': weeklyDigest,
        'leader_changes': leaderChanges,
        'steam_changes': steamChanges,
        'auto_update_check': autoUpdateCheck,
        'notify_updates': notifyUpdates,
        'poll_minutes': pollMinutes,
        'enrich_days': enrichDays,
        'season_days': seasonDays,
        'opendota_key': openDotaKey,
        'stratz_key': stratzKey,
        'opendota_base': openDotaBase,
        'github_token': githubToken,
        'update_repo': updateRepo,
        'default_period': defaultPeriod,
        'last_digest_day': lastDigestDay,
        'last_weekly_day': lastWeeklyDay,
        'leaders': leaders,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    return Settings(
      mmrStep: _int(j['mmr_step']) ?? d.mmrStep,
      notifyMatches: _bool(j['notify_matches']) ?? d.notifyMatches,
      dailyDigest: _bool(j['daily_digest']) ?? d.dailyDigest,
      digestHour: _int(j['digest_hour']) ?? d.digestHour,
      weeklyDigest: _bool(j['weekly_digest']) ?? d.weeklyDigest,
      leaderChanges: _bool(j['leader_changes']) ?? d.leaderChanges,
      steamChanges: _bool(j['steam_changes']) ?? d.steamChanges,
      autoUpdateCheck: _bool(j['auto_update_check']) ?? d.autoUpdateCheck,
      notifyUpdates: _bool(j['notify_updates']) ?? d.notifyUpdates,
      pollMinutes: _int(j['poll_minutes']) ?? d.pollMinutes,
      enrichDays: _int(j['enrich_days']) ?? d.enrichDays,
      seasonDays: _int(j['season_days']) ?? d.seasonDays,
      openDotaKey: (j['opendota_key'] ?? '').toString(),
      stratzKey: (j['stratz_key'] ?? '').toString(),
      openDotaBase: (j['opendota_base'] ?? '').toString(),
      githubToken: (j['github_token'] ?? '').toString(),
      updateRepo: (j['update_repo'] ?? d.updateRepo).toString(),
      defaultPeriod: (j['default_period'] ?? d.defaultPeriod).toString(),
      lastDigestDay: _int(j['last_digest_day']) ?? 0,
      lastWeeklyDay: _int(j['last_weekly_day']) ?? 0,
      leaders: j['leaders'] is Map
          ? Map<String, String>.from((j['leaders'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          : {},
    );
  }
}

class Season {
  final int number;
  final int startTs;
  final int plannedEndTs;
  int? endTs;
  final int lengthDays;
  String? champion;
  List<Map<String, dynamic>> table; // [{player, points, golds}]

  Season({
    required this.number,
    required this.startTs,
    required this.plannedEndTs,
    this.endTs,
    required this.lengthDays,
    this.champion,
    List<Map<String, dynamic>>? table,
  }) : table = table ?? [];

  bool get finished => endTs != null;

  Map<String, dynamic> toJson() => {
        'number': number,
        'start_ts': startTs,
        'planned_end_ts': plannedEndTs,
        'end_ts': endTs,
        'length_days': lengthDays,
        'champion': champion,
        'table': table,
      };

  factory Season.fromJson(Map<String, dynamic> j) => Season(
        number: _int(j['number']) ?? 1,
        startTs: _int(j['start_ts']) ?? 0,
        plannedEndTs: _int(j['planned_end_ts']) ?? 0,
        endTs: _int(j['end_ts']),
        lengthDays: _int(j['length_days']) ?? 30,
        champion: j['champion'] as String?,
        table: (j['table'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      );
}
