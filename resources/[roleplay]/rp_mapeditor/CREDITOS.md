# Créditos de rp_mapeditor

| Archivos | Origen en el repo | Autor y licencia |
|---|---|---|
| `images/keys/*.png` | `assets/kenney/teclas/teclado-raton/64px/` | Kenney, Input Prompts (CC0) — `assets/kenney/licencias/input-prompts.txt` |
| `html/sounds/*.ogg` | `assets/kenney/sonidos/interfaz/` | Kenney, Interface Sounds (CC0) — `assets/kenney/licencias/interface-sounds.txt` |
| Miniaturas 3D | recurso `object_preview` | Ren712 (ver `object_preview/readme.txt`) |

`server/s_models.lua` y `html/models.js` solo contienen ids y nombres de modelos, generados con
`tools/generar-catalogo.ps1` desde la instalación local de GTA SA; no incluyen archivos del juego.

`html/categories.js` (árbol de categorías del navegador de objetos y palabras clave) se genera con
`tools/generar-categorias.ps1` a partir de `[editor]/editor_gui/client/browser/objects.xml` de
[multitheftauto/mtasa-resources](https://github.com/multitheftauto/mtasa-resources) — MIT License,
Copyright (c) 2008-2020 mtasa-resources contributors. Nombres de categoría traducidos al español.
