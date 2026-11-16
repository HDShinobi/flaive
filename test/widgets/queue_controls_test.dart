import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/downloads_provider.dart';
import 'package:lossless_music_download/screens/queue_screen.dart';

// Pause/resume applies to a populated queue; the empty-state action is disabled.
class _ActiveQueue extends DownloadQueueController {
  @override
  List<DownloadEntry> build() => const [
    DownloadEntry(
      track: Track(id: 'active', name: 'Song', artists: 'Artist'),
      itemId: 'active',
      status: 'downloading',
      progress: 0.5,
      bytesReceived: 1024,
    ),
  ];
}

void main() {
  for (final locale in ['en', 'vi']) {
    testWidgets('queue pause, resume and Wi-Fi reason in $locale', (tester) async {
      final c = ProviderContainer(overrides: [
        downloadQueueProvider.overrideWith(_ActiveQueue.new),
        downloadsProvider.overrideWith((ref) => Stream.value([])),
      ]);
      addTearDown(c.dispose);
      final t = lookupAppLocalizations(Locale(locale));
      await tester.pumpWidget(UncontrolledProviderScope(container: c,
        child: MaterialApp(locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const QueueScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.queuePause));
      await tester.pumpAndSettle();
      expect(find.text(t.queuePaused), findsOneWidget);
      await tester.tap(find.byTooltip(t.queueResume));
      await tester.pumpAndSettle();
      expect(find.text(t.queuePaused), findsNothing);
      c.read(queuePauseReasonProvider.notifier).set('waiting_wifi');
      await tester.pump();
      expect(find.text(t.queueWaitingWifi), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text(t.queueClearCompleted), findsOneWidget);
      expect(find.text(t.queueRetryAllFailed), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
