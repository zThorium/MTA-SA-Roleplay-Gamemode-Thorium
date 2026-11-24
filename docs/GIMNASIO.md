# Gimnasios (rp_gym): documento funcional

Fases 1 a 4 del encargo: investigación, tabla de funcionalidades, integración y arquitectura.
**Todavía no hay código del recurso.** Las fases 5 a 7 esperan las decisiones de la sección 8.

Regla de este documento: cada dato lleva su categoría.

- **[C]** Confirmado del juego original (con fuente).
- **[A]** Adaptación técnica necesaria en MTA.
- **[L]** Limitación que impide una reproducción idéntica.
- **[?]** No documentado: no se inventa ningún valor. Se marca para decidir (sección 8).

## 1. Fuentes y su fiabilidad

| Fuente | Qué aporta | Fiabilidad |
|---|---|---|
| [Grand Theft Wiki: Gym](https://www.grandtheftwiki.com/Gym) | Máquinas, pesos, límite de 12 h, entrenadores | Media: última edición 2012 |
| [GTA Wiki: Statistics](https://gta.wiki/w/Statistics) | Rangos y valores por defecto de stats, ritmos de ganancia y pérdida | Media: citas parciales, algunas cifras contradicen a Grand Theft Wiki |
| [GTA Wiki: Ganton Gym](https://gta.wiki/w/Ganton_Gym), [Cobra](https://gta.wiki/w/Cobra_Marital_Arts_Gym) | Ubicación, entrenador, detalles de interior | Media |
| [Grand Theft Wiki: Below the Belt Gym](https://www.grandtheftwiki.com/Below_the_Belt_Gym) | Ubicación y estilo | Media |
| [MTA wiki: setPedStat](https://wiki.multitheftauto.com/wiki/SetPedStat), [setPedFightingStyle](https://wiki.multitheftauto.com/wiki/SetPedFightingStyle), [setPedAnimation](https://wiki.multitheftauto.com/wiki/SetPedAnimation), [Animations](https://wiki.multitheftauto.com/wiki/Animations) | IDs, firmas, rangos, nombres de animaciones | Alta (documentación oficial de MTA) |
| [GTAMods: List of statistics (SA)](https://gtamods.com/wiki/List_of_statistics_(SA)) | IDs de stats de récords del gimnasio | Alta (solo listado) |
| [main.scm filtrado (gist)](https://gist.github.com/JuniorDjjr/2129e1e7640f7969acdfb1c56c263155) | Existen los scripts `gymbike.sc`, `gymbench.sc`, `gymtread.sc`; valores iniciales (ENERGY 800, BODY_MUSCLE 50). Truncado: no incluye la lógica | Alta pero incompleta |

**Hallazgo clave:** ninguna fuente pública consultada da las constantes exactas de la lógica de las máquinas
(barra de potencia, velocidades, pasos de peso, repeticiones máximas, controles). Esos datos viven en los scripts
originales `gymbike.sc`, `gymbench.sc` y `gymtread.sc` y en el de los entrenadores, que no pude leer.

## 2. Mecánicas confirmadas del juego original [C]

**Acceso**
- Los gimnasios de interior se desbloquean con la llamada de Sweet tras la misión "Drive-Thru". Abren las 24 h. Fuente: Grand Theft Wiki: Gym.
- Cobra: entrar antes de "The Green Sabre" da 4 estrellas. Below the Belt: sin atención policial solo tras "Yay Ka-Boom-Boom". Fuente: GTA Wiki y Grand Theft Wiki.
- Ubicaciones: Ganton (Ganton, Los Santos), Cobra Martial Arts (Garcia, San Fierro), Below the Belt (Redsands East, Las Venturas).
- Ganton: el interior real está en Red County. Disparar dentro vuelve hostiles al entrenador y al espectador (solo en Ganton).

**Máquinas** (cada gimnasio tiene las cuatro)

| Máquina | Mejora | Detalle confirmado |
|---|---|---|
| Cinta | Resistencia, quema grasa | 10 niveles de velocidad (más nivel, cambian más rápido las stats). Medidores de potencia y de distancia, indicador de nivel. Hay que mantener el ritmo o la potencia se vacía y el personaje se cae |
| Bicicleta estática | Resistencia, quema grasa | 10 niveles. Si la potencia se vacía hay que empezar de nuevo |
| Press de banca | Músculo, quema grasa | Pesos de 40 a 320 lb. Barra de potencia e indicador de repeticiones. Hay que llenar la barra para completar una repetición |
| Mancuernas | Músculo, quema grasa | Pesos de 20 a 110 lb. Misma barra e indicador que el press |

**Ritmos de cambio de stats**

| Actividad | Resistencia | Músculo | Grasa | Fuente |
|---|---|---|---|---|
| Cinta o bici (gimnasio) | +4 % cada 14 s | +1 % cada 14 s | -2,5 % cada 14 s | Ambas wikis coinciden |
| Pesas (por repetición) | no consta | +0,1 % a +0,9 % (según peso y fuerza actual) | -0,1 % | GTA Wiki |
| Pesas (por repetición) | no consta | +1 % | -2,5 % | Grand Theft Wiki. **Contradice a GTA Wiki** |

Detalles de GTA Wiki: más peso da más ganancia; un CJ más fuerte gana menos; el press supera a las mancuernas
al mismo peso; la primera mancuerna (20 lb) siempre da la ganancia completa (fallo del juego).

**Stats**
- Rango interno 0 a 1000 para músculo, grasa y resistencia. Valores por defecto: resistencia 100 (10 %), músculo 50 (5 %), grasa 200 (20 %). Fuente: GTA Wiki.
- Solo se pierde músculo cuando la grasa está en 0 y CJ no come lo suficiente. Fuente: GTA Wiki.
- Grasa y músculo solo se ven en CJ. En MTA, `setPedStat` devuelve false para FAT y BODY_MUSCLE en un ped que no es CJ. Fuente: MTA wiki.

**Límite diario** (solo Grand Theft Wiki): si en un día se pierde 40 % de grasa o se gana 20 % de resistencia o de músculo,
hay que esperar 12 horas. GTA Wiki no lo menciona: **fuente única** [C débil].

**Entrenadores y estilos**
- Ganton: boxeo. Cobra: kung fu. Below the Belt: kickboxing.
- Requisito de músculo: una guía da 35 % ([SegmentNext](https://segmentnext.com/gta-san-andreas-fighting-styles/)); Grand Theft Wiki solo dice "suficiente". **Fuente única** [C débil].
- Cada entrenador enseña un ataque en carrera, un ataque en el suelo y un combo. Hay que derrotarlo.
- Rendirse en cualquiera de los tres hace perder todas las armas que se llevan, sin posibilidad de recuperarlas.
- En Cobra la pelea es sobre una esterilla y acaba antes si CJ o el instructor salen de ella.
- Solo se usa un estilo a la vez. Aprender uno nuevo reemplaza al anterior. Aprender los tres cuenta para el 100 %.

**Animaciones disponibles en MTA** (nombres exactos de la wiki de MTA)
- Bloque `gymnasium`: `gym_tread_geton`, `gym_tread_walk`, `gym_tread_jog`, `gym_tread_sprint`, `gym_tread_tired`, `gym_tread_falloff`, `gym_tread_getoff`, `gym_tread_celebrate`, `gym_bike_geton`, `gym_bike_pedal`, `gym_bike_slow`, `gym_bike_fast`, `gym_bike_faster`, `gym_bike_still`, `gym_bike_getoff`, `gym_bike_celebrate`, `pedals_slow`, `pedals_med`, `pedals_fast`, `pedals_still`, `gym_jog_falloff`, `gym_walk_falloff`, `gym_shadowbox`, `gymshadowbox`.
- Bloque `freeweights`: `gym_barbell`, `gym_free_pickup`, `gym_free_putdown`, `gym_free_a`, `gym_free_b`, `gym_free_loop`, `gym_free_down`, `gym_free_up_smooth`, `gym_free_celebrate`.
- Bloque `benchpress`: `gym_bp_geton`, `gym_bp_down`, `gym_bp_up_a`, `gym_bp_up_b`, `gym_bp_up_smooth`, `gym_bp_celebrate`, `gym_bp_getoff`.
- Combate: bloques `fight_b` (boxeo), `fight_c` (kung fu), `fight_d`, `fight_e` (patadas), `box`, `ped`.

**Stats de récords del juego** (IDs de MTA/GTAMods): 28 `DIST_TREADMILL`, 29 `DIST_EXCERSISE_BIKE`, 44 `LONGEST_TREADMILL_TIME`,
45 `LONGEST_EXCERSISE_BIKE_TIME`, 46 `HEAVIEST_WEIGHT_BENCH_PRESS`, 47 `HEAVIEST_WEIGHT_DUMBELLS`, 198 `VISITS_TO_GYM`.

## 3. No documentado [?]

No se programa ninguno de estos valores sin decisión (sección 8).

| Mecánica | Qué falta |
|---|---|
| Controles | Teclas de cada máquina y de las barras. Ninguna fuente fiable. Una discusión de Steam apunta al teclado numérico, sin confirmar |
| Cinta | Velocidad real de cada uno de los 10 niveles y cómo se calcula la distancia virtual |
| Bici | Qué cambia en cada uno de los 10 niveles |
| Barra de potencia | Cuánto sube por pulsación, cuánto baja por segundo, umbral de fallo, ritmo exigido por nivel |
| Pesas | Pasos de peso entre 40-320 lb y 20-110 lb, repeticiones máximas, cuándo se interrumpe, qué pasa al fallar |
| Ganancias exactas | Fórmula por repetición (solo hay rangos), efecto de cada nivel de la cinta y la bici en los ritmos de la tabla |
| Límite diario | Confirmación de los umbrales (40 % grasa, 20 % resistencia o músculo) y cómo se mide "un día" |
| Entrenadores | Nombres, vida, IA, reglas de victoria y derrota, requisito exacto de músculo, lista exacta de movimientos de cada estilo |
| Mundo | Coordenadas y números de interior de las máquinas y los entrenadores (solo consta que el de Ganton está en Red County) |

**Cómo cerrar el hueco:** los scripts `gymbike.sc`, `gymbench.sc`, `gymtread.sc` y el de entrenadores de tu copia del juego
se pueden descompilar con Sanny Builder. Si los aportas o me dices que los valores se tomen de otra fuente, se rellena esta tabla con datos reales.

## 4. Adaptaciones [A] y limitaciones [L]

- [L] **No se puede ejecutar el SCM original.** Todas las máquinas se recrean con animaciones, objetos y lógica propios.
- [L] **Grasa y músculo solo se ven en CJ.** Los personajes con otro skin entrenan y guardan sus valores, pero no cambian de aspecto. El servidor ya usa skin 0 para los masculinos y skins propios para el resto (ver `rp_characters/shared/s_body.lua`).
- [A] **Persistencia en el sistema existente.** `rp_characters` ya guarda `body_fat` y `body_muscle` como `TINYINT` 0-100 por personaje. Esa precisión no sirve (el juego cambia 0,1 % por repetición). Hace falta una columna nueva con escala 0-1000. Resistencia no se guarda hoy.
- [A] **El motor de GTA cambia las stats por su cuenta** (correr, nadar, ir en bici). El servidor debe tratar el valor del cliente como informativo y guardar solo lo que él calcula en el gimnasio.
- [A] **Cliente y servidor.** `setPedStat` en servidor afecta al jugador. Un `setPedStat` en cliente solo vale para peds creados en el cliente. El servidor aplica y guarda; el cliente solo dibuja animaciones y barras.
- [A] **Interfaz en dx**, no CEF, para reproducir los medidores del original. Las barras exactas (posición, colores) tampoco constan en ninguna fuente: se tomarán de capturas del juego si las aportas.
- [A] **Estilo kickboxing = `STYLE_KNEE_HEAD` (7).** La wiki de MTA lista los IDs (4 estándar, 5 boxeo, 6 kung fu, 7 knee-head, 15 grab-kick, 16 elbows) pero no dice cuál es el kickboxing. La correspondencia con 7 es **inferencia mía**: se debe verificar en juego.
- [A] **Rendirse en MTA:** perder las armas se aplica con el sistema de armas de `rp_ammunation` (items `wpn_*`), no con las armas nativas.

## 5. Tabla de funcionalidades (Fase 2)

| Mecánica original | Estado | Implementación en MTA |
|---|---|---|
| 3 gimnasios con 4 máquinas | [C] | Marcadores e interacción con E, interior y dimensión propios, un objeto por máquina |
| Cinta, 10 niveles | [C] niveles, [?] valores | Animaciones `gym_tread_*`, ritmo por nivel pendiente de decisión |
| Bici, 10 niveles | [C] niveles, [?] valores | Animaciones `gym_bike_*` y `pedals_*` |
| Press de banca | [C] 40-320 lb, [?] resto | Animaciones `gym_bp_*`; barra de potencia pendiente |
| Mancuernas | [C] 20-110 lb, [?] resto | Animaciones `freeweights`; barra pendiente |
| Ganancias de cinta y bici | [C] | 4 % / 1 % / -2,5 % cada 14 s, aplicadas por el servidor |
| Ganancias de pesas | [C] rango contradictorio | Pendiente de decisión (sección 8, pregunta 2) |
| Límite diario de 12 h | [C débil] | Tabla `gym_daily` en el servidor |
| Entrenadores y estilos | [C] estilos, [?] combate | `setPedFightingStyle` 5, 6 y 7 |
| Requisito de músculo | [C débil] 35 % | Pendiente de confirmar |
| Rendirse pierde las armas | [C] | Con `rp_ammunation` |
| Músculo, grasa y resistencia | [C] | `setPedStat` 23, 21 y 22 aplicado por el servidor |
| Membresías, pagos, XP, buffs | no existen en el original | **No se implementan** |

## 6. Integración con el servidor (Fase 3)

- **Cuentas y personajes:** `exports.rp_characters:getPlayerCharacterId(player)` identifica al personaje. Todo se guarda por `character_id`, sin sistema paralelo.
- **Base de datos:** una sola conexión (`rp_database`). Cambios solo con entradas nuevas al final de `schema.lua`. Se añade `rp_gym` en esa tabla de migraciones, no un `gym.sql` aparte (regla 6 del proyecto).
- **Cuerpo:** `rp_characters` aplica `applyBodyStats` al hacer spawn con `body_fat` y `body_muscle`. `rp_gym` debe sustituir esa fuente por la suya (escala 0-1000) sin dos escritores. Hay que tocar `rp_characters` o exponerle un export.
- **Resistencia:** `rp_dealers` (`c_effects.lua`) ya modifica el stat de resistencia en el cliente con las drogas, y `rp_hud` tiene su propia estamina para correr y saltar. Son independientes del stat nativo de GTA: hay que evitar que se pisen.
- **Interiores:** `rp_ammunation` usa el interior 4 en la dimensión 22000+id. Se reservará otro rango de dimensión para el gimnasio.
- **Armas:** el efecto de rendirse necesita un export de `rp_inventory` o `rp_ammunation` para quitar todas las armas.
- **Administración:** los comandos de colocación (máquinas, entrenadores) siguen la skill `comando-admin` y se añaden a `rp_adminpanel`.

## 7. Arquitectura y plan (Fase 4)

Estructura adaptada a la convención del proyecto (prefijo `rp_`, `meta.xml`, carpetas `shared/server/client`):

```
resources/[roleplay]/rp_gym/
  meta.xml
  shared/s_config.lua     gimnasios, máquinas, niveles, pesos (valores [C] y los decididos en la sección 8)
  server/s_main.lua       ciclo de vida, entrada y salida, liberar máquinas al salir
  server/s_machines.lua   estado de cada máquina, validación de distancia, ocupación
  server/s_stats.lua      cálculo y aplicación de músculo, grasa y resistencia
  server/s_trainers.lua   entrenadores, pelea de instrucción, desbloqueo de estilos
  server/s_cooldown.lua   límite diario y descanso de 12 h
  server/s_database.lua   carga y guardado por personaje
  client/c_main.lua       interacción, controles
  client/c_machines.lua   lógica de cada máquina y barra de potencia
  client/c_animations.lua animaciones y sincronización
  client/c_interface.lua  medidores dx
```

Eventos: `rp:gym:start`, `rp:gym:rep`, `rp:gym:stop`, `rp:gym:trainer:fight`, `rp:gym:state` (servidor a clientes), todos validados con `client`.

Tablas nuevas (al final de `schema.lua`): `character_gym` (músculo, grasa y resistencia 0-1000, estilo actual, estilos desbloqueados, último entrenamiento) y `gym_daily` (ganancia y pérdida acumulada del día).

Fases de desarrollo una vez resuelta la sección 8:

1. Base: tablas, config, entrada, ocupación de máquinas y guardado de stats.
2. Cinta y bici con sus medidores.
3. Pesas (press y mancuernas).
4. Entrenadores, pelea de instrucción y estilos.
5. Revisión de seguridad y sincronización, pruebas, `RECURSOS.md` y `rp_test`.

## 8. Decisiones tomadas e implementación (Fases 5 a 7)

Decisiones del proyecto:

1. Los valores sin fuente documentada se implementan como **adaptación propia**, marcada `[A]` en `rp_gym/shared/s_config.lua`.
2. Pesas: **+0,5 % de músculo y -0,5 % de grasa por repetición** (fijo, sin depender del peso). La indicación original decía "50 %" de músculo; se interpretó como 0,5 %, porque 50 % por repetición llenaría el músculo en dos repeticiones. Se cambia en `GYM.REP_MUSCLE` (unidades de 0 a 1000, 5 = 0,5 %).
3. Límite de 12 h y 35 % de músculo: implementados tal cual (fuente única, ver sección 2).
4. Máquinas y entrenadores se colocan con comandos de admin.
5. `rp_characters` es el único escritor de grasa, músculo y resistencia (`getBodyStats` y `setBodyStats`).

### Valores de adaptación [A] (no son del juego original)

| Dato | Valor | Dónde |
|---|---|---|
| Teclas | `A`/`D` alternando (cinta y bici), `Espacio` (pesas), flechas = nivel o peso, `Enter` empezar, `Retroceso` salir | `client/c_machines.lua` |
| Barra de potencia, cinta y bici | empieza en 50 %; pierde `6 + 2,4 x nivel` % por segundo; cada pulsación alterna da 12 % | `GYM_KINDS` |
| Velocidad virtual | cinta `3 + nivel` km/h; bici `8 + 1,5 x nivel` km/h | `GYM_KINDS` |
| Ritmo de stats por nivel | los 4 % / 1 % / -2,5 % cada 14 s son el nivel 10; los demás niveles escalan `nivel / 10` | `GYM.RATE_*` |
| Pesas | pasos de 20 lb (banca) y 10 lb (mancuernas); cada pulsación da `18 - 10 x peso relativo` %; la barra baja `10 + 25 x peso relativo` % por segundo; una repetición dura 1,5 s; 5 s con la barra vacía suelta el peso | `GYM_KINDS`, `GYM_*` |
| Repeticiones máximas | sin tope; las limita el límite diario | |
| "Un día" del límite | ventana de 24 h desde el primer entrenamiento | `GYM.DAY_SECONDS` |
| Combate | el entrenador gana si el jugador baja de 20 de vida y pierde si él baja de 20; ring de 7 m (3,5 m en Cobra); salir del ring es rendirse | `GYM`, `GYM_STYLES` |
| Skins de entrenadores | 80 (boxeo), 49 (kung fu), 81 (kickboxing) | `GYM_STYLES` |
| Modelos de máquinas | 2627 cinta, 2630 bici, 2629 banca, 2913 mancuernas; desplazamiento Z -1,0 | `GYM_KINDS` |
| Resistencia inicial | 100 (10 %) si el personaje nunca entrenó | `BODY.STAMINA_DEFAULT` |

**Los modelos de máquinas, los IDs de skin y las animaciones no están verificados en juego.** Si una máquina sale con otro objeto, se cambia `model` en `GYM_KINDS`.

### Limitaciones [L] añadidas durante la implementación

- La rueda de la cinta y los pedales de la bici (animaciones `pedals_*`) pertenecen al objeto de la máquina, y MTA no tiene animación de objetos: no se mueven.
- `setPedAnimationSpeed` no se sincroniza: el ajuste de velocidad por nivel solo lo ve el que entrena.
- Las stats de récords del juego (`DIST_TREADMILL`, etc.) quedan acotadas a 1000 por el rango de `setPedStat`.
- El motor de GTA cambia las stats del cliente (correr, nadar); el servidor solo conserva lo que guarda el gimnasio.
- Grasa y músculo solo se ven en el cuerpo de CJ (skin 0).

### Cambios en otros recursos

- `rp_characters`: columnas `stat_fat`, `stat_muscle`, `stat_stamina` (0-1000, `NULL` = sin entrenar). `applyPlayerLook` usa esos valores si existen. Exports nuevos `getBodyStats` y `setBodyStats`; este último mantiene `body_fat` y `body_muscle` (0-100) sincronizados.
- `rp_database`: entradas nuevas al final de `schema.lua` (columnas anteriores y tablas `gym_machines`, `gym_trainers`, `character_gym`).
- `rp_adminpanel`: categoría "Gimnasio" en el catálogo. `mtaserver.conf`: `rp_gym` tras `rp_backpacks`.

### Eventos

| Evento | Sentido | Descripción |
|---|---|---|
| `rp:gym:start (machineId, opcion)` | cliente a servidor | Subir a una máquina; `opcion` = índice de peso en pesas |
| `rp:gym:pulse (lado)` | cliente a servidor | 1 o 2 alternando (cinta, bici); 0 (pesas) |
| `rp:gym:level (-1 o 1)` | cliente a servidor | Cambiar de nivel |
| `rp:gym:stop` | cliente a servidor | Bajarse |
| `rp:gym:trainer (trainerId)` | cliente a servidor | Hablar con un entrenador y confirmar el combate |
| `rp:gym:near (tipo, id, etiqueta, extra)` | servidor a cliente | Aviso "Pulsa E" |
| `rp:gym:state (tabla o false)` | servidor a cliente | Estado de la sesión para los medidores |

### Instalación

1. Arrancar el servidor: `rp_database` aplica las entradas nuevas de `schema.lua` al iniciar.
2. `start rp_gym` (ya está en `mtaserver.conf`). Reiniciar `rp_characters` si estaba en marcha.
3. Entrar al interior de un gimnasio y, de pie donde debe quedar el personaje y mirando hacia donde mira la máquina, usar `/crearmaquina <cinta|bici|banca|mancuernas>`. Repetir por cada máquina. `/crearentrenador <boxeo|kungfu|kickboxing>` para los entrenadores.

### Lista de pruebas

1. **Cinta:** `E`, alternar `A`/`D`, subir y bajar nivel con las flechas. Dejar de pulsar: la potencia baja y el personaje se cae. Comprobar que sube resistencia y músculo y baja grasa.
2. **Bici:** igual que la cinta.
3. **Press y mancuernas:** `E`, elegir peso con las flechas, `Enter`, pulsar `Espacio` hasta llenar la barra: +1 repetición, +0,5 % de músculo y -0,5 % de grasa. Con la barra vacía 5 s se suelta el peso.
4. **Máquina ocupada:** un segundo jugador no puede subir. Desconectar al primero y comprobar que se libera.
5. **Distancia:** intentar `rp:gym:start` lejos de la máquina (debe rechazarse).
6. **Límite diario:** entrenar hasta ganar 20 % de músculo o resistencia (o perder 40 % de grasa): la sesión termina y no se puede volver en 12 h.
7. **Entrenador:** con menos de 35 % de músculo, rechaza. Con 35 % o más, `E` dos veces, ganar (aprende el estilo y lo usa), perder (sin penalización) y salir del ring (pierde las armas).
8. **Persistencia:** reconectar y comprobar músculo, grasa, resistencia, estilo y bloqueo.
