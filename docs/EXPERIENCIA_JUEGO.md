# Experiencia de juego (UX) en Thorium

Cómo hacer que un sistema **se entienda solo**: que un jugador que nunca lo vio (y que puede ser un
niño) sepa qué hacer sin leer un manual ni que nadie se lo explique. Es el estándar de las reglas
`UX-*` de [`ESTANDAR_RECURSOS.md`](ESTANDAR_RECURSOS.md) y lo aplican las skills `crear-recurso`,
`mejorar-recurso`, `arreglar-recurso` e `interfaz-cef`.

Caso de referencia: **`rp_pizzeria`** (trabajo de pizzero). Una jugadora nueva lo completó sin ayuda.
Todo lo de abajo está implementado allí; copia de ese código antes de inventar otro.

## Principios

1. **Una cosa a la vez.** En cada momento hay *un* objetivo destacado. Lo demás se atenúa o no se dibuja.
   Ocho marcadores brillantes, una flecha, un visor y una tarjeta a la vez agobian (caso real).
2. **Mostrar antes que explicar.** La tecla dibujada, el ratón dibujado, una línea guía con un cuchillo
   que la recorre... valen más que una frase. El texto, de una línea.
3. **La guía va donde el jugador mira.** Nunca una tarjeta fija en una esquina que obliga a mirar
   arriba y luego a la izquierda: se coloca junto al objeto o al panel que importa.
4. **Cada acción tiene respuesta.** Sonido, animación o efecto al hacer algo y al hacerlo bien.
5. **Se acepta la acción donde el jugador la intenta.** Si va a entregar al cliente, se entrega donde
   está el cliente (todo el mostrador), no en un punto exacto que hay que adivinar.
6. **El jugador ve cómo va.** Estado de los NPC, tiempo, progreso y resultado siempre visibles y claros.

## Reglas (resumen de `UX-*`)

| ID | Qué |
|---|---|
| UX-01 | Toda interacción muestra **la tecla o el gesto dibujado** (`assets/kenney/teclas/`): E en el aviso y sobre el objeto; ratón de clic o arrastrar en las acciones de ratón. |
| UX-02 | **Una cosa a la vez**: dentro de una actividad, indicadores discretos y solo se enciende lo útil ahora. |
| UX-03 | Actividad con varios pasos = **tutorial guiado** automático la primera vez y repetible a petición; el paso se deduce del estado y avanza solo. |
| UX-04 | La guía **va donde hay que mirar**: visor/resaltado sobre el objetivo 3D; foco con pantalla oscura sobre la parte del HUD; tarjeta junto al foco. |
| UX-05 | Paneles CEF con varios pasos: **entrenador** (orden fijo, solo lo tocable iluminado, globo pegado, herramienta automática, conteo) al menos en el tutorial y niveles bajos. |
| UX-06 | **Respuesta a cada acción**: sonido por evento (variantes al azar si se repite, nunca en ráfaga), efectos de acierto y recompensa visible. |
| UX-07 | **Estado legible de los NPC y del tiempo**: globos de ánimo (`assets/kenney/emotes/`), «!» cuando esperan al jugador, urgencia multimodal cuando algo está por fallar. |
| UX-08 | La acción se acepta **donde el jugador la intenta** y los momentos los marca lo que se ve (ej.: «llegó a la caja» lo avisa el ped, con mínimo validado en el servidor). |
| UX-09 | Durante una actividad con HUD propio, el HUD general se oculta con `rp_hud:setHudHidden` (no con `setHudSuppressed`, que quita chat y avisos). |
| UX-10 | Assets **desde `assets/`** (biblioteca del repo, licencia libre), copiando **solo** los archivos usados al recurso y anotándolos en `CREDITOS.md`. |

## Patrones (con dónde está el código)

### Tecla y ratón dibujados (UX-01)
- Imágenes: `images/keys/keyboard_e.png`, `mouse_left.png` (clic), `mouse_move.png` (arrastrar), de
  `assets/kenney/teclas/teclado-raton/128px/`. Hay de todas las teclas, con y sin contorno.
- dx: textura creada **una vez** (al empezar la actividad, nunca en `onClientRender`) y dibujada a la
  izquierda del texto del aviso, y sobre el objeto resaltado. `rp_pizzeria/client/c_pizzeria.lua` (aviso)
  y `c_tutorial.lua` (resaltado).
- CEF: `<img class="key-ico" src="../images/keys/mouse_move.png">` dentro del globo o del paso. Sobre
  fondo claro, contorno con `filter: drop-shadow(0 0 1px #2b2520)` (las teclas de Kenney son blancas).

### Indicadores discretos y lo útil ahora (UX-02)
- `rp_markers` es para **sitios en la calle** (tiendas, puertas). Dentro de una actividad con muchas
  estaciones juntas, indicador propio: aro fino en el suelo (`dxDrawLine3D`) y nombre solo de cerca.
- Se enciende (color y pulso) solo lo que sirve **ahora** según el estado: con la pizza cruda en la
  mano, los hornos libres; con la caja, el mostrador. `c_tutorial.lua` → `updateRelevant`, `drawStations`.

### Guía hacia el objetivo (UX-04)
- **Lejos**: visor de esquinas verdes sobre el punto (`getScreenFromWorldPosition`); si está fuera de
  pantalla, triángulo verde en el borde apuntando hacia él (`dxDrawPrimitive`).
- **Cerca (≈2,5 m)**: el **objeto real resaltado** con un marco blanco que late. Para muebles del mapa
  (no son elementos), se crea una copia invisible del modelo (`setElementAlpha 0`, sin colisión) solo
  para medir su caja (`getElementBoundingBox` + `getElementMatrix`) y proyectar sus 8 esquinas.
  Modelo y posición reales con `scripts/leer-ipl-interior.ps1`. Para un NPC, se usa el ped.
- Código: `c_tutorial.lua` → `drawGuide`, `screenBox`, `ghostOf`.

### Foco sobre el HUD (UX-04)
- Cuando el paso trata de la interfaz (la comanda, una barra), **toda la pantalla se oscurece** y solo
  queda iluminado ese panel con borde blanco que parpadea, sin guía 3D a la vez:
  `.spot { z-index: 50; box-shadow: 0 0 0 4000px rgba(0,0,0,.62); outline: 3px solid #fff; animation: spotBlink 1s infinite; }`
- La tarjeta del tutorial se coloca al lado del panel enfocado; con objetivo 3D, Lua manda su posición
  en pantalla (máx. 10/s, umbral 10 px) y la tarjeta se pone a su lado. Con una ventana abierta se esconde.
  `app.js` → `placeTutorial`, `PZ.tutorialAt`, `PZ.tutorialHidden`.

### Tutorial guiado (UX-03)
- Automático si el jugador nunca completó la actividad (contador de `rp_jobs`/BD); botón «con tutorial»
  para repetirlo. El servidor simplifica la partida (un solo cliente, pedido fácil, sin prisa).
- **El paso se deduce del estado** que manda el servidor (qué lleva en la mano, qué hay en el horno...),
  no de un contador: si el jugador se adelanta o se equivoca, la guía se corrige sola.
- Texto de **una línea** por paso, verbo en imperativo («Pulsa E en el horno»). Al final, 2-3 pasos
  informativos de lo que no usó (despensa, freidora) y un cierre. `c_tutorial.lua` → `currentStep`.

### Entrenador dentro de un panel (UX-05)
- Pasos en **orden obligatorio** (salsa → queso → ingredientes → horno): sin él, un jugador nuevo hace
  el paso 3 antes que el 1 (caso real).
- Oscurece la ventana (`.coach-dim`), ilumina **solo** lo que hay que tocar (`.coach-spot`), globo pegado
  a ese elemento con «Paso N de M», el gesto dibujado y el conteo («Llevas 2 de 4»). Al cambiar de paso
  elige sola la herramienta y suena un aviso. `app.js` → `coach()`.
- Guías que enseñan haciendo: línea punteada numerada con un objeto animado que la recorre y **ajuste**
  del trazo a la guía con «¡Bien!». Se quitan al subir de nivel (`GUIDES_UP_TO_LEVEL`) para que
  progresar se note. `app.js` → `panelCut`.

### Respuesta y recompensa (UX-06)
- Un sonido por evento (`SOUNDS` en `app.js`, con variantes al azar para lo repetido). **Nunca** un
  sonido por frame o por tramo mientras se arrastra: uno al empezar el trazo y otro al completarlo
  (caso real: la salsa sonaba «a fallo»).
- Acierto: destello, rebote, «¡Bien!». Resultado: tarjeta con nota y desglose, la queja concreta si salió
  mal, confeti en las excelentes y el dinero que vuela al marcador. Efectos 3D de GTA (`createEffect`,
  `fxAddSparks`) para lo que pasa en el mundo (vapor, humo de quemado). `c_fx.lua`.

### Estado de NPC y urgencia (UX-07)
- Globo sobre la cabeza (`assets/kenney/emotes/vector/estilo-3-x4/`): cara según la
  paciencia, **«!» que late cuando el NPC espera al jugador**, corazones, 💲 propina, 💢 queja.
- Urgencia **multimodal** cuando algo está por fallar: la música acelera (`playbackRate`, gradual), suena
  un reloj, los bordes de la pantalla laten en rojo; al resolverlo todo vuelve solo a la calma.

### Interacción que no hay que adivinar (UX-08)
- Zona amplia y lógica para la acción (todo el mostrador), validada en el servidor con margen.
- Lo que el jugador ve manda: el cliente avisa «el NPC llegó» y el servidor lo acepta si es plausible
  (tiempo mínimo); un tiempo calculado queda como respaldo.
- NPC que caminan: controles `"forwards"` + `"walk"` (con s), orientándolos al siguiente punto, como
  `rp_citizens` (`setWalking`). Nunca animación de andar en el sitio + deslizar, ni teletransporte.

## Assets

**Todo sale de [`assets/`](../assets/README.md), en la raíz del repo**: viene con cada clon, así que no
hay que descargar nada. Ahí están, categorizados, los packs de Kenney (CC0) y los assets propios:

| Carpeta | Qué tiene |
|---|---|
| `assets/kenney/teclas/` | todas las teclas del teclado y el ratón (64 y 128 px, normal y contorno) + botones genéricos |
| `assets/kenney/emotes/` | globos de emoción en 8 estilos (vector y pixel); `vector/estilo-3-x4/` ya escalado para NPC |
| `assets/kenney/interfaz/` | UI Pack: botones, paneles, flechas, checks en 5 colores + fuentes Kenney Future |
| `assets/kenney/sonidos/` | 157 sonidos de interfaz (Interface Sounds, UI Audio, UI Pack) |
| `assets/propios/` | hechos para Thorium (p. ej. `sonidos/freir.wav`) |

El README de `assets/` tiene la **paleta estándar** (qué imagen y qué sonido usar en cada situación: «pulsa E»,
«arrastra», «llega alguien», «¡bien!», «se quema»...). Úsala para que toda la GM se vea y suene igual.

### Cómo usarlos
1. Elige en la paleta estándar o en las vistas previas (`assets/kenney/*/vista-previa*`).
2. **Copia solo esos archivos** al recurso (MTA no sirve `assets/`: un recurso solo usa archivos de su
   carpeta): imágenes a `rp_x/images/` (teclas en `images/keys/`), sonidos de CEF a `rp_x/html/sounds/`.
3. Decláralos en `meta.xml` y anótalos en `rp_x/CREDITOS.md` (origen en `assets/` y licencia).
4. Si un tamaño no existe (p. ej. otro estilo de emote más grande), escálalo con `scripts/escalar-png.ps1`.
5. Asset nuevo para la biblioteca: solo con licencia libre comprobada, en su categoría de `assets/`, con su
   licencia en `assets/kenney/licencias/` (o nota en `assets/README.md`) y fila en el README.
6. Si el mismo asset ya lo copian tres o más recursos, propón un recurso compartido de UI.

## Verificación (además de PRU-02)

- **Prueba del jugador nuevo**: alguien que nunca lo jugó lo completa sin que le expliquen nada.
  Si se traba, en ese punto falta guía (UX-03/04/05).
- En cada paso del tutorial hay un solo objetivo destacado y la tarjeta está junto a él.
- Cada acción suena una vez y se ve; nada suena en bucle ni se repite en ráfaga.
- Claude no puede probar el cliente: lo dice y pide a Fabián este recorrido.
