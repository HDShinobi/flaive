import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/album_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/history_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _tracks = [
  Track(id: 'qobuz:2', name: 'Second', artists: 'A', durationMs: 2200),
  Track(id: 'qobuz:missing', name: 'Missing', artists: 'A'),
  Track(id: 'qobuz:1', name: 'First', artists: 'B', durationMs: 4100),
];

class _Bridge extends BackendBridge {
  @override
  Future<void> setDownloadDirectory(String path) async {}
  @override
  Future<void> allowDownloadDir(String path) async {}
  @override
  Future<Map<String, dynamic>?> getProviderMetadata(
    String provider,
    String type,
    String id,
  ) async => {
    'name': 'Actual Mix',
    'track_list': [
      for (final track in _tracks)
        {
          'id': track.id,
          'name': track.name,
          'artists': track.artists,
          'duration_ms': track.durationMs,
        },
    ],
  };
}

class _Queue extends DownloadQueueController {
  final intents = <String?>[];
  @override
  List<DownloadEntry> build() => [];
  @override
  Future<void> enqueue(
    Track track, {
    String? service,
    String? quality,
    String? playlistName,
    bool bypassDuplicateCheck = false,
  }) async {
    intents.add(playlistName);
  }
}

class _Extensions extends ExtensionsController {
  @override
  Future<List<InstalledExtension>> build() async => [
    InstalledExtension.fromJson({
      'id': 'qobuz',
      'name': 'Qobuz',
      'enabled': true,
      'has_download_provider': true,
    }),
  ];
}

void main() {
  sqfliteFfiInit();
  test(
    'export selection uses existing history files in playlist order',
    () async {
      final root = await Directory.systemTemp.createTemp('playlist_selection_');
      final db = HistoryDatabase(
        path: '${root.path}/history.db',
        factory: databaseFactoryFfi,
      );
      final c = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) async => db)],
      );
      try {
        for (final track in _tracks.reversed) {
          final path = '${root.path}/${track.name}.flac';
          if (track.name != 'Missing') await File(path).writeAsString('audio');
          await db.upsert(
            HistoryEntry(
              id: track.id,
              track: track,
              service: 'qobuz',
              filePath: path,
              downloadedAt: DateTime(2026),
            ),
          );
        }
        final entries = await c.read(
          playlistExportEntriesProvider(HistoryLookupBatch(_tracks)).future,
        );
        expect(entries.map((e) => e.title), ['Second', 'First']);
        expect(entries.map((e) => e.durationSec), [2, 4]);
      } finally {
        c.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );

  for (final setting in [
    (enabled: false, mode: 'artist_album'),
    (enabled: true, mode: 'artist_album'),
    (enabled: false, mode: 'playlist'),
  ]) {
    testWidgets(
      'manual export honors folder setting $setting and reports partial count',
      (tester) async {
        final root = Directory.systemTemp.createTempSync('playlist_ui_');
        SharedPreferences.setMockInitialValues({
          'create_playlist_folder': setting.enabled,
          'folder_organization': setting.mode,
        });
        final batch = HistoryLookupBatch(_tracks);
        final c = ProviderContainer(
          overrides: [
            backendBridgeProvider.overrideWithValue(_Bridge()),
            downloadDirPathProvider.overrideWithValue(Future.value(root.path)),
            downloadedTracksProvider(batch).overrideWith((ref) async => {}),
            playlistExportEntriesProvider(batch).overrideWith(
              (ref) async => [
                (
                  path: '${root.path}/Second.flac',
                  artist: 'A',
                  title: 'Second',
                  durationSec: 2,
                ),
                (
                  path: '${root.path}/First.flac',
                  artist: 'B',
                  title: 'First',
                  durationSec: 4,
                ),
              ],
            ),
          ],
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: c,
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: Locale('en'),
                home: AlbumScreen(
                  args: AlbumRouteArgs(
                    id: 'qobuz:p',
                    name: 'Route Mix',
                    artist: 'A',
                    resourceType: 'playlist',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final directory = setting.enabled
              ? '${root.path}/Actual Mix'
              : root.path;
          final file = File('$directory/Actual Mix.m3u8');
          expect(
            file.existsSync(),
            false,
            reason: 'No automatic export on opening a playlist',
          );
          await c.read(folderRulesReadyProvider.future);
          await c.read(folderOrganizationProvider.notifier).ready;
          await tester.tap(find.text('Export M3U8'));
          await tester.pumpAndSettle();
          for (
            var i = 0;
            i < 100 && find.text('Exported 2 of 3 tracks').evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(file.existsSync(), true);
          expect(find.text('Exported 2 of 3 tracks'), findsOneWidget);
          expect(
            file.readAsStringSync(),
            contains(setting.enabled ? '../Second.flac' : '\nSecond.flac'),
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          root.deleteSync(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'empty export is disabled and download all threads the resolved playlist title',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final queue = _Queue();
      final batch = HistoryLookupBatch(_tracks);
      final c = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(_Bridge()),
          downloadQueueProvider.overrideWith(() => queue),
          extensionsProvider.overrideWith(_Extensions.new),
          downloadedTracksProvider(batch).overrideWith((ref) async => {}),
          playlistExportEntriesProvider(batch).overrideWith((ref) async => []),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: AlbumScreen(
              args: AlbumRouteArgs(
                id: 'qobuz:p',
                name: 'Route Mix',
                artist: 'A',
                resourceType: 'playlist',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Export M3U8'),
      );
      expect(button.onPressed, isNull);
      // Resolve sources before opening the source/quality sheet.
      await c.read(extensionsProvider.future);
      await tester.tap(find.text('Download all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await tester.pumpAndSettle();
      expect(queue.intents, ['Actual Mix', 'Actual Mix', 'Actual Mix']);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
