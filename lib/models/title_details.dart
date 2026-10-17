class TrailerInfo {
  const TrailerInfo({
    required this.name,
    required this.key,
    required this.type,
    required this.official,
    required this.language,
  });

  final String name;
  final String key;
  final String type;
  final bool official;
  final String language;

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$key';
}

class WatchProvider {
  const WatchProvider({required this.name, this.logoPath});

  final String name;
  final String? logoPath;
}

class TitleDetails {
  const TitleDetails({
    required this.overview,
    required this.genres,
    required this.trailers,
    required this.streaming,
    required this.rent,
    required this.buy,
    required this.region,
    required this.watchLink,
    this.runtime,
    this.releaseDate,
  });

  final String overview;
  final List<String> genres;
  final List<TrailerInfo> trailers;
  final List<WatchProvider> streaming;
  final List<WatchProvider> rent;
  final List<WatchProvider> buy;
  final String region;
  final String? watchLink;
  final int? runtime;
  final String? releaseDate;

  TrailerInfo? get preferredTrailer {
    for (final trailer in trailers) {
      if (trailer.type == 'Trailer' &&
          trailer.official &&
          trailer.language == 'es') {
        return trailer;
      }
    }
    for (final trailer in trailers) {
      if (trailer.type == 'Trailer' && trailer.official) {
        return trailer;
      }
    }
    for (final trailer in trailers) {
      if (trailer.type == 'Trailer') {
        return trailer;
      }
    }
    return trailers.isEmpty ? null : trailers.first;
  }

  factory TitleDetails.fromJson(Map<String, dynamic> json) {
    final providers = json['providers'] is Map<String, dynamic>
        ? json['providers'] as Map<String, dynamic>
        : const <String, dynamic>{};

    List<WatchProvider> parseProviders(Object? value) {
      if (value is! List) {
        return const [];
      }
      return value
          .whereType<Map<String, dynamic>>()
          .map(
            (provider) => WatchProvider(
              name: provider['provider_name'] as String? ?? '',
              logoPath: provider['logo_path'] as String?,
            ),
          )
          .where((provider) => provider.name.isNotEmpty)
          .toList();
    }

    final videoJson = json['videos'];
    final videos = videoJson is List
        ? videoJson.whereType<Map<String, dynamic>>()
        : const <Map<String, dynamic>>[];

    return TitleDetails(
      overview: json['overview'] as String? ?? '',
      genres: json['genres'] is List
          ? (json['genres'] as List).whereType<String>().toList()
          : const [],
      trailers: videos
          .where((video) => video['key'] is String && video['name'] is String)
          .map(
            (video) => TrailerInfo(
              name: video['name'] as String,
              key: video['key'] as String,
              type: video['type'] as String? ?? '',
              official: video['official'] == true,
              language: video['language'] as String? ?? '',
            ),
          )
          .toList(),
      streaming: parseProviders(providers['flatrate']),
      rent: parseProviders(providers['rent']),
      buy: parseProviders(providers['buy']),
      region: providers['region'] as String? ?? 'CO',
      watchLink: providers['link'] as String?,
      runtime: _asInt(json['runtime']),
      releaseDate: json['release_date'] as String?,
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
