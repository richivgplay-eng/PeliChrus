import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/services/tmdb_config.dart';

class AssistantMessage {
  const AssistantMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AssistantReply {
  const AssistantReply({required this.text, required this.recommendations});

  final String text;
  final List<ContentItem> recommendations;
}

class RecommendationAssistantException implements Exception {
  const RecommendationAssistantException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RecommendationAssistantClient {
  RecommendationAssistantClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<AssistantReply> ask(List<AssistantMessage> messages) async {
    final uri = Uri.parse('${TmdbConfig.apiBaseUrl}/api/assistant');
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': messages.map((message) => message.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const RecommendationAssistantException(
        'No pude conectar con Peli. Comprueba que el servidor esté activo e inténtalo otra vez.',
      );
    }

    final data = _decodeResponse(response.body);
    if (response.statusCode != 200) {
      final message = data?['error'];
      throw RecommendationAssistantException(
        message is String
            ? message
            : 'Peli respondió con el código ${response.statusCode}.',
      );
    }
    if (data == null || data['reply'] is! String) {
      throw const RecommendationAssistantException(
        'El servidor devolvió una respuesta no válida.',
      );
    }

    final rawRecommendations = data['recommendations'];
    final recommendations = rawRecommendations is List
        ? rawRecommendations
              .whereType<Map<String, dynamic>>()
              .map(_contentItemFromJson)
              .whereType<ContentItem>()
              .toList()
        : <ContentItem>[];
    return AssistantReply(
      text: data['reply'] as String,
      recommendations: recommendations,
    );
  }

  static Map<String, dynamic>? _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static ContentItem? _contentItemFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final mediaType = data['media_type'];
    final title = data['title'];
    if (id is! int ||
        (mediaType != 'movie' && mediaType != 'tv') ||
        title is! String ||
        title.trim().isEmpty) {
      return null;
    }

    final date = data['release_date'];
    final year = date is String && date.length >= 4
        ? int.tryParse(date.substring(0, 4)) ?? 0
        : 0;
    final score = data['vote_average'];
    final popularity = data['popularity'];
    final kind = mediaType == 'movie' ? ContentKind.movie : ContentKind.series;
    return ContentItem(
      id: '${kind.name}-$id',
      title: title.trim(),
      year: year,
      kind: kind,
      genres: const [],
      score: score is num ? score.toDouble() : 0,
      popularity: popularity is num ? popularity.toDouble() : 0,
      keywords: const [],
      franchises: const [],
      overview: data['overview'] is String ? data['overview'] as String : '',
      posterAccent: 0xFF483C67,
      posterEmoji: kind == ContentKind.movie ? '🎬' : '📺',
      posterPath: data['poster_path'] is String
          ? data['poster_path'] as String
          : null,
    );
  }
}
