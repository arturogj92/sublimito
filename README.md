# Sublimito

Editor de texto nativo para macOS, estilo Sublime Text. Texto plano con visor de Markdown.

_Native macOS plain text editor with a Sublime-style workflow: total hot exit, single window with tabs, Markdown preview and external change detection._

Licencia MIT. Incluye [marked](https://github.com/markedjs/marked) y [github-markdown-css](https://github.com/sindresorhus/github-markdown-css), ver `THIRD_PARTY_LICENSES.md`.

## Features

- **Nada se pierde nunca:** todo buffer es un fichero físico. Las notas sin guardar se respaldan en `~/Library/Application Support/Sublimito/Buffers/` desde el primer carácter (autosave 2s). Hot exit total: cierra la app o la pestaña sin guardar y se recupera.
- **Ventana única con pestañas.** Abrir desde Finder, dock o Cmd+O siempre va a la misma ventana.
- **Markdown:** Cmd+Shift+P alterna entre raw y preview renderizado (estilo GitHub, claro/oscuro). Botón "Copiar raw".
- **Sidebar:** Fijados, Abiertos y Recientes (30, persistidos). Fijar, renombrar, cerrar y mostrar en Finder desde el menú contextual.
- **Cambios externos:** si el fichero cambia en disco (git, otro editor) se recarga solo; si hay cambios locales, banner de conflicto. Si el fichero desaparece, el buffer pasa a nota temporal respaldada.
- **Buscador (Cmd+P):** fuzzy por nombre de pestaña o reciente, y búsqueda por contenido con salto a la línea exacta.
- Buscar/reemplazar nativo (Cmd+F), números de línea, contador de palabras, zoom de fuente (Cmd+ / Cmd-), cerrar pestaña con Cmd+W o clic central del ratón.

## Build

```bash
xcodegen generate
xcodebuild -project Sublimito.xcodeproj -scheme Sublimito -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build
cp -R build/Build/Products/Debug/Sublimito.app ~/Applications/
```

## App por defecto para ficheros de texto

```bash
swift scripts/set-default-app.swift
```

Registra Sublimito como handler de txt, md, markdown, log, ini, cfg, conf, yaml y yml.

## Atajos

| Atajo | Acción |
|-------|--------|
| Cmd+N | Nueva nota |
| Cmd+O | Abrir fichero |
| Cmd+S / Cmd+Shift+S | Guardar / Guardar como |
| Cmd+W o clic central | Cerrar pestaña (sin diálogos, nada se pierde) |
| Cmd+P | Buscador: pestañas, recientes y contenido |
| Cmd+Shift+P | Alternar vista Markdown |
| Cmd+B | Mostrar/ocultar sidebar |
| Cmd+F | Buscar en el documento |
| Cmd+Shift+] / [ | Pestaña siguiente / anterior |
| Cmd+ / Cmd- / Cmd+0 | Zoom de fuente |
