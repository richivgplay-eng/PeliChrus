enum ContentKind { movie, series }

class ContentItem {
  const ContentItem({
    required this.id,
    required this.title,
    required this.year,
    required this.kind,
    required this.genres,
    required this.score,
    this.popularity = 0,
    required this.keywords,
    required this.franchises,
    required this.overview,
    required this.posterAccent,
    required this.posterEmoji,
    this.posterPath,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final int year;
  final ContentKind kind;
  final List<String> genres;
  final double score;
  final double popularity;
  final List<String> keywords;
  final List<String> franchises;
  final String overview;
  final int posterAccent;
  final String posterEmoji;
  final String? posterPath;
  final bool isFavorite;

  String get contentTypeLabel => kind == ContentKind.movie ? 'Película' : 'Serie';
  String? get posterUrl => posterPath == null
      ? null
      : 'https://image.tmdb.org/t/p/w500$posterPath';

  @override
  String toString() => '$title ($year)';
}
