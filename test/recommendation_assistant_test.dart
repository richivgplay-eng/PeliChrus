import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pelichrus/main.dart';
import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/services/content_repository.dart';
import 'package:pelichrus/services/recommendation_assistant_client.dart';
import 'package:pelichrus/services/tmdb_api_client.dart';
import 'package:pelichrus/widgets/recommendation_assistant.dart';

void main() {
  test(
    'assistant client sends conversation and decodes verified results',
    () async {
      late http.Request sentRequest;
      final client = RecommendationAssistantClient(
        client: MockClient((request) async {
          sentRequest = request;
          return http.Response(
            jsonEncode({
              'reply': 'Encontré una opción para ti.',
              'recommendations': [
                {
                  'id': 42,
                  'media_type': 'movie',
                  'title': 'Aventura de prueba',
                  'release_date': '2023-02-01',
                  'vote_average': 8.2,
                  'overview': 'Una historia de aventura.',
                  'poster_path': null,
                },
                {
                  'id': 43,
                  'media_type': 'person',
                  'title': 'No mostrar personas',
                },
              ],
            }),
            200,
          );
        }),
      );

      final reply = await client.ask([
        const AssistantMessage(role: 'user', content: 'Quiero una aventura'),
      ]);

      expect(sentRequest.url.path, '/api/assistant');
      expect(jsonDecode(sentRequest.body)['messages'], [
        {'role': 'user', 'content': 'Quiero una aventura'},
      ]);
      expect(reply.text, 'Encontré una opción para ti.');
      expect(reply.recommendations, hasLength(1));
      expect(reply.recommendations.single.title, 'Aventura de prueba');
      expect(reply.recommendations.single.kind, ContentKind.movie);
      expect(reply.recommendations.single.year, 2023);
    },
  );

  testWidgets('Peli shows quick prompts and renders recommendations', (
    tester,
  ) async {
    final client = RecommendationAssistantClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'reply': 'Encontré títulos de aventura para ti.',
            'recommendations': [
              {
                'id': 55,
                'media_type': 'tv',
                'title': 'Serie de aventura',
                'release_date': '2021-01-01',
                'vote_average': 7.6,
                'overview': 'Una serie de prueba.',
              },
            ],
          }),
          200,
        );
      }),
    );
    ContentItem? openedItem;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: RecommendationAssistant(
            client: client,
            onItemTap: (item) => openedItem = item,
          ),
        ),
      ),
    );

    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
    expect(find.text('Una película de aventuras'), findsOneWidget);
    await tester.tap(find.text('Una película de aventuras'));
    await tester.pumpAndSettle();

    expect(find.text('Encontré títulos de aventura para ti.'), findsOneWidget);
    expect(find.text('Serie de aventura'), findsOneWidget);
    await tester.tap(find.text('Serie de aventura'));
    expect(openedItem?.kind, ContentKind.series);
  });

  testWidgets('main screen starts in Peli; search remains a separate tab', (
    tester,
  ) async {
    final repository = ContentRepository(
      apiClient: TmdbApiClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'page': 1,
              'total_pages': 1,
              'total_results': 0,
              'results': [],
            }),
            200,
          ),
        ),
      ),
    );

    await tester.pumpWidget(PeliChrusApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('¿Qué te apetece ver hoy?'), findsNothing);
    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();
    expect(find.text('¿Qué te apetece ver hoy?'), findsOneWidget);

    await tester.tap(find.text('Peli').first);
    await tester.pumpAndSettle();
    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
  });

  testWidgets('Peli welcome screen fits a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: RecommendationAssistant(onItemTap: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¡Ey! Soy Peli, tu amigo cinéfilo 👋'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Peli includes earlier turns when the user follows up', (
    tester,
  ) async {
    final sentConversations = <List<dynamic>>[];
    final client = RecommendationAssistantClient(
      client: MockClient((request) async {
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        sentConversations.add(decoded['messages'] as List<dynamic>);
        return http.Response(
          jsonEncode({
            'reply': '¡Claro! Vamos por algo distinto.',
            'recommendations': [
              {
                'id': 88,
                'media_type': 'movie',
                'title': 'Opción real',
                'release_date': '2022-01-01',
                'vote_average': 7.8,
              },
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: RecommendationAssistant(client: client, onItemTap: (_) {}),
        ),
      ),
    );

    await tester.tap(find.text('Una película de aventuras'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Que no sea tan intensa');
    await tester.tap(find.byTooltip('Enviar pregunta'));
    await tester.pumpAndSettle();

    expect(sentConversations, hasLength(2));
    final followUp = sentConversations[1];
    expect(followUp, hasLength(3));
    expect(followUp[0]['content'], 'Una película de aventuras');
    expect(followUp[1]['role'], 'assistant');
    expect(followUp[1]['content'], contains('Vamos por algo distinto'));
    expect(followUp[1]['content'], contains('Opción real'));
    expect(followUp[2]['content'], 'Que no sea tan intensa');
  });

  test('assistant client surfaces backend errors in Spanish', () async {
    final client = RecommendationAssistantClient(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'error': 'El asistente aún no está configurado.'}),
          503,
        ),
      ),
    );

    await expectLater(
      client.ask([
        const AssistantMessage(role: 'user', content: 'Recomiéndame algo'),
      ]),
      throwsA(
        isA<RecommendationAssistantException>().having(
          (error) => error.message,
          'message',
          'El asistente aún no está configurado.',
        ),
      ),
    );
  });
}
