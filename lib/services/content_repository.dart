import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/models/search_intent.dart';
import 'package:pelichrus/models/title_details.dart';
import 'package:pelichrus/services/tmdb_api_client.dart';

class ContentRepository {
  ContentRepository({TmdbApiClient? apiClient})
    : _catalog = _buildCatalog(),
      _apiClient = apiClient ?? TmdbApiClient();

  final List<ContentItem> _catalog;
  final TmdbApiClient _apiClient;
  final Map<String, TmdbSearchPage> _cache = {};
  final Map<String, Future<TitleDetails>> _detailsCache = {};

  Future<List<ContentItem>> fetchTrending() async {
    final response = await _apiClient.fetchTrending();
    return response.items;
  }
  List<ContentItem> get movies =>
      _catalog.where((item) => item.kind == ContentKind.movie).toList();
  List<ContentItem> get series =>
      _catalog.where((item) => item.kind == ContentKind.series).toList();

  Future<TmdbSearchPage> search({
    required SearchIntent intent,
    int page = 1,
  }) async {
    final key =
        '${intent.normalizedQuery}|${intent.contentType.name}|${intent.channel}|$page';
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    final searchQuery = _queryFor(intent);
    final response = await _apiClient.search(
      query: searchQuery,
      page: page,
      contentType: intent.contentType,
      keyword: _keywordFor(intent),
      channel: intent.channel,
      startYear: intent.startYear,
      endYear: intent.endYear,
    );
    final filtered = response.items.where((item) {
      if (intent.channel == null &&
          intent.contentType == ContentType.movie &&
          item.kind != ContentKind.movie) {
        return false;
      }
      if (intent.channel == null &&
          intent.contentType == ContentType.series &&
          item.kind != ContentKind.series) {
        return false;
      }
      if (intent.startYear != null &&
          item.year != 0 &&
          item.year < intent.startYear!) {
        return false;
      }
      if (intent.endYear != null &&
          item.year != 0 &&
          item.year > intent.endYear!) {
        return false;
      }
      return true;
    }).toList();

    final ordered = _sort(filtered, intent.order);
    final searchPage = TmdbSearchPage(
      items: ordered,
      page: response.page,
      totalPages: response.totalPages,
      totalResults: response.totalResults,
    );
    _cache[key] = searchPage;
    return searchPage;
  }

  Future<TitleDetails> detailsFor(ContentItem item) async {
    final cached = _detailsCache[item.id];
    if (cached != null) {
      return cached;
    }
    final request = _apiClient.fetchTitleDetails(item);
    _detailsCache[item.id] = request;
    try {
      return await request;
    } on Exception {
      _detailsCache.remove(item.id);
      rethrow;
    }
  }

  static String _queryFor(SearchIntent intent) {
    if (intent.channel != null) {
      return switch (intent.channel) {
        'fox_kids' => 'fox kids',
        'cartoon_network' => 'cartoon network',
        'boomerang' => 'boomerang',
        'warner' => 'Warner',
        'nickelodeon' => 'Nickelodeon',
        'disney_channel' => 'Disney Channel',
        'hbo' => 'HBO',
        'netflix' => 'Netflix',
        'tnt' => 'TNT',
        _ => intent.originalQuery,
      };
    }
    if (intent.franchises.isNotEmpty) {
      return intent.franchises.join(' ');
    }
    if (intent.isReferenceSearch &&
        intent.title != null &&
        intent.title!.trim().isNotEmpty) {
      return intent.title!.trim();
    }
    if (intent.keywords.isNotEmpty) {
      return intent.keywords.join(' ');
    }
    if (intent.genres.isNotEmpty) {
      return intent.genres.join(' ');
    }
    if (intent.title != null && intent.title!.trim().isNotEmpty) {
      return intent.title!.trim();
    }
    return intent.originalQuery;
  }

  static String? _keywordFor(SearchIntent intent) {
    switch (intent.channel) {
      case 'fox_kids':
      case 'cartoon_network':
      case 'boomerang':
        return 'cartoon|animation|children';
      case 'nickelodeon':
      case 'disney_channel':
        return null;
      case 'warner':
        return 'drama|comedy';
      case 'hbo':
      case 'netflix':
      case 'tnt':
      case null:
        break;
    }
    if (intent.franchises.isNotEmpty || intent.keywords.isEmpty) {
      return null;
    }
    return switch (intent.keywords.first) {
      'desastres naturales' => 'natural disaster',
      'princesas' => 'princess',
      'familia' => 'family',
      'terror' => 'horror',
      'marvel' => 'marvel',
      'disney' => 'disney',
      'ciencia ficción' => 'science fiction',
      'superhéroes' => 'superhero',
      'dinosaurio' => 'dinosaur',
      'comedia' => 'comedy',
      'para llorar' => 'tearjerker|emotional',
      'para reflexionar' => 'philosophical|thought provoking',
      'anime' => 'anime',
      'comiquitas de los 90' => 'cartoon|animation',
      _ => null,
    };
  }

  static List<ContentItem> _sort(List<ContentItem> items, SearchOrder order) {
    final sorted = [...items];
    switch (order) {
      case SearchOrder.popularity:
        sorted.sort((a, b) => b.popularity.compareTo(a.popularity));
      case SearchOrder.relevant:
        return items;
      case SearchOrder.newest:
        sorted.sort((a, b) => b.year.compareTo(a.year));
      case SearchOrder.oldest:
        sorted.sort((a, b) => a.year.compareTo(b.year));
    }
    return sorted;
  }

  static List<ContentItem> _buildCatalog() {
    return const [
      ContentItem(
        id: 'm1',
        title: 'Interstellar',
        year: 2014,
        kind: ContentKind.movie,
        genres: ['Ciencia ficción', 'Drama'],
        score: 8.7,
        keywords: ['desastres naturales', 'espacio', 'ciencia ficción'],
        franchises: ['Original'],
        overview: 'Aventura espacial y exploración del futuro.',
        posterAccent: 0xFF5C6BC0,
        posterEmoji: '🚀',
      ),
      ContentItem(
        id: 'm2',
        title: 'The Day After Tomorrow',
        year: 2004,
        kind: ContentKind.movie,
        genres: ['Desastres', 'Acción'],
        score: 6.1,
        keywords: ['desastres naturales', 'cataclismo'],
        franchises: ['Original'],
        overview:
            'Un cambio climático extremo desencadena una catástrofe global.',
        posterAccent: 0xFF26A69A,
        posterEmoji: '🌪️',
      ),
      ContentItem(
        id: 'm3',
        title: 'The Lion King',
        year: 1994,
        kind: ContentKind.movie,
        genres: ['Familia', 'Animación'],
        score: 8.5,
        keywords: ['familia', 'princesas', 'disney'],
        franchises: ['Disney'],
        overview: 'El rey de la sabana vive un drama épico cargado de emoción.',
        posterAccent: 0xFFE65100,
        posterEmoji: '🦁',
      ),
      ContentItem(
        id: 'm4',
        title: 'Guardians of the Galaxy',
        year: 2014,
        kind: ContentKind.movie,
        genres: ['Acción', 'Ciencia ficción'],
        score: 8.0,
        keywords: ['marvel', 'superhéroes', 'ciencia ficción'],
        franchises: ['Marvel'],
        overview:
            'Un grupo inusual de héroes salva la galaxia con energía y humor.',
        posterAccent: 0xFFD81B60,
        posterEmoji: '🛸',
      ),
      ContentItem(
        id: 'm5',
        title: 'Jurassic World',
        year: 2015,
        kind: ContentKind.movie,
        genres: ['Aventura', 'Acción'],
        score: 7.0,
        keywords: ['dinosaurios', 'aventura'],
        franchises: ['Universal'],
        overview: 'Un parque jurásico regresa con nuevas amenazas.',
        posterAccent: 0xFF4CAF50,
        posterEmoji: '🦖',
      ),
      ContentItem(
        id: 's1',
        title: 'The Mandalorian',
        year: 2019,
        kind: ContentKind.series,
        genres: ['Ciencia ficción', 'Aventura'],
        score: 8.4,
        keywords: ['star wars', 'fantasía', 'espacio'],
        franchises: ['Star Wars'],
        overview: 'Un cazarrecompensas atraviesa la frontera del universo.',
        posterAccent: 0xFF9C27B0,
        posterEmoji: '🪐',
      ),
      ContentItem(
        id: 's2',
        title: 'Loki',
        year: 2021,
        kind: ContentKind.series,
        genres: ['Superhéroes', 'Drama'],
        score: 8.2,
        keywords: ['marvel', 'superhéroes', 'tiempo'],
        franchises: ['Marvel'],
        overview: 'La historia del dios del engaño toma un giro inesperado.',
        posterAccent: 0xFF607D8B,
        posterEmoji: '⌛',
      ),
      ContentItem(
        id: 's3',
        title: 'The Owl House',
        year: 2020,
        kind: ContentKind.series,
        genres: ['Animación', 'Familia'],
        score: 8.1,
        keywords: ['familia', 'fantasía', 'animación'],
        franchises: ['Disney'],
        overview:
            'Una adolescente descubre un mundo mágico en pleno crecimiento.',
        posterAccent: 0xFF7E57C2,
        posterEmoji: '🦉',
      ),
      ContentItem(
        id: 's4',
        title: 'Wednesday',
        year: 2022,
        kind: ContentKind.series,
        genres: ['Thriller', 'Comedia'],
        score: 8.3,
        keywords: ['familia', 'misterio', 'dramática'],
        franchises: ['Original'],
        overview:
            'Una estudiante peculiar intenta resolver enigmas de su escuela.',
        posterAccent: 0xFF37474F,
        posterEmoji: '🕷️',
      ),
      ContentItem(
        id: 'm6',
        title: 'Inside Out',
        year: 2015,
        kind: ContentKind.movie,
        genres: ['Animación', 'Familia'],
        score: 8.1,
        keywords: ['familia', 'animación', 'emociones'],
        franchises: ['Pixar'],
        overview:
            'Las emociones de una niña se vuelven protagonistas en una historia brillante.',
        posterAccent: 0xFFFFC107,
        posterEmoji: '🎨',
      ),
      ContentItem(
        id: 'm7',
        title: 'Shrek',
        year: 2001,
        kind: ContentKind.movie,
        genres: ['Comedia', 'Familia'],
        score: 7.9,
        keywords: ['familia', 'princesas', 'comedia'],
        franchises: ['DreamWorks'],
        overview:
            'Un ogro se convierte en el centro de una aventura ligera y divertida.',
        posterAccent: 0xFF4DB6AC,
        posterEmoji: '🧚',
      ),
    ];
  }
}
