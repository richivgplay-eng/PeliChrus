# PeliChrus

Aplicación Flutter para descubrir películas y series, con datos locales de prueba y un backend Node.js opcional que protege las credenciales de TMDB.

La identidad visual usa el logo en `assets/images/pelichrus_logo.png`, la paleta turquesa y azul marino en la navegación y las acciones principales, y los iconos de marca para la pestaña y la instalación web.

En pantallas de teléfono, la app presenta una introducción breve al iniciar y continúa al tocar **Explorar ahora**. Los cambios entre Inicio y Favoritos usan una transición suave; al escribir, solo se actualiza el botón de búsqueda.

## Backend de TMDB local

Requisitos: Node.js 20.6 o posterior.

1. Copia `server/.env.example` como `server/.env`.
2. Abre `server/.env` y reemplaza `TMDB_ACCESS_TOKEN` por tu **token de acceso de lectura (Bearer) de TMDB**. Este backend no necesita la clave API v3.
3. En Windows PowerShell, ejecuta `npm.cmd start` desde la raíz del proyecto. En otros terminales, ejecuta `npm start`.
4. Comprueba `http://localhost:3000/health`. Para buscar, visita `http://localhost:3000/api/search?query=marvel`.
5. En otra terminal, ejecuta `flutter run -d chrome` para abrir la app web. Flutter usa el backend local en `http://localhost:3000` por defecto.

## Asistente de recomendaciones Peli

La pantalla principal abre directamente **Peli**, un amigo cinéfilo que conversa en español y ayuda a encontrar películas y series según el ánimo, el género o lo que te gustó. La pestaña **Buscar** conserva la búsqueda manual. Peli consulta el catálogo de TMDB desde el backend y muestra tarjetas verificadas que abren la ficha del contenido. No confirma disponibilidad en plataformas: esa información se comprueba en la ficha. La conversación no se guarda en una cuenta ni en una base de datos; el servidor envía al proveedor de IA hasta los últimos ocho turnos para mantener el hilo, afinando las recomendaciones según las respuestas anteriores.

Para activarlo, configura en `server/.env`:

```text
GEMINI_API_KEY=tu_clave_de_gemini
GEMINI_MODEL=gemini-3.5-flash-lite
AI_DAILY_TOKEN_LIMIT=100000
```

La clave se obtiene en Google AI Studio y debe permanecer únicamente en el entorno del servidor. Si no se configura, la pestaña sigue visible, pero el backend responde que el asistente no está configurado. `GEMINI_MODEL` puede cambiarse sin modificar Flutter. El servidor aplica un límite de cinco solicitudes por minuto y una cuota diaria aproximada de tokens; ambos contadores residen en memoria del proceso, se reinician al reiniciar el servidor y no son un límite monetario exacto. No publiques el endpoint como servicio público hasta añadir límites compartidos y persistentes en el hosting, porque hoy no hay autenticación, almacenamiento de uso ni infraestructura de producción configurada.

## Publicar para pruebas móviles

Render es el despliegue recomendado para las primeras pruebas: el backend recibe HTTPS y las claves se guardan como variables privadas del servicio, no en Flutter. El archivo `render.yaml` declara un servicio gratuito con comprobación de salud y un límite inicial de 5.000 tokens diarios. El nivel gratuito puede suspender el servicio cuando no se usa; el primer acceso desde el móvil puede tardar en despertar.

1. Crea un repositorio **privado** en GitHub y sube el proyecto. Confirma antes que `server/.env` esté excluido; nunca subas ni copies claves en el repositorio.
2. En Render, crea un Blueprint desde ese repositorio y completa `TMDB_ACCESS_TOKEN`, `GEMINI_API_KEY` y `CORS_ORIGINS`. Deja `GEMINI_MODEL` y `AI_DAILY_TOKEN_LIMIT` con los valores de `render.yaml`. Primero despliega el backend.
3. Cuando Render entregue una URL `https://...onrender.com`, prueba `https://...onrender.com/health`. En Render, cambia `CORS_ORIGINS` al origen HTTPS exacto donde se publicará la web (sin barra final). CORS solo controla navegadores; no autentica clientes ni impide llamadas directas al API.
4. Construye Flutter Web con `flutter build web --release --dart-define=PELICHRUS_API_BASE_URL=https://...onrender.com` y publica el contenido de `build/web` en un hosting estático HTTPS. Abre el enlace desde el móvil para probar el diseño adaptable y a Peli.
5. Para instalar la app Android, genera una compilación release con la misma URL del backend y distribuye el APK de prueba de forma privada.

Este despliegue es solo para una beta controlada: el asistente no exige inicio de sesión y sus límites se guardan en memoria, por lo que reinicios del servicio los restablecen. Limita el uso de la clave y revisa las cuotas de Google antes de compartir el enlace; antes de abrirlo al público habrá que añadir autenticación y límites persistentes.

Si un chip (por ejemplo, Marvel) no devuelve resultados después de cambiar código, detén y reinicia tanto el backend como Flutter para que tomen los cambios y la URL por defecto. Usa la app servida por este comando, sin un `--dart-define` que apunte a un puerto temporal:

```powershell
flutter run -d web-server --web-port 5000 --web-hostname 127.0.0.1
```

El chip Marvel debe abrir `/api/search?query=marvel&type=multi` en el backend. Si usas otro puerto web en desarrollo, reinicia el backend con el código actual, que admite orígenes loopback locales.

PowerShell puede bloquear `npm.ps1` por la política de ejecución de scripts. Usa `npm.cmd` en lugar de cambiar dicha política.

`server/.env` está excluido de Git. No copies credenciales a `--dart-define`, Flutter, JavaScript del navegador, imágenes Docker públicas ni archivos versionados. En desarrollo el backend acepta orígenes HTTP locales (localhost/127.0.0.1) en cualquier puerto. Para producción, establece `NODE_ENV=production`, define `TMDB_ACCESS_TOKEN` como secreto en la configuración del hosting y `CORS_ORIGINS` con el origen exacto del frontend. La app Flutter Web y las apps móviles deben llamar a este backend; no deben llamar a TMDB con el token.

El endpoint acepta `type=movie`, `type=tv` o `type=multi` (predeterminado), además de `query`, `page`, `language`, un rango opcional de años, hasta cuatro `keyword` separados por `|` y los canales configurados `fox_kids`, `tnt`, `cartoon_network`, `boomerang`, `warner`, `nickelodeon`, `disney_channel`, `hbo` y `netflix`. Las consultas de canal descubren series por red original de TMDB: Cartoon Network (56), TNT (41), The WB/Warner (21), Nickelodeon (13), Disney Channel (54), HBO (49) y Netflix (213). Fox Kids se aproxima con FOX (19), géneros de animación/infantil y fechas 1990-2004 porque era un bloque, no una red independiente consistente en TMDB. TMDB no ofrece Boomerang como red independiente en los metadatos consultados; su sugerencia se aproxima a dibujos infantiles asociados a Cartoon Network, así que esos resultados no garantizan emisión efectiva por Boomerang. TNT y otros canales solo pueden encontrarse por sus series originales: TMDB no registra de forma fiable cada película licenciada o retransmitida por un canal. El buscador Flutter muestra resultados, carteles y puntuaciones reportados por la fuente y permite paginar. Las búsquedas multi generales eliminan entradas de personas. Los resultados se ordenan por popularidad; para temas reconocidos como superhéroes, dinosaurios, comedia, películas para llorar, para reflexionar, anime y comiquitas de los 90, el backend descubre contenido por palabras clave en vez de limitarse a coincidencias del título. Anime usa metadatos localizados en español y filtra por idioma original japonés; esto no garantiza que la pista de audio esté doblada al español. Las comiquitas de los 90 se buscan como series animadas de 1990 a 1999. Las consultas libres que no se identifican como tema siguen usando la búsqueda textual de TMDB. Antes de publicar, verifica los términos y permisos comerciales de TMDB; este proyecto no implica autorización de TMDB.

La portada carga el carrusel **Top del momento** desde `/api/trending?language=es-MX`, basado en las tendencias diarias de películas y series de TMDB; no incluye personas. Las tarjetas abren la misma ficha que los resultados de búsqueda. Para una experiencia inicial más directa, la búsqueda queda vacía al abrir y los resultados solo aparecen después de una consulta. Si TMDB no responde, la sección de tendencias muestra el error y permite reintentar.

Al abrir una ficha, la app solicita `/api/title/{movie|tv}/{id}` para mostrar sinopsis, géneros, tráiler de YouTube y plataformas de Colombia. El dato de proveedores proviene de JustWatch vía TMDB, con atribución visible en la interfaz y enlace a TMDB. El botón de WhatsApp abre un chat con el contacto configurado en la app.

En emulador Android, el cliente apunta por defecto al host de desarrollo `10.0.2.2:3000`; el permiso HTTP sin TLS solo está habilitado en el manifiesto debug. En un dispositivo físico, configura la IP local del computador como URL del backend, por ejemplo `flutter run --dart-define=PELICHRUS_API_BASE_URL=http://192.168.1.20:3000`. Producción debe usar HTTPS.

## Verificación

- `npm.cmd test` (Windows PowerShell) o `npm test` ejecuta las pruebas HTTP locales del backend sin usar credenciales ni llamar a TMDB.
- `flutter analyze` y `flutter test` validan el cliente Flutter.
