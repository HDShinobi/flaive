import 'dart:convert';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/screens/download_history_screen.dart';
import 'package:lossless_music_download/services/history_database.dart';

// UI tests keep storage synchronous; SQLite CRUD/migrations use real FFI in
// services/history_database_test.dart.
class _MemoryHistory extends HistoryDatabase {
  _MemoryHistory() : super(path: 'unused');
  final rows = <HistoryEntry>[];
  String? recoveryRoot;
  List<String>? recoveryPreviousRoots;
  @override
  Future<({int relinked, int missing})> findMoved({required String currentRoot, required List<String> previousRoots}) async {
    recoveryRoot = currentRoot;
    recoveryPreviousRoots = previousRoots;
    return (relinked: 1, missing: 2);
  }
  @override
  Future<void> upsert(HistoryEntry entry) async => rows.add(entry);
  @override
  Future<List<HistoryEntry>> list({
    String search = '',
    int limit = 100,
    int offset = 0,
  }) async => rows
      .where(
        (e) => '${e.track.name} ${e.track.artists}'.toLowerCase().contains(
          search.toLowerCase(),
        ),
      )
      .toList();
  @override
  Future<void> remove(String id) async => rows.removeWhere((e) => e.id == id);
}

void main() {
  testWidgets('history recovers with saved roots and copies stored catalog link', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    SharedPreferences.setMockInitialValues({'download_previous_dirs_v1': jsonEncode(['/old'])});
    final db = _MemoryHistory();
    db.rows.add(HistoryEntry(id: 'one', track: const Track(id: 'qobuz:42', name: 'Song', artists: 'Artist'),
      service: 'tidal', filePath: '/old/song.flac', downloadedAt: DateTime(2026)));
    final container = ProviderContainer(overrides: [
      historyDatabaseProvider.overrideWith((ref) async => db),
      downloadDirProvider.overrideWith((ref) async => '/new'),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DownloadHistoryScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.drive_file_move_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Folder layout and filenames must be unchanged.'), findsOneWidget);
    await tester.tap(find.text('Find moved downloads'));
    await tester.pumpAndSettle();
    expect(db.recoveryRoot, '/new');
    expect(db.recoveryPreviousRoots, ['/old']);
    expect(container.read(historyRevisionProvider), 1);
    expect(find.text('Relinked 1; still missing: 2.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Qobuz link'));
    await tester.pumpAndSettle();
    expect(calls.singleWhere((call) => call.method == 'Clipboard.setData').arguments,
      {'text': 'https://play.qobuz.com/track/42'});
    // The first snackbar is still visible; let the queued copied notice appear.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Copied Qobuz link'), findsOneWidget);
    expect(db.rows, hasLength(1));
  });
  testWidgets(
    'history searches title/artist and removes entry without deleting audio',
    (tester) async {
      late Directory dir;
      late HistoryDatabase db;
      late File file;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('history_ui_');
        db = _MemoryHistory();
        file = await File('${dir.path}/song.flac').writeAsString('audio');
        await db.upsert(
          HistoryEntry(
            id: 'one',
            track: const Track(
              id: '1',
              name: 'First song',
              artists: 'Artist One',
            ),
            service: 'qobuz',
            filePath: file.path,
            downloadedAt: DateTime(2026),
          ),
        );
      });
      final c = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) async => db)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DownloadHistoryScreen(),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Missing');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsNothing);
      await tester.enterText(find.byType(TextField), 'artist one');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copy '), findsNothing);
      await tester.tap(find.text('Remove entry'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsNothing);
      await tester.runAsync(() async {
        expect(await file.exists(), isTrue);
        c.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
