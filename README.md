# LetrasCar 🎵🚗

App personal para iPhone que muestra la letra sincronizada de lo que suena en **Spotify**
como *Actividad en vivo*: en la pantalla bloqueada, en la Dynamic Island y en **CarPlay** (iOS 26).

- Canción y segundo exacto: API de Spotify (requiere Premium en la cuenta dueña de la app).
- Letras sincronizadas: [LRCLIB](https://lrclib.net), gratis.
- Sin Mac: se compila gratis en GitHub Actions y se instala con SideStore.

---

## 1. Crear la app en Spotify (5 min)

1. Entra a <https://developer.spotify.com/dashboard> con tu cuenta Premium.
2. **Create app**:
   - Nombre: `LetrasCar` (cualquiera)
   - Redirect URI: `letrascar://callback` (exactamente así) → **Add**
   - API: marca **Web API**
3. Guarda y copia el **Client ID**. (No necesitas el Client Secret.)

## 2. Subir el proyecto a GitHub y compilar

1. Crea una cuenta en <https://github.com> si no tienes.
2. **New repository** → nombre `LetrasCar` → **Public** (en público los minutos de Mac son gratis
   e ilimitados; el código no tiene datos tuyos, el Client ID se escribe dentro de la app).
3. En el repositorio vacío: **uploading an existing file** → arrastra **todo el contenido**
   de esta carpeta (incluida la carpeta `.github`) → **Commit changes**.
   - Si `.github` no se sube: **Add file → Create new file**, escribe
     `.github/workflows/build.yml` como nombre y pega el contenido de ese archivo.
4. Pestaña **Actions** → se ejecuta *Compilar LetrasCar* (unos 5–10 min).
5. Al terminar, en **Releases** (columna derecha de la portada) aparece `LetrasCar.ipa`.

## 3. Instalar en el iPhone con SideStore

1. Sigue la guía oficial para instalar SideStore desde Windows: <https://docs.sidestore.io>
   (se hace una sola vez con el iPhone conectado por cable).
2. En el iPhone, abre el link de **Releases** en Safari y descarga `LetrasCar.ipa`.
3. Ábrelo con SideStore (**Mis apps → +** y elige el archivo).
4. Cada 7 días: SideStore → **Refrescar todo**.

## 4. Usarla

1. Abre LetrasCar, pega el **Client ID** y toca **Conectar con Spotify**.
2. Pon música en Spotify y toca **Iniciar letras en vivo**.
3. Si pregunta, permite las Actividades en vivo
   (Ajustes → LetrasCar → Actividades en vivo).
4. Conecta CarPlay: la letra aparece en el panel. Si no la ves, revisa
   Ajustes → General → CarPlay → tu auto.
5. Si la letra va adelantada o atrasada, usa **Ajuste de sincronía** (±0,25 s).

## Límites conocidos

- La app se mantiene viva en segundo plano reproduciendo silencio mezclado con Spotify.
  Funciona para uso personal; Apple no la aceptaría en la App Store.
- iOS cierra las Actividades en vivo después de ~8 horas: basta con Detener e Iniciar.
- Si no hay letra en LRCLIB para una canción, se avisa en pantalla.
- Spotify se consulta cada 4 s; entre consultas el avance se calcula localmente.

## Estructura

```
project.yml                  → definición del proyecto (XcodeGen)
App/                         → app principal (SwiftUI)
  SpotifyAuth.swift          → inicio de sesión PKCE
  SpotifyClient.swift        → "¿qué suena y en qué segundo?"
  LRCLib.swift               → busca y lee letras .lrc
  LyricsEngine.swift         → sincroniza y actualiza la Actividad en vivo
  BackgroundKeeper.swift     → mantiene la app activa en segundo plano
Widget/LyricsLiveActivity.swift → vista para CarPlay, bloqueo y Dynamic Island
Shared/LyricsAttributes.swift   → datos compartidos app ↔ widget
.github/workflows/build.yml     → compilación automática del .ipa
```
