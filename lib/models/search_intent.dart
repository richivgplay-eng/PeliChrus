enum ContentType { movie, series, both }
enum SearchOrder { relevant, popularity, newest, oldest }

class SearchIntent {
  const SearchIntent({
    required this.originalQuery,
    required this.normalizedQuery,
    required this.contentType,
    required this.genres,
    required this.keywords,
    required this.franchises,
    required this.channel,
    required this.startYear,
    required this.endYear,
    required this.order,
    required this.title,
    required this.preferences,
    required this.generalTextSearch,
    required this.isReferenceSearch,
    this.periodLabel,
  });

  final String originalQuery;
  final String normalizedQuery;
  final ContentType contentType;
  final List<String> genres;
  final List<String> keywords;
  final List<String> franchises;
  final String? channel;
  final int? startYear;
  final int? endYear;
  final SearchOrder order;
  final String? title;
  final Map<String, bool> preferences;
  final bool generalTextSearch;
  final bool isReferenceSearch;
  final String? periodLabel;

  bool get hasFilters =>
      genres.isNotEmpty ||
      keywords.isNotEmpty ||
      franchises.isNotEmpty ||
      channel != null ||
      startYear != null ||
      endYear != null ||
      title != null;

  @override
  String toString() {
    return 'SearchIntent(' 
        'contentType: $contentType, '
        'genres: $genres, '
        'keywords: $keywords, '
        'franchises: $franchises, '
        'channel: $channel, '
        'title: $title, '
        'period: $startYear-$endYear, '
        'order: $order)';
  }
}
