# Estándar de recursos de Thorium

Reglas que cumple todo recurso `rp_*`, sea nuevo, mejorado o arreglado. Cada regla tiene un
**identificador** (para citarla en commits, PRs y auditorías), una **gravedad** y una forma de
**verificarla**. Las skills `crear-recurso`, `mejorar-recurso` y `arreglar-recurso` aplican este
documento; si una regla cambia, se cambia aquí y en `scripts/auditar-recurso.sh` en el mismo PR.

## Cómo se verifica

```bash
scripts/auditar-recurso.sh rp_bikes          # informe de un recurso (código 0 = sin FALLA [B])
scripts/auditar-recurso.sh rp_bikes --md     # mismo informe en Markdown, para el registro
scripts/auditar-recurso.sh --todos           # nota de todos los rp_*, de peor a mejor
```

- **Gravedad**: **B** bloqueante (no se fusiona con ella), **I** importante (se corrige al tocar el
  recurso), **R** recomendada.
- **Verificación**: **auto** la comprueba el script; **manual** la revisa quien toca el recurso,
  leyendo el código (las skills dicen cómo).
- **Nota** = 100 − 15 por FALLA B − 5 por FALLA I − 2 por AVISO. Es una medida para comparar
  antes y después, no un objetivo en sí: una nota alta con una regla manual rota sigue estando mal.

### Excepciones justificadas

Si un caso concreto incumple una regla automática **a propósito**, se marca en la línea (o la
anterior) con un comentario `estandar:<etiqueta> <motivo>`. El script la acepta y la excepción
queda visible y buscable (`grep -rn "estandar:"`). Sin motivo no vale.

| Etiqueta | Regla | Ejemplo |
|---|---|---|
| `estandar:sin-client` | SEG-01 | `-- estandar:sin-client solo abre portones, valida ids y no da nada al jugador` |
| `estandar:sincrono` | BD-02 | `-- estandar:sincrono export que devuelve el saldo; los exports no aceptan callbacks` |
| `estandar:sql-seguro` | BD-03 | `-- estandar:sql-seguro marks = string.rep("?,", n), sin datos del usuario` |
| `estandar:dep-opcional rp_x` | EST-03 | dependencia circular; se comprueba que `rp_x` está en marcha antes de llamarla |
| `estandar:secreto` | SEG-05 | texto que parece secreto y no lo es (marcador de posición) |
| `estandar:loadstring` | SEG-06 | solo con código del propio servidor, nunca del cliente |
| `estandar:radio` / `estandar:mundo` | INT-01 / INT-02 | el recurso dueño de ese sistema |

---

## EST · Estructura

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| EST-01 | B | auto | `meta.xml` con `<info author name description version type>` y `<min_mta_version server client>`. |
| EST-02 | I | auto | Todo `<script type="client">` lleva `cache="false"`. |
| EST-03 | I | auto | Cada recurso cuyos exports se llaman está en `<include>`. Si eso crea un ciclo, la dependencia es opcional: se comprueba con `getResourceFromName("rp_x")` + `getResourceState(...) == "running"` antes de llamarla. |
| EST-04 | I | auto | Lo que declara `meta.xml` existe y todo `.lua` del recurso está declarado (salvo `tools/` y `*.example.lua`). |
| EST-05 | I | auto | `server/` → `s_*.lua`, `client/` → `c_*.lua`, `shared/` → `s_*.lua`. |
| EST-06 | R | auto | Cada `.lua` empieza con una cabecera `--[[ rp_x / archivo · qué hace ]]`. |
| EST-07 | B | auto | Registrado en `mtaserver.conf` **después** de todas sus dependencias (salvo recursos de desarrollo: `rp_animlab`, `rp_test`). |
| EST-08 | I | manual | Configuración ajustable (precios, tiempos, coords, textos) en `shared/s_config.lua` (o `server/s_config.lua` si el cliente no debe verla), en una tabla global en MAYÚSCULAS. Nada de números mágicos repartidos. |
| EST-09 | R | manual | Archivos de menos de ~600 líneas; si crecen, se parten por responsabilidad. |

## SEG · Seguridad

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| SEG-01 | B | auto | En el handler de un evento remoto (`addEvent(..., true)`) el jugador es **`client`**, nunca `source` ni un argumento. |
| SEG-02 | B | manual | El servidor revalida todo lo que llega del cliente: tipos (`tonumber`, `type`), rangos y enteros, longitud de textos, cercanía (posición + interior + dimensión), item, dinero, permisos y estado del jugador. El cliente solo pide. |
| SEG-03 | I | manual | Acciones repetibles con cooldown o bandera de "ocupado" por jugador (anti-spam y anti-doble cobro). |
| SEG-04 | B | manual | Todo comando o evento de admin comprueba `getPlayerAdminLevel(p) >= N` (o `rp_adminpanel:hasPermission`) en el servidor. |
| SEG-05 | B | auto | Sin contraseñas, claves, tokens, IPs privadas ni emails en el código (los secretos van en archivos ignorados como `config.lua`). |
| SEG-06 | B | auto | Sin `loadstring`. |
| SEG-07 | I | manual | Datos que el cliente no debe conocer (premios, probabilidades, posiciones de botín) solo en scripts de servidor; elementData sincronizado solo si los demás clientes lo necesitan. |

## BD · Base de datos

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| BD-01 | B | auto | Una sola conexión: `exports.rp_database:getConnection()`. Nunca `dbConnect`. |
| BD-02 | B | auto | Consultas asíncronas con callback y `dbPoll(qh, 0)`. `dbPoll(qh, -1)` solo en un export que debe devolver un valor, marcado con `estandar:sincrono`. |
| BD-03 | B | auto | SQL siempre parametrizado con `?`. Concatenar solo partes fijas del propio código, marcado con `estandar:sql-seguro`. |
| BD-04 | B | auto | Tablas y columnas solo en `rp_database/schema.lua` (skill `migracion-bd`): al final, idempotente y sin editar entradas ya publicadas. |
| BD-05 | I | auto | Si usa la BD al arrancar, espera a `isReady()` o a `rp:onDatabaseReady`. |
| BD-06 | B | manual | Cobros atómicos (`UPDATE ... SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?` y comprobar filas afectadas) **antes** de entregar; si la entrega falla, se devuelve. Efectivo: `takePlayerMoney` + `saveCharacter`. |
| BD-07 | I | manual | Datos del personaje con `character_id` + `FOREIGN KEY ... ON DELETE CASCADE`; se escriben en el momento de la acción, no solo al salir. |

## CIC · Ciclo de vida

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| CIC-01 | I | auto | El estado por jugador (`tabla[player] = ...`) se limpia en `onPlayerQuit`. |
| CIC-02 | I | auto | Si el estado depende del personaje, también en `rp:onCharacterLogout`. |
| CIC-03 | I | manual | Reiniciar el recurso con jugadores dentro funciona: en `onResourceStart` se rehidrata a los que ya tienen personaje y en `onResourceStop` se guarda lo pendiente. |
| CIC-04 | I | auto | Los timers por jugador o de actividad se guardan y se matan (`isTimer` + `killTimer`) al terminar, salir o parar. |
| CIC-05 | I | auto | Si el cliente toca cámara, controles, cursor, fundido o supresión de HUD/radio, lo devuelve en `onClientResourceStop`. |
| CIC-06 | I | manual | Quedar abatido (`rp:onPlayerDowned`), esposado o entrar en misión/carrera corta o bloquea la actividad cuando no tiene sentido continuarla. |

## INT · Integración con la GM

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| INT-01 | B | auto | HUD, chat y radio se ocultan/silencian solo con `rp_hud:setHudSuppressed` y `rp_radio:setRadioSuppressed`; nunca `rp:hudHidden` ni `setRadioChannel` directos. |
| INT-02 | I | auto | Hora y clima los gobierna `rp_events` (`setWeatherState`); nadie más llama a `setTime`/`setWeather`. |
| INT-03 | I | auto | Eventos propios con nombre `rp:<sistema>:<accion>` (CEF: `rp:<sistema>:ui:<accion>`). |
| INT-04 | R | auto | Avisos de acciones con `rp_notify` (`notify`, `popup`, `bubble`), no con `outputChatBox`. |
| INT-05 | B | auto | Dimensiones propias en un bloque libre que no comparte ningún otro recurso (registro en la skill `crear-recurso`, `referencia/REGISTROS.md`). |
| INT-06 | R | auto | Teclas globales sin chocar con otro recurso (E es contextual y compartida). |
| INT-07 | I | manual | Se reutilizan los sistemas de la GM en vez de duplicarlos: dinero (BD-06), inventario (`rp_inventory`), identidad (`rp_characters`, `rp_ids`), búsqueda (`rp_wanted`), facciones, XP (`rp_levels`), necesidades. API en `.claude/skills/crear-recurso/referencia/API.md`. |
| INT-08 | I | manual | Textos al jugador en español con tildes correctas; tono de rol. |

## CLI · Cliente

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| CLI-01 | I | auto | Las teclas no actúan con el chat, la consola o el cursor activos (y tampoco abatido o en cinemática). |
| CLI-02 | R | auto | `onClientRender` sin trabajo pesado por frame (`getElementsByType`, crear texturas o fuentes, leer archivos): se precalcula o se hace con un timer. |
| CLI-03 | I | manual | Interfaces HTML con la skill `interfaz-cef` (patrón, paleta, Esc cierra). |
| CLI-04 | I | auto | Un script de cliente con `cache="false"` puede ejecutarse **antes** que un `shared` cacheado: no copies su config al cargar (`local C = CONFIG` queda `nil`). Léela dentro de funciones o en `onClientResourceStart`, o declara ese shared también con `cache="false"`. (Caso real: `rp_balizas`, 2026-11-25.) |

## DOC · Documentación

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| DOC-01 | B | auto | Fila en `RECURSOS.md`: qué hace, teclas, exports, tablas, comandos. |
| DOC-02 | I | auto | Cada export del `meta.xml` aparece en `RECURSOS.md`. |
| DOC-03 | I | auto | Cada comando aparece en `RECURSOS.md`, en el catálogo de `rp_adminpanel` (admin) o en la ayuda de `rp_help` (jugador). |
| DOC-04 | R | auto | Registro de auditoría en `docs/auditorias/<recurso>.md` (formato abajo). |
| DOC-05 | I | manual | Las reglas de diseño que no caben en una fila van en `docs/<SISTEMA>.md`. |

## PRU · Pruebas

| ID | Grav. | Verif. | Regla |
|---|---|---|---|
| PRU-01 | I | auto | Si usa la BD, `rp_test` tiene pruebas del recurso (cobros, tablas, exports). |
| PRU-02 | B | manual | `restart` del recurso sin errores en la consola; `scripts/test.sh` en `FIN OK`; el cliente se prueba en juego (flujo feliz y casos de error) con `/debugscript 3` limpio. Claude no puede probar el cliente: lo dice explícitamente a Fabián. |

---

## Registro de auditoría (`docs/auditorias/<recurso>.md`)

Un archivo por recurso; cada intervención añade una entrada **arriba**. Así se ve la historia de
calidad de cada sistema y quién la cambió.

```markdown
# Auditoría de rp_x

## 2026-11-25 · arreglar · commit abc1234
- **Motivo**: el cajero cobraba dos veces al pulsar rápido.
- **Nota**: 62 → 81 (FALLA B 2 → 0).
- **Cambios**: cooldown y bandera `busy` en `rp:bank:withdraw` (SEG-03); dbPoll(-1) marcado como export síncrono (BD-02).
- **Reglas manuales revisadas**: SEG-02 ✔, SEG-04 ✔, BD-06 ✔, CIC-03 ✔.
- **Pendiente**: DOC-02 (exports sin documentar), PRU-01.
- **Probar en juego**: retirar 2 veces seguidas; retirar sin saldo.

<details><summary>Informe automático</summary>

(salida de scripts/auditar-recurso.sh rp_x --md)

</details>
```

## Reglas que el script no puede comprobar bien

El script busca patrones; no entiende el código. Puede dar falsos positivos (se resuelven con una
excepción justificada) y no detecta todo: por ejemplo, SEG-01 solo mira que el handler mencione
`client`, no que lo use bien. Las reglas **manual** son obligatorias aunque la nota sea 100.
Si una regla automática da falsos positivos repetidos, se mejora el script en el mismo PR.
