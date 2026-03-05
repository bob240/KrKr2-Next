/// A single scraping result candidate (e.g. from VNDB).
/// Used for search list display and cover download.
class GameMetadataCandidate {
  const GameMetadataCandidate({
    required this.title,
    required this.coverImageUrl,
    this.sourceId,
    this.sourceLabel,
  });

  final String title;
  final String coverImageUrl;
  final String? sourceId;
  final String? sourceLabel;
}
