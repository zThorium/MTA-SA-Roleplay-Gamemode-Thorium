# Auditoría de rp_metaldetector

## 2026-11-27 · mejorar (5 detectores por nivel, tienda CEF, nivel de buscador, modelo 3D y pose)
- **Motivo**: Fabián mandó un recurso de FiveM como referencia: tienda de detectores bloqueados por nivel con radio, profundidad y precisión, panel de progreso y detector 3D en la mano barriendo el suelo, con un color por nivel.
- **Nota**: 100 → 100 (OK 32).
- **Cambios**:
  - 5 items `metal_detector_1..5` (sustituyen a `metal_detector`, que no llegó a `main`) con `metalDetectorStats`: alcance, profundidad máxima (filtra el botín), precisión (error y engaños del VDI) y bonus de rareza.
  - Tabla `metal_detecting` (XP, objetos, dinero; BD-02) y aviso `rp:jobs:onMarketSale` en `rp_jobs`.
  - Tienda propia con panel CEF (`html/`): confirmación, entrenador de la primera compra (UX-05) y sonidos (UX-06). Sustituye a `rp_shops:addTempShop`.
  - El servidor cobra después de validar distancia, nivel, peso y efectivo, y devuelve el dinero si la entrega falla (SEG-02, ECO).
  - Detector en la mano dibujado por cada cliente (`c_hold.lua`) a partir de `rp:heldItem`: posición de la mano, orientación por el rumbo del personaje y bobina apoyada en el suelo con un rayo; barrido y ajuste en vivo con `/mdprop`. La primera versión usaba los ejes del hueso de la mano y rotaba el hombro: en juego el brazo salía en cruz y el detector hacia arriba, así que la pose del brazo quedó apagada (`POSE_ENABLED`).
  - Modelo en Blender (`tools/build_detector.py`, exporta con DragonFF).
  - `/detector` y `/hallazgos` abren el panel; se quita la bitácora dx.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: la compra la valida el servidor y el premio depende del detector que se tiene en el servidor.
  - SEG-04 ✔: cooldown de compra.
  - BD-06 ✔.
  - PRU-02 ✔: prueba del upsert de `metal_detecting`, aún sin ejecutar.
  - UX-01, UX-05, UX-06 ✔.
- **Pendiente** [A]:
  - Modelo 3D generado (5 DFF de ~2.600 triángulos, TXD de la pantalla, `tools/detector.blend`; iconos con `tools/render_icons.py`). Falta verlo en juego: orientación en la mano (`/mdprop`), iluminación y escala.
  - Afinar en juego `PROP_OFFSET` y `POSE`.
  - Comprobar que la pose del brazo no duplica la cabeza custom (`rp_heads`; con `rp_phone` pasó).
- **Probar en juego**:
  - Tienda junto al vendedor: los niveles bloqueados no se pueden comprar; confirmar la compra; sin dinero.
  - Comprar la pala.
  - Sacar el detector: que se vea en la mano y barra, también visto por otro jugador.
  - Subir de nivel (con XP alta de prueba) y que se desbloquee el siguiente detector.
  - Vender en el Puesto del buscador y ver el dinero ganado en `/detector`.
  - El alcance distinto por detector.
  - `restart` con el detector en la mano.

## 2026-11-27 · mejorar (experiencia: interfaz, sonido, efectos y sensación de hallazgo)
- **Motivo**: pedido de Fabián: «que realmente te genere eso de encontrar algo». Eligió paladas, identificación del metal, colección en BD y más botín con rarezas; aportó el pack de iconos de SwisserDev (CC0).
- **Nota**: 100 → 100 (OK 29 → 32).
- **Cambios**:
  - **Servidor**: el botín se decide al enterrar el punto. El cliente solo recibe la lectura (VDI con ±6 y un 12 % de lecturas engañosas), la profundidad y las paladas.
  - **Excavación a paladas**: eventos `stroke` y `cancelDig`. El servidor exige 550 ms entre paladas y cancela tras 20 s; el cliente no decide el premio (SEG-02).
  - **Botín**: 12 objetos en 5 rarezas, con XP por rareza. Se quita `buried_chest`, que no llegó a `main`.
  - **Colección**: tabla `metal_finds` (BD-02, migración al final de `schema.lua`), `/hallazgos` y aviso «¡nuevo!».
  - **Cliente** en tres archivos:
    - `c_ui.lua`: fuentes Rubik, texturas y formas.
    - `c_fx.lua`: hoyos, arena, revelación con aro, icono que sube, brillo, haz de luz, chispas, plano cercano con `setHudSuppressed` (INT-01) y destello para los jugadores cercanos.
    - `c_metaldetector.lua`: pantalla del detector con arco, aguja, VDI, barras y LED; audio por fuerza y tipo de metal; minijuego de paladas; tarjeta de hallazgo; bitácora con siluetas.
  - **Assets**: iconos `png-256` y `webp-100` en `assets/swisser-iconos/` (CC0). Sonidos y texturas sintetizados con `tools/gen_assets.ps1` en `assets/propios/`.
  - **Integración**: 11 iconos nuevos en `rp_inventory` y el mercado `beachfinds` ampliado.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el premio está decidido en el servidor antes de cavar y las paladas tienen ritmo mínimo.
  - SEG-04 ✔: cooldowns y tope por hora.
  - BD-06 ✔: `INSERT ... ON DUPLICATE KEY` parametrizado.
  - PRU-02 ✔: prueba del upsert de `metal_finds` en `rp_test`, aún sin ejecutar.
  - UX-01 ✔: E y Retroceso dibujadas.
  - UX-02 ✔: solo la pantalla del detector, y el aviso de cavar en el punto.
  - UX-03 ✔: guía hasta el primer hallazgo del personaje.
  - UX-05 ✔: el minijuego explica la zona verde.
  - UX-06 ✔: sonido por evento.
  - UX-07 ✔: revelación y tarjeta.
  - UX-10 ✔: `CREDITOS.md`.
- **Pendiente** [A]: los valores de juego (materiales, posición del vendedor, prop del detector) siguen sin medir. Los volúmenes de los sonidos sintetizados no se han escuchado en juego.
- **Probar en juego**:
  - Equipar el detector: sonido de encendido y barrido de la aguja.
  - Seguir la señal: el número cambia de color por metal; el hierro gruñe y el oro pita agudo; tono continuo en el punto.
  - Cavar con paladas buenas y flojas; Retroceso a mitad; quedarse 20 s sin cavar.
  - Ver la revelación de varias rarezas. Para el plano de cámara del legendario se puede bajar su peso temporalmente en `server/s_config.lua`.
  - La tarjeta «¡nuevo!» y `/hallazgos` con siluetas.
  - Que otro jugador vea el destello.
  - Abatido durante la revelación; `restart` con el detector equipado; `/debugscript 3` limpio.

<details><summary>Informe de la auditoría (mejorar)</summary>

### Auditoría automática (2026-11-27, commit adfe9fd)

**Nota: 100/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-27 · crear
- **Motivo**: pedido de Fabián: detector de metales en las playas con tienda, validación de arena, pitidos por cercanía, excavación con pala y tabla de botín, integrado en la GM (items reales, `rp_shops`, `rp_markers`, `rp_jobs` para vender).
- **Cambios**: recurso nuevo (`shared/s_config.lua`, `server/s_config.lua` con el botín, `server/s_metaldetector.lua`, `client/c_metaldetector.lua`). Items `metal_detector`, `shovel`, `scrap_metal` y `buried_chest` en `rp_inventory`. Mercado `beachfinds` en `rp_jobs` y dos items nuevos en la compraventa. Ayuda F1, catálogo del panel de admin, pruebas en `rp_test` (`s_tests_metaldetector.lua`).
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente solo propone el punto y pide excavar. El servidor revalida la distancia, la zona de playa, el detector y la pala, el estado y el cooldown, y termina la excavación con su timer. El botín vive solo en el servidor.
  - SEG-04 ✔: cooldowns de propuesta y de excavación, y tope de 40 hallazgos por hora y personaje.
  - BD-06 N/A: no tiene tablas.
  - PRU-02 ✔: se añadió prueba en `rp_test`, aún sin ejecutar.
  - UX-01 ✔: la E va dibujada.
  - UX-02 ✔: el LED es discreto y solo destaca el aviso de excavar.
  - UX-03 ✔: una guía de una línea junto al LED hasta el primer hallazgo.
  - UX-06 ✔: hay sonido para el pitido, al clavar la pala, para los golpes y para el hallazgo.
  - UX-07 ✔: el hallazgo se muestra en grande.
  - UX-08 ✔: E funciona donde está la señal.
  - UX-10 ✔: los assets están anotados en `CREDITOS.md`.
- **Pendiente** [A]:
  - Hay valores puestos a ojo que se ajustan en juego: la posición del vendedor y del puesto, los IDs de material de arena (`/detectorsuelo`) y el modelo y los offsets del prop del detector (palo de golf 333 provisional).
  - El estado equipado no sobrevive a un `restart` del recurso: hay que volver a usar el item.
- **Probar en juego**:
  - Comprar los dos items. Equipar y comprobar que no dispara ni golpea.
  - Pisar asfalto (no suena) y luego arena.
  - Seguir los pitidos y el LED y excavar.
  - Intentarlo sin pala, subir al coche, quedar abatido y salir a mitad de la excavación.
  - Vender en el Puesto del buscador.
  - Prueba del jugador nuevo. `/debugscript 3` limpio.

<details><summary>Informe de la auditoría</summary>

### Auditoría automática (2026-11-27, commit adfe9fd)

**Nota: 98/100** · OK 28 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_metaldetector.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
