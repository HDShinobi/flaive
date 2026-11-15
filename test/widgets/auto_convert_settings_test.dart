import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/screens/auto_convert_settings_screen.dart';

void main() {
  testWidgets(
    'conversion settings show FLAC caps and lossy bitrate conditionally',
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
      expect(find.text('Maximum bit depth'), findsNothing);
      expect(find.text('Bitrate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
