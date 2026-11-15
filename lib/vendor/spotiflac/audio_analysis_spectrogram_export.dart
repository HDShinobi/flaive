// LOCAL ADDITION (see SYNC.md): adapted from Mornye @ 0afdacae.
part of 'audio_analysis_widget.dart';

final _invalidExportNameChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

/// The file name stem for a saved spectrogram: [exportName] when it has
/// one, otherwise the audio file's name without its extension. Content and
/// network URIs use their decoded last path segment.
String audioSpectrogramExportBaseName(String filePath, {String? exportName}) {
  String sanitize(String value) => value
      .replaceAll(_invalidExportNameChars, '_')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '');

  final named = sanitize(exportName ?? '');
  if (named.isNotEmpty) return named;

  var name = filePath;
  final uri = Uri.tryParse(filePath);
  // One-letter schemes are Windows drive letters, not URIs.
  if (uri != null && uri.scheme.length > 1) {
    name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  }
  // SAF document IDs keep their folders after decoding ("primary:Music/a").
  name = name.split(RegExp(r'[/\\:]')).last;
  final dot = name.lastIndexOf('.');
  final stem = sanitize(dot > 0 ? name.substring(0, dot) : name);
  return stem.isEmpty ? 'audio' : stem;
}

/// Draws the spectrogram as the card shows it (axes, grid and the dBFS
/// legend) under a [title] and sample-rate details, and encodes it as PNG at 2x.
/// [duration] supplies the real time axis; [channel] is zero-based when present.
Future<Uint8List> renderAudioSpectrogramPng({
  required ui.Image spectrogram,
  required String title,
  required int sampleRate,
  int? channel,
  double duration = 0,
}) async {
  // Own a handle before the first await: rescan/dispose may release the card's.
  final image = spectrogram.clone();
  try {
    const scale = 2.0;
    final details = [
      '$sampleRate Hz',
      '${(sampleRate / 2000).toStringAsFixed(1)} kHz Nyquist',
      if (channel != null && channel >= 0) 'Ch ${channel + 1}',
    ];
    const labelColor = Color(0xFFB5B5B5);
    const padding = 16.0;
    const plotWidth = 800.0;
    const plotHeight = plotWidth / 2;
    const legendHeight = 8.0;
    const chartWidth = _SpectrogramPainter.leftGutter + plotWidth;
    const chartHeight = plotHeight + _SpectrogramPainter.bottomGutter;

    TextPainter text(String value, TextStyle style) => TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: chartWidth);

    final titlePainter = text(
      title,
      const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    final detailsPainter = text(
      details.join('   '),
      const TextStyle(color: labelColor, fontSize: 11),
    );
    const legendStyle = TextStyle(color: labelColor, fontSize: 10);
    final minLabel = text('-120 dBFS', legendStyle);
    final maxLabel = text('0 dBFS', legendStyle);

    final chartTop =
        padding + titlePainter.height + 4 + detailsPainter.height + 12;
    final legendTop = chartTop + chartHeight + 10;
    final legendRowHeight = math.max(legendHeight, minLabel.height);
    final width = padding * 2 + chartWidth;
    final height = legendTop + legendRowHeight + padding;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.black,
    );
    titlePainter.paint(canvas, const Offset(padding, padding));
    detailsPainter.paint(
      canvas,
      Offset(padding, padding + titlePainter.height + 4),
    );

    canvas.save();
    canvas.translate(padding, chartTop);
    _SpectrogramPainter(
      image: image,
      maxFreqHz: sampleRate / 2,
      durationSec: duration,
      labelColor: labelColor,
      gridColor: Colors.white.withValues(alpha: 0.10),
    ).paint(canvas, const Size(chartWidth, chartHeight));
    canvas.restore();

    final barLeft = padding + _SpectrogramPainter.leftGutter;
    final barStart = barLeft + minLabel.width + 8;
    final barEnd = padding + chartWidth - maxLabel.width - 8;
    final rowCenter = legendTop + legendRowHeight / 2;
    minLabel.paint(canvas, Offset(barLeft, rowCenter - minLabel.height / 2));
    maxLabel.paint(canvas, Offset(barEnd + 8, rowCenter - maxLabel.height / 2));
    final bar = Rect.fromLTRB(
      barStart,
      rowCenter - legendHeight / 2,
      barEnd,
      rowCenter + legendHeight / 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: _SpectrogramView._legendColors(),
        ).createShader(bar),
    );

    final picture = recorder.endRecording();
    final ui.Image rendered;
    try {
      rendered = await picture.toImage(
        (width * scale).round(),
        (height * scale).round(),
      );
    } finally {
      picture.dispose();
      titlePainter.dispose();
      detailsPainter.dispose();
      minLabel.dispose();
      maxLabel.dispose();
    }
    try {
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Could not encode the spectrogram image');
      }
      return bytes.buffer.asUint8List();
    } finally {
      rendered.dispose();
    }
  } finally {
    image.dispose();
  }
}
