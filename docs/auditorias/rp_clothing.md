# Auditoría de rp_clothing

## 2026-11-27 · mejorar (estudio de compra y gizmo 3D para accesorios)
- **Motivo**: Fabián pide que colocar accesorios sea fácil «estilo Blender» (antes eran deslizadores de coordenadas), un marcador de `rp_markers` en el mostrador que abra la vista de compra, previsualizar los accesorios antes de comprarlos y que el ajuste se guarde para que quede bien pegado al personaje.
- **Nota**: 94 → 98.
- **Cambios**:
  - **Marcadores** (regla 12, UX-02): la puerta (antes pickup + colshape), la salida (antes colshape) y un **mostrador** nuevo son cilindros de `rp_markers` con icono `clothes`/`exit`. Los tres se registran: `door<id>` y `exit<id>` con `ownerSaves` (se guardan en `clothing_stores` desde `rp:markers:moved`) y `caja_<tipo>` con `placePoint` (lo guarda `rp_markers` y vale para todas las tiendas del mismo tipo). El mostrador de Binco es el punto medido por Fabián (217.16, -98.67, 1005.26, int 15); los demás son provisionales a 3 m de la puerta, hasta que se coloquen con ALT.
  - **Validación en el servidor** (SEG-02): el estudio solo se abre a menos de `COUNTER_RADIUS` del mostrador, y probar o comprar vuelve a comprobarlo (`stillFitting`). Antes bastaba con estar en cualquier punto del interior. Los ajustes de accesorios se recortan con `sanitizeToyAdjust` (compartido) al guardarlos y también al comprarlos.
  - **Estudio** (`c_studio.lua`, UX-01/04/05/08): panel CEF lateral y el personaje a la izquierda con cámara orbital (arrastrar y rueda). En la tienda: ropa, catálogo con **vista previa** puesta (objeto solo del cliente) y «Mis accesorios». `/accesorios` abre el mismo estudio. El HUD se oculta con `rp_hud:setHudHidden` y los controles se devuelven al cerrar, al morir, al quedar abatido, al cerrar sesión con el personaje y al parar el recurso (CIC-05).
  - **Gizmo 3D** (`c_gizmo.lua`): flechas en los ejes del hueso para mover, anillos en los ejes del objeto para rotar (R' = Q·R, pasado a los ángulos de `bone_attach`), cubos para escalar por eje y uno central para escalar todo. G/R/S, Shift para precisión, Ctrl para encajar, Ctrl+Z para deshacer (40 pasos), Enter para guardar y Esc para cancelar. Se dibuja en 2D con los puntos proyectados, así que siempre queda visible y se puede pulsar. Las matemáticas se comprobaron con el `lua5.1.dll` del servidor (ida y vuelta entre ángulos y matriz con un error de 2e-15, base dextrógira y signo de giro).
  - **Comprar con ajuste**: `rp:cloth:buyToy(key, adjust)` guarda la posición del gizmo y te pone el accesorio si te queda hueco (`worn`). El editor antiguo (`c_editor.lua`, `editor.html/js`) se elimina.
  - **Experiencia** (UX-01, UX-03, UX-06): la tecla E y el ratón aparecen dibujados (Kenney) en el aviso y en la ayuda en pantalla, y el panel tiene un entrenador paso a paso (mover → rotar → escalar opcional → guardar o comprar) que marca cada paso al hacerlo. Hay sonidos de interfaz de la paleta estándar. Los assets se copiaron desde `assets/` y están anotados en `CREDITOS.md` (UX-10).
  - **Cabeza custom** (`c_headlink.lua`): `rp_heads` pega su cabeza al cuello (hueso 2) y el hueso 1 «Cabeza» se balancea por su cuenta al andar, así que los accesorios se separaban al moverse. Ahora, con el personaje quieto, se mide una vez la relación K = B1·Hᵀ entre el hueso 1 y el objeto cabeza, y en cada fotograma (después de `bone_attach`) el accesorio se recoloca sobre la cabeza custom con sus mismos offsets. Vale para todos los jugadores visibles y para la vista previa, y el gizmo usa el mismo marco. `rp:toy` pasa a estar sincronizado para que cada cliente reconozca los accesorios.
  - **Tiendas duplicadas**: la siembra (`seedStore`) es atómica (`WHERE NOT EXISTS`, mismo tipo a menos de 3 m) y `removeDuplicates` borra al cargar las copias (se queda la puerta colocada por un admin o, si no, la de id menor). En la BD local se borraron las 7-12 y sus `marker_points` (door/exit 7-12), con respaldo.
  - CIC-04: el temporizador que vuelve a mostrar el accesorio del servidor tras guardar se puede cancelar.
- **Reglas manuales revisadas**: SEG-02 ✔ (distancia al mostrador e interior en cada prueba y compra) · SEG-04 ✔ (ajustes recortados en el servidor, hueso entero 1-20, sin NaN ni infinitos) · BD-06 ✔ · CIC-03 ✔ (abatido o muerto cierra el estudio en cliente y servidor) · INT-07 ✔ (HUD con `setHudHidden`) · UX-01 ✔ · UX-02 ✔ (un solo marcador destacado en el mostrador) · UX-03 ✔ (entrenador) · UX-06 ✔ · UX-10 ✔ · PRU-02: sin prueba nueva en `rp_test` (no cambian el esquema ni los exports; la prueba de admin existente sigue usando `adminElements`).
- **Pendiente**: colocar con ALT los mostradores de SubUrban, ProLaps, ZIP, Victim y Didier Sachs (son provisionales). Si en el hueso del cuello (2) las flechas se mueven al revés, `computeFrame` ya intenta corregir el signo comparando con la posición real del objeto.
- **Probar en juego**: entrar a Binco → marcador en el mostrador → E abre el estudio; girar la cámara arrastrando y hacer zoom con la rueda; ropa: probar con las flechas y comprar; accesorios: tocar uno (se ve puesto), «Ajustar», arrastrar las flechas, pulsar R y arrastrar un anillo, pulsar S y escalar, Ctrl+Z, «Comprar» (sale puesto en el mismo sitio y los demás jugadores lo ven igual); en «Mis accesorios»: Ajustar → Guardar, Cancelar (vuelve como estaba), Poner, Quitar y Tirar; `/accesorios` en la calle; salir con Esc; abatido con el estudio abierto; mover con ALT la puerta, la salida y el mostrador y comprobar que persisten tras `restart rp_clothing`; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit f8ea8b3)

**Nota: 98/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_clothing.md |
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 2 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 20000 |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |

</details>
