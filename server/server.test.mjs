import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { afterEach, test } from 'node:test';
import { createHandler } from './server.mjs';

const servers = [];

async function startServer(options) {
  const server = createServer(createHandler(options));
  servers.push(server);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return `http://127.0.0.1:${address.port}`;
}

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise((resolve, reject) => {
          server.close((error) => (error ? reject(error) : resolve()));
        }),
    ),
  );
});

test('health reports whether the TMDB token is configured without returning it', async () => {
  const token = 'test-token-not-for-production';
  const baseUrl = await startServer({ accessToken: token });
  const response = await fetch(`${baseUrl}/health`);
  const body = await response.text();

  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(body), { status: 'ok', tmdbConfigured: true });
  assert.equal(body.includes(token), false);
});

test('trending returns localized TMDB movie and TV results without people', async () => {
  let receivedUrl;
  let receivedAuthorization;
  const token = 'test-trending-token';
  const baseUrl = await startServer({
    accessToken: token,
    fetchImpl: async (url, options) => {
      receivedUrl = url;
      receivedAuthorization = options.headers.Authorization;
      return Response.json({
        page: 1,
        total_pages: 1,
        total_results: 3,
        results: [
          { id: 1, media_type: 'movie', title: 'Trending movie' },
          { id: 2, media_type: 'tv', name: 'Trending series' },
          { id: 3, media_type: 'person', name: 'Trending actor' },
        ],
      });
    },
  });
  const response = await fetch(`${baseUrl}/api/trending?language=es-MX`);
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(receivedUrl.pathname, '/3/trending/all/day');
  assert.equal(receivedUrl.searchParams.get('language'), 'es-MX');
  assert.equal(receivedAuthorization, `Bearer ${token}`);
  assert.deepEqual(body.results.map((item) => item.media_type), ['movie', 'tv']);
  assert.equal(body.total_results, 3);
  assert.equal(JSON.stringify(body).includes(token), false);
});

test('trending validates language and reports missing credentials', async () => {
  const baseUrl = await startServer();
  const invalidLanguage = await fetch(
    `${baseUrl}/api/trending?language=invalid`,
  );
  const missingToken = await fetch(`${baseUrl}/api/trending`);

  assert.equal(invalidLanguage.status, 400);
  assert.equal(missingToken.status, 503);
});

test('search sends the token to TMDB and excludes person results', async () => {
  const token = 'test-token-not-for-production';
  let receivedUrl;
  let receivedAuthorization;
  const baseUrl = await startServer({
    accessToken: token,
    fetchImpl: async (url, options) => {
      receivedUrl = url;
      receivedAuthorization = options.headers.Authorization;
      return Response.json({
        page: 1,
        total_pages: 2,
        total_results: 3,
        results: [
          { id: 1, media_type: 'movie', title: 'Demo Movie' },
          { id: 2, media_type: 'tv', name: 'Demo Series' },
          { id: 3, media_type: 'person', name: 'Person' },
        ],
      });
    },
  });
  const response = await fetch(`${baseUrl}/api/search?query=space&page=2`);
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(receivedAuthorization, `Bearer ${token}`);
  assert.equal(receivedUrl.pathname, '/3/search/multi');
  assert.equal(receivedUrl.searchParams.get('query'), 'space');
  assert.equal(receivedUrl.searchParams.get('page'), '2');
  assert.equal(receivedUrl.pathname, '/3/search/multi');
  assert.deepEqual(body.results.map((item) => item.media_type), ['movie', 'tv']);
  assert.equal(JSON.stringify(body).includes(token), false);
});

test('movie search uses the TMDB movie endpoint and labels its result type', async () => {
  let receivedUrl;
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      receivedUrl = url;
      return Response.json({
        page: 1,
        total_pages: 1,
        total_results: 1,
        results: [{ id: 42, title: 'Demo movie' }],
      });
    },
  });
  const response = await fetch(`${baseUrl}/api/search?query=demo&type=movie`);
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(receivedUrl.pathname, '/3/search/movie');
  assert.equal(body.results[0].media_type, 'movie');
});

test('thematic search discovers related titles by keyword and popularity', async () => {
  const requestedUrls = [];
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      if (url.pathname === '/3/search/keyword') {
        return Response.json({ results: [{ id: 9715 }] });
      }
      if (url.pathname === '/3/discover/movie') {
        return Response.json({
          total_pages: 2,
          total_results: 3,
          results: [
            { id: 1, title: 'Batman', popularity: 80 },
            { id: 2, title: 'Iron Man', popularity: 95 },
          ],
        });
      }
      return Response.json({
        total_pages: 1,
        total_results: 1,
        results: [{ id: 3, name: 'Superhero Series', popularity: 70 }],
      });
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=superh%C3%A9roes&keyword=superhero&type=multi`,
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(
    requestedUrls.map((url) => url.pathname),
    ['/3/search/keyword', '/3/discover/movie', '/3/discover/tv'],
  );
  assert.equal(requestedUrls[1].searchParams.get('with_keywords'), '9715');
  assert.equal(requestedUrls[1].searchParams.get('sort_by'), 'popularity.desc');
  assert.deepEqual(
    body.results.map((item) => item.title ?? item.name),
    ['Iron Man', 'Batman', 'Superhero Series'],
  );
  assert.equal(body.total_results, 4);
});

test('thematic search combines multiple keyword categories', async () => {
  const requestedUrls = [];
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      if (url.pathname === '/3/search/keyword') {
        return Response.json({
          results: [{ id: url.searchParams.get('query') === 'tearjerker' ? 123 : 456 }],
        });
      }
      return Response.json({
        total_pages: 1,
        total_results: 1,
        results: [{ id: 1, title: 'Emotional movie', popularity: 80 }],
      });
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=para%20llorar&keyword=tearjerker%7Cemotional&type=movie`,
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(
    requestedUrls
      .filter((url) => url.pathname === '/3/search/keyword')
      .map((url) => url.searchParams.get('query'))
      .sort(),
    ['emotional', 'tearjerker'],
  );
  assert.equal(
    requestedUrls.find((url) => url.pathname === '/3/discover/movie')
      .searchParams.get('with_keywords'),
    '123|456',
  );
  assert.equal(body.results[0].title, 'Emotional movie');
});

test('thematic discovery applies date ranges and Japanese language for anime', async () => {
  const requestedUrls = [];
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      if (url.pathname === '/3/search/keyword') {
        return Response.json({ results: [{ id: 200 }] });
      }
      return Response.json({ results: [], total_pages: 1, total_results: 0 });
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=anime&keyword=anime&type=tv&start_year=1990&end_year=1999`,
  );

  assert.equal(response.status, 200);
  const discoverUrl = requestedUrls.find((url) => url.pathname === '/3/discover/tv');
  assert.equal(discoverUrl.searchParams.get('first_air_date.gte'), '1990-01-01');
  assert.equal(discoverUrl.searchParams.get('first_air_date.lte'), '1999-12-31');
  assert.equal(discoverUrl.searchParams.get('with_original_language'), 'ja');
});

test('channel discovery filters TV series to the configured channel network', async () => {
  const requestedUrls = [];
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      if (url.pathname === '/3/search/keyword') {
        return Response.json({ results: [{ id: 11 }, { id: 12 }] });
      }
      return Response.json({
        page: 1,
        total_pages: 1,
        total_results: 1,
        results: [{ id: 101, name: 'Batman: The Animated Series' }],
      });
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=fox%20kids&keyword=cartoon%7Canimation%7Cchildren&channel=fox_kids&type=multi`,
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(
    requestedUrls
      .filter((url) => url.pathname.startsWith('/3/discover/'))
      .map((url) => url.pathname),
    ['/3/discover/tv'],
  );
  assert.equal(
    requestedUrls.find((url) => url.pathname === '/3/discover/tv')
      .searchParams.get('with_networks'),
    '19',
  );
  assert.equal(
    requestedUrls.find((url) => url.pathname === '/3/discover/tv')
      .searchParams.get('with_genres'),
    '16,10762',
  );
  assert.equal(
    requestedUrls.find((url) => url.pathname === '/3/discover/tv')
      .searchParams.get('first_air_date.lte'),
    '2004-12-31',
  );
  assert.equal(body.results[0].media_type, 'tv');
  assert.equal(body.results[0].name, 'Batman: The Animated Series');
});

test('movie requests for a channel still return channel-associated series', async () => {
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      if (url.pathname === '/3/search/keyword') {
        return Response.json({ results: [{ id: 91 }] });
      }
      return Response.json({
        page: 1,
        total_pages: 1,
        total_results: 1,
        results: [{ id: 92, name: 'TNT original series' }],
      });
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=TNT&channel=tnt&type=movie`,
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.results[0].media_type, 'tv');
});

test('TNT channel discovery works without a keyword and accepts multi search', async () => {
  let discoverUrl;
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      if (url.pathname.startsWith('/3/discover/')) {
        discoverUrl = url;
        return Response.json({
          page: 1,
          total_pages: 1,
          total_results: 1,
          results: [{ id: 42, name: 'Babylon 5' }],
        });
      }
      throw new Error(`Unexpected TMDB path: ${url.pathname}`);
    },
  });
  const response = await fetch(
    `${baseUrl}/api/search?query=TNT&channel=tnt&type=multi`,
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(discoverUrl.pathname, '/3/discover/tv');
  assert.equal(discoverUrl.searchParams.get('with_networks'), '41');
  assert.equal(discoverUrl.searchParams.has('with_keywords'), false);
  assert.equal(body.results[0].media_type, 'tv');
});

test('additional channel filters map to their TMDB networks', async () => {
  const channels = [
    ['cartoon_network', '56', '16'],
    ['boomerang', '56', '16,10762'],
    ['warner', '21', null],
    ['nickelodeon', '13', '16,10762'],
    ['disney_channel', '54', '16,10762'],
    ['hbo', '49', null],
    ['netflix', '213', null],
  ];
  for (const [channel, networkId, genres] of channels) {
    let discoverUrl;
    const baseUrl = await startServer({
      accessToken: 'test-token',
      fetchImpl: async (url) => {
        if (url.pathname.startsWith('/3/discover/')) {
          discoverUrl = url;
          return Response.json({ results: [], total_pages: 1, total_results: 0 });
        }
        if (url.pathname === '/3/search/keyword') {
          return Response.json({ results: [{ id: 700 }] });
        }
        throw new Error(`Unexpected TMDB path: ${url.pathname}`);
      },
    });
    const response = await fetch(
      `${baseUrl}/api/search?query=${channel}&channel=${channel}&keyword=cartoon&type=multi`,
    );

    assert.equal(response.status, 200, `${channel} status`);
    assert.equal(discoverUrl.pathname, '/3/discover/tv', `${channel} media type`);
    assert.equal(
      discoverUrl.searchParams.get('with_networks'),
      networkId,
      `${channel} network`,
    );
    assert.equal(
      discoverUrl.searchParams.get('with_genres'),
      genres,
      `${channel} genres`,
    );
  }
});

test('title details combine TMDB detail, video, and regional provider data', async () => {
  const requestedPaths = [];
  const baseUrl = await startServer({
    accessToken: 'test-token',
    fetchImpl: async (url) => {
      requestedPaths.push(url.pathname);
      if (url.pathname.endsWith('/videos')) {
        return Response.json({
          results: [{
            name: 'Official trailer',
            key: 'trailer-key',
            site: 'YouTube',
            type: 'Trailer',
            official: true,
            iso_639_1: 'es',
          }],
        });
      }
      if (url.pathname.endsWith('/watch/providers')) {
        return Response.json({
          results: {
            CO: {
              link: 'https://www.themoviedb.org/movie/123-watch',
              flatrate: [{ provider_name: 'Demo Stream' }],
            },
          },
        });
      }
      return Response.json({
        id: 123,
        title: 'Demo film',
        overview: 'A test overview.',
        genres: [{ id: 28, name: 'Acción' }],
        runtime: 120,
        vote_average: 8,
      });
    },
  });

  const response = await fetch(`${baseUrl}/api/title/movie/123?region=CO`);
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(requestedPaths.sort(), [
    '/3/movie/123',
    '/3/movie/123/videos',
    '/3/movie/123/watch/providers',
  ]);
  assert.deepEqual(body.genres, ['Acción']);
  assert.equal(body.videos[0].key, 'trailer-key');
  assert.equal(body.providers.region, 'CO');
  assert.equal(body.providers.flatrate[0].provider_name, 'Demo Stream');
});

test('search rejects invalid input and reports missing backend credentials', async () => {
  const baseUrl = await startServer();
  const invalidResponse = await fetch(`${baseUrl}/api/search?query=%20`);
  const missingTokenResponse = await fetch(`${baseUrl}/api/search?query=marvel`);
  const invalidTypeResponse = await fetch(`${baseUrl}/api/search?query=marvel&type=company`);

  assert.equal(invalidResponse.status, 400);
  assert.equal(missingTokenResponse.status, 503);
  assert.equal(invalidTypeResponse.status, 400);
  assert.match((await missingTokenResponse.json()).error, /TMDB_ACCESS_TOKEN/);
  const invalidDetailsId = await fetch(`${baseUrl}/api/title/movie/0`);
  assert.equal(invalidDetailsId.status, 400);
});

test('assistant uses TMDB tools and returns only verified titles', async () => {
  const tmdbRequests = [];
  const providerRequests = [];
  const tmdbToken = 'test-tmdb-token';
  const geminiKey = 'test-gemini-key';
  const baseUrl = await startServer({
    accessToken: tmdbToken,
    geminiApiKey: geminiKey,
    fetchImpl: async (url, options) => {
      tmdbRequests.push({ url, options });
      return Response.json({
        results: [
          {
            id: 15,
            media_type: 'movie',
            title: 'Película verificada',
            release_date: '2022-01-01',
            vote_average: 8.1,
            popularity: 90,
            poster_path: '/poster.jpg',
            overview: 'Sinopsis reportada por TMDB.',
          },
          { id: 99, media_type: 'person', name: 'No incluir personas' },
        ],
      });
    },
    geminiFetchImpl: async (url, options) => {
      providerRequests.push({ url, options });
      if (providerRequests.length === 1) {
        return Response.json({
          candidates: [{
            content: {
              role: 'model',
              parts: [{
                functionCall: {
                  name: 'find_titles',
                  args: { query: 'aventura', content_type: 'multi' },
                },
              }],
            },
          }],
          usageMetadata: { promptTokenCount: 120, candidatesTokenCount: 18 },
        });
      }
      const requestBody = JSON.parse(options.body);
      const toolResult = requestBody.contents.at(-1).parts[0].functionResponse;
      assert.equal(requestBody.toolConfig.functionCallingConfig.mode, 'NONE');
      assert.equal(toolResult.name, 'find_titles');
      assert.match(JSON.stringify(toolResult.response.result), /Película verificada/);
      return Response.json({
        candidates: [{
          content: {
            role: 'model',
            parts: [{ text: 'Esta aventura podría gustarte.' }],
          },
        }],
        usageMetadata: { promptTokenCount: 160, candidatesTokenCount: 12 },
      });
    },
  });

  const response = await fetch(`${baseUrl}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'user', content: 'Recomiéndame una aventura.' }],
    }),
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(providerRequests.length, 2);
  assert.equal(
    providerRequests[0].url,
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent',
  );
  assert.equal(providerRequests[0].options.headers['x-goog-api-key'], geminiKey);
  assert.equal(
    providerRequests[0].options.headers['content-type'],
    'application/json',
  );
  assert.equal(tmdbRequests[0].url.pathname, '/3/search/multi');
  assert.equal(tmdbRequests[0].options.headers.Authorization, `Bearer ${tmdbToken}`);
  assert.equal(body.reply, 'Esta aventura podría gustarte.');
  assert.deepEqual(
    body.recommendations.map((item) => item.title),
    ['Película verificada'],
  );
  assert.equal(JSON.stringify(body).includes(tmdbToken), false);
  assert.equal(JSON.stringify(body).includes(geminiKey), false);
});

test('assistant discovers real movies and series from selected genres', async () => {
  const requestedUrls = [];
  let providerTurn = 0;
  const baseUrl = await startServer({
    accessToken: 'test-token',
    geminiApiKey: 'test-key',
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      return Response.json({
        results: [
          {
            id: url.pathname.endsWith('/movie') ? 10 : 20,
            title: url.pathname.endsWith('/movie') ? 'Comedia real' : undefined,
            name: url.pathname.endsWith('/tv') ? 'Serie real' : undefined,
            popularity: 25,
          },
        ],
      });
    },
    geminiFetchImpl: async () => {
      providerTurn += 1;
      return providerTurn === 1
        ? Response.json({
            candidates: [{
              content: {
                role: 'model',
                parts: [{
                  functionCall: {
                    name: 'discover_by_genre',
                    args: { genre_ids: ['35'], content_type: 'multi' },
                  },
                }],
              },
            }],
          })
        : Response.json({
            candidates: [{
              content: {
                role: 'model',
                parts: [{ text: 'Encontré opciones de comedia.' }],
              },
            }],
          });
    },
  });

  const response = await fetch(`${baseUrl}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'user', content: 'Quiero algo gracioso.' }],
    }),
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(
    requestedUrls.map((url) => url.pathname),
    ['/3/discover/movie', '/3/discover/tv'],
  );
  assert.deepEqual(
    requestedUrls.map((url) => url.searchParams.get('with_genres')),
    ['35', '35'],
  );
  assert.deepEqual(
    body.recommendations.map((item) => item.title),
    ['Comedia real', 'Serie real'],
  );
});

test('assistant validates requests and reports missing credentials', async () => {
  const notConfigured = await startServer();
  const missingKeyResponse = await fetch(`${notConfigured}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'user', content: 'Hola' }],
    }),
  });
  assert.equal(missingKeyResponse.status, 503);

  const configured = await startServer({
    accessToken: 'test-token',
    geminiApiKey: 'test-key',
  });
  const invalidConversation = await fetch(`${configured}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'assistant', content: 'No termina en una pregunta.' }],
    }),
  });
  assert.equal(invalidConversation.status, 400);
});

test('assistant preserves up to eight turns of conversation context', async () => {
  let receivedMessages;
  const baseUrl = await startServer({
    accessToken: 'test-token',
    geminiApiKey: 'test-key',
    geminiFetchImpl: async (url, options) => {
      receivedMessages = JSON.parse(options.body).contents;
      return Response.json({
        candidates: [{
          content: { role: 'model', parts: [{ text: 'Sigamos buscando.' }] },
        }],
      });
    },
  });
  const messages = Array.from({ length: 15 }, (_, index) => ({
    role: index % 2 === 0 ? 'user' : 'assistant',
    content: `Turno ${index + 1}`,
  }));
  const response = await fetch(`${baseUrl}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages }),
  });

  assert.equal(response.status, 200);
  assert.equal(receivedMessages.length, 15);
  assert.equal(receivedMessages[0].parts[0].text, 'Turno 1');
  assert.equal(receivedMessages.at(-1).parts[0].text, 'Turno 15');
});

test('assistant enforces per-address request and daily token limits', async () => {
  const rateLimited = await startServer({
    accessToken: 'test-token',
    geminiApiKey: 'test-key',
    geminiFetchImpl: async () =>
      Response.json({
        candidates: [{
          content: { role: 'model', parts: [{ text: 'Dime qué te apetece.' }] },
        }],
      }),
  });
  const request = () =>
    fetch(`${rateLimited}/api/assistant`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [{ role: 'user', content: 'Busco una película.' }],
      }),
    });
  const responses = [];
  for (let index = 0; index < 6; index += 1) {
    responses.push(await request());
  }
  assert.deepEqual(
    responses.map((response) => response.status),
    [200, 200, 200, 200, 200, 429],
  );

  let providerCalled = false;
  const tokenLimited = await startServer({
    accessToken: 'test-token',
    geminiApiKey: 'test-key',
    assistantDailyTokenLimit: 1,
    geminiFetchImpl: async () => {
      providerCalled = true;
      return Response.json({
        candidates: [{
          content: { role: 'model', parts: [{ text: 'No disponible.' }] },
        }],
      });
    },
  });
  const limitedResponse = await fetch(`${tokenLimited}/api/assistant`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'user', content: 'Busco una película.' }],
    }),
  });
  assert.equal(limitedResponse.status, 429);
  assert.equal(providerCalled, false);
});

test('search rejects disallowed browser origins', async () => {
  const baseUrl = await startServer({
    accessToken: 'test-token',
    allowedOrigins: ['https://pelichrus.example'],
  });
  const response = await fetch(`${baseUrl}/api/search?query=marvel`, {
    headers: { Origin: 'https://unexpected.example' },
  });

  assert.equal(response.status, 403);
});

test('development allows loopback web origins, while production requires allow-list entries', async () => {
  const developmentServer = await startServer({
    accessToken: 'test-token',
    fetchImpl: async () => Response.json({ results: [] }),
  });
  const developmentResponse = await fetch(
    `${developmentServer}/api/search?query=marvel`,
    { headers: { Origin: 'http://127.0.0.1:5001' } },
  );
  assert.equal(developmentResponse.headers.get('access-control-allow-origin'), 'http://127.0.0.1:5001');

  const productionServer = await startServer({
    accessToken: 'test-token',
    allowedOrigins: ['https://pelichrus.example'],
    allowLocalhost: false,
  });
  const productionResponse = await fetch(
    `${productionServer}/api/search?query=marvel`,
    { headers: { Origin: 'http://127.0.0.1:5001' } },
  );
  assert.equal(productionResponse.status, 403);
});
