import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const TMDB_BASE_URL = 'https://api.themoviedb.org/3';
const MAX_QUERY_LENGTH = 200;
const REQUEST_TIMEOUT_MS = 10_000;
const GEMINI_API_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models';
const MAX_ASSISTANT_BODY_BYTES = 16_000;
const MAX_ASSISTANT_MESSAGES = 16;
const MAX_ASSISTANT_MESSAGE_LENGTH = 800;
const MAX_ASSISTANT_TOOL_CALLS = 4;
const MAX_ASSISTANT_RESULTS = 3;
const ASSISTANT_RATE_WINDOW_MS = 60_000;
const ASSISTANT_RATE_LIMIT = 5;
const CHANNEL_NETWORKS = {
  fox_kids: { id: '19', genres: '16,10762', startYear: 1990, endYear: 2004 },
  tnt: { id: '41' },
  cartoon_network: { id: '56', genres: '16' },
  boomerang: { id: '56', genres: '16,10762', startYear: 1990, endYear: 2015 },
  warner: { id: '21' },
  nickelodeon: { id: '13', genres: '16,10762' },
  disney_channel: { id: '54', genres: '16,10762' },
  hbo: { id: '49' },
  netflix: { id: '213' },
};

export function createHandler({
  accessToken = '',
  allowedOrigins = [
    'http://localhost:5000',
    'http://127.0.0.1:5000',
    'http://localhost:7357',
    'http://127.0.0.1:7357',
  ],
  allowLocalhost = process.env.NODE_ENV !== 'production',
  fetchImpl = fetch,
  geminiApiKey = '',
  geminiModel = 'gemini-3.5-flash-lite',
  assistantDailyTokenLimit = 100_000,
  geminiFetchImpl = fetch,
} = {}) {
  if (!Number.isSafeInteger(assistantDailyTokenLimit) || assistantDailyTokenLimit < 1) {
    throw new Error('AI_DAILY_TOKEN_LIMIT debe ser un entero positivo.');
  }
  const assistantRequests = new Map();
  let assistantUsageDate = new Date().toISOString().slice(0, 10);
  let assistantTokensUsed = 0;

  return async (request, response) => {
    const origin = request.headers.origin;
    if (origin && !isAllowedOrigin(origin, allowedOrigins, allowLocalhost)) {
      sendJson(response, 403, { error: 'Origen no permitido.' });
      return;
    }

    if (origin) {
      response.setHeader('Access-Control-Allow-Origin', origin);
      response.setHeader('Vary', 'Origin');
    }
    response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method === 'OPTIONS') {
      response.writeHead(204);
      response.end();
      return;
    }

    const requestUrl = new URL(request.url ?? '/', 'http://localhost');

    if (request.method === 'POST' && requestUrl.pathname === '/api/assistant') {
      if (!geminiApiKey || !accessToken) {
        sendJson(response, 503, {
          error: 'El asistente aún no está configurado en el servidor.',
        });
        return;
      }

      const remoteAddress = request.socket.remoteAddress ?? 'unknown';
      if (!allowAssistantRequest(assistantRequests, remoteAddress)) {
        sendJson(response, 429, {
          error: 'Has enviado varias consultas seguidas. Espera un minuto e inténtalo de nuevo.',
        });
        return;
      }

      let conversation;
      try {
        conversation = await readAssistantConversation(request);
      } catch (error) {
        sendJson(response, error.statusCode ?? 400, { error: error.message });
        return;
      }

      const today = new Date().toISOString().slice(0, 10);
      if (today !== assistantUsageDate) {
        assistantUsageDate = today;
        assistantTokensUsed = 0;
      }
      if (assistantTokensUsed >= assistantDailyTokenLimit) {
        sendJson(response, 429, {
          error: 'El asistente alcanzó su límite diario. Vuelve a intentarlo mañana.',
        });
        return;
      }

      try {
        const result = await getAssistantRecommendation({
          conversation,
          accessToken,
          geminiApiKey,
          geminiModel,
          fetchImpl,
          geminiFetchImpl,
          canUseTokens: (estimatedTokens) =>
            assistantTokensUsed + estimatedTokens <= assistantDailyTokenLimit,
          onTokenUsage: (tokens) => {
            assistantTokensUsed += tokens;
          },
        });
        sendJson(response, 200, result);
      } catch (error) {
        if (error.code === 'DAILY_LIMIT') {
          sendJson(response, 429, {
            error: 'El asistente alcanzó su límite diario. Vuelve a intentarlo mañana.',
          });
          return;
        }
        if (error.code === 'PROVIDER_ERROR') {
          console.error('Gemini recommendation request failed:', error.message);
          sendJson(response, 502, {
            error: 'Peli no pudo responder ahora. Inténtalo de nuevo en un momento.',
          });
          return;
        }
        sendJson(response, 502, {
          error: 'No se pudieron consultar recomendaciones en este momento.',
        });
      }
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/health') {
      sendJson(response, 200, { status: 'ok', tmdbConfigured: Boolean(accessToken) });
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/api/trending') {
      const language = requestUrl.searchParams.get('language')?.trim() || 'es-MX';
      if (!/^[a-z]{2}-[A-Z]{2}$/.test(language)) {
        sendJson(response, 400, { error: 'El idioma debe tener formato xx-YY.' });
        return;
      }
      if (!accessToken) {
        sendJson(response, 503, {
          error: 'TMDB no está configurado. Define TMDB_ACCESS_TOKEN en server/.env.',
        });
        return;
      }

      const trendingUrl = new URL(`${TMDB_BASE_URL}/trending/all/day`);
      trendingUrl.searchParams.set('language', language);
      try {
        const data = await fetchTmdbJson(fetchImpl, trendingUrl, accessToken);
        sendJson(response, 200, {
          page: data.page ?? 1,
          total_pages: data.total_pages ?? 1,
          total_results: data.total_results ?? data.results?.length ?? 0,
          results: Array.isArray(data.results)
            ? data.results.filter((item) =>
                item.media_type === 'movie' || item.media_type === 'tv',
              )
            : [],
        });
      } catch {
        sendJson(response, 502, { error: 'No se pudieron cargar las tendencias de TMDB.' });
      }
      return;
    }

    if (request.method !== 'GET') {
      sendJson(response, 404, { error: 'Ruta no encontrada.' });
      return;
    }

    const titleRoute = requestUrl.pathname.match(/^\/api\/title\/(movie|tv)\/(\d+)$/);
    if (titleRoute) {
      const [, mediaType, rawId] = titleRoute;
      const titleId = Number.parseInt(rawId, 10);
      const region = requestUrl.searchParams.get('region')?.trim() || 'CO';
      const language = requestUrl.searchParams.get('language')?.trim() || 'es-MX';
      if (!Number.isSafeInteger(titleId) || titleId < 1) {
        sendJson(response, 400, { error: 'El identificador del contenido no es válido.' });
        return;
      }
      if (!/^[A-Z]{2}$/.test(region)) {
        sendJson(response, 400, { error: 'La región debe ser un código de país de dos letras.' });
        return;
      }
      if (!/^[a-z]{2}-[A-Z]{2}$/.test(language)) {
        sendJson(response, 400, { error: 'El idioma debe tener formato xx-YY.' });
        return;
      }
      if (!accessToken) {
        sendJson(response, 503, {
          error: 'TMDB no está configurado. Define TMDB_ACCESS_TOKEN en server/.env.',
        });
        return;
      }

      const titlePath = `/${mediaType}/${titleId}`;
      const requestTmdb = async (path) => {
        const url = new URL(`${TMDB_BASE_URL}${path}`);
        url.searchParams.set('language', language);
        const tmdbResponse = await fetchImpl(url, {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            Accept: 'application/json',
          },
          signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        });
        if (!tmdbResponse.ok) {
          throw new Error(`TMDB respondió ${tmdbResponse.status} para ${path}.`);
        }
        return tmdbResponse.json();
      };

      try {
        const [details, videos, watchProviders] = await Promise.all([
          requestTmdb(titlePath),
          requestTmdb(`${titlePath}/videos`),
          requestTmdb(`${titlePath}/watch/providers`),
        ]);
        const regionProviders = watchProviders.results?.[region] ?? {};
        sendJson(response, 200, {
          id: details.id,
          title: details.title ?? details.name,
          overview: details.overview ?? '',
          genres: Array.isArray(details.genres)
            ? details.genres.map((genre) => genre.name).filter(Boolean)
            : [],
          runtime: details.runtime ?? details.episode_run_time?.[0] ?? null,
          release_date: details.release_date ?? details.first_air_date ?? '',
          vote_average: details.vote_average ?? 0,
          videos: Array.isArray(videos.results)
            ? videos.results
                .filter((video) => video.site === 'YouTube' && video.key)
                .map((video) => ({
                  name: video.name,
                  key: video.key,
                  type: video.type,
                  official: video.official,
                  language: video.iso_639_1,
                }))
            : [],
          providers: {
            region,
            link: regionProviders.link ?? null,
            flatrate: regionProviders.flatrate ?? [],
            rent: regionProviders.rent ?? [],
            buy: regionProviders.buy ?? [],
          },
        });
      } catch {
        sendJson(response, 502, { error: 'No se pudieron cargar los detalles desde TMDB.' });
      }
      return;
    }

    if (requestUrl.pathname !== '/api/search') {
      sendJson(response, 404, { error: 'Ruta no encontrada.' });
      return;
    }

    const query = requestUrl.searchParams.get('query')?.trim() ?? '';
    const language = requestUrl.searchParams.get('language')?.trim() || 'es-MX';
    const pageValue = Number.parseInt(requestUrl.searchParams.get('page') ?? '1', 10);
    const searchType = requestUrl.searchParams.get('type') ?? 'multi';
    const channel = requestUrl.searchParams.get('channel')?.trim() ?? '';
    const startYearValue = requestUrl.searchParams.get('start_year');
    const endYearValue = requestUrl.searchParams.get('end_year');
    const startYear = startYearValue === null ? null : Number(startYearValue);
    const endYear = endYearValue === null ? null : Number(endYearValue);
    const keywordTerms = (requestUrl.searchParams.get('keyword') ?? '')
      .split('|')
      .map((term) => term.trim())
      .filter(Boolean);

    if (!query || query.length > MAX_QUERY_LENGTH) {
      sendJson(response, 400, {
        error: `La consulta debe tener entre 1 y ${MAX_QUERY_LENGTH} caracteres.`,
      });
      return;
    }
    if (!Number.isInteger(pageValue) || pageValue < 1 || pageValue > 500) {
      sendJson(response, 400, { error: 'La página debe estar entre 1 y 500.' });
      return;
    }
    if (!/^[a-z]{2}-[A-Z]{2}$/.test(language)) {
      sendJson(response, 400, { error: 'El idioma debe tener formato xx-YY.' });
      return;
    }
    if (!['multi', 'movie', 'tv'].includes(searchType)) {
      sendJson(response, 400, { error: 'El tipo debe ser multi, movie o tv.' });
      return;
    }
    if (channel && !Object.hasOwn(CHANNEL_NETWORKS, channel)) {
      sendJson(response, 400, { error: 'El canal solicitado no está configurado.' });
      return;
    }
    if (
      (startYear !== null && (!Number.isInteger(startYear) || startYear < 1870 || startYear > 2100)) ||
      (endYear !== null && (!Number.isInteger(endYear) || endYear < 1870 || endYear > 2100)) ||
      (startYear !== null && endYear !== null && startYear > endYear)
    ) {
      sendJson(response, 400, { error: 'El rango de años no es válido.' });
      return;
    }
    if (keywordTerms.length > 4 || keywordTerms.some((term) => term.length > MAX_QUERY_LENGTH)) {
      sendJson(response, 400, {
        error: 'La búsqueda puede incluir hasta cuatro palabras clave.',
      });
      return;
    }
    if (!accessToken) {
      sendJson(response, 503, {
        error: 'TMDB no está configurado. Define TMDB_ACCESS_TOKEN en server/.env.',
      });
      return;
    }

    if (keywordTerms.length > 0 || channel) {
      try {
        const keywordResults = await Promise.all(
          keywordTerms.map(async (term) => {
            const keywordUrl = new URL(`${TMDB_BASE_URL}/search/keyword`);
            keywordUrl.searchParams.set('query', term);
            keywordUrl.searchParams.set('language', 'en-US');
            return fetchTmdbJson(fetchImpl, keywordUrl, accessToken);
          }),
        );
        const keywordIds = [
          ...new Set(
            keywordResults.flatMap((keywordData) =>
              Array.isArray(keywordData.results)
                ? keywordData.results
                    .map((item) => item.id)
                    .filter((id) => Number.isSafeInteger(id) && id > 0)
                : [],
            ),
          ),
        ];

        if (keywordIds.length > 0 || channel) {
          const mediaTypes = channel
            ? ['tv']
            : searchType === 'multi'
              ? ['movie', 'tv']
              : [searchType];
          const discovered = await Promise.all(
            mediaTypes.map(async (mediaType) => {
              const discoverUrl = new URL(`${TMDB_BASE_URL}/discover/${mediaType}`);
              if (keywordIds.length > 0) {
                discoverUrl.searchParams.set('with_keywords', keywordIds.join('|'));
              }
              discoverUrl.searchParams.set('sort_by', 'popularity.desc');
              discoverUrl.searchParams.set('language', language);
              discoverUrl.searchParams.set('page', String(pageValue));
              discoverUrl.searchParams.set('include_adult', 'false');
              if (channel) {
                const channelConfig = CHANNEL_NETWORKS[channel];
                discoverUrl.searchParams.set('with_networks', channelConfig.id);
                if (channelConfig.genres) {
                  discoverUrl.searchParams.set('with_genres', channelConfig.genres);
                }
                if (channelConfig.startYear) {
                  discoverUrl.searchParams.set(
                    'first_air_date.gte',
                    `${channelConfig.startYear}-01-01`,
                  );
                }
                if (channelConfig.endYear) {
                  discoverUrl.searchParams.set(
                    'first_air_date.lte',
                    `${channelConfig.endYear}-12-31`,
                  );
                }
              }
              if (startYear !== null) {
                discoverUrl.searchParams.set(
                  mediaType === 'movie' ? 'primary_release_date.gte' : 'first_air_date.gte',
                  `${startYear}-01-01`,
                );
              }
              if (endYear !== null) {
                discoverUrl.searchParams.set(
                  mediaType === 'movie' ? 'primary_release_date.lte' : 'first_air_date.lte',
                  `${endYear}-12-31`,
                );
              }
              if (keywordTerms.includes('anime')) {
                discoverUrl.searchParams.set('with_original_language', 'ja');
              }
              const result = await fetchTmdbJson(fetchImpl, discoverUrl, accessToken);
              return { mediaType, result };
            }),
          );
          const results = discovered
            .flatMap(({ mediaType, result }) =>
              (Array.isArray(result.results) ? result.results : []).map((item) => ({
                ...item,
                media_type: mediaType,
              })),
            )
            .sort((left, right) => (right.popularity ?? 0) - (left.popularity ?? 0));
          const uniqueResults = [
            ...new Map(results.map((item) => [`${item.media_type}-${item.id}`, item])).values(),
          ];
          sendJson(response, 200, {
            page: pageValue,
            total_pages: Math.max(...discovered.map(({ result }) => result.total_pages ?? 1)),
            total_results: discovered.reduce(
              (total, { result }) => total + (result.total_results ?? 0),
              0,
            ),
            results: uniqueResults,
          });
          return;
        }
      } catch {
        sendJson(response, 502, { error: 'No se pudo completar la búsqueda temática en TMDB.' });
        return;
      }
    }

    const tmdbUrl = new URL(`${TMDB_BASE_URL}/search/${searchType}`);
    tmdbUrl.searchParams.set('query', query);
    tmdbUrl.searchParams.set('language', language);
    tmdbUrl.searchParams.set('page', String(pageValue));
    tmdbUrl.searchParams.set('include_adult', 'false');

    try {
      const tmdbResponse = await fetchImpl(tmdbUrl, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });

      if (!tmdbResponse.ok) {
        sendJson(response, 502, { error: 'TMDB no pudo completar la búsqueda.' });
        return;
      }

      const data = await tmdbResponse.json();
      sendJson(response, 200, {
        page: data.page,
        total_pages: data.total_pages,
        total_results: data.total_results,
        results: Array.isArray(data.results)
          ? data.results
              .filter((item) =>
                searchType === 'multi'
                  ? item.media_type === 'movie' || item.media_type === 'tv'
                  : true,
              )
              .map((item) => ({
                ...item,
                media_type: item.media_type ?? searchType,
              }))
          : [],
      });
    } catch {
      sendJson(response, 502, { error: 'No se pudo conectar con TMDB.' });
    }
  };
}

const ASSISTANT_TOOLS = [
  {
    name: 'find_titles',
    description:
      'Busca películas o series reales por título, tema, saga o nombres de artistas. Usa esta herramienta antes de recomendar títulos concretos.',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string' },
        content_type: { type: 'string', enum: ['movie', 'tv', 'multi'] },
      },
      required: ['query', 'content_type'],
    },
  },
  {
    name: 'discover_by_genre',
    description:
      'Descubre títulos populares de TMDB por uno o dos géneros. Úsala para recomendaciones por ánimo o género.',
    input_schema: {
      type: 'object',
      properties: {
        genre_ids: {
          type: 'array',
          items: {
            type: 'string',
            enum: [
              '12',
              '14',
              '16',
              '18',
              '27',
              '28',
              '35',
              '53',
              '80',
              '99',
              '9648',
              '10749',
              '10751',
              '878',
            ],
          },
        },
        content_type: { type: 'string', enum: ['movie', 'tv', 'multi'] },
      },
      required: ['genre_ids', 'content_type'],
    },
  },
  {
    name: 'get_trending',
    description: 'Consulta las películas y series populares del día en TMDB.',
    input_schema: { type: 'object', properties: {} },
  },
];

const ASSISTANT_SYSTEM_PROMPT = `Eres Peli, ese amigo cinéfilo cercano y de confianza que disfruta ayudar a elegir qué ver. Habla siempre en español natural, con calidez, entusiasmo tranquilo y sin sonar a robot, vendedor o crítico pretencioso. Puedes usar expresiones amistosas con moderación.
Escucha lo que la persona ya dijo en los mensajes anteriores y conserva el hilo: recuerda su ánimo, gustos, límites, si prefiere película o serie y qué recomendaciones ya descartó. No vuelvas a preguntar algo que ya quedó claro. Si te dice que una opción no le convence, acepta el comentario con buena onda y ajusta la siguiente búsqueda según su motivo. Haz como máximo una pregunta concreta cuando realmente ayude a afinar.
Antes de proponer algo concreto, consulta una herramienta. Recomienda únicamente títulos y datos que estén en los resultados actuales de herramientas; nunca inventes películas, series, puntuaciones, años, argumentos ni plataformas, y no des por hecho disponibilidad en streaming.
No escribas títulos de películas o series en el texto: la app mostrará únicamente tarjetas con títulos verificados. No cuentes ni adornes argumentos; las fichas ya muestran información del catálogo y el texto debe centrarse en conversar con la persona. Si hay opciones, conecta brevemente con lo que pidió, basándote solo en sus preferencias y los géneros disponibles. Si no hay resultados, dilo con honestidad y sugiere juntos cómo probar otra búsqueda. Responde en un máximo de dos frases cortas, con naturalidad y calidez de amigo; no repitas saludos en cada turno.
No solicites datos personales.`;

async function readAssistantConversation(request) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body, 'utf8') > MAX_ASSISTANT_BODY_BYTES) {
      const error = new Error('La conversación es demasiado larga.');
      error.statusCode = 413;
      throw error;
    }
  }

  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    throw new Error('La solicitud del asistente no contiene JSON válido.');
  }
  if (!Array.isArray(parsed.messages) || parsed.messages.length === 0) {
    throw new Error('Escribe una pregunta para conversar con Peli.');
  }

  const messages = parsed.messages.slice(-MAX_ASSISTANT_MESSAGES);
  if (messages[0]?.role === 'assistant') {
    messages.shift();
  }
  let totalCharacters = 0;
  let previousRole;
  const conversation = [];
  for (const message of messages) {
    if (
      !message ||
      !['user', 'assistant'].includes(message.role) ||
      typeof message.content !== 'string'
    ) {
      throw new Error('El formato de la conversación no es válido.');
    }
    const content = message.content.trim();
    if (
      content.length === 0 ||
      content.length > MAX_ASSISTANT_MESSAGE_LENGTH ||
      message.role === previousRole
    ) {
      throw new Error('La conversación contiene mensajes vacíos, repetidos o demasiado largos.');
    }
    totalCharacters += content.length;
    conversation.push({ role: message.role, content });
    previousRole = message.role;
  }
  if (totalCharacters > 6_000 || conversation.at(-1)?.role !== 'user') {
    throw new Error('La conversación es demasiado larga o no termina con una pregunta.');
  }
  return conversation;
}

function allowAssistantRequest(requestsByAddress, remoteAddress) {
  const now = Date.now();
  for (const [address, timestamps] of requestsByAddress) {
    const recent = timestamps.filter((timestamp) => now - timestamp < ASSISTANT_RATE_WINDOW_MS);
    if (recent.length === 0) {
      requestsByAddress.delete(address);
    } else {
      requestsByAddress.set(address, recent);
    }
  }
  if (requestsByAddress.size >= 10_000 && !requestsByAddress.has(remoteAddress)) {
    return false;
  }
  const timestamps = requestsByAddress.get(remoteAddress) ?? [];
  if (timestamps.length >= ASSISTANT_RATE_LIMIT) {
    return false;
  }
  timestamps.push(now);
  requestsByAddress.set(remoteAddress, timestamps);
  return true;
}

async function getAssistantRecommendation({
  conversation,
  accessToken,
  geminiApiKey,
  geminiModel,
  fetchImpl,
  geminiFetchImpl,
  canUseTokens,
  onTokenUsage,
}) {
  const contents = conversation.map((message) => ({
    role: message.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: message.content }],
  }));
  const recommendations = new Map();
  let reply = '';
  let toolCallCount = 0;

  for (let turn = 0; turn < 2; turn += 1) {
    const requestBody = {
      systemInstruction: { parts: [{ text: ASSISTANT_SYSTEM_PROMPT }] },
      tools: [
        {
          functionDeclarations: ASSISTANT_TOOLS.map(({ name, description, input_schema }) => ({
            name,
            description,
            parameters: input_schema,
          })),
        },
      ],
      toolConfig: {
        functionCallingConfig: { mode: turn === 0 ? 'AUTO' : 'NONE' },
      },
      generationConfig: { maxOutputTokens: 400 },
      contents,
    };
    const estimatedTokens = Math.ceil(JSON.stringify(requestBody).length / 4) + 400;
    if (!canUseTokens(estimatedTokens)) {
      const error = new Error('Daily assistant limit reached.');
      error.code = 'DAILY_LIMIT';
      throw error;
    }
    const response = await geminiFetchImpl(
      `${GEMINI_API_BASE_URL}/${encodeURIComponent(geminiModel)}:generateContent`,
      {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': geminiApiKey,
      },
      body: JSON.stringify(requestBody),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    );
    if (!response.ok) {
      let providerMessage = '';
      try {
        const errorBody = await response.json();
        providerMessage =
          typeof errorBody.error?.message === 'string'
            ? errorBody.error.message
            : '';
      } catch {
        providerMessage = '';
      }
      const error = new Error(
        `Gemini respondió ${response.status}${providerMessage ? `: ${providerMessage}` : '.'}`,
      );
      error.code = 'PROVIDER_ERROR';
      throw error;
    }
    const data = await response.json();
    onTokenUsage(
      (Number.isSafeInteger(data.usageMetadata?.promptTokenCount)
        ? data.usageMetadata.promptTokenCount
        : 0) +
        (Number.isSafeInteger(data.usageMetadata?.candidatesTokenCount)
          ? data.usageMetadata.candidatesTokenCount
          : 0),
    );

    const parts = data.candidates?.[0]?.content?.parts;
    const responseParts = Array.isArray(parts) ? parts : [];
    const toolCalls = responseParts.filter((part) => part.functionCall);
    reply = responseParts
      .filter((part) => typeof part.text === 'string')
      .map((block) => block.text)
      .join('\n')
      .trim();
    if (toolCalls.length === 0 || turn === 1) {
      break;
    }

    contents.push({ role: 'model', parts: responseParts });
    const toolResults = [];
    for (const toolCall of toolCalls) {
      toolCallCount += 1;
      if (toolCallCount > MAX_ASSISTANT_TOOL_CALLS) {
        break;
      }
      const result = await runAssistantTool(
        toolCall.functionCall,
        accessToken,
        fetchImpl,
      );
      for (const item of result) {
        const key = `${item.media_type}-${item.id}`;
        if (!recommendations.has(key)) {
          recommendations.set(key, item);
        }
      }
      toolResults.push({
        functionResponse: {
          name: toolCall.functionCall.name,
          response: { result },
        },
      });
    }
    if (toolResults.length === 0) {
      break;
    }
    contents.push({ role: 'user', parts: toolResults });
  }

  return {
    reply:
      reply ||
      (recommendations.size > 0
        ? 'Encontré algunas opciones que pueden encajar. Mira las tarjetas y abre una ficha para conocer más.'
        : 'Cuéntame qué te apetece ver y te buscaré algunas opciones.'),
    recommendations: [...recommendations.values()].slice(0, MAX_ASSISTANT_RESULTS),
  };
}

async function runAssistantTool(toolCall, accessToken, fetchImpl) {
  const input = toolCall.args;
  const results = [];
  if (toolCall.name === 'get_trending') {
    const url = new URL(`${TMDB_BASE_URL}/trending/all/day`);
    url.searchParams.set('language', 'es-MX');
    const data = await fetchTmdbJson(fetchImpl, url, accessToken);
    results.push(...compactAssistantResults(data.results));
  } else if (toolCall.name === 'find_titles') {
    if (
      typeof input?.query !== 'string' ||
      input.query.trim().length === 0 ||
      input.query.length > 120 ||
      !['movie', 'tv', 'multi'].includes(input.content_type)
    ) {
      return [];
    }
    const searchType = input.content_type;
    const url = new URL(`${TMDB_BASE_URL}/search/${searchType}`);
    url.searchParams.set('query', input.query.trim());
    url.searchParams.set('language', 'es-MX');
    url.searchParams.set('include_adult', 'false');
    const data = await fetchTmdbJson(fetchImpl, url, accessToken);
    results.push(
      ...compactAssistantResults(
        Array.isArray(data.results)
          ? data.results.map((item) => ({
              ...item,
              media_type: item.media_type ?? searchType,
            }))
          : [],
      ),
    );
  } else if (toolCall.name === 'discover_by_genre') {
    if (
      !Array.isArray(input?.genre_ids) ||
      input.genre_ids.length === 0 ||
      input.genre_ids.length > 2 ||
      input.genre_ids.some(
        (id) =>
          typeof id !== 'string' ||
          !['12', '14', '16', '18', '27', '28', '35', '53', '80', '99', '9648', '10749', '10751', '878'].includes(
            id,
          ),
      ) ||
      !['movie', 'tv', 'multi'].includes(input.content_type)
    ) {
      return [];
    }
    const genreIds = input.genre_ids.map(Number);
    const mediaTypes =
      input.content_type === 'multi' ? ['movie', 'tv'] : [input.content_type];
    const data = await Promise.all(
      mediaTypes.map(async (mediaType) => {
        const url = new URL(`${TMDB_BASE_URL}/discover/${mediaType}`);
        url.searchParams.set('with_genres', genreIds.join(','));
        url.searchParams.set('sort_by', 'popularity.desc');
        url.searchParams.set('language', 'es-MX');
        url.searchParams.set('include_adult', 'false');
        const response = await fetchTmdbJson(fetchImpl, url, accessToken);
        return (Array.isArray(response.results) ? response.results : []).map((item) => ({
          ...item,
          media_type: mediaType,
        }));
      }),
    );
    results.push(...compactAssistantResults(data.flat()));
  }
  return results.slice(0, MAX_ASSISTANT_RESULTS);
}

function compactAssistantResults(items) {
  if (!Array.isArray(items)) {
    return [];
  }
  return items
    .filter(
      (item) =>
        Number.isSafeInteger(item.id) &&
        (item.media_type === 'movie' || item.media_type === 'tv') &&
        typeof (item.title ?? item.name) === 'string' &&
        (item.title ?? item.name).trim().length > 0,
    )
    .slice(0, MAX_ASSISTANT_RESULTS)
    .map((item) => ({
      id: item.id,
      media_type: item.media_type,
      title: item.title ?? item.name,
      overview: typeof item.overview === 'string' ? item.overview.slice(0, 360) : '',
      release_date: item.release_date ?? item.first_air_date ?? '',
      vote_average: typeof item.vote_average === 'number' ? item.vote_average : 0,
      popularity: typeof item.popularity === 'number' ? item.popularity : 0,
      genre_ids: Array.isArray(item.genre_ids) ? item.genre_ids.slice(0, 5) : [],
      poster_path: typeof item.poster_path === 'string' ? item.poster_path : null,
    }));
}

async function fetchTmdbJson(fetchImpl, url, accessToken) {
  const tmdbResponse = await fetchImpl(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!tmdbResponse.ok) {
    throw new Error(`TMDB respondió ${tmdbResponse.status} para ${url.pathname}.`);
  }
  return tmdbResponse.json();
}

function isAllowedOrigin(origin, allowedOrigins, allowLocalhost) {
  if (allowedOrigins.includes(origin)) {
    return true;
  }
  if (!allowLocalhost) {
    return false;
  }
  try {
    const url = new URL(origin);
    return (
      url.protocol === 'http:' &&
      (url.hostname === 'localhost' ||
        url.hostname === '127.0.0.1' ||
        url.hostname === '[::1]')
    );
  } catch {
    return false;
  }
}

function sendJson(response, statusCode, data) {
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(data));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const port = Number.parseInt(process.env.PORT ?? '3000', 10);
  const allowedOrigins = (process.env.CORS_ORIGINS ??
    'http://localhost:5000,http://127.0.0.1:5000,http://localhost:7357,http://127.0.0.1:7357')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const server = createServer(
    createHandler({
      accessToken: process.env.TMDB_ACCESS_TOKEN?.trim() ?? '',
      allowedOrigins,
      allowLocalhost: process.env.NODE_ENV !== 'production',
      geminiApiKey: process.env.GEMINI_API_KEY?.trim() ?? '',
      geminiModel: process.env.GEMINI_MODEL?.trim() || 'gemini-3.5-flash-lite',
      assistantDailyTokenLimit: Number.parseInt(
        process.env.AI_DAILY_TOKEN_LIMIT ?? '100000',
        10,
      ),
    }),
  );

  server.listen(port, '0.0.0.0', () => {
    console.log(`PeliChrus API escuchando en el puerto ${port}.`);
    if (!process.env.TMDB_ACCESS_TOKEN?.trim()) {
      console.warn('TMDB_ACCESS_TOKEN no está configurado; /api/search responderá 503.');
    }
    if (!process.env.GEMINI_API_KEY?.trim()) {
      console.warn('GEMINI_API_KEY no está configurado; /api/assistant responderá 503.');
    }
  });
}
