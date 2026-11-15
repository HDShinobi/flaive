/// Download path construction.
///
/// The Go engine treats `filenameFormat` as a single **basename** — before
/// writing it runs the whole string through `sanitizeFilename`, which turns `/`
/// into a space (a filename containing `/` is illegal on every filesystem). So
/// a template like `{artist}/{album}/{title}` never produces folders; it
/// collapses into one flat name.
///
/// Following SpotiFLAC, folder layout is therefore a *separate* concern from the
/// filename template: we resolve a relative folder here, sanitizing each segment
/// on its own so the hierarchy survives, and hand the engine an absolute
/// `outputDir` plus a flat basename template.
library;

/// How downloads are grouped into folders under the download directory.
enum FolderOrganization {
  /// Everything in one folder.
  none,

  /// `<Artist>/`
  artist,

  /// `<Album>/`
  album,

  /// `<Artist>/<Album>/`
  artistAlbum;

  /// Persisted form. Matches SpotiFLAC's `folderOrganization` setting values so
  /// the two apps can read each other's settings.
  String get storageValue => switch (this) {
        FolderOrganization.none => 'none',
        FolderOrganization.artist => 'artist',
        FolderOrganization.album => 'album',
        FolderOrganization.artistAlbum => 'artist_album',
      };

  static FolderOrganization fromStorage(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'none' => FolderOrganization.none,
        'artist' => FolderOrganization.artist,
        'album' => FolderOrganization.album,
        'artist_album' => FolderOrganization.artistAlbum,
        _ => FolderOrganization.artistAlbum,
      };
}

/// Shared folder and single-file preferences. Defaults retain legacy paths.
class FolderRules {
  const FolderRules({
    this.useAlbumArtistForFolders = true,
    this.usePrimaryArtistOnly = false,
    this.filterContributingArtistsInAlbumArtist = false,
    this.separateSingles = false,
    this.albumFolderStructure = 'artist_album',
    this.singleFilenameTemplate = '',
  });

  final bool useAlbumArtistForFolders;
  final bool usePrimaryArtistOnly;
  final bool filterContributingArtistsInAlbumArtist;
  final bool separateSingles;
  final String albumFolderStructure;
  final String singleFilenameTemplate;

  static const albumFolderStructures = [
    'artist_album',
    'artist_year_album',
    'album_only',
    'year_album',
    'artist_album_singles',
    'artist_album_flat',
  ];
}

final _primaryArtistSeparator = RegExp(
  r'\s*[,;]\s*|\s+(?:feat\.?|ft\.?|featuring|with|x)\s+',
  caseSensitive: false,
);

String primaryArtist(String artists) =>
    artists.split(_primaryArtistSeparator).first.trim();

/// The metadata flag is independent of which artist supplies folder names.
String? albumArtistForMetadata(String? artist, FolderRules rules) {
  final value = artist?.trim();
  if (value == null || value.isEmpty) return null;
  return rules.filterContributingArtistsInAlbumArtist
      ? primaryArtist(value)
      : value;
}

/// The subset of track metadata that folder names are built from.
class FolderMetadata {
  const FolderMetadata({
    required this.artist,
    this.albumArtist,
    this.album,
    this.isSingle = false,
    this.releaseDate,
  });

  final String artist;
  final String? albumArtist;
  final String? album;
  final bool isSingle;
  final String? releaseDate;
}

/// Characters no Android/Linux/Windows filesystem accepts in a path segment.
final _invalidSegmentChars = RegExp(r'[\\/:*?"<>|]');
final _whitespaceRun = RegExp(r'\s+');

/// Cleans one path segment. Unlike the engine's `sanitizeFilename` this runs per
/// segment, so `/` between segments is preserved by the caller.
String sanitizeFolderSegment(String name) {
  final withoutControl = name.runes
      .where((r) => r >= 0x20 && r != 0x7f)
      .map(String.fromCharCode);
  var out = withoutControl
      .join()
      .replaceAll(_invalidSegmentChars, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  // Trailing dots and leading/trailing spaces break Windows shares and confuse
  // Android's media scanner; a leading dot would also hide the folder.
  out = out
      .replaceAll(RegExp(r'^[.\s]+'), '')
      .replaceAll(RegExp(r'[.\s]+$'), '');
  return out.isEmpty ? 'Unknown' : out;
}

/// Strips featured artists so "A feat. B" and "A" land in the same folder.
final _featuredArtist = RegExp(
  r'(?:\s+|\s*[\[(]\s*)(?:feat\.?|ft\.?|featuring|with)\s+.*$',
  caseSensitive: false,
);

/// Builds the relative folder for [track] under the download directory.
/// Returns `''` when no folder should be created.
String buildRelativeFolder(
  FolderOrganization mode,
  FolderMetadata track, {
  FolderRules rules = const FolderRules(),
}) {
  if (!rules.separateSingles && mode == FolderOrganization.none) return '';

  final albumArtist = track.albumArtist;
  final hasAlbumArtist = albumArtist != null && albumArtist.trim().isNotEmpty;
  final rawArtist = rules.useAlbumArtistForFolders && hasAlbumArtist
      ? albumArtist
      : track.artist;
  final usePrimary =
      rules.usePrimaryArtistOnly ||
      (rules.useAlbumArtistForFolders &&
          hasAlbumArtist &&
          rules.filterContributingArtistsInAlbumArtist);
  // Keep legacy featured-credit cleanup even with the default rules.
  final folderArtist = usePrimary
      ? primaryArtist(rawArtist)
      : rawArtist.replaceAll(_featuredArtist, '');
  final artist = rawArtist.trim().isEmpty
      ? null
      : sanitizeFolderSegment(folderArtist);
  final album = (track.album?.trim().isNotEmpty ?? false)
      ? sanitizeFolderSegment(track.album!)
      : null;

  if (rules.separateSingles) {
    final a = artist ?? 'Unknown';
    final record = album ?? 'Unknown';
    if (track.isSingle) {
      return switch (rules.albumFolderStructure) {
        'artist_album_singles' => '$a/Singles',
        'artist_album_flat' => a,
        _ => 'Singles',
      };
    }
    final year = RegExp(r'^\d{4}').stringMatch(track.releaseDate?.trim() ?? '');
    final yearAlbum = year == null ? record : '[$year] $record';
    return switch (rules.albumFolderStructure) {
      'artist_album_singles' || 'artist_album_flat' => '$a/$record',
      'album_only' => 'Albums/$record',
      'artist_year_album' => 'Albums/$a/$yearAlbum',
      'year_album' => 'Albums/$yearAlbum',
      _ => 'Albums/$a/$record',
    };
  }

  final segments = switch (mode) {
    FolderOrganization.artist => [artist],
    FolderOrganization.album => [album],
    FolderOrganization.artistAlbum => [artist, album],
    FolderOrganization.none => const <String?>[],
  };

  return segments.whereType<String>().join('/');
}

/// The flat basename template to pair with [mode].
///
/// When downloads are grouped into folders the artist and album already live in
/// the path, so the filename stays short. Without folders the filename is all
/// the user has to tell two tracks apart, so it carries the artist too.
/// Multi-disc albums prefix the disc (unpadded) before the track (two digits),
/// using the engine's standard numeric placeholders. Unknown totals are not
/// evidence of multiple discs unless the track itself belongs to disc 2+.
String basenameTemplateFor(
  FolderOrganization mode, {
  int? discNumber,
  int? totalDiscs,
}) {
  if (mode == FolderOrganization.none) return '{artist} - {title}';
  final multiDisc =
      (totalDiscs ?? 0) > 1 ||
      ((totalDiscs ?? 0) <= 0 && (discNumber ?? 0) > 1);
  return multiDisc ? '{disc}-{track}. {title}' : '{track}. {title}';
}

final _trackNumberPrefix = RegExp(r'^\d+(?:-\d+)?[\s.]\s*');
final _dottedTrackNumberPrefix = RegExp(r'^\d+(?:-\d+)?\.\s*');

/// Removes one track-number prefix, optionally preceded by a disc number.
/// Callers handle file extensions separately. [requireDot] preserves artist
/// matching's stricter separator rule so titles like "7 Rings" stay intact.
String stripTrackNumberPrefix(String name, {bool requireDot = false}) =>
    name.replaceFirst(
      requireDot ? _dottedTrackNumberPrefix : _trackNumberPrefix,
      '',
    );

final _placeholder = RegExp(r'\{([a-z_]+)(?::[^}]*)?\}');

/// Removes placeholders whose value is empty, together with the punctuation left
/// stranded around them — otherwise a missing track number renders `{track}.
/// {title}` as `". Title"` and a missing year renders `({year})` as `()`.
///
/// Contract: [values] carries every placeholder the caller could resolve, using
/// `''` for the ones that resolved to nothing. A placeholder *absent* from
/// [values] is one only the engine understands (padded numbers, date formats),
/// so it is left in place — pruning those would silently drop parts of a user's
/// template.
String pruneEmptyPlaceholders(String template, Map<String, String> values) {
  const gap = '\u0000';

  var out = template.replaceAllMapped(_placeholder, (m) {
    final key = m.group(1)!;
    if (!values.containsKey(key)) return m.group(0)!;
    return values[key]!.trim().isEmpty ? gap : m.group(0)!;
  });

  if (!out.contains(gap)) return template;

  // Bracketed groups that lost their only content go entirely.
  out = out.replaceAll(RegExp('[(\\[]\\s*$gap\\s*[)\\]]'), gap);
  // Then the gap plus any separator glued to one side of it.
  out = out
      .replaceAll(RegExp('\\s*[-–—.,/]?\\s*$gap\\s*[-–—.,/]?\\s*'), ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  out = out.replaceAll(RegExp(r'^[-–—.,/\s]+'), '').replaceAll(RegExp(r'[-–—.,/\s]+$'), '');

  // Never hand the engine an empty template; it would fall back to a generic
  // "artist - title" and lose the user's intent entirely.
  return out.isEmpty ? template : out;
}
