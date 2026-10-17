import 'package:flutter/material.dart';
import 'package:pelichrus/models/content_item.dart';
import 'package:pelichrus/models/search_intent.dart';
import 'package:pelichrus/models/title_details.dart';
import 'package:pelichrus/query_interpreter.dart';
import 'package:pelichrus/services/content_repository.dart';
import 'package:pelichrus/widgets/recommendation_assistant.dart';
import 'package:url_launcher/url_launcher.dart';

const _brandTeal = Color(0xFF00D4D0);
const _brandBlue = Color(0xFF164AA3);

void main() {
  runApp(const PeliChrusApp());
}

class PeliChrusApp extends StatelessWidget {
  const PeliChrusApp({super.key, this.repository});

  final ContentRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeliChrus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandTeal,
          secondary: _brandBlue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF080F19),
        useMaterial3: true,
      ),
      home: HomeScreen(repository: repository),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.repository});

  final ContentRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _favoritesScrollController = ScrollController();
  final Set<String> _favoriteIds = {};
  late final ContentRepository _repository =
      widget.repository ?? ContentRepository();

  late SearchIntent _currentIntent = QueryInterpreter.interpret('');
  List<ContentItem> _trendingItems = const [];
  List<ContentItem> _movies = const [];
  List<ContentItem> _series = const [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasSearched = false;
  String? _searchError;
  String? _trendingError;
  bool _isTrendingLoading = true;
  bool _hasRequestedTrending = false;
  int _totalResults = 0;
  int _currentPage = 1;
  int _totalPages = 1;
  int _requestVersion = 0;
  int _selectedTab = 0;
  bool _mobileIntroCompleted = false;

  static const List<String> _suggestions = [
    'Marvel',
    'Disney',
    'Terror',
    'Princesas',
    'Películas de comedia',
    'Películas para llorar',
    'Películas para reflexionar',
    'Películas sobre dinosaurios',
    'Anime en español',
    'Comiquitas de los 90',
    'Comiquitas de Fox Kids',
    'Series de Cartoon Network',
    'Comiquitas de Boomerang',
    'Series de Warner',
    'Series de Nickelodeon',
    'Series de Disney Channel',
    'Series de TNT',
    'Series de HBO',
    'Series de Netflix',
    'Desastres naturales',
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageScrollController.dispose();
    _favoritesScrollController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
    if (index == 1) {
      if (!_hasRequestedTrending) {
        _loadTrending();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_pageScrollController.hasClients) {
          _pageScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        _searchFocusNode.requestFocus();
      });
    }
  }

  void _toggleFavorite(ContentItem item) {
    setState(() {
      if (!_favoriteIds.add(item.id)) {
        _favoriteIds.remove(item.id);
      }
    });
  }

  List<ContentItem> get _favoriteItems {
    final itemsById = <String, ContentItem>{};
    for (final item in [..._trendingItems, ..._movies, ..._series]) {
      if (_favoriteIds.contains(item.id)) {
        itemsById[item.id] = item;
      }
    }
    return itemsById.values.toList();
  }

  Future<void> _loadTrending() async {
    _hasRequestedTrending = true;
    setState(() {
      _isTrendingLoading = true;
      _trendingError = null;
    });
    try {
      final items = await _repository.fetchTrending();
      if (!mounted) {
        return;
      }
      setState(() {
        _trendingItems = items;
        _isTrendingLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _trendingError = error.toString();
        _isTrendingLoading = false;
      });
    }
  }

  Future<void> _loadResults(String query) async {
    if (query.trim().isEmpty) {
      return;
    }
    final intent = QueryInterpreter.interpret(query);
    final requestVersion = ++_requestVersion;
    setState(() {
      _currentIntent = intent;
      _hasSearched = true;
      _isLoading = true;
      _searchError = null;
      _movies = const [];
      _series = const [];
      _totalResults = 0;
      _currentPage = 1;
      _totalPages = 1;
    });

    try {
      final page = await _repository.search(intent: intent);
      if (!mounted || requestVersion != _requestVersion) {
        return;
      }
      setState(() {
        _movies = page.items
            .where((item) => item.kind == ContentKind.movie)
            .toList();
        _series = page.items
            .where((item) => item.kind == ContentKind.series)
            .toList();
        _totalResults = page.totalResults;
        _currentPage = page.page;
        _totalPages = page.totalPages;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted || requestVersion != _requestVersion) {
        return;
      }
      setState(() {
        _searchError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _totalPages) {
      return;
    }
    final intent = _currentIntent;
    setState(() => _isLoadingMore = true);

    try {
      final page = await _repository.search(
        intent: intent,
        page: _currentPage + 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final knownIds = {
          ..._movies,
          ..._series,
        }.map((item) => item.id).toSet();
        final newItems = page.items
            .where((item) => knownIds.add(item.id))
            .toList();
        _movies = [
          ..._movies,
          ...newItems.where((item) => item.kind == ContentKind.movie),
        ];
        _series = [
          ..._series,
          ...newItems.where((item) => item.kind == ContentKind.series),
        ];
        _currentPage = page.page;
        _totalPages = page.totalPages;
        _isLoadingMore = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchError = error.toString();
        _isLoadingMore = false;
      });
    }
  }

  void _showDetails(ContentItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => _TitleDetailsDialog(
        item: item,
        loadDetails: () => _repository.detailsFor(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final isWide = width >= 900;

    if (screenSize.shortestSide < 600 && !_mobileIntroCompleted) {
      return _MobileIntro(
        onContinue: () => setState(() => _mobileIntroCompleted = true),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B13),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                if (isWide)
                  SizedBox(
                    width: 220,
                    child: _Sidebar(
                      selectedTab: _selectedTab,
                      onTap: _selectTab,
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.015, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: switch (_selectedTab) {
                      0 => KeyedSubtree(
                        key: const ValueKey('assistant-tab'),
                        child: RecommendationAssistant(
                          onItemTap: _showDetails,
                        ),
                      ),
                      2 => KeyedSubtree(
                        key: const ValueKey('favorites-tab'),
                        child: _buildFavoritesBody(),
                      ),
                      _ => KeyedSubtree(
                        key: const ValueKey('search-tab'),
                        child: _buildBody(),
                      ),
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedTab,
              onTap: _selectTab,
              backgroundColor: const Color(0xFF12121B),
              selectedItemColor: _brandTeal,
              unselectedItemColor: Colors.white70,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.auto_awesome_rounded),
                  label: 'Peli',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded),
                  label: 'Buscar',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite_rounded),
                  label: 'Favoritos',
                ),
              ],
            ),
    );
  }

  Widget _buildFavoritesBody() {
    final items = _favoriteItems;
    return SingleChildScrollView(
      controller: _favoritesScrollController,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
              const _SectionHeader(title: 'Favoritos'),
              const SizedBox(height: 8),
              const Text(
                'Tu lista personal de películas y series.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                _SearchMessage(
                  message:
                      'Todavía no tienes favoritos. Guarda una película o serie con el icono del corazón.',
                  actionLabel: 'Ir a Inicio',
                  onAction: () => _selectTab(0),
                )
              else
                _GridSection(
                  items: items,
                  onItemTap: _showDetails,
                  favoriteIds: _favoriteIds,
                  onFavoriteTap: _toggleFavorite,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 420 ? 16.0 : 28.0;
        return SingleChildScrollView(
          controller: _pageScrollController,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (constraints.maxWidth < 900) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/images/pelichrus_logo.png',
                            key: const ValueKey('pelichrus-brand-logo'),
                            width: 116,
                            height: 76,
                            fit: BoxFit.cover,
                            semanticLabel:
                                'PeliChrus: tu universo de streaming',
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF101D2B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _brandTeal.withValues(alpha: 0.28),
                            ),
                          ),
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.notifications_none_rounded),
                            color: _brandTeal,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '¿Qué te apetece ver hoy?',
                    style: TextStyle(
                      fontSize: constraints.maxWidth < 700 ? 27 : 36,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Encuentra películas y series según tu ánimo, tus gustos o ese canal que recuerdas.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, searchConstraints) {
                      final compactSearch = searchConstraints.maxWidth < 560;
                      final searchField = TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onSubmitted: _loadResults,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _brandTeal,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF171C28),
                          hintText: 'Describe lo que quieres ver...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                        ),
                      );
                      final discoverButton =
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, child) => SizedBox(
                              height: 56,
                              width: compactSearch ? double.infinity : null,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isLoading || value.text.trim().isEmpty
                                    ? null
                                    : () => _loadResults(value.text),
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('Descubrir'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _brandTeal,
                                  foregroundColor: const Color(0xFF06131B),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                ),
                              ),
                            ),
                          );

                      if (compactSearch) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            searchField,
                            const SizedBox(height: 10),
                            discoverButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          discoverButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _TrendingCarousel(
                    items: _trendingItems,
                    isLoading: _isTrendingLoading,
                    error: _trendingError,
                    onRetry: _loadTrending,
                    onItemTap: _showDetails,
                    favoriteIds: _favoriteIds,
                    onFavoriteTap: _toggleFavorite,
                  ),
                  const SizedBox(height: 24),
                  if (_currentIntent.hasFilters ||
                      _currentIntent.generalTextSearch)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171B27),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        'Intención: ${_formatContentType(_currentIntent.contentType)} · ${_currentIntent.periodLabel ?? 'Consulta general'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _suggestions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ActionChip(
                          label: Text(suggestion),
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Colors.white10),
                          backgroundColor: const Color(0xFF171C28),
                          labelStyle: const TextStyle(color: Colors.white),
                          onPressed: () {
                            _searchController.text = suggestion;
                            _loadResults(suggestion);
                          },
                        );
                      },
                    ),
                  ),
                  if (_hasSearched) ...[
                    const SizedBox(height: 30),
                    const _SectionHeader(title: 'Resultados de TMDB'),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_searchError != null)
                      _SearchMessage(
                        message: _searchError!,
                        actionLabel: 'Reintentar',
                        onAction: () => _loadResults(_searchController.text),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '$_totalResults resultados reportados por TMDB',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionHeader(title: 'Películas para descubrir'),
                      const SizedBox(height: 12),
                      if (_movies.isEmpty)
                        const _SearchMessage(
                          message: 'No hay películas para esta búsqueda.',
                        )
                      else
                        _GridSection(
                          items: _movies,
                          onItemTap: _showDetails,
                          favoriteIds: _favoriteIds,
                          onFavoriteTap: _toggleFavorite,
                        ),
                      const SizedBox(height: 26),
                      const _SectionHeader(title: 'Series para descubrir'),
                      const SizedBox(height: 12),
                      if (_series.isEmpty)
                        const _SearchMessage(
                          message: 'No hay series para esta búsqueda.',
                        )
                      else
                        _GridSection(
                          items: _series,
                          onItemTap: _showDetails,
                          favoriteIds: _favoriteIds,
                          onFavoriteTap: _toggleFavorite,
                        ),
                      if (_currentPage < _totalPages)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: OutlinedButton(
                              onPressed: _isLoadingMore ? null : _loadMore,
                              child: Text(
                                _isLoadingMore
                                    ? 'Cargando...'
                                    : 'Cargar más resultados',
                              ),
                            ),
                          ),
                        ),
                      if (_searchError != null)
                        _SearchMessage(
                          message: _searchError!,
                          actionLabel: 'Reintentar',
                          onAction: _loadMore,
                        ),
                      const SizedBox(height: 26),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF12121B),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 12,
                          children: const [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PeliChrus',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Contacto y novedades',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Contacto · Novedades próximamente',
                                style: TextStyle(color: _brandTeal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatContentType(ContentType type) {
    switch (type) {
      case ContentType.movie:
        return 'Películas';
      case ContentType.series:
        return 'Series';
      case ContentType.both:
        return 'Películas y series';
    }
  }
}

class _MobileIntro extends StatelessWidget {
  const _MobileIntro({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080F19),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -100,
              child: _IntroGlow(
                color: _brandTeal.withValues(alpha: 0.12),
                size: 300,
              ),
            ),
            Positioned(
              bottom: -160,
              left: -120,
              child: _IntroGlow(
                color: _brandBlue.withValues(alpha: 0.2),
                size: 360,
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, child) => Opacity(
                      opacity: progress,
                      child: Transform.translate(
                        offset: Offset(0, 22 * (1 - progress)),
                        child: child,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.asset(
                            'assets/images/pelichrus_logo.png',
                            width: 236,
                            height: 156,
                            fit: BoxFit.cover,
                            semanticLabel: 'PeliChrus',
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Tu próxima historia empieza aquí',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Descubre películas y series para cada momento, '
                          'y encuentra dónde verlas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 34),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: onContinue,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Explorar ahora'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandTeal,
                              foregroundColor: const Color(0xFF06131B),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'PELÍCULAS · SERIES · TUS FAVORITOS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroGlow extends StatelessWidget {
  const _IntroGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedTab, required this.onTap});

  final int selectedTab;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF12121B),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/images/pelichrus_logo.png',
              key: const ValueKey('pelichrus-sidebar-logo'),
              width: 188,
              height: 138,
              fit: BoxFit.cover,
              semanticLabel: 'PeliChrus: tu universo de streaming',
            ),
          ),
          const SizedBox(height: 20),
          _SidebarItem(
            label: 'Peli',
            icon: Icons.auto_awesome_rounded,
            selected: selectedTab == 0,
            onTap: () => onTap(0),
          ),
          _SidebarItem(
            label: 'Buscar',
            icon: Icons.search_rounded,
            selected: selectedTab == 1,
            onTap: () => onTap(1),
          ),
          _SidebarItem(
            label: 'Favoritos',
            icon: Icons.favorite_rounded,
            selected: selectedTab == 2,
            onTap: () => onTap(2),
          ),
          const Spacer(),
          const Text('Beta local', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFF10263B) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(icon, color: selected ? _brandTeal : Colors.white70),
          title: Text(
            label,
            style: TextStyle(color: selected ? Colors.white : Colors.white70),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171B27),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white70)),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _TrendingCarousel extends StatefulWidget {
  const _TrendingCarousel({
    required this.items,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.onItemTap,
    required this.favoriteIds,
    required this.onFavoriteTap,
  });

  final List<ContentItem> items;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<ContentItem> onItemTap;
  final Set<String> favoriteIds;
  final ValueChanged<ContentItem> onFavoriteTap;

  @override
  State<_TrendingCarousel> createState() => _TrendingCarouselState();
}

class _TrendingCarouselState extends State<_TrendingCarousel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double direction) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = (_scrollController.offset + direction * 420)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'Top del momento'),
                  SizedBox(height: 4),
                  Text(
                    'Lo más visto hoy en películas y series',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (widget.items.isNotEmpty) ...[
              IconButton(
                tooltip: 'Ver anteriores',
                onPressed: () => _scrollBy(-1),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                color: Colors.white70,
              ),
              IconButton(
                tooltip: 'Ver más tendencias',
                onPressed: () => _scrollBy(1),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                color: Colors.white70,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (widget.isLoading)
          const SizedBox(
            height: 252,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.error != null)
          _SearchMessage(
            message: widget.error!,
            actionLabel: 'Reintentar',
            onAction: widget.onRetry,
          )
        else if (widget.items.isEmpty)
          const _SearchMessage(
            message: 'No hay tendencias disponibles en este momento.',
          )
        else
          SizedBox(
            height: 252,
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final accent = Color(item.posterAccent);
                return SizedBox(
                  width: 154,
                  child: Material(
                    color: const Color(0xFF141521),
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onItemTap(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [accent, const Color(0xFF06131B)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: item.posterUrl == null
                                      ? Center(
                                          child: Text(
                                            item.posterEmoji,
                                            style: const TextStyle(
                                              fontSize: 38,
                                            ),
                                          ),
                                        )
                                      : Image.network(
                                          item.posterUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Center(
                                                    child: Text(
                                                      item.posterEmoji,
                                                      style: const TextStyle(
                                                        fontSize: 38,
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black38,
                                        Colors.transparent,
                                        Colors.black87,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _brandTeal,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'TOP ${index + 1}',
                                      style: const TextStyle(
                                        color: Color(0xFF06131B),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: IconButton(
                                    tooltip:
                                        widget.favoriteIds.contains(item.id)
                                        ? 'Quitar de favoritos'
                                        : 'Añadir a favoritos',
                                    onPressed: () => widget.onFavoriteTap(item),
                                    icon: Icon(
                                      widget.favoriteIds.contains(item.id)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: const Color(0xFFFF7F7F),
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      minimumSize: const Size(36, 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 11,
                                  right: 11,
                                  bottom: 11,
                                  child: Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.year > 0
                                        ? '${item.contentTypeLabel} · ${item.year}'
                                        : item.contentTypeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (item.score > 0) ...[
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: Color(0xFFFFD166),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    item.score.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _GridSection extends StatelessWidget {
  const _GridSection({
    required this.items,
    required this.onItemTap,
    required this.favoriteIds,
    required this.onFavoriteTap,
  });

  final List<ContentItem> items;
  final ValueChanged<ContentItem> onItemTap;
  final Set<String> favoriteIds;
  final ValueChanged<ContentItem> onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 220).floor().clamp(2, 5);
        const spacing = 16.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final cardHeight = cardWidth / 0.69 + 48;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 22,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) => _PosterCard(
            item: items[index],
            onTap: () => onItemTap(items[index]),
            isFavorite: favoriteIds.contains(items[index].id),
            onFavoriteTap: () => onFavoriteTap(items[index]),
          ),
        );
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.onTap,
    required this.isFavorite,
    required this.onFavoriteTap,
  });

  final ContentItem item;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(item.posterAccent);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        accent,
                        accent.withValues(alpha: 0.7),
                        const Color(0xFF0B0B13),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.posterUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            item.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.78),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black38,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.contentTypeLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            if (item.posterUrl == null)
                              Text(
                                item.posterEmoji,
                                style: const TextStyle(fontSize: 30),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: isFavorite
                              ? 'Quitar de favoritos'
                              : 'Añadir a favoritos',
                          onPressed: onFavoriteTap,
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite
                                ? const Color(0xFFFF7F7F)
                                : Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (item.year > 0)
                    Text(
                      '${item.year}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  if (item.score > 0) ...[
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFFFFD166),
                    ),
                    Text(
                      item.score.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              if (item.genres.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.genres.take(2).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleDetailsDialog extends StatelessWidget {
  const _TitleDetailsDialog({required this.item, required this.loadDetails});

  final ContentItem item;
  final Future<TitleDetails> Function() loadDetails;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF11121B),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: FutureBuilder<TitleDetails>(
          future: loadDetails(),
          builder: (context, snapshot) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : snapshot.hasError
                      ? _SearchMessage(
                          message:
                              'No se pudo cargar la ficha: ${snapshot.error}',
                          actionLabel: 'Reintentar',
                          onAction: () {
                            Navigator.of(context).pop();
                            showDialog<void>(
                              context: context,
                              builder: (_) => _TitleDetailsDialog(
                                item: item,
                                loadDetails: loadDetails,
                              ),
                            );
                          },
                        )
                      : _detailsBody(context, snapshot.data!),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detailsBody(BuildContext context, TitleDetails details) {
    final trailer = details.preferredTrailer;
    final watchProviders = [
      ...details.streaming,
      ...details.rent,
      ...details.buy,
    ].map((provider) => provider.name).toSet().toList();
    final releaseYear = item.year > 0 ? item.year.toString() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 580;
        final poster = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: horizontal ? 190 : 130,
            height: horizontal ? 280 : 190,
            child: item.posterUrl == null
                ? ColoredBox(
                    color: Color(item.posterAccent),
                    child: Center(
                      child: Text(
                        item.posterEmoji,
                        style: const TextStyle(fontSize: 48),
                      ),
                    ),
                  )
                : Image.network(
                    item.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: Color(item.posterAccent),
                      child: Center(
                        child: Text(
                          item.posterEmoji,
                          style: const TextStyle(fontSize: 48),
                        ),
                      ),
                    ),
                  ),
          ),
        );
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoBadge(label: item.contentTypeLabel),
                if (releaseYear != null) _InfoBadge(label: releaseYear),
                if (item.score > 0)
                  _InfoBadge(label: '★ ${item.score.toStringAsFixed(1)}'),
                if (details.runtime != null && details.runtime! > 0)
                  _InfoBadge(label: '${details.runtime} min'),
              ],
            ),
            const SizedBox(height: 14),
            if (details.genres.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: details.genres
                    .map((genre) => _InfoBadge(label: genre))
                    .toList(),
              ),
            const SizedBox(height: 16),
            Text(
              details.overview.isEmpty
                  ? 'Sin sinopsis disponible.'
                  : details.overview,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (horizontal)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    poster,
                    const SizedBox(width: 20),
                    Expanded(child: summary),
                  ],
                )
              else ...[
                Center(child: poster),
                const SizedBox(height: 18),
                summary,
              ],
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Tráiler'),
              const SizedBox(height: 10),
              if (trailer == null)
                const _SearchMessage(
                  message: 'No hay tráiler disponible en TMDB.',
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        _openExternal(context, Uri.parse(trailer.youtubeUrl)),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text('Ver tráiler · ${trailer.name}'),
                  ),
                ),
              const SizedBox(height: 22),
              const _SectionHeader(title: 'Dónde verla en Colombia'),
              const SizedBox(height: 10),
              if (watchProviders.isEmpty)
                const _SearchMessage(
                  message: 'No hay plataformas reportadas para Colombia.',
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: watchProviders
                      .map((name) => _InfoBadge(label: name))
                      .toList(),
                ),
                if (details.watchLink != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () =>
                        _openExternal(context, Uri.parse(details.watchLink!)),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Ver opciones en TMDB'),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Disponibilidad de JustWatch a través de TMDB; puede variar.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final text = Uri.encodeComponent(
                      'Hola, quisiera más información sobre ${item.title}.',
                    );
                    _openExternal(
                      context,
                      Uri.parse('https://wa.me/573052936246?text=$text'),
                    );
                  },
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Consultar por WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: const Color(0xFF092B16),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF232437),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
