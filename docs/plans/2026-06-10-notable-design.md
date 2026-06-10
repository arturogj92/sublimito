# Notable, diseño v1 (2026-06-10)

Editor de texto nativo para macOS, estilo Sublime Text. Motivación: Sublime está capado en la empresa.

## Decisiones validadas con Arturo

- **Stack:** Swift nativo (SwiftUI shell + NSTextView para el editor). XcodeGen. Sin dependencias externas: el render Markdown usa marked.js + github-markdown-css bundleados en Resources, mostrados en WKWebView.
- **Markdown:** toggle por pestaña (Cmd+Shift+P) entre texto raw y preview renderizado. Botón "Copiar raw" en el preview.
- **Buffers = ficheros físicos siempre:** un buffer sin guardar se respalda desde el primer carácter en `~/Library/Application Support/Notable/Buffers/<uuid>.txt`. Hot exit total: cerrar la app nunca pierde nada. Cmd+W tampoco pregunta, los buffers cerrados van a recientes y se recuperan. Se pueden fijar y renombrar sin guardarlos en ningún sitio.
- **Ventana única:** abrir ficheros (Finder, dock, Cmd+O, drag) siempre añade pestaña a la misma ventana.
- **Cambios externos (petición explícita):** cada buffer con ruta vigila su fichero (DispatchSource). Sin cambios locales: recarga automática. Con cambios locales: banner de conflicto con "Recargar del disco" / "Mantener lo mío". Fichero borrado: el buffer pasa a temporal respaldado, no se pierde.
- **Nombre:** Notable. Icono lo genera Arturo después.

## Arquitectura

- `NotableApp.swift`: scene Window única, menús (Cmd+N/O/S/W, Cmd+Shift+P, Cmd+P, Cmd+B, zoom), AppDelegate (open files, flush al salir).
- `AppState`: singleton observable. Lista de buffers, activo, recientes (30, persistidos), sesión (hot exit), autosave con debounce 2s, guardado, fijar, renombrar, conflictos externos.
- `Buffer`: clase observable. id, fileURL opcional, nombre, contenido, dirty, pinned, modo preview, UndoManager propio (undo por pestaña), draft en Buffers/.
- `FileWatcher`: DispatchSource sobre fd O_EVTONLY, eventos write/delete/rename, supresión durante guardados propios, rearmado tras rename (git, otros editores).
- `EditorTextView`: NSViewRepresentable de NSTextView. Números de línea (NSRulerView custom), find bar nativo (Cmd+F), fuente mono con zoom.
- `MarkdownPreviewView`: WKWebView con HTML template (css + marked inline), render incremental por JS, links abren en navegador.
- `SidebarView`: secciones Abiertos (fijados arriba) y Recientes. Context menu: fijar, renombrar, guardar, mostrar en Finder, cerrar.
- `TabBarView`, `StatusBarView` (palabras, caracteres, líneas), `QuickOpenView` (Cmd+P fuzzy sobre pestañas + recientes).

## Persistencia

- `~/Library/Application Support/Notable/session.json`: pestañas abiertas, orden, activa, flags.
- `~/Library/Application Support/Notable/recents.json`: recientes (ficheros y drafts cerrados).
- `~/Library/Application Support/Notable/Buffers/`: drafts físicos.
- UserDefaults: tamaño de fuente, sidebar visible.

## Fuera de alcance v1

Firma/notarización/Sparkle (hay skills para ello cuando toque distribuir), syntax highlighting de código, split view, plugins.
