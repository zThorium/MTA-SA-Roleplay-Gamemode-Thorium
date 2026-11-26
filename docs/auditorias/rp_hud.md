# Auditoría de rp_hud

## 2026-11-25 · mejorar
- **Foco**: rediseño del HUD con efectos visuales y de sonido, más intuitivo y con tutorial de primera vez que explique las necesidades y los demás indicadores.
- **Nota**: 89 → 100.
- **Cambios**:
  - **Estructura (EST-02, CIC-04, CLI-01)**: scripts de cliente con `cache="false"`; nuevo `c_fx.lua` (estado compartido `Hud`, sonidos, textos flotantes, viñeta) y `c_tutorial.lua`; F7 y las teclas del tutorial ignoran chat y consola; el timer del tutorial se mata al parar.
  - **Rendimiento (CLI-02)**: la lista de blips del minimapa se refresca 1 vez por segundo en vez de en cada frame; texturas (viñeta, teclas) creadas al arrancar.
  - **Respuesta a cada acción (UX-06)**: vida con estela de daño y destello verde con «+N» al curarse; necesidades que rebotan con «+N» y sonido al comer/beber/dormir, tiemblan y suenan al entrar en rojo; dinero y banco que ruedan hasta el valor nuevo con «+$N/−$N» flotante y monedas/caída; estrella nueva que rebota con onda dorada; aviso de poca bencina; viñeta roja con latido sonoro con vida ≤ 25 y ámbar si el hambre o la sed están a 0; destello rojo al recibir daño.
  - **Una cosa a la vez (UX-02)**: aliento solo visible mientras no está lleno (y 2,5 s después) y cordura solo si baja; los iconos se deslizan a su sitio. El aviso de dinero ya no empuja el resto del bloque (flota encima).
  - **Que se entienda solo (UX-01, UX-03, UX-04)**: tutorial guiado automático la primera vez en el PC (14 pasos, los que no aplican se saltan): pantalla oscura con foco animado que viaja de indicador en indicador, tarjeta pegada con puntero, «Paso N de M», teclas y ratón dibujados (Kenney), demostración de cada necesidad (se vacía hasta rojo y se llena). Se pausa en cinemáticas y sigue después; `/hud tutorial` o `/tutorial` lo repite. **Consejos de primera vez** junto al indicador (hambre, sed, energía, aliento, cordura, vida, motor apagado, bencina, estrellas), una vez cada uno. El nombre de la necesidad aparece bajo su icono al cambiar de estado y la más urgente muestra qué hacer («Come algo: restaurante, tienda 24/7 o expendedora»). Tecla J dibujada en el velocímetro con el motor apagado.
  - **Minimapa**: destino de navegación y objetivos de misión con onda que late, halo en la flecha del jugador, nombre de zona que entra con fundido y anuncio grande al cambiar de barrio (no al entrar en interiores).
  - **Arreglos**: `/hud mapa` (o cualquier opción) ocultaba las estrellas; las estrellas y el panel de miedo de `rp_robbery` calculaban su altura con medidas antiguas y se podían solapar con dinero/banco. Ahora `c_hud` publica `Hud.starsY` y el export `getTopRightBottom()`, que usa `rp_robbery`.
  - **Assets (UX-10)**: teclas y sonidos copiados de `assets/kenney/`; `heartbeat.wav` y `coins.wav` propios (`tools/gen_sounds.ps1`, también en `assets/propios/sonidos/`). `CREDITOS.md`. `/hud sonidos` los silencia.
  - **Docs (DOC-02/03)**: fila de `RECURSOS.md` con comandos y exports, `/hud tutorial` en la ayuda F1 (`rp_help`), `getTopRightBottom` en `crear-recurso/referencia/API.md`.
- **Reglas manuales revisadas**: SEG-02/SEG-04 N/A (solo cliente, sin eventos remotos), BD-06 N/A, CIC-03 ✔ (al cambiar de personaje se reinician dinero, vida, zona y se cierra la guía sin marcarla), CIC-06 ✔ (al parar: HUD nativo, cursor y timer), INT-07 ✔ (avisos con `rp_notify`), CLI-03 ✔, UX-01..04 ✔, UX-06 ✔, UX-08/09 N/A. PRU-02: pendiente de probar en juego.
- **Pendiente**: el tutorial se guarda por PC (`@hud_tutorial.xml`), no por cuenta: un jugador nuevo en un PC ya usado no lo ve solo (puede usar `/hud tutorial`). Si se quiere por cuenta, columna en `accounts` con `migracion-bd`.
- **Probar en juego**: personaje nuevo en un PC sin `@hud_tutorial.xml` (borrar el archivo en `MTA San Andreas 1.6/mods/deathmatch/resources/rp_hud/`): a los 5 s arranca la guía; recorrerla con clic, Enter, ← y saltarla con Retroceso; `/hud tutorial` a mitad de una cinemática (se pausa). Comer/beber (rebote, «+N», sonido), correr hasta quedarse sin aliento (consejo), recibir daño y curarse, cobrar y pagar (dinero que rueda, monedas), subir al auto con motor apagado (J dibujada, consejo), conseguir una estrella, cambiar de barrio (anuncio), `/hud sonidos`, `/hud mapa` (las estrellas siguen), un robo de 24/7 (panel de miedo bajo las estrellas). Y la **prueba del jugador nuevo**: alguien que no conoce el servidor entiende el HUD sin ayuda.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 27 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos | f7 jump |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |
</details>
