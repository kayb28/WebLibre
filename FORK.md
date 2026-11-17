# WebLibre — registro del fork (kayb28)

Fork de [FaFre/WebLibre](https://github.com/FaFre/WebLibre) con un objetivo: **un navegador que funcione mejor con las interfaces web de los modelos de IA** (chats web). Este documento registra qué se hizo, build por build, para que ninguna función se pierda entre versiones.

## Versiones del fork

| Release | versionCode | Contenido |
|---|---|---|
| v0.50.0-alpha-fork.1 | 423 | Solo artefactos de CI; sin GitHub Release. CI: `workflow_dispatch`, artefactos APK, caché Gradle/Pub (`591b7b41`) |
| v0.50.0-alpha-fork.2 | 423 | Publicada. CI + idioma de UI por defecto = idioma del sistema (`44679b7b`) |
| v0.50.0-alpha-fork.3 | 423 | Publicada. + Hibernación de pestañas inactivas (30 min, luna) (`41d473f6`) + auto-ocultar barra contextual al scroll (`b47b1403`) + CI sin APKs Impeller (`02f1d373`) |
| v0.50.0-alpha-fork.4 | **483** | Publicada. Fix de versionCode (423 < 473 de la alpha-6 instalada — Android rechazaba el update) (`62d818e1`) |
| v0.50.0-alpha-fork.5 | **493** | Publicada. **Primera release con todo el trabajo de IA**: merge `main` → `feature/chat-generation-detection` (`aeafcd58`) |
| v0.50.0-alpha-fork.6 | **503** | Publicada. Mejoras UI/rendimiento + fix de integración hibernación ↔ generación (ver abajo) |

## El trabajo de IA (feature/chat-generation-detection)

1. **Keep-alive en segundo plano por sitio** (`c73263f0`): foreground service `dataSync` (`KeepAliveService.kt`) que mantiene el proceso vivo mientras haya una pestaña abierta de un sitio marcado; toggle por sitio en la hoja de info. Arranca con la primera pestaña marcada, se detiene con la última.
2. **Detección de generación activa** (`68b7a8e3`): extensión integrada `chat_detector` (background.js + content.js) observa streams de respuesta del motor; SSE y endpoints de completación reconocidos abren una "generación" en su pestaña exacta. Máquina de estados en Dart: `generating → stabilizing → completed` (`chat_session.dart`), con `stabilizationDelay` 3 s y `completedRetention` 30 s. El keep-alive corre si hay un sitio marcado abierto **o** cualquier pestaña en generación.
3. **Endurecimiento del detector** (`e817c079`): solo streams POST confiables (los GET de notificaciones auto-reconectables mantenían el servicio vivo 24/7); listeners webRequest filtrados a `xmlhttprequest`; ventana de confianza por edad de la **cadena** de streams (10 min máx), no del último stream. Permisos: se quitó `webRequestBlocking`.
4. **Pool de procesos de contenido = 8** (`a40e9e8c`): `dom.ipc.processCount` en el baseline del engine (rama default de Gecko, respeta overrides de usuario). Los chats ya no se recargan con 3-4 pestañas abiertas.
5. **Fix del teclado sobre el input del chat** (`4739558a`, `6f2e1559`): insets re-despachados en cada resume (`requestApplyInsets` en `onPostResume` + al recuperar foco); latch de animación IME limpiado si quedó huérfano tras pausa.
6. **Fix del puente de prefs** (`248f9584`): ints de 32 bits llegan como `Int` de Kotlin y `setPref` los rechazaba; el baseline entero fallaba silenciosamente.
7. **Fix de compilación** (`1414cec0`, `79543652`): EventChannel/EventSink y genéricos del snapshot map; coma suelta tras un `when`.

## Mejoras de esta build (fork.6)

- **Indicador "generando…" en pestañas**: punto pulsante (primary color) en el thumbnail del grid y en la fila de subtítulo de la lista mientras el chat de esa pestaña está generando; punto tenue durante `stabilizing`. Widget: `generating_indicator.dart`. El estado es el mismo que mantiene el keep-alive, lo que ves es lo que protege el servicio.
- **Fix de integración hibernación ↔ generación**: la política de hibernación (30 min) ahora excluye pestañas con generación activa (`isActiveGeneration`) — suspender su sesión del motor mataría el stream que el keep-alive protege. Este caso era la pérdida de función más probable entre versiones.
- **Sección Performance en settings.json**: `dom.image-lazy-loading.enabled` = true (lazy-load de imágenes fuera del viewport). Verificada contra Firefox (documentada desde Firefox 75). `network.prefetch-next` e HTTP/3 ya existían en el archivo y NO se duplicaron.
- **Registro**: este archivo FORK.md + notas de release en cada prerelease del repo.

## Convenios del fork

- versionCode estrictamente creciente: …423 (fork.1-3, error) → 483 (fork.4) → 493 (fork.5) → 503 (fork.6).
- Notas de release en español en cada prerelease (el upstream no las llena).
- El árbol de feature se mantiene siempre por delante de main; main absorbe por merge, nunca se descarta trabajo.
