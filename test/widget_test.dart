import 'package:flutter_test/flutter_test.dart';
import 'package:animetka_tv/api.dart';

void main() {
  test('HLS quality parsing preserves query parameters', () {
    final v = qualityVariants(
      '[360]/video/1/360.m3u8?code=//source/video/1,[720]/video/1/720.m3u8?code=//source/video/1,',
    );
    expect(v.length, 2);
    expect(v.first['quality'], '360');
    expect(
      v.last['url'],
      'https://animetka.com/video/1/720.m3u8?code=//source/video/1',
    );
  });
  test('Source URL normalization', () {
    expect(absolute('//cdn.example/video'), 'https://cdn.example/video');
    expect(absolute('//video/test'), 'https://animetka.com/video/test');
  });
  test('IDs use material identifier', () {
    expect(animeId({'animetka_id': 228, 'id': 99}), 228);
    expect(animeId({'id': '2778'}), 2778);
  });
  test('History entry ID cannot replace material ID', () {
    expect(
      animeId(
        historyAnime({
          'id': 999,
          'animetka_id': 228,
          'material': {'id': 228, 'title': 'Film'},
        }),
      ),
      228,
    );
    expect(
      animeId(
        historyAnime({
          'id': 999,
          'material': {'id': 2778},
        }),
      ),
      2778,
    );
    expect(number(120.5), 120);
  });
  test('Video credentials are never sent to an external CDN', () {
    expect(
      videoHeaders(
        'https://p12.solodcdn.com/movie.m3u8',
        token: 'fake',
      ).containsKey('Authorization'),
      isFalse,
    );
    expect(
      videoHeaders(
        'https://animetka.com.evil.test/file.mp4',
        token: 'fake',
      ).containsKey('Authorization'),
      isFalse,
    );
    expect(
      videoHeaders(
        'https://animetka.com/movie.m3u8',
        token: 'fake',
      ).containsKey('Authorization'),
      isFalse,
    );
    expect(
      videoHeaders(
        'https://animetka.com/movie.mp4',
        token: 'fake',
      )['Authorization'],
      'Bearer fake',
    );
    expect(
      videoHeaders('https://cache.anilibria.tv/movie.m3u8')['Referer'],
      'https://anilibria.tv/',
    );
  });
}
