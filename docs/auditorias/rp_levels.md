# Auditoría de rp_levels

## 2026-11-26 · mejorar · foco: HUD de niveles más propio, con sonidos y anuncio central al subir de nivel
- **Motivo**: Fabián: la barra «se ve muy IA y básica y sin sonidos cool»; quiere el anuncio central de `rp_notify` al subir de nivel.
- **Nota**: 96 → 98.
- **Cambios**:
  - Barra rediseñada con la línea de `rp_notify`: tarjeta trapezoidal colgada del borde superior que baja con rebote, insignia con el nivel y **aro de progreso**, etiqueta `NIVEL N`, contador **`+N XP` que sube rodando**, barra redondeada con la parte ganada en blanco que se tiñe y cabeza brillante, y `actual / necesario XP · faltan N para el N+1`. Formas suavizadas (`client/c_dx.lua`), fuentes de `rp_notify` (`:rp_notify/fonts/...`).
  - Al subir de nivel: barra y aro en dorado, destello y onda desde la insignia, chispas doradas, brillo que cruza la tarjeta, el número viejo se encoge y el nuevo salta, y después la barra se rellena con el progreso del nivel nuevo.
  - **Anuncio central** de `rp_notify` («¡Nivel N!» y cuánto falta para el siguiente) con el tipo nuevo `level` (dorado, icono de flecha; el anuncio no suena porque suena la subida de nivel).
  - **Sonidos** (Kenney CC0): entrada (`maximize_003`), ticks que suben de tono mientras se llena (`tick_001`), cierre (`confirmation_001`) y subida de nivel (`levelup.ogg`, que ya estaba en el recurso pero no se usaba). Antes: un sonido nativo de GTA solo al subir.
  - Con el HUD suprimido (cinemáticas) la animación se pausa en vez de perderse.
  - `/probarnivel`: simula una subida de nivel solo en tu pantalla (no da XP ni toca la BD).
  - Fuera `sounds/levelup_alt.ogg` (no se usaba) y `LICENSE.txt` (pasa a `CREDITOS.md`).
- **Reglas manuales revisadas**: SEG-02 ✔ (el servidor no cambia; el cliente solo dibuja), CIC-06 ✔, CLI-03 ✔ (fuentes creadas una vez), UX-06 ✔ (sonido por evento, ticks con límite de 70 ms). PRU-02: pendiente de probar en juego.
- **Pendiente**: PRU-01 (prueba de `giveXP` en `rp_test`, anterior a este cambio).
- **Probar en juego**: `/probarnivel`; `/darxp <tu id> 300` (sin subir) y `/darxp <tu id> 5000` (sube uno o varios niveles); dos `/darxp` seguidos (se encolan); que el anuncio central salga dorado y la barra no tape el dinero ni las estrellas; volumen de los ticks.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit ec328f2)

**Nota: 98/100** · OK 28 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | PRU-01 | Pruebas en rp_test | usa la BD y rp_test no lo menciona |
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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
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
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-04 | Los timers se pueden cancelar |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
