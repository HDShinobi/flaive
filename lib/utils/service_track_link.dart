import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/track.dart';

const _hosts = {
  'spotify': 'open.spotify.com',
  'tidal': 'listen.tidal.com',
  'qobuz': 'play.qobuz.com',
  'deezer': 'www.deezer.com',
};
final _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');

/// Use catalog identity, never the service that delivered the audio file.
/// Unknown extension ids do not imply a streaming catalog. Amazon is omitted.
Uri? serviceTrackLink(Track t) {
  final raw = t.id.trim();
  final source = t.source?.trim().toLowerCase() ?? '';
  String? service;
  var id = raw;
  for (final name in _hosts.keys) {
    if (raw.startsWith('$name:')) {
      service = name;
      id = raw.substring(name.length + 1);
      // Upstream also accepts spotify:track:ID.
      if (name == 'spotify' &&
          id.startsWith('track:') &&
          _spotifyId.hasMatch(id.substring(6))) {
        id = id.substring(6);
      }
      break;
    }
  }
  service ??= _spotifyId.hasMatch(raw)
      ? 'spotify'
      : _hosts.containsKey(source)
      ? source
      : null;
  if (service != null &&
      id.isNotEmpty &&
      !id.contains('/') &&
      !id.contains(':')) {
    return Uri.https(_hosts[service]!, '/track/$id');
  }
  final deezer = t.deezerId?.trim() ?? '';
  if (RegExp(r'^\d+$').hasMatch(deezer)) {
    return Uri.https(_hosts['deezer']!, '/track/$deezer');
  }
  return null;
}

String serviceTrackLinkName(Uri link) => switch (link.host) {
  'listen.tidal.com' => 'Tidal',
  'play.qobuz.com' => 'Qobuz',
  'www.deezer.com' => 'Deezer',
  _ => 'Spotify',
};

Future<void> copyServiceTrackLink(BuildContext context, Track track) async {
  final link = serviceTrackLink(track);
  if (link == null) return;
  await Clipboard.setData(ClipboardData(text: link.toString()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppLocalizations.of(
          context,
        ).copiedServiceLink(serviceTrackLinkName(link)),
      ),
    ),
  );
}
