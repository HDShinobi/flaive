import 'package:flutter/material.dart';
import 'package:lossless_music_download/providers/library_busy_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/verified_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';
import 'package:lossless_music_download/vendor/spotiflac/audio_analysis_widget.dart';

const _flacVerified = LibraryEntry(
  path: '/music/Artist/Album/01 Song.flac',
  name: '01 Song.flac',
  sizeBytes: 20971520,
  artistName: 'Artist',
  albumName: 'Album',
  format: 'FLAC',
  verified: true,
);

const _mp3Unverified = LibraryEntry(
  path: '/music/Track.mp3',
  name: 'Track.mp3',
  sizeBytes: 5242880,
  artistName: null,
  albumName: null,
  format: 'MP3',
  verified: false,
);

Widget _screen(LibraryEntry entry, {bool busy = false, String locale = 'en'}) =>
    ProviderScope(
      overrides: [if (busy) libraryBusyProvider.overrideWithValue(true)],
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        home: VerifiedScreen(entry: entry),
      ),
    );

void main() {
  for (final locale in ['en', 'vi']) {
    for (final action in [
      'manageEdit',
      'manageReEnrich',
      'manageReplayGain',
      'manageConvert',
      'manageDelete',
    ]) {
      testWidgets('busy $action refuses with $locale snackbar', (tester) async {
        await tester.pumpWidget(
          _screen(_flacVerified, busy: true, locale: locale),
        );
        final t = AppLocalizations.of(
          tester.element(find.byType(VerifiedScreen)),
        );
        final label = switch (action) {
          'manageEdit' => t.manageEdit,
          'manageReEnrich' => t.manageReEnrich,
          'manageReplayGain' => t.manageReplayGain,
          'manageConvert' => t.manageConvert,
          _ => t.manageDelete,
        };
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pump();
        expect(find.text(t.libraryBusyHint), findsOneWidget);
        expect(find.text(t.reEnrichStarted), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }
  testWidgets('header omits unknown PCM details before analysis', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(_flacVerified));
    await tester.pump();
    expect(find.text('FLAC'), findsNWidgets(2));
    expect(find.textContaining('kHz'), findsNothing);
    final cover = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (widget) =>
              widget.constraints?.maxWidth == 104 &&
              widget.constraints?.maxHeight == 104,
        );
    expect(cover, hasLength(1));
  });

  for (final cutoff in <double?>[22000, 16000, null]) {
    testWidgets('analysis updates specs and verdict band for cutoff $cutoff', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(_flacVerified));
      await tester.pump();
      final card = tester.widget<AudioAnalysisCard>(
        find.byType(AudioAnalysisCard),
      );
      card.onAnalyzed!(
        AudioAnalysisData(
          filePath: _flacVerified.path,
          fileSize: 100,
          codec: 'flac',
          sampleRate: 96000,
          channels: 2,
          bitsPerSample: 24,
          duration: 120,
          bitrate: 2304,
          bitDepth: '24-bit',
          dynamicRange: 12,
          peakAmplitude: 0.9,
          rmsLevel: 0.2,
          totalSamples: 11520000,
          spectralCutoffHz: cutoff,
        ),
      );
      await tester.pump();
      expect(find.text('FLAC · 24-bit · 96.0 kHz · 2ch'), findsOneWidget);
      final context = tester.element(find.byType(VerifiedScreen));
      final t = AppLocalizations.of(context);
      final label = cutoff == null
          ? t.verdictInconclusive
          : cutoff < 18000
          ? t.verdictSuspect
          : t.verdictLossless;
      final band = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      final decoration = band.decoration! as BoxDecoration;
      expect(
        decoration.color,
        cutoff == null
            ? context.tokens.infoSoft
            : cutoff < 18000
            ? context.tokens.suspectSoft
            : context.tokens.accentSoft,
      );
      expect(
        find.text(
          t.verdictCutoff(
            cutoff == null ? '—' : '${(cutoff / 1000).toStringAsFixed(1)} kHz',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('verified FLAC: shows Genuine lossless badge', (tester) async {
    await tester.pumpWidget(_screen(_flacVerified));
    await tester.pump();

    expect(find.text('Genuine lossless'), findsOneWidget);
  });

  testWidgets('unverified MP3: shows Not verified, not Genuine lossless', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(_mp3Unverified));
    await tester.pump();

    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Genuine lossless'), findsNothing);
  });
}
