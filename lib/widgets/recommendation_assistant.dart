import 'package:flutter/material.dart';
import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/services/recommendation_assistant_client.dart';

const _assistantTeal = Color(0xFF00D4D0);

class RecommendationAssistant extends StatefulWidget {
  const RecommendationAssistant({
    required this.onItemTap,
    this.client,
    super.key,
  });

  final ValueChanged<ContentItem> onItemTap;
  final RecommendationAssistantClient? client;

  @override
  State<RecommendationAssistant> createState() =>
      _RecommendationAssistantState();
}

class _RecommendationAssistantState extends State<RecommendationAssistant> {
  static const _quickPrompts = [
    'Una comedia ligera para hoy',
    'Una película de aventuras',
    'Una serie de misterio',
    'Algo de ciencia ficción',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AssistantTurn> _turns = [];
  late final RecommendationAssistantClient _client =
      widget.client ?? RecommendationAssistantClient();
  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? prompt]) async {
    final text = (prompt ?? _inputController.text).trim();
    if (text.isEmpty || _isSending) {
      return;
    }
    if (text.length > 800) {
      setState(() {
        _turns.add(
          const _AssistantTurn(
            text: 'Tu mensaje es muy largo. Prueba con una consulta más breve.',
            isError: true,
          ),
        );
      });
      return;
    }

    final history = [
      ..._turns.map(
        (turn) => AssistantMessage(
          role: turn.isUser ? 'user' : 'assistant',
          content: turn.isUser
              ? turn.text
              : [
                  turn.text,
                  ...turn.recommendations.map(
                    (item) =>
                        '${item.title} (${item.contentTypeLabel}${item.year > 0 ? ', ${item.year}' : ''})',
                  ),
                ].join('\n'),
        ),
      ),
      AssistantMessage(role: 'user', content: text),
    ];
    setState(() {
      _turns.add(_AssistantTurn(text: text, isUser: true));
      _isSending = true;
      _inputController.clear();
    });
    _scrollToBottom();

    try {
      final reply = await _client.ask(history);
      if (!mounted) {
        return;
      }
      setState(() {
        _turns.add(
          _AssistantTurn(
            text: reply.text,
            recommendations: reply.recommendations,
          ),
        );
        _isSending = false;
      });
    } on RecommendationAssistantException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _turns.add(_AssistantTurn(text: error.message, isError: true));
        _isSending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10263B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _assistantTeal.withValues(alpha: 0.38),
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: _assistantTeal,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Peli',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Tu amigo cinéfilo, listo para recomendarte algo',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  if (_turns.isNotEmpty)
                    TextButton.icon(
                      onPressed: _isSending
                          ? null
                          : () => setState(_turns.clear),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Nueva charla'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _turns.isEmpty
                    ? _buildWelcome()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _turns.length + (_isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _turns.length) {
                            return const _ThinkingIndicator();
                          }
                          return _TurnBubble(
                            turn: _turns[index],
                            onItemTap: widget.onItemTap,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              _buildComposer(),
              const SizedBox(height: 8),
              const Text(
                'Busco títulos reales en TMDB y te ayudo a elegir con honestidad.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121B28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Ey! Soy Peli, tu amigo cinéfilo 👋',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '¿Noche de risas, misterio o aventura? Cuéntame qué te gusta y buscamos juntos. Si una recomendación no te convence, dime por qué y afinamos hasta encontrar algo para ti.',
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Para romper el hielo',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPrompts
                .map(
                  (prompt) => ActionChip(
                    label: Text(prompt),
                    backgroundColor: const Color(0xFF171C28),
                    side: const BorderSide(color: Colors.white12),
                    labelStyle: const TextStyle(color: Colors.white),
                    onPressed: _isSending ? null : () => _sendMessage(prompt),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            minLines: 1,
            maxLines: 3,
            maxLength: 800,
            textInputAction: TextInputAction.send,
            onSubmitted: _isSending ? null : (_) => _sendMessage(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Cuéntame qué te apetece ver...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF171C28),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: 'Enviar pregunta',
          onPressed: _isSending ? null : () => _sendMessage(),
          style: IconButton.styleFrom(
            backgroundColor: _assistantTeal,
            foregroundColor: const Color(0xFF06131B),
            minimumSize: const Size(52, 52),
          ),
          icon: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF06131B),
                  ),
                )
              : const Icon(Icons.send_rounded),
        ),
      ],
    );
  }
}

class _AssistantTurn {
  const _AssistantTurn({
    required this.text,
    this.isUser = false,
    this.isError = false,
    this.recommendations = const [],
  });

  final String text;
  final bool isUser;
  final bool isError;
  final List<ContentItem> recommendations;
}

class _TurnBubble extends StatelessWidget {
  const _TurnBubble({required this.turn, required this.onItemTap});

  final _AssistantTurn turn;
  final ValueChanged<ContentItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.isUser;
    final bubbleColor = turn.isError
        ? const Color(0xFF3A2026)
        : isUser
        ? const Color(0xFF10263B)
        : const Color(0xFF171B27);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUser
                  ? _assistantTeal.withValues(alpha: 0.2)
                  : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                turn.text,
                style: TextStyle(
                  color: turn.isError ? const Color(0xFFFFB4AB) : Colors.white,
                  height: 1.4,
                ),
              ),
              if (turn.recommendations.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final item in turn.recommendations)
                  _RecommendationTile(item: item, onTap: () => onItemTap(item)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.item, required this.onTap});

  final ContentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final year = item.year > 0 ? ' · ${item.year}' : '';
    final rating = item.score > 0
        ? ' · ★ ${item.score.toStringAsFixed(1)}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: const Color(0xFF0B111A),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 62,
                    child: item.posterUrl == null
                        ? const ColoredBox(
                            color: Color(0xFF232437),
                            child: Icon(
                              Icons.movie_rounded,
                              color: Colors.white54,
                            ),
                          )
                        : Image.network(
                            item.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: Color(0xFF232437),
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: Colors.white54,
                                  ),
                                ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.contentTypeLabel}$year$rating',
                        style: const TextStyle(
                          color: _assistantTeal,
                          fontSize: 12,
                        ),
                      ),
                      if (item.overview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _assistantTeal,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Peli está buscando...',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}
