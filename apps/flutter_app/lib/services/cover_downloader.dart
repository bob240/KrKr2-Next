import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/game_metadata_candidate.dart';

/// Downloads cover image from URL to app documents/covers/.
/// Returns local file path or null on failure.
class CoverDownloader {
  final http.Client _client = http.Client();

  /// Download cover for [candidate] to covers/<source>_<sourceId>.<ext>.
  /// Returns the local path, or null if download fails.
  Future<String?> downloadCover(GameMetadataCandidate candidate) async {
    if (candidate.coverImageUrl.isEmpty) return null;

    final uri = Uri.tryParse(candidate.coverImageUrl);
    if (uri == null || !uri.hasScheme) return null;

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${dir.path}/covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final source = (candidate.sourceLabel ?? 'scrape')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final sourceId = candidate.sourceId ?? '${candidate.title.hashCode}';
      final ext = _extensionFromUri(uri) ?? _extensionFromContentType(
          response.headers['content-type']) ?? 'jpg';
      final safeId = sourceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = '${source}_$safeId.$ext';
      final filePath = '${coversDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  static String? _extensionFromUri(Uri uri) {
    final path = uri.path;
    if (path.isEmpty) return null;
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return null;
  }

  static String? _extensionFromContentType(String? contentType) {
    if (contentType == null) return null;
    final lower = contentType.toLowerCase();
    if (lower.contains('jpeg') || lower.contains('jpg')) return 'jpg';
    if (lower.contains('png')) return 'png';
    if (lower.contains('webp')) return 'webp';
    return null;
  }
}
