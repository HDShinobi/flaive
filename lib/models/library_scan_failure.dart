/// A file the last library scan could not read, with the reader's reason.
class LibraryScanFailure {
  const LibraryScanFailure({required this.path, required this.message});

  final String path;
  final String message;

  String get fileName {
    var value = path;
    if (value.startsWith('content://')) {
      try {
        final segments = Uri.parse(value).pathSegments;
        if (segments.isNotEmpty) value = segments.last;
      } on FormatException {
        // Keep a malformed URI readable without blocking the failure list.
      }
    }
    return value.replaceAll('\\', '/').split('/').last;
  }
}
