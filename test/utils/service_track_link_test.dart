import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/utils/service_track_link.dart';

void main() {
  Track track(String id, {String? source, String? deezerId}) => Track(
    id: id,
    source: source,
    deezerId: deezerId,
    name: 'Song',
    artists: 'Artist',
  );
  for (final entry in {
    'spotify': 'open.spotify.com',
    'tidal': 'listen.tidal.com',
    'qobuz': 'play.qobuz.com',
    'deezer': 'www.deezer.com',
  }.entries) {
    test('serviceTrackLink ${entry.key} prefix', () {
      expect(
        serviceTrackLink(track('${entry.key}:123')).toString(),
        'https://${entry.value}/track/123',
      );
    });
  }
  test('serviceTrackLink bare Spotify ID', () {
    expect(
      serviceTrackLink(track('4uLU6hMCjMI75M1A2tKUQC')).toString(),
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
    );
  });
  test('serviceTrackLink bare known source and deezerId fallback', () {
    expect(
      serviceTrackLink(track('123', source: 'qobuz')).toString(),
      'https://play.qobuz.com/track/123',
    );
    expect(
      serviceTrackLink(track('', deezerId: '456')).toString(),
      'https://www.deezer.com/track/456',
    );
  });
  test('serviceTrackLink null for extension source', () {
    expect(serviceTrackLink(track('123', source: 'my-extension')), isNull);
    expect(serviceTrackLink(track('my-extension:123')), isNull);
  });
  test('serviceTrackLink skips Amazon and invalid or absent IDs', () {
    for (final t in [
      track('amazon:123'),
      track('123', source: 'amazon'),
      track(''),
      track('123'),
      track('qobuz:'),
      track('qobuz:a/b'),
      track('qobuz:a:b'),
      track('', deezerId: 'bad'),
    ]) {
      expect(serviceTrackLink(t), isNull, reason: t.id);
    }
  });
}
