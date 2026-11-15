import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/extension_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/widgets/extension_settings_section.dart';

class _Bridge extends BackendBridge {
  Future<Map<String, dynamic>>? load;
  Map<String, dynamic> stored = {'_enabled': true, 'other': 'x'};
  final saves = <Map<String, dynamic>>[];
  final actions = <(String, String)>[];
  Completer<void>? saveGate;
  bool failSave = false;
  Map<String, dynamic> result = {
    'success': true,
    'message': 'Connected',
    'setting_updates': {'api_key': 'session-key'},
  };

  @override
  Future<Map<String, dynamic>> getExtensionSettings(String id) async =>
      load == null ? Map.of(stored) : await load!;

  @override
  Future<void> setExtensionSettings(
    String id,
    Map<String, dynamic> settings,
  ) async {
    expect(id, 'test');
    saves.add(Map.of(settings));
    await saveGate?.future;
    if (failSave) throw StateError('save failed');
    stored = Map.of(settings);
  }

  @override
  Future<Map<String, dynamic>> invokeExtensionAction(
    String id,
    String action,
  ) async {
    actions.add((id, action));
    return result;
  }
}

const _settings = <Map<String, dynamic>>[
  {
    'key': 'customEndpoint',
    'label': 'Endpoint',
    'grantsNetwork': true,
    'default': 'https://default.example',
  },
  {'key': 'api_key', 'label': 'API key', 'secret': true},
  {'key': 'limit', 'label': 'Limit', 'type': 'number', 'default': 10},
  {'key': 'active', 'label': 'Active', 'type': 'boolean', 'default': false},
  {
    'key': 'countryCode',
    'label': 'Country',
    'type': 'select',
    'options': ['US', 'VN'],
    'default': 'US',
  },
  {'key': 'server_url', 'label': 'Server', 'required': true},
  {
    'key': 'test_button',
    'label': 'Test connection',
    'type': 'button',
    'action': 'testConnection',
  },
];

Widget _app(_Bridge bridge, {String locale = 'en'}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale(locale),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ExtensionSettingsSection(
          ext: InstalledExtension.fromJson({
            'id': 'test',
            'settings': _settings,
          }),
          bridge: bridge,
        ),
      ),
    ),
  ),
);

Future<void> _edit(
  WidgetTester tester,
  String label,
  String value, {
  String save = 'Save',
}) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), value);
  await tester.tap(find.text(save));
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Test connection'));
  await tester.tap(find.text('Test connection'));
  await tester.pumpAndSettle();
}

class _Extensions extends ExtensionsController {
  _Extensions(this.ext);
  final InstalledExtension ext;
  @override
  Future<List<InstalledExtension>> build() async => [ext];
}

void main() {
  for (final locale in ['en', 'vi']) {
    testWidgets('save merges into loaded map keeping _enabled ($locale)', (
      tester,
    ) async {
      final b = _Bridge();
      await tester.pumpWidget(_app(b, locale: locale));
      await tester.pumpAndSettle();
      await _edit(
        tester,
        'Endpoint',
        'https://user.example',
        save: locale == 'en' ? 'Save' : 'Lưu',
      );
      expect(b.saves.single, {
        '_enabled': true,
        'other': 'x',
        'customEndpoint': 'https://user.example',
      });
      expect(find.text('https://user.example'), findsOneWidget);
    });
  }

  testWidgets('controls disabled until load completes', (tester) async {
    final load = Completer<Map<String, dynamic>>();
    final b = _Bridge()..load = load.future;
    await tester.pumpWidget(_app(b));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    }
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.tap(find.text('Endpoint'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(b.saves, isEmpty);
    load.complete({'_enabled': true});
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _edit(tester, 'Endpoint', 'ready');
    expect(b.stored, {'_enabled': true, 'customEndpoint': 'ready'});
  });

  testWidgets('default shown but not saved when untouched', (tester) async {
    final b = _Bridge();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    expect(find.text('https://default.example'), findsOneWidget);
    expect(b.saves, isEmpty);
    await _edit(tester, 'API key', 'key');
    expect(b.saves.single, {'_enabled': true, 'other': 'x', 'api_key': 'key'});
  });

  testWidgets('secret value is masked', (tester) async {
    final b = _Bridge()..stored['api_key'] = 'top-secret';
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    expect(find.text('top-secret'), findsNothing);
    expect(find.text('••••'), findsOneWidget);
    await tester.tap(find.text('API key'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(b.saves, isEmpty);
  });

  testWidgets('button runs action and applies setting_updates', (tester) async {
    final b = _Bridge();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _action(tester);
    expect(b.actions, [('test', 'testConnection')]);
    expect(b.saves.single, {
      '_enabled': true,
      'other': 'x',
      'api_key': 'session-key',
    });
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('••••'), findsOneWidget);
  });

  testWidgets('nested action result is supported', (tester) async {
    final b = _Bridge()
      ..result = {
        'success': true,
        'result': {
          'success': true,
          'message': 'Logged out',
          'setting_updates': {'api_key': ''},
        },
      };
    b.stored['api_key'] = 'old';
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _action(tester);
    expect(b.stored['api_key'], '');
    expect(find.text('Logged out'), findsOneWidget);
    expect(find.text('••••'), findsNothing);
  });

  testWidgets('failed action does not apply updates', (tester) async {
    final b = _Bridge()
      ..result = {
        'success': false,
        'error': 'Denied',
        'setting_updates': {'api_key': 'bad'},
      };
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _action(tester);
    expect(find.text('Denied'), findsOneWidget);
    expect(b.saves, isEmpty);
  });

  testWidgets('invalid number not saved', (tester) async {
    final b = _Bridge();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _edit(tester, 'Limit', 'abc');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Enter a valid number'), findsOneWidget);
    expect(b.saves, isEmpty);
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(b.saves, isEmpty);
    await tester.enterText(find.byType(TextField), '12.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(b.stored['limit'], 12.5);
  });

  testWidgets('two quick edits both persist', (tester) async {
    final gate = Completer<void>();
    final b = _Bridge()..saveGate = gate;
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _edit(tester, 'Endpoint', 'first');
    expect(b.saves, hasLength(1));
    // The row must keep the prior value until the engine save succeeds.
    expect(find.text('https://default.example'), findsOneWidget);
    await _edit(tester, 'API key', 'second');
    expect(b.saves, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(b.saves, [
      {'_enabled': true, 'other': 'x', 'customEndpoint': 'first'},
      {
        '_enabled': true,
        'other': 'x',
        'customEndpoint': 'first',
        'api_key': 'second',
      },
    ]);
  });

  testWidgets('save error keeps previous value and queue recovers', (
    tester,
  ) async {
    final b = _Bridge()..failSave = true;
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _edit(tester, 'Endpoint', 'rejected');
    expect(find.text('https://default.example'), findsOneWidget);
    expect(find.text('Could not save extension settings'), findsOneWidget);
    b.failSave = false;
    await _edit(tester, 'API key', 'accepted');
    expect(b.stored, {'_enabled': true, 'other': 'x', 'api_key': 'accepted'});
  });

  testWidgets(
    'load error disables controls rather than replacing unknown settings',
    (tester) async {
      final load = Completer<Map<String, dynamic>>();
      final b = _Bridge()..load = load.future;
      await tester.pumpWidget(_app(b));
      load.completeError(StateError('load failed'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load extension settings'), findsOneWidget);
      await tester.tap(find.text('Endpoint'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(b.saves, isEmpty);
    },
  );

  testWidgets(
    'boolean and select save typed values without persisting defaults',
    (tester) async {
      final b = _Bridge();
      await tester.pumpWidget(_app(b));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Country'));
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VN'));
      await tester.pumpAndSettle();
      expect(b.stored, {
        '_enabled': true,
        'other': 'x',
        'active': true,
        'countryCode': 'VN',
      });
    },
  );

  testWidgets('required empty value warns without blocking save', (
    tester,
  ) async {
    final b = _Bridge();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    expect(find.textContaining('Required value is empty'), findsOneWidget);
    await _edit(tester, 'Server', '');
    expect(b.stored['server_url'], '');
  });
  testWidgets('action opens auth URL externally and shows message', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final b = _Bridge()
      ..result = {
        'success': true,
        'open_auth_url': 'https://auth.example/login',
        'message': 'Sign in',
      };
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await _action(tester);
    expect(calls.single.method, 'launch');
    expect(calls.single.arguments['url'], 'https://auth.example/login');
    expect(calls.single.arguments['useWebView'], false);
    expect(calls.single.arguments['useSafariVC'], false);
    expect(find.text('Sign in'), findsOneWidget);
    expect(b.saves, isEmpty);
  });

  for (final hasSettings in [true, false]) {
    testWidgets('detail settings placement (hasSettings: $hasSettings)', (
      tester,
    ) async {
      final b = _Bridge();
      final ext = InstalledExtension.fromJson({
        'id': 'test',
        'display_name': 'Test source',
        'settings': hasSettings ? [_settings.first] : [],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(b),
            extensionsProvider.overrideWith(() => _Extensions(ext)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ExtensionDetailScreen(id: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (hasSettings) {
        expect(find.byType(ExtensionSettingsSection), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Extension settings')).dy,
          lessThan(tester.getTopLeft(find.text('Permissions')).dy),
        );
      } else {
        expect(find.byType(ExtensionSettingsSection), findsNothing);
        expect(find.text('Permissions'), findsOneWidget);
      }
    });
  }
}
