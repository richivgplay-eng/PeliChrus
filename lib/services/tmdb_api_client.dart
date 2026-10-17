import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/models/search_intent.dart';
import 'package:pelichrus/models/title_details.dart';
import 'package:pelichrus/services/tmdb_config.dart';

class TmdbSearchPage {
  const TmdbSearchPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<ContentItem> items;
  final int page;
  final int totalPages;
  final int totalResults;
}

class TmdbApiException implements Exception {
  const TmdbApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TmdbApiClient {
  TmdbApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<TmdbSearchPage> fetchTrending({String language = 'es-MX'}) async {
    final uri = Uri.parse(
      '${TmdbConfig.apiBaseUrl}/api/trending',
    ).replace(queryParameters: {'language': language});
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const TmdbApiException(
        'No se pudieron cargar las tendencias. Verifica que el backend esté activo.',
      );
    }
    if (response.statusCode != 200) {
      throw _responseException(response);
    }
    return _decodeSearchPage(response.body, fallbackPage: 1);
  }

  Future<TitleDetails> fetchTitleDetails(ContentItem item) async {
    final mediaType = item.kind == ContentKind.movie ? 'movie' : 'tv';
    final tmdbId = item.id.split('-').last;
    final uri = Uri.parse(
      '${TmdbConfig.apiBaseUrl}/api/title/$mediaType/$tmdbId',
    ).replace(queryParameters: const {'region': 'CO', 'language': 'es-MX'});

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const TmdbApiException(
        'No se pudieron cargar los detalles. Verifica que el backend esté activo.',
      );
    }
    if (response.statusCode != 200) {
      var message =
          'El backend respondió con el código ${response.statusCode}.';
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['error'] is String) {
          message = data['error'] as String;
        }
      } on FormatException {
        // Keep the status-based message for a non-JSON response.
      }
      throw TmdbApiException(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TmdbApiException('El backend devolvió detalles no válidos.');
    }
    return TitleDetails.fromJson(decoded);
  }

  static const Map<int, String> _genreNames = {
    28: 'Acción',
    12: 'Aventura',
    16: 'Animación',
    35: 'Comedia',
    80: 'Crimen',
    99: 'Documental',
    18: 'Drama',
    10751: 'Familia',
    14: 'Fantasía',
    36: 'Historia',
    27: 'Terror',
    10402: 'Música',
    9648: 'Misterio',
    10749: 'Romance',
    878: 'Ciencia ficción',
    10770: 'Película de TV',
    53: 'Thriller',
    10752: 'Bélica',
    37: 'Western',
    10759: 'Acción y aventura',
    10762: 'Infantil',
    10763: 'Noticias',
    10764: 'Reality',
    10765: 'Ciencia ficción y fantasía',
    10766: 'Telenovela',
    10767: 'Talk show',
    10768: 'Bélica y política',
  };

  Future<TmdbSearchPage> search({
    required String query,
    required int page,
    required ContentType contentType,
    String? keyword,
    String? channel,
    int? startYear,
    int? endYear,
    String language = 'es-MX',
  }) async {
    final queryParameters = <String, String>{
      'query': query,
      'page': '$page',
      'language': language,
      'type': switch (contentType) {
        ContentType.movie => 'movie',
        ContentType.series => 'tv',
        ContentType.both => 'multi',
      },
    };
    if (keyword != null) {
      queryParameters['keyword'] = keyword;
    }
    if (channel != null) {
      queryParameters['channel'] = channel;
    }
    if (startYear != null) {
      queryParameters['start_year'] = '$startYear';
    }
    if (endYear != null) {
      queryParameters['end_year'] = '$endYear';
    }
    final uri = Uri.parse(
      '${TmdbConfig.apiBaseUrl}/api/search',
    ).replace(queryParameters: queryParameters);

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const TmdbApiException(
        'No se pudo conectar con el backend. Verifica que esté ejecutándose.',
      );
    }

    if (response.statusCode != 200) {
      throw _responseException(response);
    }

    return _decodeSearchPage(response.body, fallbackPage: page);
  }

  TmdbApiException _responseException(http.Response response) {
    var error = 'El backend respondió con el código ${response.statusCode}.';
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['error'] is String) {
        error = data['error'] as String;
      }
    } on FormatException {
      // Keep the status-based message for a non-JSON server response.
    }
    return TmdbApiException(error);
  }

  TmdbSearchPage _decodeSearchPage(
    String body, {
    required int fallbackPage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      throw const TmdbApiException(
        'El backend devolvió una respuesta no válida.',
      );
    }

    final results = decoded['results'] as List<dynamic>;
    final items = <ContentItem>[];
    final seen = <String>{};
    for (final result in results) {
      if (result is! Map<String, dynamic>) {
        continue;
      }
      final item = _mapItem(result);
      if (item != null && seen.add(item.id)) {
        items.add(item);
      }
    }

    return TmdbSearchPage(
      items: items,
      page: _asInt(decoded['page']) ?? fallbackPage,
      totalPages: _asInt(decoded['total_pages']) ?? fallbackPage,
      totalResults: _asInt(decoded['total_results']) ?? items.length,
    );
  }

  ContentItem? _mapItem(Map<String, dynamic> data) {
    final mediaType = data['media_type'];
    final kind = switch (mediaType) {
      'movie' => ContentKind.movie,
      'tv' => ContentKind.series,
      _ => null,
    };
    final tmdbId = _asInt(data['id']);
    final title = (data['title'] ?? data['name']) as String?;
    if (kind == null ||
        tmdbId == null ||
        title == null ||
        title.trim().isEmpty) {
      return null;
    }

    final dateValue = data['release_date'] ?? data['first_air_date'];
    final year = dateValue is String && dateValue.length >= 4
        ? int.tryParse(dateValue.substring(0, 4)) ?? 0
        : 0;
    final genreIds = data['genre_ids'];
    final genres = genreIds is List
        ? genreIds
              .map(_asInt)
              .whereType<int>()
              .map((id) => _genreNames[id])
              .whereType<String>()
              .toList()
        : <String>[];
    final posterPath = data['poster_path'] as String?;
    final overview = data['overview'] as String?;
    final voteAverage = data['vote_average'];
    final score = voteAverage is num ? voteAverage.toDouble() : 0.0;
    final popularityValue = data['popularity'];
    final popularity = popularityValue is num
        ? popularityValue.toDouble()
        : 0.0;

    return ContentItem(
      id: '${kind.name}-$tmdbId',
      title: title.trim(),
      year: year,
      kind: kind,
      genres: genres,
      score: score,
      popularity: popularity,
      keywords: const [],
      franchises: const [],
      overview: overview ?? '',
      posterAccent: 0xFF483C67,
      posterEmoji: kind == ContentKind.movie ? '🎬' : '📺',
      posterPath: posterPath,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
