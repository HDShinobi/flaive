import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/settings_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/brand_mark.dart';

class _Extensions extends ExtensionsController {
  @override
  Future<List<InstalledExtension>> build() async => [];
}

void main() {
  testWidgets(
    'About card shows branding, licenses and GitHub launch failures',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Flaive',
        packageName: 'xyz.losslessmusic.app',
        version: '1.2.3',
        buildNumber: '42',
        buildSignature: '',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            extensionsProvider.overrideWith(_Extensions.new),
            downloadDirProvider.overrideWith((_) async => '/music'),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('ABOUT'), 400);
      await tester.pumpAndSettle();
      expect(find.text('Flaive'), findsOneWidget);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('v1.2.3'), findsOneWidget);
      await tester.ensureVisible(find.text('GitHub'));
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final throws in [false, true]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (throws) throw PlatformException(code: 'launch_failed');
              return false;
            });
        await tester.tap(find.text('GitHub'));
        await tester.pumpAndSettle();
        expect(find.text('Could not open link'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Licenses'));
      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    },
  );
}
