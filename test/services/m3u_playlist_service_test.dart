import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/m3u_playlist_service.dart';

void main() {
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
