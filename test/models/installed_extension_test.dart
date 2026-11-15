import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';

void main() {
  test('parses settings with secret required grantsNetwork', () {
    final ext = InstalledExtension.fromJson({
      'settings': [
        {
          'key': 'customEndpointApiKey',
          'label': 'API key',
          'type': 'string',
          'default': '',
          'description': 'Private key',
          'secret': true,
          'required': true,
          'grantsNetwork': true,
        },
        {
          'key': 'countryCode',
          'label': 'Country',
          'type': 'select',
          'options': ['US', 'VN'],
          'default': 'US',
        },
        {
          'key': 'test_button',
          'label': 'Test',
          'type': 'button',
          'action': 'testConnection',
        },
      ],
    });
    expect(ext.settings, hasLength(3));
    final setting = ext.settings.first;
    expect(setting.key, 'customEndpointApiKey');
    expect(setting.label, 'API key');
    expect(setting.type, 'string');
    expect(setting.defaultValue, '');
    expect(setting.description, 'Private key');
    expect(setting.secret, isTrue);
    expect(setting.required, isTrue);
    expect(setting.grantsNetwork, isTrue);
    expect(ext.settings[1].options, ['US', 'VN']);
    expect(ext.settings[2].action, 'testConnection');
  });

  test('type defaults to string', () {
    final ext = InstalledExtension.fromJson({
      'settings': [
        {'key': 'appId', 'label': 'App ID'},
      ],
    });
    expect(ext.settings.single.type, 'string');
    expect(ext.settings.single.options, isEmpty);
    expect(ext.settings.single.secret, isFalse);
    expect(ext.settings.single.required, isFalse);
    expect(ext.settings.single.grantsNetwork, isFalse);
    final empty = InstalledExtension.fromJson({});
    expect(empty.settings, isEmpty);
  });

  test('hasHomeFeed true when capabilities.homeFeed == true', () {
    final e = InstalledExtension.fromJson({
      'id': 'ytmusic', 'name': 'yt', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'YT', 'description': '', 'status': '',
      'permissions': const [], 'capabilities': {'homeFeed': true},
    });
    expect(e.hasHomeFeed, isTrue);
  });

  test('hasHomeFeed false when capabilities absent', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
    });
    expect(e.hasHomeFeed, isFalse);
    expect(e.capabilities, isEmpty);
  });

  test('const constructor works without capabilities (backward compat)', () {
    const e = InstalledExtension(
      id: 'x', name: 'x', version: '1', enabled: true, types: [],
      displayName: 'X', description: '', status: '', permissions: [],
      hasMetadataProvider: false, hasDownloadProvider: false, hasLyricsProvider: false,
    );
    expect(e.hasHomeFeed, isFalse);
  });

  test('parses quality_options into qualityOptions', () {
    final e = InstalledExtension.fromJson({
      'id': 'tidal', 'name': 'tidal', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'Tidal', 'description': '', 'status': '',
      'permissions': const [],
      'quality_options': [
        {'id': 'HI_RES_LOSSLESS', 'label': 'Hi-Res FLAC', 'description': 'Up to 24-bit / 192 kHz'},
        {'id': 'LOSSLESS', 'label': 'FLAC Lossless', 'description': '16-bit / 44.1 kHz'},
      ],
    });
    expect(e.qualityOptions, hasLength(2));
    expect(e.qualityOptions.first.id, 'HI_RES_LOSSLESS');
    expect(e.qualityOptions.first.label, 'Hi-Res FLAC');
    expect(e.qualityOptions.first.description, 'Up to 24-bit / 192 kHz');
  });

  test('qualityOptions empty when quality_options absent', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
    });
    expect(e.qualityOptions, isEmpty);
  });

  test('quality option label falls back to id when label missing', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
      'quality_options': [
        {'id': 'LOSSLESS'},
      ],
    });
    expect(e.qualityOptions.single.label, 'LOSSLESS');
    expect(e.qualityOptions.single.description, '');
  });
}
