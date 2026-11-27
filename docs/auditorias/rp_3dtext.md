# Auditoría de rp_3dtext

## 2026-11-27 · mejorar (efectos del icono)
- **Motivo**: Fabián lo probó en juego: funciona, pero pide el texto más centrado y un icono más vistoso (shader animado, partículas, efectos y sonido).
- **Nota**: 100 → 100.
- **Cambios**: el icono pasa de pickup a objeto 1239 para que el cliente pueda animarlo y aplicarle shader (los shaders de textura no admiten pickups como destino). Gira y flota; `fx/icon.fx` lo pinta dorado, siempre brillante, con pulso, reflejo y borde luminoso (con técnica `fallback` sin shader model 3). `fx/glow.fx` (procedural, aditivo) dibuja halo, columna de luz, anillo y onda en el suelo y chispas que suben (tope `MAX_SPARKS`, solo a menos de `FX_DISTANCE`). Tarjeta "INFO" con fuentes de la GM (Rubik y Kenney Future), líneas partidas y centradas a mano sobre el icono, que aparece deslizándose con `glass_001.ogg` (UX-06, paleta "aviso amable"). Assets copiados desde `assets/` con `CREDITOS.md` (UX-10).
- **Reglas manuales revisadas**: UX-10 ✔ · CLI-02 ✔ (sin `getElementsByType` por fotograma: lista refrescada cada segundo; layouts de texto cacheados) · CIC-05 ✔ (timer liberado al parar; shaders y fuentes se destruyen con el recurso).
- **Pendiente**: nada.
- **Probar en juego**: el icono gira, flota y brilla de día y de noche; halo, haz, anillos y chispas visibles; al acercarte suena un cristal una sola vez y la tarjeta aparece centrada sobre el icono; un texto largo se parte en varias líneas centradas; FPS estables con varios textos juntos.

## 2026-11-27 · crear
- **Motivo**: los admins necesitan colocar textos informativos en el mundo (`/create3dtext <texto>`) y poder auditar quién los creó, editó o borró y cuándo.
- **Nota**: — → 100.
- **Cambios**: recurso nuevo. Pickup de info (modelo 1239, no se recoge) en la posición, interior y dimensión del admin; el texto viaja en el elementData `rp:text3d` y el cliente lo dibuja a menos de 8 m con línea de visión. Tablas `text3d` (borrado lógico con `deleted_at`/`deleted_by_*`) y `text3d_log` (crear/editar/borrar con cuenta, nombre y hora) al final de `schema.lua` (BD-04). Gramática Owl vía `WORLD_TYPES` de `rp_admin` (`/nearby3dtexts`, `/goto3dtext`, `/del3dtext`...); `rp_admin` ahora pasa el admin como 3.er argumento de `adminDelete` para auditar quién borra (los demás recursos lo ignoran).
- **Reglas manuales revisadas**: SEG-02 ✔ (solo comandos de servidor con `admin_level >= 1`, sin eventos remotos) · SEG-04 ✔ (texto limpiado: sin códigos de color ni caracteres de control, 2-200 caracteres, cooldown 2 s) · BD-06 ✔ (escrituras en el momento de la acción) · PRU-02 ✔ (`s_tests_3dtext.lua`) · UX-10 N/A (sin assets propios; el icono es del juego) · INT-04: los 2 `outputChatBox` son el listado de `/3dtextinfo` (permitido para listados).
- **Pendiente**: nada.
- **Probar en juego**: `/create3dtext Hola\nmundo` (sale el icono; el texto aparece al acercarse y se desvanece al alejarse; no se ve a través de paredes ni desde otra dimensión), `/edit3dtext <id> ...`, `/del3dtext <id>`, `/3dtextinfo <id>` muestra creado/editado/borrado con autor y hora; con cuenta sin admin los comandos se rechazan; `restart rp_3dtext` vuelve a cargar los textos.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 04f6b16)

**Nota: 100/100** · OK 29 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 2 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | no usa personajes |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
</details>
