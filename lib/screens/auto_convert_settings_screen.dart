import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/download_options_provider.dart';

class AutoConvertSettingsScreen extends ConsumerWidget {
  const AutoConvertSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final enabled = ref.watch(autoConvertDownloadsProvider);
    final format = ref.watch(autoConvertFormatProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.downloadAutoConvert)),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(t.downloadAutoConvert),
            subtitle: Text(t.downloadAutoConvertSubtitle),
            value: enabled,
            onChanged: ref.read(autoConvertDownloadsProvider.notifier).set,
          ),
          if (enabled) ...[
            ListTile(
              title: Text(t.downloadAutoConvertFormat),
              trailing: DropdownButton<String>(
                value: format,
                items: [
                  for (final f in ['flac', 'alac', 'mp3', 'aac', 'opus'])
                    DropdownMenuItem(value: f, child: Text(f.toUpperCase())),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(autoConvertFormatProvider.notifier).set(v);
                  }
                },
              ),
            ),
            if (format == 'flac' || format == 'alac') ...[
              ListTile(
                title: Text(t.downloadAutoConvertMaxBitDepth),
                trailing: DropdownButton<int>(
                  value: ref.watch(autoConvertMaxBitDepthProvider),
                  items: [
                    for (final n in [16, 24, 0])
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          n == 0 ? t.downloadAutoConvertKeepOriginal : '$n bit',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(autoConvertMaxBitDepthProvider.notifier).set(v);
                    }
                  },
                ),
              ),
              ListTile(
                title: Text(t.downloadAutoConvertMaxSampleRate),
                trailing: DropdownButton<int>(
                  value: ref.watch(autoConvertMaxSampleRateProvider),
                  items: [
                    for (final n in [44100, 48000, 96000, 192000, 0])
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          n == 0
                              ? t.downloadAutoConvertKeepOriginal
                              : '${n % 1000 == 0 ? n ~/ 1000 : n / 1000} kHz',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(autoConvertMaxSampleRateProvider.notifier)
                          .set(v);
                    }
                  },
                ),
              ),
            ] else
              ListTile(
                title: Text(t.downloadAutoConvertBitrate),
                trailing: DropdownButton<String>(
                  value: ref.watch(autoConvertBitrateProvider),
                  items: [
                    for (final b in ['128k', '160k', '192k', '256k', '320k'])
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(autoConvertBitrateProvider.notifier).set(v);
                    }
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
