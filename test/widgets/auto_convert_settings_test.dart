import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/screens/auto_convert_settings_screen.dart';

void main() {
  for (final locale in ['en', 'vi']) {
    testWidgets('replacement warning is visible in $locale', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AutoConvertSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          locale == 'en'
              ? 'Lossy formats and ALAC replace the original FLAC file.'
              : 'Định dạng lossy và ALAC sẽ thay thế (xoá) file FLAC gốc.',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('sample rates omit trailing decimal zeros', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_convert_downloads': true});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(autoConvertDownloadsProvider.notifier).set(true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AutoConvertSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = tester
        .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .last;
    expect(dropdown.items!.map((item) => (item.child as Text).data).toList(), [
      '44.1 kHz',
      '48 kHz',
      '96 kHz',
      '192 kHz',
      'Keep original',
    ]);
  });
  testWidgets(
    'conversion settings show FLAC and ALAC caps and lossy bitrate conditionally',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AutoConvertSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(c.read(autoConvertDownloadsProvider), true);
      expect(find.text('Maximum bit depth'), findsOneWidget);
      expect(find.text('Maximum sample rate'), findsOneWidget);
      expect(find.text('Bitrate'), findsNothing);
      await c.read(autoConvertFormatProvider.notifier).set('mp3');
      await tester.pumpAndSettle();
      expect(find.text('Maximum bit depth'), findsNothing);
      expect(find.text('Bitrate'), findsOneWidget);
      await c.read(autoConvertFormatProvider.notifier).set('alac');
      await tester.pumpAndSettle();
      expect(find.text('Maximum bit depth'), findsOneWidget);
      expect(find.text('Maximum sample rate'), findsOneWidget);
      expect(find.text('Bitrate'), findsNothing);
      await c.read(autoConvertMaxBitDepthProvider.notifier).set(24);
      await c.read(autoConvertMaxSampleRateProvider.notifier).set(96000);
      await tester.pumpAndSettle();
      expect(find.text('24 bit'), findsWidgets);
      expect(find.text('96 kHz'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
