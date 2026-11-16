import 'dart:io';
import 'dart:async';

import '../providers/batch_re_enrich_provider.dart';
import '../providers/library_busy_provider.dart';
import '../providers/download_options_provider.dart';
import '../widgets/batch_re_enrich_panel.dart';
import '../theme/app_tokens.dart';

import 'download_history_screen.dart';
import 'library_reorganize_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_album_screen.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';
import 'package:lossless_music_download/widgets/serve_banner.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  void _toggle(LibraryEntry entry) => setState(() {
    if (!_selected.add(entry.path)) _selected.remove(entry.path);
  });

  int _segment = 0; // 0=All, 1=Albums, 2=Singles
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LibraryEntry> _filter(List<LibraryEntry> all) {
    if (_searchQuery.isEmpty) return all;
    return all.where((e) {
      final title = (e.title ?? e.name).toLowerCase();
      final artist = e.artistName?.toLowerCase() ?? '';
      return title.contains(_searchQuery) || artist.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final asyncEntries = ref.watch(sortedLibraryProvider);
    final failures = ref.watch(libraryStateProvider).scanFailures;
    final sort = ref.watch(librarySortProvider);
    final libraryBusy = ref.watch(libraryBusyProvider);

    return Scaffold(
      appBar: AppBar(
        // Room for the 28px title plus the mono file-count line at large text scales.
        toolbarHeight: 72,
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: t.batchRefreshDismiss,
                onPressed: () => setState(_selected.clear),
              )
            : null,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selecting
                  ? t.librarySelectedCount(_selected.length)
                  : t.tabLibrary,
              style: AppText.pageTitle,
            ),
            if (!_selecting && asyncEntries.hasValue)
              Text(
                t.libraryCount(asyncEntries.value!.length),
                style: context.tokens.mono
                    .merge(AppText.caption)
                    .copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: t.librarySort,
            initialValue: sort,
            onSelected: (value) => ref
                .read(librarySortPreferenceProvider.notifier)
                .set(value.name),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: LibrarySort.title,
                child: Text(t.librarySortTitle),
              ),
              PopupMenuItem(
                value: LibrarySort.sizeDesc,
                child: Text(t.librarySortSizeDesc),
              ),
              PopupMenuItem(
                value: LibrarySort.sizeAsc,
                child: Text(t.librarySortSizeAsc),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: t.reorganizeExisting,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LibraryReorganizeScreen(
                    selection: _selecting ? Set.of(_selected) : null,
                  ),
                ),
              );
              if (mounted) setState(_selected.clear);
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: t.downloadHistory,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadHistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: () => ref.invalidate(libraryProvider),
          ),
        ],
      ),
      bottomNavigationBar: const BatchReEnrichPanel(),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(t.libraryError)),
        data: (entries) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failures.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(t.libraryScanFailureCount(failures.length)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SafeArea(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                t.libraryScanFailureCount(failures.length),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: failures.length,
                                itemBuilder: (_, index) => ListTile(
                                  title: Text(failures[index].fileName),
                                  subtitle: Text(failures[index].message),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (entries.isEmpty)
                Expanded(child: Center(child: Text(t.libraryEmpty)))
              else ...[
                if (_selecting)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _selected.addAll(
                              _filter(entries)
                                  .where(
                                    (e) => _segment != 2 || e.albumName == null,
                                  )
                                  .map((e) => e.path),
                            );
                          }),
                          child: Text(t.librarySelectAll),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            final albums = entries
                                .where(
                                  (e) =>
                                      _selected.contains(e.path) &&
                                      e.albumName != null,
                                )
                                .map(
                                  (e) => (
                                    (e.artistName ?? '').toLowerCase(),
                                    e.albumName!.toLowerCase(),
                                  ),
                                )
                                .toSet();
                            _selected.addAll(
                              entries
                                  .where(
                                    (e) =>
                                        e.albumName != null &&
                                        albums.contains((
                                          (e.artistName ?? '').toLowerCase(),
                                          e.albumName!.toLowerCase(),
                                        )),
                                  )
                                  .map((e) => e.path),
                            );
                          }),
                          child: Text(t.librarySelectAlbum),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.auto_fix_high),
                          onPressed: libraryBusy
                              ? null
                              : () {
                                  final tracks = entries
                                      .where((e) => _selected.contains(e.path))
                                      .toList();
                                  unawaited(
                                    ref
                                        .read(batchReEnrichProvider.notifier)
                                        .start(tracks),
                                  );
                                  setState(_selected.clear);
                                },
                          label: Text(t.batchRefreshMetadata),
                        ),
                        if (libraryBusy) Text(t.libraryBusyHint),
                      ],
                    ),
                  ),
                // Segment toggle buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      textStyle: AppText.caption,
                    ),
                    segments: [
                      ButtonSegment(value: 0, label: Text(t.libraryAll)),
                      ButtonSegment(value: 1, label: Text(t.libraryAlbums)),
                      ButtonSegment(value: 2, label: Text(t.librarySingles)),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (selection) =>
                        setState(() => _segment = selection.single),
                  ),
                ),
                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: t.librarySearchHint,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                // List area
                Expanded(child: _buildList(context, entries)),
                // Serve banner always at bottom
                Theme(
                  data: Theme.of(context).copyWith(
                    extensions: [
                      context.tokens.copyWith(
                        accentSoft: Theme.of(
                          context,
                        ).colorScheme.surfaceContainer,
                        accentLine: context.tokens.lineSoft,
                      ),
                    ],
                  ),
                  child: ServeBanner(count: entries.length),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<LibraryEntry> entries) {
    final t = AppLocalizations.of(context);
    final filtered = _filter(entries);
    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(child: Text(t.libraryNoResults));
    }
    switch (_segment) {
      case 1:
        return _buildAlbumsView(context, filtered);
      case 2:
        return _buildSinglesView(filtered);
      default:
        return _buildAllView(filtered);
    }
  }

  Widget _buildAllView(List<LibraryEntry> entries) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => _trackTile(context, entries[index]),
    );
  }

  Widget _trackTile(BuildContext context, LibraryEntry entry) =>
      LibraryTrackTile(
        entry: entry,
        selected: _selecting ? _selected.contains(entry.path) : null,
        onSelected: (_) => _toggle(entry),
        onLongPress: () => _toggle(entry),
        onTap: () => _selecting
            ? _toggle(entry)
            : context.push('/library/verified', extra: entry),
      );

  Widget _buildAlbumsView(BuildContext context, List<LibraryEntry> entries) {
    // Group entries that have an albumName by (artistName, albumName)
    final grouped = <(String, String), List<LibraryEntry>>{};
    for (final entry in entries) {
      if (entry.albumName == null) continue;
      final key = (entry.artistName ?? '', entry.albumName!);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    if (grouped.isEmpty) {
      return const Center(child: SizedBox.shrink());
    }

    final sort = ref.watch(librarySortProvider);
    final sizes = sort == LibrarySort.title
        ? <(String, String), int>{}
        : {
            for (final album in grouped.entries)
              album.key: album.value.fold<int>(
                0,
                (sum, e) => sum + e.sizeBytes,
              ),
          };
    final albums = grouped.entries.toList();
    if (sort != LibrarySort.title) {
      albums.sort((a, b) {
        final bySize = sizes[a.key]!.compareTo(sizes[b.key]!);
        if (bySize != 0) {
          return sort == LibrarySort.sizeDesc ? -bySize : bySize;
        }
        final byTitle = a.key.$2.compareTo(b.key.$2);
        return byTitle != 0 ? byTitle : a.key.$1.compareTo(b.key.$1);
      });
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final kv = albums[index];
        final artist = kv.key.$1;
        final album = kv.key.$2;
        final tracks = kv.value;
        // Pick the first track that has a local cover extracted.
        final coverEntry = tracks.firstWhere(
          (e) => e.coverPath != null,
          orElse: () => tracks.first,
        );
        return _AlbumTile(
          artist: artist,
          album: album,
          tracks: tracks,
          coverEntry: coverEntry,
          onLongPress: () => setState(() {
            _selected.addAll(tracks.map((e) => e.path));
            _segment = 0;
          }),
          onTap: () => context.push(
            '/library/album',
            extra: LibraryAlbumRouteArgs(artistName: artist, albumName: album),
          ),
        );
      },
    );
  }

  Widget _buildSinglesView(List<LibraryEntry> entries) {
    final singles = entries.where((e) => e.albumName == null).toList();
    if (singles.isEmpty) {
      return const Center(child: SizedBox.shrink());
    }
    return ListView.builder(
      itemCount: singles.length,
      itemBuilder: (context, index) => _trackTile(context, singles[index]),
    );
  }
}

// ---------------------------------------------------------------------------
// Album cover grid tile
// ---------------------------------------------------------------------------

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.artist,
    required this.album,
    required this.tracks,
    required this.coverEntry,
    required this.onTap,
    this.onLongPress,
  });

  final String artist;
  final String album;
  final List<LibraryEntry> tracks;
  final LibraryEntry coverEntry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final coverPath = coverEntry.coverPath;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: coverPath != null
                  ? Image.file(
                      File(coverPath),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _coverPlaceholder(cs),
                    )
                  : _coverPlaceholder(cs),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (artist.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                    style: AppText.badge.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerHigh,
    child: Center(
      child: Icon(
        Icons.album_outlined,
        size: 36,
        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    ),
  );
}
