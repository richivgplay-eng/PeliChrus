import 'models/search_intent.dart';

class QueryInterpreter {
  static final Map<String, List<String>> _genreAliases = {
    'terror': ['terror', 'horror', 'miedo'],
    'comedia': ['comedia', 'humor', 'cómico', 'comica'],
    'ciencia ficción': ['ciencia ficcion', 'ciencia ficción', 'sci fi', 'sf'],
    'acción': ['accion', 'acción', 'action'],
    'animación': ['animacion', 'animación', 'cartoon'],
    'aventura': ['aventura', 'adventure'],
    'fantasía': ['fantasia', 'fantasía', 'fantasy'],
    'drama': ['drama', 'dramatic'],
    'familia': ['familia', 'family'],
    'romance': ['romance', 'romántica'],
    'documental': ['documental', 'documentary'],
    'thriller': ['thriller', 'suspenso'],
    'superhéroes': ['superheroes', 'superhéroes', 'superhero'],
  };

  static final Map<String, List<String>> _franchiseAliases = {
    'marvel': ['marvel', 'avengers', 'guardians', 'spider man', 'iron man'],
    'disney': ['disney', 'clasicos de disney', 'clásicos de disney'],
    'pixar': ['pixar'],
    'star wars': ['star wars', 'la guerra de las galaxias'],
    'harry potter': ['harry potter'],
  };

  static const Map<String, List<String>> _keywordThemes = {
    'desastres naturales': ['desastres naturales'],
    'princesas': ['princesas', 'princesa'],
    'familia': ['familia', 'en familia'],
    'terror': ['terror', 'miedo'],
    'marvel': ['marvel'],
    'disney': ['disney'],
    'ciencia ficción': ['ciencia ficción', 'ciencia ficcion'],
    'superhéroes': ['superhéroes', 'superheroes', 'superheroe', 'superheroes'],
    'dinosaurio': ['dinosaurio', 'dinosaurios'],
    'anime': ['anime', 'animes', 'anime en español', 'anime en espanol'],
    'comiquitas de los 90': [
      'comiquitas',
      'caricaturas',
      'dibujos animados',
      'cartoons',
    ],
    'comedia': [
      'comedia',
      'comedias',
      'humor',
      'graciosas',
      'divertidas',
      'para reir',
      'que te hagan reir',
    ],
    'para llorar': [
      'para llorar',
      'que hagan llorar',
      'que te hagan llorar',
      'que me hagan llorar',
      'tristes',
      'tearjerker',
    ],
    'para reflexionar': [
      'para reflexionar',
      'que hagan reflexionar',
      'que te hagan reflexionar',
      'que te hagan pensar',
      'para pensar',
      'reflexivas',
      'profundas',
    ],
  };

  static const Map<String, List<String>> _channelAliases = {
    'fox_kids': [
      'fox kids',
      'fox kid',
      'foxkid',
      'fox kids latinoamerica',
    ],
    'tnt': ['tnt', 'turner network television'],
    'cartoon_network': ['cartoon network', 'cartoonnetwork'],
    'boomerang': ['boomerang'],
    'warner': ['warner', 'warner bros', 'the wb', 'wb network'],
    'nickelodeon': ['nickelodeon', 'nick'],
    'disney_channel': ['disney channel'],
    'hbo': ['hbo'],
    'netflix': ['netflix'],
  };

  static SearchIntent interpret(String rawQuery) {
    final original = rawQuery.trim();
    final normalized = _normalize(original);
    final hasMovieIntent = _containsAny(normalized, [
      'pelicula',
      'películas',
      'pelicula y serie',
      'movie',
      'movies',
      'filme',
      'films',
    ]);
    final hasSeriesIntent = _containsAny(normalized, [
      'serie',
      'series',
      'show',
      'shows',
      'programa',
      'programas',
      'comiquita',
      'caricatura',
      'dibujo animado',
    ]);
    final hasBothIntent = _containsAny(normalized, [
      'y series',
      'y peliculas',
      'películas y series',
      'peliculas y series',
      'series y peliculas',
      'series y películas',
    ]);

    ContentType contentType;
    if (hasBothIntent || (!hasMovieIntent && !hasSeriesIntent)) {
      contentType = ContentType.both;
    } else if (hasMovieIntent && !hasSeriesIntent) {
      contentType = ContentType.movie;
    } else if (hasSeriesIntent && !hasMovieIntent) {
      contentType = ContentType.series;
    } else {
      contentType = ContentType.both;
    }

    final genres = _extractGenres(normalized);
    final keywords = _extractKeywords(normalized);
    final franchises = _extractFranchises(normalized);
    final channel = _extractChannel(normalized);
    final years = _extractYears(normalized);
    final title = _extractTitle(normalized);
    final order = _extractOrder(normalized);
    final preferences = _extractPreferences(normalized);

    return SearchIntent(
      originalQuery: original,
      normalizedQuery: normalized,
      contentType: contentType,
      genres: genres,
      keywords: keywords,
      franchises: franchises,
      channel: channel,
      startYear: years.$1,
      endYear: years.$2,
      order: order,
      title: title,
      preferences: preferences,
      generalTextSearch:
          normalized.isNotEmpty &&
          genres.isEmpty &&
          keywords.isEmpty &&
          franchises.isEmpty &&
          channel == null &&
          title == null,
      isReferenceSearch: _containsAny(normalized, [
        'parecida a',
        'parecidas a',
        'similares a',
        'similar a',
        'como',
      ]),
      periodLabel: _extractPeriodLabel(normalized),
    );
  }

  static String _normalize(String query) {
    var text = query.toLowerCase();
    text = text.replaceAll(RegExp(r'[áàäâ]'), 'a');
    text = text.replaceAll(RegExp(r'[éèëê]'), 'e');
    text = text.replaceAll(RegExp(r'[íìïî]'), 'i');
    text = text.replaceAll(RegExp(r'[óòöô]'), 'o');
    text = text.replaceAll(RegExp(r'[úùüû]'), 'u');
    text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  static bool _containsAny(String text, List<String> terms) {
    return terms.any((term) => text.contains(term));
  }

  static List<String> _extractGenres(String normalized) {
    final found = <String>[];
    for (final entry in _genreAliases.entries) {
      if (_containsAny(normalized, entry.value)) {
        found.add(entry.key);
      }
    }
    return found;
  }

  static List<String> _extractKeywords(String normalized) {
    final found = <String>[];
    for (final entry in _keywordThemes.entries) {
      if (_containsAny(normalized, entry.value.map(_normalize).toList())) {
        found.add(entry.key);
      }
    }
    return found;
  }

  static List<String> _extractFranchises(String normalized) {
    final found = <String>[];
    for (final entry in _franchiseAliases.entries) {
      if (_containsAny(normalized, entry.value)) {
        found.add(entry.key);
      }
    }
    return found;
  }

  static String? _extractChannel(String normalized) {
    for (final entry in _channelAliases.entries) {
      if (_containsAny(normalized, entry.value.map(_normalize).toList())) {
        return entry.key;
      }
    }
    return null;
  }

  static (int? startYear, int? endYear) _extractYears(String normalized) {
    final decadeMatch = RegExp(
      r'\b(?:de los |anos )?(?:19)?(70|80|90)s?\b',
    ).firstMatch(normalized);
    if (decadeMatch != null) {
      final decade = int.parse(decadeMatch.group(1)!);
      return (1900 + decade, 1900 + decade + 9);
    }
    if (_containsAny(normalized, ['noventas', 'noventera', 'noventeras'])) {
      return (1990, 1999);
    }
    if (_containsAny(normalized, ['ochentas', 'ochentera', 'ochenteras'])) {
      return (1980, 1989);
    }

    final latestTenYearsMatch = RegExp(
      r'ultimos?\s*(\d+)\s*anios|ultimos?\s*(\d+)\s*años|ultimos?\s*(\d+)\s*anos',
    );
    final match = latestTenYearsMatch.firstMatch(normalized);
    if (match != null) {
      final value = match.group(1) ?? match.group(2) ?? match.group(3);
      if (value != null) {
        final yearsSpan = int.tryParse(value) ?? 10;
        final currentYear = DateTime.now().year;
        return (currentYear - yearsSpan, currentYear);
      }
    }

    if (normalized.contains('ultimos diez anios') ||
        normalized.contains('ultimos diez años') ||
        normalized.contains('ultimos diez anos')) {
      final currentYear = DateTime.now().year;
      return (currentYear - 10, currentYear);
    }

    if (normalized.contains('clasicos') || normalized.contains('clásicos')) {
      return (1900, 1999);
    }

    return (null, null);
  }

  static String? _extractTitle(String normalized) {
    final match = RegExp(
      r'parecida[s]? a ([a-z0-9 ]+)|similar a ([a-z0-9 ]+)',
    ).firstMatch(normalized);
    if (match != null) {
      final captured = match.group(1) ?? match.group(2);
      if (captured != null && captured.trim().isNotEmpty) {
        final text = captured.trim();
        if (text.length > 2) {
          return text.split(' ').take(3).join(' ');
        }
      }
    }

    final titleMatch = RegExp(
      r'(?:peliculas?|series?)\s+(?:de|sobre|como)?\s*([a-z0-9 ]{3,})',
    ).firstMatch(normalized);
    if (titleMatch != null) {
      final title = titleMatch.group(1)?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
    }

    if (normalized.contains('interstellar')) {
      return 'interstellar';
    }

    return null;
  }

  static SearchOrder _extractOrder(String normalized) {
    if (normalized.contains('populares') ||
        normalized.contains('mas populares')) {
      return SearchOrder.popularity;
    }
    if (normalized.contains('nuevas') ||
        normalized.contains('recientes') ||
        normalized.contains('ultimas')) {
      return SearchOrder.newest;
    }
    if (normalized.contains('antiguas') || normalized.contains('mas viejas')) {
      return SearchOrder.oldest;
    }
    return SearchOrder.popularity;
  }

  static Map<String, bool> _extractPreferences(String normalized) {
    final prefs = <String, bool>{
      'family_friendly':
          normalized.contains('familia') || normalized.contains('en familia'),
      'light':
          normalized.contains('divertido') ||
          normalized.contains('entretenido'),
      'serious': normalized.contains('serio') || normalized.contains('intenso'),
      'adult': normalized.contains('adultos') || normalized.contains('mayores'),
      'short': normalized.contains('rapida') || normalized.contains('corta'),
    };
    return prefs;
  }

  static String? _extractPeriodLabel(String normalized) {
    if (normalized.contains('ultimos diez anios') ||
        normalized.contains('ultimos diez años') ||
        normalized.contains('ultimos diez anos')) {
      return 'Últimos 10 años';
    }
    if (normalized.contains('clasicos') || normalized.contains('clásicos')) {
      return 'Clásicos';
    }
    return null;
  }
}
