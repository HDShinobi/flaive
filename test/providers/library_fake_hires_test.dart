import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

class _Scan extends BackendBridge {
  final List<String> paths;
  _Scan(this.paths);
  @override
  Future<void> setLibraryCoverCacheDir(String path) async {}
  @override
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String path) async =>
      [for (final p in paths) {'filePath': p, 'trackName': 'Song'}];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('library excludes fake hi-res backups before display and backfill', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('library-fake-hires');
    addTearDown(() => dir.deleteSync(recursive: true));
    final visible = '${dir.path}/Artist/song.flac';
    final c = ProviderContainer(overrides: [
      downloadDirProvider.overrideWith((_) async => dir.path),
      libraryCoverCacheDirProvider.overrideWithValue(Future.value(dir.path)),
      historyDatabaseProvider.overrideWith((_) async => throw StateError('no history')),
      backendBridgeProvider.overrideWithValue(_Scan([
        visible, '${dir.path}/.fake-hires/item/song.flac',
        '${dir.path}/Artist/.fake-hires/item/backup.wav',
      ])),
    ]);
    addTearDown(c.dispose);
    expect((await c.read(libraryProvider.future)).map((e) => e.path), [visible]);
  });
}
