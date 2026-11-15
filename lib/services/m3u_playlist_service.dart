import 'dart:convert';
import 'dart:io';

import 'download_paths.dart';

/// Manual UTF-8 export, using upstream's EXTM3U / EXTINF line format.
abstract final class M3uPlaylistService {
  static String _relativePath(String path, String directory) {
    final target = File(path).absolute.uri.normalizePath().pathSegments;
    final base = Directory(directory).absolute.uri
        .normalizePath()
        .pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    var common = 0;
    while (common < target.length &&
        common < base.length &&
        target[common] == base[common]) {
      common++;
    }
    final relative = [
      for (var i = common; i < base.length; i++) '..',
      ...target.skip(common),
    ].join('/');
    return relative.startsWith('#') ? './$relative' : relative;
  }

  static Future<String> write({
    required String playlistName,
    required List<({String path, String artist, String title, int durationSec})>
    entries,
    required String m3uDir,
  }) async {
    // Metadata cannot inject extra directives or path lines.
    String line(String value) => value.replaceAll(RegExp(r'[\r\n]'), ' ');
    final buffer = StringBuffer('#EXTM3U\n');
    for (final entry in entries) {
      if (entry.path.contains(RegExp(r'[\r\n]'))) {
        throw ArgumentError.value(
          entry.path,
          'path',
          'M3U paths must be one line',
        );
      }
      buffer
        ..writeln(
          '#EXTINF:${entry.durationSec},${line(entry.artist)} - ${line(entry.title)}',
        )
        ..writeln(_relativePath(entry.path, m3uDir));
    }
    final directory = Directory(m3uDir);
    await directory.create(recursive: true);
    final name = sanitizePlaylistFolder(playlistName);
    var file = File('$m3uDir/$name.m3u8');
    for (var suffix = 2; await file.exists(); suffix++) {
      file = File('$m3uDir/$name ($suffix).m3u8');
    }
    await file.writeAsString(buffer.toString(), encoding: utf8, flush: true);
    return file.path;
  }
}
