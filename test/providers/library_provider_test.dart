import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

class ScanBridge extends BackendBridge {
  ScanBridge(this.paths) : super(const MethodChannel('task9'));
  final List<String> paths;
  final calls = <String>[];
  Completer<void>? scanGate;
  List<({String path, String message})> failures = [];
  @override
  Future<void> setLibraryCoverCacheDir(String path) async {}
  @override
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String path) async {
    calls.add('scan');
    await scanGate?.future;
    return [
      for (final p in paths) {'filePath': p},
    ];
  }

  @override
  Future<List<({String path, String message})>> getLibraryScanFailures() async {
    calls.add('failures');
    return failures;
  }
}

class StatFile implements File {
  StatFile(this.readStat);
  final Future<FileStat> Function() readStat;
  @override
  Future<FileStat> stat() => readStat();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ScanBridge bridge;
  late ProviderContainer c;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('library_size_');
    await File('${dir.path}/a.flac').writeAsBytes(List.filled(7, 0));
    await File('${dir.path}/b.flac').writeAsBytes(List.filled(19, 0));
    bridge = ScanBridge([
      '${dir.path}/a.flac',
      '${dir.path}/b.flac',
      '${dir.path}/missing.flac',
    ]);
    c = ProviderContainer(
      overrides: [
        downloadDirProvider.overrideWith((_) async => dir.path),
        libraryCoverCacheDirProvider.overrideWithValue(Future.value(dir.path)),
        historyDatabaseProvider.overrideWith(
          (_) async => throw StateError('no history'),
        ),
        backendBridgeProvider.overrideWithValue(bridge),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await dir.delete(recursive: true);
  });

  test('sizeBytes filled from file stat, lazy and cached per scan', () async {
    expect((await c.read(libraryProvider.future)).map((e) => e.sizeBytes), [
      0,
      0,
      0,
    ]);
    await c.read(librarySortPreferenceProvider.notifier).set('sizeDesc');
    expect(
      (await c.read(sortedLibraryProvider.future)).map((e) => e.sizeBytes),
      [19, 7, 0],
    );
    await File('${dir.path}/a.flac').writeAsBytes(List.filled(40, 0));
    await c.read(librarySortPreferenceProvider.notifier).set('title');
    await c.read(sortedLibraryProvider.future);
    await c.read(librarySortPreferenceProvider.notifier).set('sizeAsc');
    expect(
      (await c.read(sortedLibraryProvider.future)).map((e) => e.sizeBytes),
      [0, 7, 19],
    );
    expect(bridge.calls, ['scan', 'failures']);
    c.invalidate(libraryProvider);
    expect(
      (await c.read(sortedLibraryProvider.future)).map((e) => e.sizeBytes),
      [0, 19, 40],
    );
  });

  test('size stat is lazy, bounded to 32, and errors become zero', () async {
    final stat = await File('${dir.path}/a.flac').stat();
    var reads = 0;
    var active = 0;
    var peak = 0;
    var generation = 0;
    final local = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(
          (_) async => [
            for (var i = 0; i < 65; i++)
              LibraryEntry(
                path: '/stat/$generation/$i',
                name: '$i',
                sizeBytes: 0,
                format: 'FLAC',
                verified: true,
                title: 'Title $i',
                isrc: 'ISRC$i',
                discNumber: 2,
                trackNumber: i,
                albumArtist: 'Album artist',
              ),
          ],
        ),
      ],
    );
    addTearDown(local.dispose);
    await IOOverrides.runZoned(
      () async {
        await local.read(sortedLibraryProvider.future);
        expect(reads, 0);
        await local
            .read(librarySortPreferenceProvider.notifier)
            .set('sizeDesc');
        final sized = await local.read(sortedLibraryProvider.future);
        expect(reads, 65);
        expect(peak, 32);
        expect(sized.where((e) => e.sizeBytes == 0), hasLength(1));
        expect(sized.first.title, 'Title 0');
        expect(sized.first.isrc, 'ISRC0');
        expect(sized.first.discNumber, 2);
        expect(sized.first.albumArtist, 'Album artist');
        await local.read(librarySortPreferenceProvider.notifier).set('title');
        await local.read(sortedLibraryProvider.future);
        generation++;
        local.invalidate(libraryProvider);
        await local.read(sortedLibraryProvider.future);
        expect(
          reads,
          65,
          reason: 'A scan in title mode must not stat cached size entries',
        );
      },
      createFile: (path) => StatFile(() async {
        reads++;
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        if (path.endsWith('/64')) throw const FileSystemException('unreadable');
        return stat;
      }),
    );
  });

  test('scan failures exposed in state and cleared after clean scan', () async {
    bridge.failures = [(path: '/bad.flac', message: 'Invalid header')];
    await c.read(libraryProvider.future);
    expect(c.read(libraryStateProvider).scanFailures.single.path, '/bad.flac');
    expect(
      c.read(libraryStateProvider).scanFailures.single.message,
      'Invalid header',
    );
    bridge.failures = [];
    c.invalidate(libraryProvider);
    await c.read(libraryProvider.future);
    expect(c.read(libraryStateProvider).scanFailures, isEmpty);
    expect(bridge.calls, ['scan', 'failures', 'scan', 'failures']);
  });

  test('scan failures exclude hidden and re-enrich temporary files', () async {
    bridge.failures = [
      (path: '/music/.fake-hires/hidden.flac', message: 'hidden'),
      (
        path: '/music/a.flac.reenrich-1234567890123456.flac',
        message: 'temporary',
      ),
      (path: '/music/bad.flac', message: 'unreadable'),
    ];
    await c.read(libraryProvider.future);
    expect(c.read(libraryStateProvider).scanFailures.map((f) => f.path), [
      '/music/bad.flac',
    ]);
  });

  test(
    'scan failures remain visible until the replacement scan returns',
    () async {
      bridge.failures = [(path: '/bad.flac', message: 'Invalid header')];
      await c.read(libraryProvider.future);
      bridge.scanGate = Completer<void>();
      addTearDown(() {
        if (bridge.scanGate?.isCompleted == false) bridge.scanGate!.complete();
      });
      bridge.failures = [];
      c.invalidate(libraryProvider);
      final refresh = c.read(libraryProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(
        c.read(libraryStateProvider).scanFailures.single.path,
        '/bad.flac',
      );
      bridge.scanGate!.complete();
      bridge.scanGate = null;
      await refresh;
      expect(c.read(libraryStateProvider).scanFailures, isEmpty);
    },
  );

  test(
    'startup preference is ready synchronously before the library builds',
    () async {
      SharedPreferences.setMockInitialValues({'library_sort': 'sizeAsc'});
      await c.read(librarySortPreferenceProvider.notifier).ready;
      expect(c.read(librarySortProvider), LibrarySort.sizeAsc);
      expect(
        (await c.read(sortedLibraryProvider.future)).map((e) => e.sizeBytes),
        [0, 7, 19],
      );
    },
  );

  test(
    'sort preference survives provider recreation and invalid values default to title',
    () async {
      await c.read(librarySortPreferenceProvider.notifier).set('sizeAsc');
      expect(
        (await SharedPreferences.getInstance()).getString('library_sort'),
        'sizeAsc',
      );
      c.invalidate(librarySortPreferenceProvider);
      await c.read(librarySortPreferenceProvider.notifier).ready;
      expect(c.read(librarySortProvider), LibrarySort.sizeAsc);
      await (await SharedPreferences.getInstance()).setString(
        'library_sort',
        'invalid',
      );
      c.invalidate(librarySortPreferenceProvider);
      await c.read(librarySortPreferenceProvider.notifier).ready;
      expect(c.read(librarySortProvider), LibrarySort.title);
    },
  );
}
