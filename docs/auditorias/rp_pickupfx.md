# Auditoría de rp_pickupfx

## 2026-11-27 · mejorar (copia animada como rp_3dtext)
- **Motivo**: Fabián quiere en todos los pickups lo mismo que en el icono de `rp_3dtext`: más pequeño, con giro propio y que suba y baje.
- **Nota**: 100 → 100.
- **Cambios**: el pickup original se aparca solo en el cliente en `HIDDEN_DIMENSION` (65000, registrada en `REGISTROS.md`) y se dibuja una copia local del modelo (`CLONE_SCALE` 0.85) que gira y flota, con el shader aplicado solo a ella (`"*"` + elemento, como `rp_3dtext`; ya no por nombre de textura global, sin riesgo de que brillen otros objetos). Sigue cambios del servidor (dimensión, modelo al comprar la casa, posición). Histéresis `TRACK_DISTANCE`/`RELEASE_DISTANCE` y animación solo a menos de `ANIM_DISTANCE`. Al parar el recurso se devuelven todos los originales. Los pickups creados en el cliente (fajos) no se aparcan para no romper su recogida.
- **Probar en juego**: casas, flecha, estrellas y camiseta giran y flotan más pequeñas y brillan; se siguen recogiendo/entrando igual; comprar una casa cambia la casa verde por la flecha; `stop rp_pickupfx` devuelve los pickups originales; FPS en una calle con muchas casas.

## 2026-11-27 · arreglar (shader sin efecto y menos glow que rp_3dtext)
- **Motivo**: en juego los pickups tenían anillo y chispas, pero no el brillo del modelo ni la columna de luz del icono de `rp_3dtext`.
- **Causa**: el shader se creaba con `elementTypes = "object"` y GTA no dibuja los pickups como objeto, así que nunca les llegaba.
- **Nota**: 100 → 100.
- **Cambios**: shader para `"world,object,other"`, aviso en `/debugscript 3` con las texturas a las que se aplicó; tinte del color del estilo (`tint`), reflejo y borde más fuertes; columna de luz, halo más grande y núcleo brillante como en `rp_3dtext`.
- **Probar en juego**: `/debugscript 3` muestra `modelo N: shader en X/Y texturas`; el modelo brilla con su color.

## 2026-11-27 · crear
- **Motivo**: Fabián pide el mismo glow y partículas del icono de `rp_3dtext` en los demás pickups del juego (casas verdes, flecha, estrellas...), optimizado y sin lag.
- **Nota**: — → 100.
- **Cambios**: recurso nuevo solo de cliente. Detecta los pickups cargados por modelo (`STYLES`) sin tocar los recursos que los crean. `fx/pickup.fx` se aplica una vez por modelo a sus texturas (`engineGetModelTextureNames`): brillo propio con pulso, reflejo y borde de color, técnica `fallback` sin shader model 3. `fx/glow.fx` (copia de `rp_3dtext`) dibuja halo, anillo y onda en el suelo y chispas. `rp_pickups` marca las estrellas recogidas con `rp:pickupUsed` hasta que reaparecen. `rp_3dtext` sube la prioridad de su shader para mandar sobre el general en el modelo 1239.
- **Reglas manuales revisadas**: CLI-02 ✔ (sin `getElementsByType` por fotograma; tope de pickups dibujados, de distancia y de chispas; orden por distancia solo si se pasa del tope) · CIC-05 ✔ (timer liberado; shaders se destruyen con el recurso) · UX-10 ✔ (sin assets externos) · PRU-02 N/A (solo cliente, sin BD).
- **Pendiente**: el shader va por nombre de textura: si otro objeto del mapa comparte nombre con una textura de estos pickups, también brillará. Comprobar en juego.
- **Probar en juego**: casas en venta y con dueño, estrellas (`/estrellas`), tiendas de ropa y robables brillan con su color, halo, anillos y chispas; al recoger una estrella su brillo se apaga; FPS estables en una calle con muchas casas.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 04f6b16)

**Nota: 100/100** · OK 26 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |
</details>
