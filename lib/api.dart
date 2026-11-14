import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

const baseUrl = 'https://animetka.com';
typedef Json = Map<String, dynamic>;
Json object(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};
List<Json> objects(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => object(e)).toList() : [];
int number(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
String title(Json a) =>
    '${a['title'] ?? a['anime_title'] ?? a['russian'] ?? a['name'] ?? ''}';
int animeId(Json a) => number(a['animetka_id'] ?? a['id']);
Json historyAnime(Json history) {
  final material = object(history['material']);
  final id =
      history['animetka_id'] ?? material['animetka_id'] ?? material['id'];
  return {
    ...material,
    ...history,
    'id': id,
    'animetka_id': id,
    // Material duration is minutes; history duration and timestamp are seconds.
    'duration': history['duration'],
  };
}

String poster(Json a) => '${a['anime_poster_url'] ?? a['poster_url'] ?? ''}';
String absolute(String path) {
  if (path.startsWith('//video/')) path = path.substring(1);
  if (path.startsWith('//')) return 'https:$path';
  return Uri.parse(baseUrl).resolve(path).toString();
}

List<Json> qualityVariants(String file) =>
    RegExp(r'\[([^\]]+)\]([^,]+)')
        .allMatches(file)
        .map((m) => <String, dynamic>{'quality': m[1], 'url': absolute(m[2]!)})
        .toList();

class ApiFailure implements Exception {
  final int status;
  final String message;
  ApiFailure(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  final HttpClient http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  String? token;
  VoidCallback? onUnauthorized;
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async {
    if (auth && (token == null || token!.isEmpty)) {
      throw ApiFailure(401, 'Войдите в аккаунт');
    }
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map(
        (k, v) => MapEntry(k, v is List ? v.map((e) => '$e').toList() : '$v'),
      ),
    );
    final req = await http
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Dart/${Platform.version.split(' ').first} (dart:io)',
    );
    req.headers.set('Accept', 'application/json');
    req.headers.set('X-Client-Platform', 'android');
    req.headers.set('X-Client-Version', '1.0.5');
    if (auth) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close().timeout(const Duration(seconds: 30));
    final bytes = await response
        .fold<List<int>>([], (b, e) {
          if (b.length + e.length > 12 * 1024 * 1024) {
            throw ApiFailure(502, 'Слишком большой ответ сервера');
          }
          return b..addAll(e);
        })
        .timeout(const Duration(seconds: 30));
    final text = utf8.decode(bytes);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = null;
    }
    if (response.statusCode == 401 && auth) onUnauthorized?.call();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        response.statusCode,
        '${object(data)['message'] ?? object(data)['error'] ?? 'Ошибка сервера (${response.statusCode})'}',
      );
    }
    if (text.isNotEmpty && data == null) {
      throw ApiFailure(502, 'Сервер вернул неизвестный формат данных');
    }
    return data;
  }

  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async => objects(
    await request(
      '/api/anime/search',
      query: {
        'name': name,
        'limit': 30,
        'offset': offset,
        'attributes': [
          'animetka_id',
          'title',
          'title_en',
          'title_orig',
          'poster_url',
          'anime_poster_url',
          'anime_kind',
          'shikimori_id',
          'shikimori_rating',
          'episodes_total',
          'episodes_aired',
          'all_status',
          'anime_genres',
          'year',
        ],
        ...filters,
      },
    ),
  );
  Future<Json> detail(int id) async => object(await request('/api/anime/$id'));
  Future<Json> playlist(int id, [int? tid]) async => object(
    await request('/api/anime/playlist', query: {'material': id, 'tid': ?tid}),
  );
}

class Session extends ChangeNotifier {
  final SharedPreferences prefs;
  final Api api;
  Session(this.prefs, this.api) {
    api.token = prefs.getString('token');
    api.onUnauthorized = expire;
  }
  void expire() {
    api.token = null;
    prefs.remove('token');
    prefs.remove('user');
    prefs.setBool('guest', false);
    notifyListeners();
  }

  Json get user {
    try {
      return object(jsonDecode(prefs.getString('user') ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  bool get loggedIn => api.token?.isNotEmpty ?? false;
  bool get guest => prefs.getBool('guest') ?? false;
  String get deviceId {
    var id = prefs.getString('device_id');
    if (id == null) {
      id = 'tv-${DateTime.now().microsecondsSinceEpoch}';
      prefs.setString('device_id', id);
    }
    return id;
  }

  Future<void> save(Json data) async {
    final token = data['token'] ?? data['access_token'];
    if (token is! String || token.isEmpty) {
      throw ApiFailure(401, 'Сервер не вернул сессию входа');
    }
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(data['user'] ?? {}));
    await prefs.setBool('guest', false);
    api.token = token;
    await api.request(
      '/api/auth/device/register',
      method: 'POST',
      auth: true,
      body: {
        'device_id': deviceId,
        'device_model': 'Android TV · независимый клиент',
        'os': 'Android',
        'client_version': '1.0.5',
      },
    );
  }

  Future<void> logout() async {
    try {
      if (loggedIn) {
        await api.request('/api/auth/logout', method: 'POST', auth: true);
      }
    } finally {
      await prefs.remove('token');
      await prefs.remove('user');
      api.token = null;
      await prefs.setBool('guest', false);
      notifyListeners();
    }
  }

  List<Json> get localHistory {
    try {
      return objects(jsonDecode(prefs.getString('history') ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  Json get openedTitles {
    try {
      return object(jsonDecode(prefs.getString('openedTitles') ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  Future<void> markOpened(int id) async {
    final opened = openedTitles;
    opened['$id'] = DateTime.now().toUtc().toIso8601String();
    // Keep ordering metadata bounded independently of playback progress.
    final entries = opened.entries.toList()
      ..sort((a, b) => '${b.value}'.compareTo('${a.value}'));
    await prefs.setString(
      'openedTitles',
      jsonEncode(Map.fromEntries(entries.take(500))),
    );
  }

  DateTime? historyDate(Json entry, [Json? opened]) {
    DateTime? latest;
    for (final value in [
      (opened ?? openedTitles)['${animeId(entry)}'],
      entry['updated'],
      entry['updated_at'],
      entry['updatedAt'],
      entry['last_watched_at'],
      entry['created_at'],
    ]) {
      final date = DateTime.tryParse('$value')?.toUtc();
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return latest;
  }

  List<Json> recentHistory(List<Json> remote) {
    final byId = <int, Json>{};
    for (final entry in [...remote, ...localHistory]) {
      final id = animeId(entry);
      if (id <= 0) continue;
      final old = byId[id];
      final updated = DateTime.tryParse(
        '${entry['updated'] ?? entry['updated_at'] ?? entry['updatedAt']}',
      );
      final oldUpdated = DateTime.tryParse(
        '${old?['updated'] ?? old?['updated_at'] ?? old?['updatedAt']}',
      );
      if (old == null ||
          (updated != null &&
              (oldUpdated == null || updated.isAfter(oldUpdated)))) {
        byId[id] = entry;
      }
    }
    final opened = openedTitles;
    final indexed = byId.values.indexed.toList();
    indexed.sort((a, b) {
      final x = historyDate(a.$2, opened), y = historyDate(b.$2, opened);
      if (x == null && y == null) return a.$1.compareTo(b.$1);
      if (x == null) return 1;
      if (y == null) return -1;
      final order = y.compareTo(x);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    return indexed.map((v) => historyAnime(v.$2)).toList();
  }

  Future<void> progress(
    Json anime,
    int episode,
    int seconds,
    int duration,
    int? tid, {
    int played = 0,
  }) async {
    final id = animeId(anime);
    final items = localHistory
      ..removeWhere((e) => number(e['animetka_id']) == id);
    items.insert(0, {
      'animetka_id': id,
      'material': {
        for (final key in [
          'id',
          'animetka_id',
          'title',
          'anime_title',
          'poster_url',
          'anime_poster_url',
          'year',
          'shikimori_rating',
          'episodes_total',
          'screenshot_url',
          'anime_screenshot_url',
        ])
          if (anime.containsKey(key)) key: anime[key],
        if (anime['screenshots'] is List &&
            (anime['screenshots'] as List).firstOrNull is String)
          'screenshot_url': (anime['screenshots'] as List).first,
      },
      'episode': episode,
      'timestamp': seconds,
      'duration': duration,
      'tid': tid,
      'updated': DateTime.now().toIso8601String(),
    });
    await prefs.setString('history', jsonEncode(items.take(200).toList()));
    if (loggedIn) {
      await api.request(
        '/api/user/history/$id',
        method: 'POST',
        auth: true,
        body: {
          'episode': episode,
          'timestamp': seconds,
          'duration': duration,
          'played_delta': played,
          'tid': ?tid,
          if (duration > 0 && seconds >= duration * .95) 'completed': true,
        },
      );
    }
  }
}

Map<String, String> videoHeaders(
  String url, {
  String? token,
  bool resolving = false,
}) {
  final uri = Uri.parse(url);
  final own = uri.host == 'animetka.com';
  final libria = uri.host.contains('libria');
  final headers = <String, String>{
    'User-Agent': own ? 'Dart/3.14 (dart:io)' : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': libria ? 'https://anilibria.tv/' : 'https://animetka.com/',
    if (libria) 'Origin': 'https://anilibria.tv',
    if (own) 'Origin': 'https://animetka.com',
  };
  if (own && token != null && (resolving || !url.contains('.m3u8'))) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

Future<String> resolveVideo(String source, {String? token}) async {
  var uri = Uri.parse(absolute(source));
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    for (var i = 0; i < 6; i++) {
      if (!['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ApiFailure(400, 'Недопустимый адрес видео');
      }
      if (uri.host == 'localhost' ||
          InternetAddress.tryParse(uri.host)?.isLoopback == true) {
        throw ApiFailure(400, 'Локальный адрес видео запрещён');
      }
      final request = await http
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      videoHeaders(
        uri.toString(),
        token: token,
        resolving: true,
      ).forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final location = response.headers.value('location');
      await response.listen((_) {}).cancel();
      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          location != null) {
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode >= 400) {
        throw ApiFailure(
          response.statusCode,
          'Видео недоступно (${response.statusCode})',
        );
      }
      return uri.toString();
    }
    throw ApiFailure(502, 'Слишком много перенаправлений видео');
  } finally {
    http.close(force: true);
  }
}
