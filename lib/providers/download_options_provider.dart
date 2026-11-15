import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/download_paths.dart';
import '../services/download_templates.dart';
import '../models/metadata_separators.dart';

class AskBeforeDownloadNotifier extends Notifier<bool> {
  static const _key = 'ask_before_download';

  // Tracks whether set() has been explicitly called, so the startup microtask
  // doesn't clobber a value that was already written in this session.
  bool _explicitlySet = false;

  @override
  bool build() {
    _explicitlySet = false;
    // Load persisted value on first build without blocking the UI.
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) state = p.getBool(_key) ?? true;
    });
    return true;
  }

  /// Deprecated: `build()` now auto-loads the persisted value via a microtask
  /// on first initialization. Call [set] to update the value; there is no need
  /// to call [load] manually.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}

final askBeforeDownloadProvider =
    NotifierProvider<AskBeforeDownloadNotifier, bool>(
  AskBeforeDownloadNotifier.new,
);

// ---------------------------------------------------------------------------
// Generic bool preference notifier — reusable for any on/off setting.
// ---------------------------------------------------------------------------

class _BoolPrefNotifier extends Notifier<bool> {
  _BoolPrefNotifier(this._key, this._defaultValue);

  final String _key;
  final bool _defaultValue;
  bool _explicitlySet = false;
  late Future<void> ready;

  @override
  bool build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) state = p.getBool(_key) ?? _defaultValue;
    });
    return _defaultValue;
  }

  Future<void> set(bool value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}

final embedMetadataProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_metadata', true),
);

final embedCoverProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_cover', true),
);

final embedLyricsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_lyrics', true),
);

final autoFallbackProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('auto_fallback', true),
);

final redownloadFakeHiResProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('redownload_fake_hires', false),
);

final writeLrcSidecarProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('write_lrc_sidecar', false),
);

// ---------------------------------------------------------------------------
// Folder organization — how downloads are grouped under the download directory.
// ---------------------------------------------------------------------------

class FolderOrganizationNotifier extends Notifier<FolderOrganization> {
  static const _key = 'folder_organization';

  bool _explicitlySet = false;
  late Future<void> ready;

  @override
  FolderOrganization build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) {
        state = FolderOrganization.fromStorage(p.getString(_key));
      }
    });
    // Default to artist/album: it is the layout library_provider's tag-less
    // fallback parses paths for, so grouping keeps the library usable even when
    // a download arrives without embedded tags.
    return FolderOrganization.artistAlbum;
  }

  Future<void> set(FolderOrganization value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, value.storageValue);
  }
}

final folderOrganizationProvider =
    NotifierProvider<FolderOrganizationNotifier, FolderOrganization>(
  FolderOrganizationNotifier.new,
);

// Empty templates opt into the legacy, folder-dependent defaults.
class _StringPrefNotifier extends Notifier<String> {
  _StringPrefNotifier(this.key, this.defaultValue, this.valid);
  final String key, defaultValue;
  final bool Function(String) valid;
  bool _explicitlySet = false;
  late Future<void> ready;

  @override
  String build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      final value = p.getString(key) ?? defaultValue;
      if (ref.mounted && !_explicitlySet) {
        state = valid(value) ? value : defaultValue;
      }
    });
    return defaultValue;
  }

  Future<void> set(String value) async {
    if (!valid(value)) return;
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }
}

final filenameTemplateProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('filename_template', '',
    (v) => v.isEmpty || DownloadTemplates.validate(v) == null));
final albumFolderTemplateProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('album_folder_template', '',
    (v) => v.isEmpty || DownloadTemplates.validate(v, folder: true) == null));
final artistTagModeProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('artist_tag_mode', 'joined', artistTagModes.contains));

class MetadataSeparatorsNotifier extends Notifier<MetadataSeparators> {
  static const _key = 'metadata_separators';
  bool _explicitlySet = false;
  late Future<void> ready;

  @override
  MetadataSeparators build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      try {
        final json = jsonDecode(p.getString(_key) ?? '{}');
        if (ref.mounted && !_explicitlySet && json is Map<String, dynamic>) {
          state = MetadataSeparators.fromJson(json);
        }
      } on FormatException {
        // A damaged preference must not prevent downloads or opening settings.
      }
    });
    return const MetadataSeparators();
  }

  Future<void> setField(String field, String value) async {
    if (!MetadataSeparators.fields.contains(field) ||
        !MetadataSeparators.isValid(value)) {
      return;
    }
    _explicitlySet = true;
    state = state.withField(field, value);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(state.toJson()));
  }
}

final metadataSeparatorsProvider =
    NotifierProvider<MetadataSeparatorsNotifier, MetadataSeparators>(
      MetadataSeparatorsNotifier.new);

final wifiOnlyProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('download_wifi_only', false),
);

class SimultaneousDownloadsNotifier extends Notifier<int> {
  static const _key = 'simultaneous_downloads';
  bool _explicitlySet = false;
  late Future<void> ready;
  @override
  int build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) {
        state = (p.getInt(_key) ?? 1).clamp(1, 3);
      }
    });
    return 1;
  }
  Future<void> set(int value) async {
    _explicitlySet = true;
    state = value.clamp(1, 3);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key, state);
  }
}

final simultaneousDownloadsProvider =
    NotifierProvider<SimultaneousDownloadsNotifier, int>(SimultaneousDownloadsNotifier.new);

final autoConvertDownloadsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('auto_convert_downloads', false));
final autoConvertFormatProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('auto_convert_format', 'flac',
    const ['mp3', 'aac', 'opus', 'flac', 'alac'].contains));
final autoConvertBitrateProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('auto_convert_bitrate', '320k',
    const ['128k', '160k', '192k', '256k', '320k'].contains));

class _IntPrefNotifier extends Notifier<int> {
  _IntPrefNotifier(this.key, this.defaultValue, this.values);
  final String key;
  final int defaultValue;
  final List<int> values;
  bool _explicitlySet = false;
  late Future<void> ready;

  @override
  int build() {
    _explicitlySet = false;
    ready = Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      final value = p.getInt(key) ?? defaultValue;
      if (ref.mounted && !_explicitlySet) {
        state = values.contains(value) ? value : defaultValue;
      }
    });
    return defaultValue;
  }

  Future<void> set(int value) async {
    if (!values.contains(value)) return;
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setInt(key, value);
  }
}

final autoConvertMaxBitDepthProvider = NotifierProvider<_IntPrefNotifier, int>(
  () => _IntPrefNotifier('auto_convert_max_bit_depth', 16, [16, 24, 0]));
final autoConvertMaxSampleRateProvider = NotifierProvider<_IntPrefNotifier, int>(
  () => _IntPrefNotifier('auto_convert_max_sample_rate', 48000, [44100, 48000, 96000, 192000, 0]));

final useAlbumArtistForFoldersProvider =
    NotifierProvider<_BoolPrefNotifier, bool>(
      () => _BoolPrefNotifier('use_album_artist_for_folders', true),
    );
final usePrimaryArtistOnlyProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('use_primary_artist_only', false),
);
final filterContributingArtistsInAlbumArtistProvider =
    NotifierProvider<_BoolPrefNotifier, bool>(
      () => _BoolPrefNotifier(
        'filter_contributing_artists_in_album_artist',
        false,
      ),
    );
final createPlaylistFolderProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('create_playlist_folder', false),
);

final separateSinglesProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('separate_singles', false),
);
final albumFolderStructureProvider =
    NotifierProvider<_StringPrefNotifier, String>(
      () => _StringPrefNotifier(
        'album_folder_structure',
        'artist_album',
        FolderRules.albumFolderStructures.contains,
      ),
    );
final singleFilenameTemplateProvider =
    NotifierProvider<_StringPrefNotifier, String>(
      () => _StringPrefNotifier(
        'single_filename_template',
        '',
        (v) => v.isEmpty || DownloadTemplates.validate(v) == null,
      ),
    );

final folderRulesProvider = Provider<FolderRules>(
  (ref) => FolderRules(
    useAlbumArtistForFolders: ref.watch(useAlbumArtistForFoldersProvider),
    usePrimaryArtistOnly: ref.watch(usePrimaryArtistOnlyProvider),
    filterContributingArtistsInAlbumArtist: ref.watch(
      filterContributingArtistsInAlbumArtistProvider,
    ),
    separateSingles: ref.watch(separateSinglesProvider),
    createPlaylistFolder: ref.watch(createPlaylistFolderProvider),
    albumFolderStructure: ref.watch(albumFolderStructureProvider),
    singleFilenameTemplate: ref.watch(singleFilenameTemplateProvider),
  ),
);

/// Await the folder preferences at every non-UI path-planning entry point.
final folderRulesReadyProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.read(useAlbumArtistForFoldersProvider.notifier).ready,
    ref.read(usePrimaryArtistOnlyProvider.notifier).ready,
    ref.read(filterContributingArtistsInAlbumArtistProvider.notifier).ready,
    ref.read(separateSinglesProvider.notifier).ready,
    ref.read(createPlaylistFolderProvider.notifier).ready,
    ref.read(albumFolderStructureProvider.notifier).ready,
    ref.read(singleFilenameTemplateProvider.notifier).ready,
  ]);
});
