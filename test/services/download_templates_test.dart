import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/services/download_paths.dart';
import 'package:lossless_music_download/services/download_templates.dart';

void main() {
  test('playlist sanitization stays one visible segment and keeps emoji', () {
    expect(sanitizePlaylistFolder('a/b'), 'a b');
    expect(sanitizePlaylistFolder('..'), 'Playlist');
    expect(sanitizePlaylistFolder('   '), 'Playlist');
    expect(sanitizePlaylistFolder('🎵 Mix'), '🎵 Mix');
    expect(sanitizePlaylistFolder('a..b\\c:*?"<>|'), 'a.b c');
  });
  test('playlist prefix applies to normal and custom folders', () {
    final track = DownloadTemplates.sample();
    for (final folder in ['', '{album}']) {
      final target = resolveDownloadTarget('/music', track,
        mode: FolderOrganization.artistAlbum, playlistName: 'Mix/2026',
        albumFolderTemplate: folder,
        rules: const FolderRules(createPlaylistFolder: true));
      expect(target.dir, folder.isEmpty
        ? '/music/Mix 2026/Sample Artist/Sample Album'
        : '/music/Mix 2026/Sample Album');
    }
    expect(resolveDownloadTarget('/music', track, mode: FolderOrganization.none,
      playlistName: 'Mix').dir, '/music');
  });
  test('playlist organization overrides custom folders and singles', () {
    expect(FolderOrganization.fromStorage('playlist'), FolderOrganization.playlist);
    expect(FolderOrganization.playlist.storageValue, 'playlist');
    final target = resolveDownloadTarget('/music', DownloadTemplates.sample(singleRelease: true),
      mode: FolderOrganization.playlist, playlistName: 'Mix',
      albumFolderTemplate: '{album}',
      rules: const FolderRules(createPlaylistFolder: true, separateSingles: true));
    expect(target.dir, '/music/Mix');
  });

  test('separate singles uses every upstream folder tree including Albums', () {
    const single = Track(
      id: 's',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Record',
      albumType: 'single',
      releaseDate: '2026-01-01',
    );
    const album = Track(
      id: 'a',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Record',
      albumType: 'album',
      releaseDate: '2026-01-01',
    );
    const trees = {
      'artist_album': ('Singles', 'Albums/Artist/Record'),
      'artist_year_album': ('Singles', 'Albums/Artist/[2026] Record'),
      'album_only': ('Singles', 'Albums/Record'),
      'year_album': ('Singles', 'Albums/[2026] Record'),
      'artist_album_singles': ('Artist/Singles', 'Artist/Record'),
      'artist_album_flat': ('Artist', 'Artist/Record'),
    };
    for (final entry in trees.entries) {
      for (final mode in FolderOrganization.values.where((m) => m != FolderOrganization.playlist)) {
        final rules = FolderRules(
          separateSingles: true,
          albumFolderStructure: entry.key,
        );
        expect(
          resolveDownloadTarget('/dl', single, mode: mode, rules: rules).dir,
          '/dl/${entry.value.$1}',
        );
        expect(
          resolveDownloadTarget('/dl', album, mode: mode, rules: rules).dir,
          '/dl/${entry.value.$2}',
        );
      }
    }
  });
  test('single template overrides normal filename; empty falls back', () {
    const single = Track(
      id: 's',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Record',
      albumType: 'ep',
      trackNumber: 1,
    );
    final target = resolveDownloadTarget(
      '/dl',
      single,
      mode: FolderOrganization.artistAlbum,
      filenameTemplate: '{title}',
      albumFolderTemplate: 'Custom/{album}',
      rules: const FolderRules(
        separateSingles: true,
        singleFilenameTemplate: '{title} - {artist}',
      ),
    );
    expect(target.dir, '/dl/Singles');
    expect(target.template, '{title} - {artist}');
    expect(
      resolveDownloadTarget(
        '/dl',
        single,
        mode: FolderOrganization.artistAlbum,
        filenameTemplate: '{title}',
        rules: const FolderRules(),
      ).template,
      '{title}',
    );
    const album = Track(
      id: 'a',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Record',
      albumType: 'album',
    );
    expect(
      resolveDownloadTarget(
        '/dl',
        album,
        mode: FolderOrganization.artistAlbum,
        albumFolderTemplate: 'Custom/{album}',
        rules: const FolderRules(separateSingles: true),
      ).dir,
      '/dl/Custom/Record',
    );
  });
  test('default FolderRules preserves existing path fixtures', () {
    const fixtures = [
      (
        Track(
          id: 'a',
          name: 'Song',
          artists: 'AC/DC',
          albumName: 'Album',
          discNumber: 2,
          totalDiscs: 2,
          trackNumber: 3,
        ),
        'AC DC/Album',
        '{disc}-{track}. {title}',
      ),
      (
        Track(
          id: 'b',
          name: 'Song',
          artists: 'Post Malone feat. Taylor Swift',
          albumName: 'Fortnight',
          trackNumber: 1,
        ),
        'Post Malone/Fortnight',
        '{track}. {title}',
      ),
      (
        Track(
          id: 'c',
          name: 'Song',
          artists: 'Various Artists',
          albumArtist: 'Hans Zimmer',
          albumName: 'Dune',
        ),
        'Hans Zimmer/Dune',
        '{title}',
      ),
      (
        Track(id: 'd', name: 'Song', artists: 'Taylor Swift', albumName: ''),
        'Taylor Swift',
        '{title}',
      ),
    ];
    for (final (track, folder, template) in fixtures) {
      final target = resolveDownloadTarget(
        '/dl',
        track,
        mode: FolderOrganization.artistAlbum,
        rules: const FolderRules(),
      );
      expect(target, (dir: '/dl/$folder', template: template));
    }
  });
  const track = Track(
    id: 'x',
    name: 'Song',
    artists: 'AC/DC',
    albumName: 'Album',
    releaseDate: '2026-11-07',
    trackNumber: 3,
    discNumber: 2,
    totalDiscs: 2,
  );

  test('rejects unknown, malformed, empty and unsafe templates', () {
    for (final value in [
      '',
      '  ',
      '{unknown}',
      '{title',
      '{{title}}',
      '{title}/x',
      r'{title}\x',
      '...',
      '{track:999999}',
    ]) {
      expect(DownloadTemplates.validate(value), isNotNull, reason: value);
    }
    for (final value in [
      '/absolute',
      '../{album}',
      '{artist}//{album}',
      r'C:\{album}',
      '{album}/..',
    ]) {
      expect(
        DownloadTemplates.validate(value, folder: true),
        isNotNull,
        reason: value,
      );
    }
    expect(
      DownloadTemplates.validate('{artist}/{album} ({year})', folder: true),
      isNull,
    );
  });

  test('preview renders padded numbers and adds multi-disc protection', () {
    final target = resolveDownloadTarget(
      '/dl',
      track,
      mode: FolderOrganization.artistAlbum,
      filenameTemplate: '{track:03}. {title}',
      albumFolderTemplate: '{artist}/{album} ({year})',
    );
    expect(target.dir, '/dl/AC DC/Album (2026)');
    expect(target.template, '{disc}-{track:03}. {title}');
    expect(DownloadTemplates.preview(target.template, track), '2-003. Song');
    expect(
      DownloadTemplates.preview('{disc:02}-{track}. {title}', track),
      '02-03. Song',
    );
    expect(stripTrackNumberPrefix('02-03. Song'), 'Song');
  });

  test('single disc does not gain a prefix and default remains unchanged', () {
    const single = Track(
      id: 's',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Album',
      trackNumber: 1,
      discNumber: 1,
      totalDiscs: 1,
    );
    final target = resolveDownloadTarget(
      '/dl',
      single,
      mode: FolderOrganization.artistAlbum,
    );
    expect(target.dir, '/dl/Artist/Album');
    expect(target.template, '{track}. {title}');
    expect(DownloadTemplates.preview(target.template, single), '01. Song');
    final custom = resolveDownloadTarget(
      '/dl',
      single,
      mode: FolderOrganization.none,
      filenameTemplate: '{title}',
    );
    expect(custom.template, '{title}');
  });

  test('metadata slashes never introduce extra folder levels', () {
    final target = resolveDownloadTarget(
      '/dl',
      track,
      mode: FolderOrganization.none,
      albumFolderTemplate: '{artist}/{album}',
    );
    expect(target.dir, '/dl/AC DC/Album');
    expect(DownloadTemplates.preview('{title} [{isrc}]', track), 'Song');
  });
}
