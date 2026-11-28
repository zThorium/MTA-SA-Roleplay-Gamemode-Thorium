# Biblioteca de assets de Thorium

Imágenes y sonidos **libres** para las interfaces y los sistemas de la GM, para que todos los recursos
se vean y suenen igual sin descargar nada aparte. Cómo usarlos para que el juego se entienda solo:
[`docs/EXPERIENCIA_JUEGO.md`](../docs/EXPERIENCIA_JUEGO.md) (reglas `UX-*`).

> **MTA no sirve esta carpeta.** Un recurso solo puede usar archivos que estén **dentro de su propia
> carpeta** y declarados en su `meta.xml`. Para usar un asset: **cópialo** al recurso (ver abajo).
> Esta carpeta está fuera de `resources/`, así que el servidor la ignora.

## Contenido

```
assets/
  kenney/                         Kenney (www.kenney.nl) · CC0 (ver licencias/)
    teclas/
      teclado-raton/64px|128px    todas las teclas y el ratón, normal y _outline (Input Prompts 1.5)
      generico/64px|128px         botones, sticks y gatillos genéricos
      vista-previa/               hoja con todas, para elegir de un vistazo
    emotes/
      vector/estilo-1..8          globos de emoción 32x38 (8 estilos de globo)
      vector/estilo-3-x4          estilo 3 (globo redondo) ya escalado x4: el que usa la GM
      pixel/estilo-1..8           los mismos en pixel art
      vista-previa.png
    interfaz/
      png/<Color>/Default|Double  UI Pack: botones, paneles, flechas, checks, sliders (Blue, Green, Grey, Red, Yellow, Extra)
      fuentes/                    Kenney Future y Future Narrow (.ttf)
      vista-previa.png
    sonidos/
      interfaz/                   Interface Sounds: 100 sonidos (back, bong, click, close, confirmation, drop,
                                  error, glass, glitch, maximize, minimize, open, pluck, question, scratch,
                                  scroll, select, switch, tick, toggle)
      ui/                         UI Audio: 51 (click1-5, mouseclick1, mouserelease1, rollover1-6, switch1-38)
      ui-pack/                    6 (click-a/b, switch-a/b, tap-a/b)
      impacto/                    Impact Sounds 1.0: 130 (impactPunch_medium/heavy, impactSoft, impactBell, impactGlass,
                                  impactMetal, impactWood, impactPlate, impactMining, footstep_*)
      voces-luchador/             Voiceover Pack: Fighter: 46 voces de narrador en ingles (1-10, fight, ready, round_1-5,
                                  you_win, you_lose, combo, player_1/2, prepare_yourself, winner, game_over...)
    licencias/                    License.txt original de cada pack
  pixabay/sonidos/                golpe de boxeo, campana de ring y público de estadio (Licencia de Pixabay, ver pixabay/LICENCIA.md)
  propios/                        hechos para Thorium
    sonidos/freir.wav             aceite friendo (sintetizado, rp_pizzeria/tools/gen_assets.ps1)
    sonidos/heartbeat.wav         latido "lub-dub" (vida baja; sintetizado, rp_hud/tools/gen_sounds.ps1)
    sonidos/coins.wav             monedas al cobrar (sintetizado, rp_hud/tools/gen_sounds.ps1)
    sonidos/disparo_rifle.wav     disparo de rifle (tirador del helicoptero; sintetizado, rp_wanted/tools/gen_sounds.ps1)
    sonidos/alarma_auto.wav       alarma de auto en bucle de 2 s y alarma_chirp.wav (pitido doble al apagarla); sintetizados, rp_cartheft/tools/gen_sounds.ps1
    sonidos/detector/             pitidos agudo/grave, tono y zumbido en bucle, encendido, campanas de hallazgo por rareza,
                                  destellos y «nuevo en la colección» (sintetizados, rp_metaldetector/tools/gen_assets.ps1)
    texturas/detector/            brillo radial, aro, destello de 4 puntas, hoyo en la arena y viñeta (mismo script)
  swisser-iconos/                 iconos fotorrealistas de items (SwisserDev/fivem-icons-photoreal, CC0 1.0, LICENSE.txt):
                                  png-256/ para dx (dxCreateTexture no lee webp) y webp-100/ para paneles CEF.
                                  Paquete completo (1235 iconos): github.com/SwisserDev/fivem-icons-photoreal (índice items.json)
  fuentes/
    rubik/                        Rubik Regular, Medium y SemiBold (.ttf, subconjunto latino con tildes, ñ, ¿ ¡) · SIL OFL 1.1 (OFL.txt)
  banderas/                       29 banderas 4:3 en SVG (<iso>.svg: Hispanoamérica, España, EE. UU., Brasil, Europa) · flag-icons de lipis, MIT (LICENSE.txt)
```

Nombres de las teclas: `keyboard_<tecla>.png` (`keyboard_e`, `keyboard_f1`, `keyboard_space`,
`keyboard_arrow_up`...), con variante `_outline` (solo contorno). Ratón: `mouse_left`, `mouse_right`,
`mouse_move` (arrastrar), `mouse_scroll`, `mouse_scroll_up/down`.

## Paleta estándar (úsala para que toda la GM sea coherente)

### Fuentes

| Para | Archivo |
|---|---|
| Texto que se lee (avisos, globos, nombres, subtítulos) | `fuentes/rubik/rubik_medium.ttf` (nombres: `rubik_semibold.ttf`) |
| Etiquetas cortas en mayúsculas y titulares grandes (INFO, SUSURRO, IDs) | `kenney/interfaz/fuentes/Kenney Future.ttf` |

Kenney Future no tiene minúsculas reales y tiene esquinas biseladas: en frases largas cuesta leerla.

### Imágenes

| Para | Archivo |
|---|---|
| Pulsa E (interacción universal) | `kenney/teclas/teclado-raton/128px/keyboard_e.png` |
| Otra tecla (F, H, Y/N...) | `kenney/teclas/teclado-raton/128px/keyboard_<tecla>.png` |
| Haz clic | `kenney/teclas/teclado-raton/128px/mouse_left.png` |
| Arrastra (pintar, cortar, mover) | `kenney/teclas/teclado-raton/128px/mouse_move.png` |
| Globo de ánimo de un NPC | `kenney/emotes/vector/estilo-3-x4/`: `emote_faceHappy` (bien), `emote_dots3` (esperando), `emote_faceSad` (molesto), `emote_faceAngry` (enojado) |
| «Te estoy esperando / atiéndeme» | `emote_exclamation` (que lata) |
| Reacción buena / propina / queja | `emote_hearts` / `emote_cash` / `emote_anger` |
| Otros estados | `emote_question` (duda), `emote_idea`, `emote_sleep`, `emote_music`, `emote_alert`, `emote_stars` |

Los emotes no son cuadrados (32x38; ×4 = 128x152): dibújalos con esa proporción.
Las teclas son blancas: sobre fondo claro, ponles contorno (`filter: drop-shadow(...)` en CEF).

### Sonidos

| Momento | Archivo (`kenney/sonidos/interfaz/`) |
|---|---|
| Llega alguien / aviso amable | `glass_001.ogg` |
| Acción confirmada (pedido tomado, compra) | `confirmation_001.ogg` |
| Acierto («¡bien!») | `confirmation_002.ogg` |
| Éxito grande / cobro | `confirmation_003.ogg` |
| Algo está listo (temporizador cumplido) | `bong_001.ogg` |
| Error o algo que va mal | `error_004.ogg` |
| Alarma (se quema, se acaba el tiempo) | `error_006.ogg` |
| Duda / «inténtalo otra vez» | `question_001.ogg` |
| Poner o soltar algo (varía entre ellos) | `drop_001..004.ogg` |
| Cortar / rasgar (varía) | `scratch_001..003.ogg` |
| Untar / deslizar (uno por trazo, nunca en ráfaga) | `scroll_001..003.ogg` |
| Abrir / cerrar ventana | `maximize_003.ogg` / `minimize_003.ogg` |
| Abrir algo físico (puerta, horno) / cerrar (caja) | `open_002.ogg` / `close_002.ogg` |
| Botón / elegir opción | `click_002.ogg` / `select_002.ogg` |
| Paso nuevo de tutorial | `pluck_001.ogg` |
| Reloj de urgencia (uno por segundo) | `tick_002.ogg` |
| Vida baja (latido) / cobrar dinero | `propios/sonidos/heartbeat.wav` / `propios/sonidos/coins.wav` |
| Golpe / golpe bloqueado / campana (combate) | `impacto/impactPunch_medium_00N.ogg` / `impacto/impactSoft_medium_00N.ogg` / `impacto/impactBell_heavy_000.ogg` |
| Narrador de combate o competición (cuenta, ¡pelea!, ganaste) | `voces-luchador/` (en inglés; caso de uso: `rp_gym`) |

## Cómo usarlos en un recurso

1. Elige en la vista previa o en la paleta de arriba.
2. **Copia solo esos archivos** al recurso: imágenes a `rp_x/images/` (teclas en `images/keys/`), sonidos de
   CEF a `rp_x/html/sounds/`. Nunca una carpeta entera.
3. Decláralos en `meta.xml` (`<file src="..."/>`).
4. Anótalos en `rp_x/CREDITOS.md` (origen en `assets/` y licencia).
5. Si el mismo asset ya lo copian **tres o más recursos**, propón un recurso compartido de UI en vez de una copia más.

Desde dx: `dxCreateTexture("images/keys/keyboard_e.png")` una vez (nunca en `onClientRender`).
Desde CEF: `<img src="../images/keys/mouse_left.png">` y `new Audio("sounds/kenney/glass_001.ogg")`.

## Añadir assets nuevos

- Solo con licencia libre y comprobada (CC0 ideal; CC-BY obliga a dar crédito). Nunca material de Rockstar
  ni de origen desconocido (regla `UX-10`).
- En su categoría (`teclas/`, `emotes/`, `interfaz/`, `sonidos/` o `propios/`), con su licencia en
  `licencias/` y una fila en este README. Si un asset se usa a menudo, añádelo a la paleta estándar.
- Fuera de la carpeta: los vectoriales (SVG/SWF) y los mandos de consola de Input Prompts (no se usan en MTA).
