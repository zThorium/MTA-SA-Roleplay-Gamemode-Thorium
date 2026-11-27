# Editor de mapas (`rp_mapeditor`)

Editor dentro del juego con lo que hace el editor de mapas de MTA, pero guardado en la BD y sin
reiniciar recursos. Lo usan los **super admins** (`admin_level` ≥ 3) y las cuentas con el **rol builder**.

## Quién puede usarlo

- Super admin: siempre.
- Builder: un super admin lo da en `F10` › **IAM** › **Builders** (nombre de la cuenta › «Hacer builder»).
  Es el permiso `world.build` del RBAC de `rp_adminpanel`; es el único permiso que se puede dar a una
  cuenta **sin rango de admin** (`players = true` en `PERMS`). También se puede dar a un rango entero
  (Admin, Admin senior) en la tabla de permisos.
- Quitarle el rol con el editor abierto lo saca al momento (`rp:adminpanel:permsChanged`).

## Flujo

1. `/mapeditor` abre la lista de proyectos. «Crear y abrir» crea uno en tu interior actual.
2. Entras al **borrador**: tu personaje queda congelado e invisible en la dimensión `27000 + id` del
   proyecto y manejas una cámara libre. Solo los builders que editan ese proyecto ven el borrador.
   Tu posición real se guarda en `rp:savePos` para que `rp_characters` no guarde la de la cámara.
3. Todo cambio se guarda al instante en `mapedit_elements` (no hay botón «guardar»).
4. **Publicar** crea una versión nueva (snapshot JSON completo en `mapedit_versions`) y pone el mapa en
   el mundo, en el interior y la dimensión del proyecto (Ajustes; 0 y 0 = mundo abierto).
   Editar después no toca lo publicado hasta volver a publicar.
5. **Versiones**: «Publicar esta» vuelve a una versión anterior; «Cargar en borrador» reemplaza el
   borrador por ella. **Despublicar** quita el mapa del mundo y devuelve los edificios quitados.

## Pantalla (como el editor de MTA)

Siempre a la vista solo hay dos barras pequeñas; lo demás se abre al usarlo y se cierra solo, para
que en pantallas pequeñas el mundo quede libre:

- **Barra de iconos** (arriba a la izquierda): proyectos, publicar, ajustes, versiones, importar/exportar,
  deshacer/rehacer, mover/girar/escalar, ejes locales, rejilla (tamaño y paso de giro), lista de
  elementos, probar y salir. Al pasar el ratón sale el nombre de cada icono.
- **Columna de tipos** (izquierda): objetos, vehículos, peds, marcadores, pickups, puntos y la goma
  para **quitar edificios del mapa original** (activa la herramienta: clic sobre el edificio).
- **Ventana de modelos**: se abre con un icono de la columna y se cierra al elegir un modelo. Los objetos
  se navegan con las mismas categorías del editor de MTA (Edificios › Fábricas y almacenes...), más
  Favoritos, Recientes y «Por archivo del juego»; la búsqueda mira nombre, número y palabras clave.
- **Propiedades**: doble clic sobre un elemento o Enter. Retroceso cierra la última ventana abierta.
- Abajo a la izquierda, la línea de estado con lo elegido y su posición. **H** oculta todo.

## Controles

| Tecla | Qué hace |
|---|---|
| W A S D · Q / E | Volar · bajar / subir (Mayús rápido, Alt lento, rueda = velocidad) |
| Clic derecho (mantener) | Mirar alrededor |
| Clic izquierdo | Elegir; arrastrar en vacío = caja; arrastrar lo elegido = moverlo por el suelo |
| Mayús + clic | Añadir o quitar de la selección |
| 1 · 2 · 3 | Gizmo mover · girar · escalar (Ctrl al escalar = uniforme) |
| L · G | Ejes locales / del mundo · rejilla sí / no (Mayús al arrastrar = sin rejilla) |
| R · Re Pág / Av Pág | Girar 90° en Z · subir / bajar |
| Supr | Borrar (en un quitado: restaurar el edificio) |
| Ctrl+Z / Ctrl+Y · Ctrl+C / Ctrl+V / Ctrl+D | Deshacer / rehacer · copiar, pegar (en el cursor), duplicar |
| F · H | Modo prueba (andas con tu personaje dentro del borrador) · ocultar paneles |
| Retroceso | Soltar lo que vas a colocar o la selección |

## Qué se puede colocar

| Tipo | Propiedades |
|---|---|
| Objeto | Cualquier modelo del catálogo de GTA SA (sin LOD), escala por eje, opacidad, colisiones, doble cara, congelado, rompible |
| Vehículo | Modelo, 2 colores, matrícula, mejoras, vinilo, cerrado, motor, luces, sirenas, congelado. Siempre invulnerable |
| Ped | Skin, animación en bucle (lista sugerida o bloque/animación propios), congelado. Invulnerable |
| Marcador | Forma, tamaño, color, icono y texto de `rp_markers`. Publicado se registra con `ownerSaves`: los admins lo mueven con el editor de `rp_admin` y el cambio se guarda en el proyecto |
| Pickup | Vida, chaleco, arma (con munición) o modelo propio, con tiempo de reaparición |
| Punto | Nombre y orientación. No se ve: otros recursos lo leen con `exports.rp_mapeditor:getMapPoints(mapa)` |
| Quitado | Edificio del mapa original (modelo + LOD) con radio. En el borrador se quita solo en el cliente de quien edita |

Ajustes del mapa (hora, clima, gravedad, velocidad, olas, distancia de dibujado): en el borrador los
ve quien edita; publicados solo se aplican a quien está en la dimensión del mapa si **no** es 0, para
no pisar el reloj y el clima globales de `rp_events`.

## Importar y exportar `.map`

- Exportar copia el XML al portapapeles y lo escribe en `rp_mapeditor/exports/<nombre>.map`.
- Importar acepta `object`, `vehicle`, `ped`, `marker`, `pickup`, `spawnpoint` y `removeWorldObject`.
  Lo que no pasa la validación (modelo inexistente, fuera del mapa, límite de 2000) se descarta y se avisa.

## Límites y seguridad

- 2000 elementos por proyecto, 250 por operación, 300 proyectos, coordenadas ±6000 y Z −200..3000.
- El servidor revalida todo: permiso, que estés editando **ese** proyecto, modelo, rangos, bloqueos
  (lo que otro builder tiene seleccionado no se puede tocar) y frecuencia de operaciones.
- Borrar un proyecto: solo quien lo creó o un super admin, y solo si no está publicado ni abierto.
- Todo lo de proyecto (crear, publicar, despublicar, importar, borrar...) queda en `mapedit_log`.

## Para desarrolladores

- Categorías: `tools/generar-categorias.ps1` descarga `objects.xml` del editor de MTA (mtasa-resources, MIT),
  traduce las categorías y genera `html/categories.js` (ejecutarlo después de generar el catálogo).
- Catálogo: `tools/generar-catalogo.ps1` lee los IDE de la instalación de GTA SA (ruta del registro de
  MTA) y genera `server/s_models.lua` (validación) y `html/models.js` (panel). Solo ids y nombres.
- Reglas de validación compartidas en `shared/s_rules.lua` (funciones puras; las prueba `rp_test`).
- Exports de servidor: `getPublishedMaps()`, `getMapPoints(nombre)`, `isMapPublished(nombre)`,
  `validateMapElement(fila)`, `parseMapFile(xml)`, `rowsToMapFile(filas, interior, dimension)`.
- Los elementos llevan el elementData `rp:mapedit` (nombre del proyecto), visible con la vista ALT.
