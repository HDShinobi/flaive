import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/downloads_provider.dart';
import 'package:lossless_music_download/screens/queue_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

class _EmptyQueue extends DownloadQueueController {
  @override
  List<DownloadEntry> build() => [];
}

void main() {
  testWidgets('empty queue disables pause and opens the Search branch', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/queue',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/search',
                  builder: (_, _) =>
                      const Scaffold(body: Text('Search destination')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadQueueProvider.overrideWith(_EmptyQueue.new),
          downloadsProvider.overrideWith((_) => Stream.value([])),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: appTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing downloading yet'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.pause))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Search songs'));
    await tester.pumpAndSettle();
    expect(find.text('Search destination'), findsOneWidget);
  });
}
