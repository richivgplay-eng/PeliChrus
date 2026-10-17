import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pelichrus/main.dart';
import 'package:pelichrus/models/search_intent.dart';
import 'package:pelichrus/query_interpreter.dart';
import 'package:pelichrus/services/content_repository.dart';
import 'package:pelichrus/services/tmdb_api_client.dart';

void main() {
  testWidgets('PeliChrus opens directly in the Peli assistant', (tester) async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({'page': 1, 'total_pages': 1, 'results': []}),
        200,
      ),
    );
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );
    await tester.pumpWidget(PeliChrusApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
    expect(find.text('Cuéntame qué te apetece ver...'), findsOneWidget);
    expect(find.text('¿Qué te apetece ver hoy?'), findsNothing);
    expect(find.text('Descubrir'), findsNothing);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('Resultados de TMDB'), findsNothing);
  });

  testWidgets('Marvel suggestion searches TMDB through the multi endpoint', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/trending') {
        return http.Response(
          jsonEncode({'page': 1, 'total_pages': 1, 'results': []}),
          200,
        );
      }
      expect(request.url.path, '/api/search');
      expect(request.url.queryParameters['query'], 'marvel');
      expect(request.url.queryParameters['type'], 'multi');
      return http.Response(
        jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 1,
          'results': [
            {
              'id': 999,
              'media_type': 'movie',
              'title': 'Marvel test result',
              'release_date': '2024-01-01',
              'vote_average': 8.0,
              'genre_ids': [28],
              'poster_path': null,
              'overview': 'Test result for the Marvel suggestion.',
            },
          ],
        }),
        200,
      );
    });
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );

    await tester.pumpWidget(PeliChrusApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Marvel'));
    await tester.pumpAndSettle();

    expect(find.text('Marvel test result'), findsOneWidget);
    expect(find.text('1 resultados reportados por TMDB'), findsOneWidget);
  });

  test(
    'superhero searches use related keywords and popular-first order',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/search');
        expect(request.url.queryParameters['query'], 'superhéroes');
        expect(request.url.queryParameters['keyword'], 'superhero');
        expect(request.url.queryParameters['type'], 'multi');
        return http.Response(
          jsonEncode({
            'page': 1,
            'total_pages': 1,
            'total_results': 2,
            'results': [
              {
                'id': 1,
                'media_type': 'movie',
                'title': 'Batman',
                'popularity': 80,
              },
              {
                'id': 2,
                'media_type': 'movie',
                'title': 'Iron Man',
                'popularity': 95,
              },
            ],
          }),
          200,
        );
      });
      final repository = ContentRepository(
        apiClient: TmdbApiClient(client: client),
      );
      final page = await repository.search(
        intent: QueryInterpreter.interpret('superhéroes'),
      );
      expect(page.items.map((item) => item.title), ['Iron Man', 'Batman']);
    },
  );

  test('dinosaur movie searches discover related titles by keyword', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/search');
      expect(request.url.queryParameters['query'], 'dinosaurio');
      expect(request.url.queryParameters['keyword'], 'dinosaur');
      expect(request.url.queryParameters['type'], 'movie');
      return http.Response(
        jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 1,
          'results': [
            {
              'id': 1,
              'media_type': 'movie',
              'title': 'Jurassic Park',
              'popularity': 80,
            },
          ],
        }),
        200,
      );
    });
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );
    final page = await repository.search(
      intent: QueryInterpreter.interpret('películas sobre dinosaurios'),
    );

    expect(page.items.single.title, 'Jurassic Park');
  });

  for (final (query, keyword) in [
    ('películas de comedia', 'comedy'),
    ('películas para llorar', 'tearjerker|emotional'),
    ('películas para reflexionar', 'philosophical|thought provoking'),
  ]) {
    test('$query uses thematic keyword search', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/search');
        expect(request.url.queryParameters['keyword'], keyword);
        expect(request.url.queryParameters['type'], 'movie');
        return http.Response(
          jsonEncode({
            'page': 1,
            'total_pages': 1,
            'total_results': 0,
            'results': [],
          }),
          200,
        );
      });
      final repository = ContentRepository(
        apiClient: TmdbApiClient(client: client),
      );
      await repository.search(intent: QueryInterpreter.interpret(query));
    });
  }

  test(
    'anime and 90s cartoons use thematic discovery and decade filters',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/search');
        if (request.url.queryParameters['keyword'] == 'anime') {
          expect(request.url.queryParameters['query'], 'anime');
          expect(request.url.queryParameters['language'], 'es-MX');
          expect(request.url.queryParameters['type'], 'multi');
        } else {
          expect(request.url.queryParameters['query'], 'comiquitas de los 90');
          expect(request.url.queryParameters['keyword'], 'cartoon|animation');
          expect(request.url.queryParameters['type'], 'tv');
          expect(request.url.queryParameters['start_year'], '1990');
          expect(request.url.queryParameters['end_year'], '1999');
        }
        return http.Response(
          jsonEncode({
            'page': 1,
            'total_pages': 1,
            'total_results': 0,
            'results': [],
          }),
          200,
        );
      });
      final repository = ContentRepository(
        apiClient: TmdbApiClient(client: client),
      );

      await repository.search(
        intent: QueryInterpreter.interpret('anime en español'),
      );
      final cartoonIntent = QueryInterpreter.interpret('comiquitas de los 90');
      expect(cartoonIntent.startYear, 1990);
      expect(cartoonIntent.endYear, 1999);
      expect(cartoonIntent.contentType, ContentType.series);
      await repository.search(intent: cartoonIntent);
    },
  );

  test('Fox Kids and TNT phrases carry channel filters to TMDB', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/search');
      expect(request.url.queryParameters['type'], 'tv');
      if (request.url.queryParameters['channel'] == 'fox_kids') {
        expect(request.url.queryParameters['query'], 'fox kids');
        expect(
          request.url.queryParameters['keyword'],
          'cartoon|animation|children',
        );
      } else {
        expect(request.url.queryParameters['channel'], 'tnt');
        expect(request.url.queryParameters['query'], 'TNT');
        expect(request.url.queryParameters.containsKey('keyword'), false);
      }
      return http.Response(
        jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 0,
          'results': [],
        }),
        200,
      );
    });
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );

    final foxIntent = QueryInterpreter.interpret('comiquitas de Fox Kid');
    expect(foxIntent.channel, 'fox_kids');
    await repository.search(intent: foxIntent);

    final tntIntent = QueryInterpreter.interpret('series de TNT');
    expect(tntIntent.channel, 'tnt');
    await repository.search(intent: tntIntent);
  });

  test(
    'Nickelodeon searches use the network and genres without keyword narrowing',
    () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['channel'], 'nickelodeon');
        expect(request.url.queryParameters['query'], 'Nickelodeon');
        expect(request.url.queryParameters['keyword'], isNull);
        return http.Response(
          jsonEncode({
            'page': 1,
            'total_pages': 1,
            'total_results': 0,
            'results': [],
          }),
          200,
        );
      });
      final repository = ContentRepository(
        apiClient: TmdbApiClient(client: client),
      );
      await repository.search(
        intent: QueryInterpreter.interpret('series de Nickelodeon'),
      );
    },
  );

  test('additional TV channel names are recognized', () {
    const channels = {
      'Series de Cartoon Network': 'cartoon_network',
      'Comiquitas de Boomerang': 'boomerang',
      'Series de Warner': 'warner',
      'Series de Nickelodeon': 'nickelodeon',
      'Series de Disney Channel': 'disney_channel',
      'Series de HBO': 'hbo',
      'Series de Netflix': 'netflix',
    };
    for (final entry in channels.entries) {
      expect(
        QueryInterpreter.interpret(entry.key).channel,
        entry.value,
        reason: entry.key,
      );
    }
  });

  testWidgets(
    'tapping a title opens its details modal with trailer and WhatsApp',
    (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/trending') {
          return http.Response(
            jsonEncode({'page': 1, 'total_pages': 1, 'results': []}),
            200,
          );
        }
        if (request.url.path == '/api/search') {
          return http.Response(
            jsonEncode({
              'page': 1,
              'total_pages': 1,
              'total_results': 1,
              'results': [
                {
                  'id': 123,
                  'media_type': 'movie',
                  'title': 'Movie details test',
                  'release_date': '2024-01-01',
                  'vote_average': 8,
                  'genre_ids': [28],
                  'poster_path': null,
                  'overview': 'Search overview',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/title/movie/123');
        expect(request.url.queryParameters['region'], 'CO');
        return http.Response(
          jsonEncode({
            'overview': 'A detailed overview.',
            'genres': ['Acción', 'Aventura'],
            'runtime': 120,
            'release_date': '2024-01-01',
            'videos': [
              {
                'name': 'Tráiler oficial',
                'key': 'trailer123',
                'type': 'Trailer',
                'official': true,
                'language': 'es',
              },
            ],
            'providers': {
              'region': 'CO',
              'link': 'https://www.themoviedb.org/movie/123-watch',
              'flatrate': [
                {'provider_name': 'Plataforma demo'},
              ],
              'rent': [],
              'buy': [],
            },
          }),
          200,
        );
      });
      final repository = ContentRepository(
        apiClient: TmdbApiClient(client: client),
      );

      await tester.pumpWidget(PeliChrusApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buscar').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'película de prueba');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final movieTitle = find.text('Movie details test').first;
      await tester.ensureVisible(movieTitle);
      await tester.pumpAndSettle();
      await tester.tap(movieTitle);
      await tester.pumpAndSettle();

      expect(find.text('A detailed overview.'), findsOneWidget);
      expect(find.text('Dónde verla en Colombia'), findsOneWidget);
      expect(find.text('Plataforma demo'), findsOneWidget);
      expect(find.text('Consultar por WhatsApp'), findsOneWidget);
      expect(find.textContaining('Tráiler oficial'), findsOneWidget);
    },
  );

  testWidgets('layout adapts to phone and desktop widths without overflow', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 0,
          'results': [],
        }),
        200,
      );
    });
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(PeliChrusApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Tu próxima historia empieza aquí'), findsOneWidget);
    expect(find.text('Explorar ahora'), findsOneWidget);
    await tester.tap(find.text('Explorar ahora'));
    await tester.pumpAndSettle();
    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();
    expect(find.text('Descubrir'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'búsqueda de prueba');
    await tester.pump();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Descubrir'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Descubrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar navigation opens search and manages favorites', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);

    final client = MockClient((request) async {
      expect(request.url.path, '/api/trending');
      return http.Response(
        jsonEncode({
          'page': 1,
          'total_pages': 1,
          'total_results': 1,
          'results': [
            {
              'id': 321,
              'media_type': 'movie',
              'title': 'Favorito demo',
              'release_date': '2026-01-01',
              'vote_average': 8.4,
              'popularity': 99,
              'poster_path': null,
            },
          ],
        }),
        200,
      );
    });
    final repository = ContentRepository(
      apiClient: TmdbApiClient(client: client),
    );

    await tester.pumpWidget(PeliChrusApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );

    await tester.tap(find.byTooltip('Añadir a favoritos').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritos').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Tu lista personal de películas y series.'),
      findsOneWidget,
    );
    expect(find.text('Favorito demo'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar de favoritos').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no tienes favoritos.'), findsOneWidget);

    await tester.tap(find.text('Ir a Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
  });
}
