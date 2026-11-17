import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/track.dart';
import '../utils/service_track_link.dart';
import '../theme/app_tokens.dart';
import 'preview_button.dart';

enum TrackDownloadState { idle, queued, active, done, failed }

/// A branded list-row widget for a single search result track.
///
/// [qualityHint] is optional: `null` renders no badge; non-null renders a pill
/// badge with neutral mono styling.
///
/// Multi-select support:
/// - [selectionMode] when true, shows a checkbox instead of cover art and hides
///   the download button. The whole row tap calls [onSelectToggle].
/// - [selected] the checked state of the checkbox (only used when [selectionMode]).
/// - [onLongPress] called when the user long-presses the tile in normal mode.
/// - [onSelectToggle] called when the user taps the tile in selection mode.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onDownload,
    this.qualityHint,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelectToggle,
    this.downloadState = TrackDownloadState.idle,
    this.onArtistTap,
    this.onAlbumTap,
    this.showPreview = true,
    this.downloaded = false,
    this.onCopyLink,
  });

  final VoidCallback? onCopyLink;
  final Track track;
  final bool downloaded;
  final VoidCallback onDownload;
  final String? qualityHint;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;
  final TrackDownloadState downloadState;

  /// Called when the artist name is tapped. Only wired into a tappable span
  /// when non-null AND [track] carries an `artistId`; otherwise the artist
  /// renders as plain text.
  final VoidCallback? onArtistTap;

  /// Called when the album name is tapped. Same gating as [onArtistTap] but on
  /// `albumId`.
  final VoidCallback? onAlbumTap;

  /// When true (default) and the track carries a `preview_url`, a play/pause
  /// preview button is shown before the download button. Hidden in selection
  /// mode. Set false to opt a list out of preview (e.g. offline library rows).
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final link = serviceTrackLink(track);
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final tt = Theme.of(context).textTheme;

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Leading: checkbox in selection mode, cover art otherwise
          if (selectionMode)
            Checkbox(value: selected, onChanged: (_) => onSelectToggle?.call())
          else
            _CoverArt(track: track),
          const SizedBox(width: 12),
          // Title / artists / badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(child: _buildSubtitle(context, cs, tt)),
                    if (downloaded) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message:
                            Localizations.of<AppLocalizations>(
                              context,
                              AppLocalizations,
                            )?.historyDownloaded ??
                            '',
                        child: Icon(
                          Icons.download_done,
                          key: const Key('historyDownloaded'),
                          size: 14,
                          color: cs.primary,
                        ),
                      ),
                    ],
                    if (qualityHint != null) ...[
                      const SizedBox(width: 6),
                      _QualityBadge(
                        label: qualityHint!,
                        tokens: tokens,
                        cs: cs,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Preview button — only when not selecting and a preview exists.
          if (!selectionMode && showPreview && track.hasPreview)
            PreviewButton(track: track),
          // Download button — hidden in selection mode
          if (!selectionMode)
            _DownloadStateIcon(
              downloadState: downloadState,
              onDownload: onDownload,
            ),
          if (!selectionMode && onCopyLink != null && link != null)
            PopupMenuButton<String>(
              onSelected: (_) => onCopyLink!(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).copyServiceLink(serviceTrackLinkName(link)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return InkWell(
      onTap: selectionMode ? onSelectToggle : null,
      onLongPress: selectionMode ? null : onLongPress,
      child: rowContent,
    );
  }

  String get _subtitle {
    final parts = <String>[track.artists];
    if (track.albumName != null && track.albumName!.isNotEmpty) {
      parts.add(track.albumName!);
    }
    return parts.join(' · ');
  }

  // Always tappable when a handler is wired and there's a name: the artist/
  // album ID is resolved on demand if the search result didn't include it.
  bool get _artistTappable => onArtistTap != null && track.artists.isNotEmpty;

  bool get _albumTappable =>
      onAlbumTap != null &&
      track.albumName != null &&
      track.albumName!.isNotEmpty;

  /// Builds the subtitle row. When navigation callbacks are wired and the track
  /// carries the matching IDs, the artist and/or album become tappable
  /// (underlined, accent-coloured) spans; otherwise it stays plain text — so
  /// selection mode and ID-less results render exactly as before.
  Widget _buildSubtitle(BuildContext context, ColorScheme cs, TextTheme tt) {
    final plainStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    if (selectionMode || (!_artistTappable && !_albumTappable)) {
      return Text(
        _subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: plainStyle,
      );
    }

    final linkStyle = tt.bodySmall?.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );
    final hasAlbum = track.albumName != null && track.albumName!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _artistTappable
              ? GestureDetector(
                  key: const Key('trackArtist'),
                  onTap: onArtistTap,
                  child: Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: linkStyle,
                  ),
                )
              : Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: plainStyle,
                ),
        ),
        if (hasAlbum) ...[
          Text(' · ', style: plainStyle),
          Flexible(
            child: _albumTappable
                ? GestureDetector(
                    key: const Key('trackAlbum'),
                    onTap: onAlbumTap,
                    child: Text(
                      track.albumName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: linkStyle,
                    ),
                  )
                : Text(
                    track.albumName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: plainStyle,
                  ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cover art widget: 48x48 rounded-9 with initial-letter fallback
// ---------------------------------------------------------------------------
class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    final fallback = _InitialFallback(name: track.name, tokens: tokens, cs: cs);
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 48,
        height: 48,
        child: track.coverUrl != null && track.coverUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: track.coverUrl!,
                fit: BoxFit.cover,
                // Decode at thumbnail size so a full-res cover URL doesn't
                // chew memory or stall; cached so list rebuilds don't refetch.
                memCacheWidth: 144,
                memCacheHeight: 144,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (ctx, _) => fallback,
                errorWidget: (ctx, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({
    required this.name,
    required this.tokens,
    required this.cs,
  });

  final String name;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: tokens.surface3,
      child: Center(
        child: Text(
          initial,
          style: AppText.section.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download state icon
// ---------------------------------------------------------------------------
class _DownloadStateIcon extends StatelessWidget {
  const _DownloadStateIcon({
    required this.downloadState,
    required this.onDownload,
  });

  final TrackDownloadState downloadState;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (downloadState) {
      TrackDownloadState.idle => IconButton(
        icon: const Icon(Icons.download_outlined),
        onPressed: onDownload,
        tooltip: Localizations.of<AppLocalizations>(
          context,
          AppLocalizations,
        )?.download,
      ),
      TrackDownloadState.queued => Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(Icons.schedule, size: 20, color: cs.onSurfaceVariant),
      ),
      TrackDownloadState.active => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      TrackDownloadState.done => Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(Icons.check_circle_outline, size: 20, color: cs.primary),
      ),
      TrackDownloadState.failed => Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(Icons.error_outline, size: 20, color: cs.error),
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Quality badge pill
// ---------------------------------------------------------------------------
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.label,
    required this.tokens,
    required this.cs,
  });

  final String label;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('qualityBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.surface3,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: tokens.mono
            .merge(AppText.badge)
            .copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
