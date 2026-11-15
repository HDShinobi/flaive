import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/vendor/spotiflac/audio_analysis_widget.dart';

Future<ui.Image> _plotImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 160, 80),
    Paint()..color = Colors.orange,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 80);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final outcome in ['success', 'cancel', 'error', 'unmount']) {
    testWidgets('save picker: $outcome', (tester) async {
      final audio = (await tester.runAsync(() async {
        final root = Directory(
          '${Directory.systemTemp.path}/codex-scratch/release-d-task-5',
        );
        await root.create(recursive: true);
        final dir = await root.createTemp('picker-');
        addTearDown(() => dir.delete(recursive: true));
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => dir.path,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final audio = File('${dir.path}/Song.flac');
        await audio.writeAsBytes([0]);
        // A real cached card avoids invoking native FFmpeg in a widget test.
        var hash = 0xcbf29ce484222325;
        for (final byte in utf8.encode(audio.path)) {
          hash = ((hash ^ byte) * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
        }
        final cache = Directory('${dir.path}/audio_analysis_cache');
        await cache.create();
        final prefix = '${cache.path}/${hash.toRadixString(16)}';
        final data = AudioAnalysisData(
          filePath: audio.path,
          fileSize: 1,
          sampleRate: 44100,
          channels: 2,
          bitsPerSample: 16,
          duration: 200,
          bitrate: 1411200,
          bitDepth: '16',
          dynamicRange: 12,
          peakAmplitude: -1,
          rmsLevel: -13,
          totalSamples: 8820000,
        );
        await File('$prefix.json').writeAsString(jsonEncode(data.toJson()));
        final image = await _plotImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('$prefix.png').writeAsBytes(bytes!.buffer.asUint8List());
        return audio;
      }))!;
      final picker = _SavePicker();
      FilePicker.platform = picker;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioAnalysisCard(
                filePath: audio.path,
                exportName: 'Artist: A/B - Title?',
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          if (find.byTooltip('Save Spectrogram').evaluate().isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      final button = find.byKey(
        const ValueKey('audio-analysis-save-spectrogram'),
      );
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        for (var i = 0; i < 100 && !picker.opened.isCompleted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      expect(picker.fileName, 'Artist_ A_B - Title__spectrogram.png');
      expect(picker.bytes!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      expect(picker.type, FileType.custom);
      expect(picker.extensions, ['png']);
      expect(picker.calls, 1);
      if (outcome == 'unmount') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      if (outcome == 'error') {
        picker.result.completeError(StateError('picker failed'));
      } else {
        picker.result.complete(
          outcome == 'cancel' ? null : '/Pictures/plot.png',
        );
      }
      await tester.pumpAndSettle();
      if (outcome == 'success') {
        expect(find.text('Spectrogram saved to plot.png'), findsOneWidget);
      } else if (outcome == 'error') {
        expect(find.text('Could not save spectrogram'), findsOneWidget);
      } else {
        expect(find.byType(SnackBar), findsNothing);
      }
      if (outcome != 'unmount') {
        expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('spectrogram export name', () {
    test('prefers the given name and strips characters files cannot hold', () {
      expect(
        audioSpectrogramExportBaseName(
          '/music/a.flac',
          exportName: 'Artist: A/B - Title?',
        ),
        'Artist_ A_B - Title_',
      );
    });

    test('falls back to the file name without its extension', () {
      expect(audioSpectrogramExportBaseName('/music/Song.flac'), 'Song');
      expect(
        audioSpectrogramExportBaseName(r'C:\Music\Song.flac', exportName: ' '),
        'Song',
      );
      expect(
        audioSpectrogramExportBaseName('smb://nas/share/Album/Song%201.m4a'),
        'Song 1',
      );
    });

    test('uses the document name of a content URI', () {
      expect(
        audioSpectrogramExportBaseName(
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic/document/primary%3AMusic%2FAlbum%2FSong.flac',
        ),
        'Song',
      );
    });

    test('strips all forbidden characters and edge dots', () {
      expect(
        audioSpectrogramExportBaseName(
          'a.flac',
          exportName: '..A\\B/C:D*E?F"G<H>I|J\x00K\x1f..',
        ),
        'A_B_C_D_E_F_G_H_I_J_K_',
      );
    });

    test('never returns an empty name', () {
      expect(audioSpectrogramExportBaseName('/music/'), 'audio');
      expect(audioSpectrogramExportBaseName('/music/...'), 'audio');
    });
  });

  test('keeps its clone alive if the caller disposes the source', () async {
    final plot = await _plotImage();
    final pending = renderAudioSpectrogramPng(
      spectrogram: plot,
      title: 'Song',
      sampleRate: 96000,
      channel: 1,
    );
    plot.dispose();
    expect((await pending).sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('renders the plot with axes and legend as a PNG', () async {
    final plot = await _plotImage();
    addTearDown(plot.dispose);

    final bytes = await renderAudioSpectrogramPng(
      spectrogram: plot,
      title: 'Artist - Title',
      sampleRate: 44100,
      duration: 200,
    );

    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    final codec = await ui.instantiateImageCodec(bytes);
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);
    // 16 + 34 + 800 + 16 logical pixels across, at the default 2x scale.
    expect(frame.image.width, 1732);
    expect(frame.image.height, greaterThan(800 * 1.1));
  });
}

class _SavePicker extends FilePicker {
  final opened = Completer<void>();
  final result = Completer<String?>();
  int calls = 0;
  String? fileName;
  Uint8List? bytes;
  FileType? type;
  List<String>? extensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) {
    calls++;
    this.fileName = fileName;
    this.bytes = bytes;
    this.type = type;
    extensions = allowedExtensions;
    opened.complete();
    return result.future;
  }
}
