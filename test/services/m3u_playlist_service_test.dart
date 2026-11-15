import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/m3u_playlist_service.dart';

void main() {
  test(
    'M6 export preserves existing playlists and uses first free suffix',
    () async {
      final root = await Directory.systemTemp.createTemp('m3u_collision_');
      addTearDown(() => root.delete(recursive: true));
      final original = File('${root.path}/Mix.m3u8')
        ..writeAsStringSync('user edits');
      final second = File('${root.path}/Mix (2).m3u8')
        ..writeAsStringSync('second edits');
      final fourth = File('${root.path}/Mix (4).m3u8')
        ..writeAsStringSync('fourth edits');
      final path = await M3uPlaylistService.write(
        playlistName: 'Mix',
        entries: [],
        m3uDir: root.path,
      );
      expect(path, '${root.path}/Mix (3).m3u8');
      expect(await File(path).readAsString(), '#EXTM3U\n');
      expect(await original.readAsString(), 'user edits');
      expect(await second.readAsString(), 'second edits');
      expect(await fourth.readAsString(), 'fourth edits');
    },
  );
  test('m3u8 writes UTF-8 EXTINF and relative paths in playlist order', () async {
    final root = await Directory.systemTemp.createTemp('m3u_test_');
    try {
      final path = await M3uPlaylistService.write(
        playlistName: '../Nhạc 🎵',
        m3uDir: '${root.path}/Mix',
        entries: [
          (
            path: '${root.path}/Artist/Đầu.flac',
            artist: 'Nghệ sĩ',
            title: 'Đầu',
            durationSec: 123,
          ),
          (
            path: '${root.path}/Mix/Last.flac',
            artist: 'A',
            title: 'Last',
            durationSec: 4,
          ),
        ],
      );
      expect(path, '${root.path}/Mix/Nhạc 🎵.m3u8');
      expect(
        utf8.decode(await File(path).readAsBytes()),
        '#EXTM3U\n#EXTINF:123,Nghệ sĩ - Đầu\n../Artist/Đầu.flac\n#EXTINF:4,A - Last\nLast.flac\n',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
