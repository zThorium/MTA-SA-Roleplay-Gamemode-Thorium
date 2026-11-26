# Sonidos de rp_pizzeria

Qué suena en cada momento está en `SOUNDS` al principio de `html/app.js` (un momento puede tener varios
sonidos y se elige uno al azar). Para cambiar uno: copia el archivo a `html/sounds/` (o `kenney/`),
cámbialo en `SOUNDS` y añade su `<file>` en `meta.xml`.

| Momento | Archivo |
|---|---|
| entra un cliente | `kenney/glass_001.ogg` |
| pedido tomado | `kenney/confirmation_001.ogg` |
| poner un ingrediente | `kenney/drop_001..004.ogg` (al azar) |
| pintar salsa o queso | `kenney/scroll_001..003.ogg` |
| meter / sacar del horno | `kenney/open_002.ogg` |
| pizza en su punto | `kenney/bong_001.ogg` |
| se está quemando | `kenney/error_006.ogg` |
| cada corte | `kenney/scratch_001..003.ogg` |
| caja cerrada | `kenney/close_002.ogg` |
| reponer en la despensa | `kenney/drop_002.ogg` |
| freidora | `sizzle.wav` (sintetizado, `tools/gen_assets.ps1`) |
| entrega buena | `kenney/confirmation_003.ogg` |
| queja o cliente que se va | `kenney/error_004.ogg` |
| botones / elegir herramienta | `kenney/click_002.ogg` / `kenney/select_002.ogg` |
| abrir / cerrar ventana | `kenney/maximize_003.ogg` / `kenney/minimize_003.ogg` |
| «¡Bien!» / «intenta seguir la línea» | `kenney/confirmation_002.ogg` / `kenney/question_001.ogg` |
| paso nuevo del tutorial | `kenney/pluck_001.ogg` |
| reloj de urgencia (cliente por irse) | `kenney/tick_002.ogg` |
| música de fondo (bucle; acelera con la urgencia) | `musica_fondo.mp3` |

Volumen de la música: `MUSIC_VOLUME` en `shared/s_config.lua`.

## Créditos y licencias

| Archivos | Autor / fuente | Licencia |
|---|---|---|
| `kenney/*` | `assets/kenney/sonidos/interfaz/` (Kenney «Interface Sounds») | CC0 (dominio público, crédito opcional) |
| `sizzle.wav` | generado con `tools/gen_assets.ps1` | propio |
| `musica_fondo.mp3` | aportado por Fabián (música libre; anotar aquí la fuente exacta) | libre |
