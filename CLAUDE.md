# CLAUDE.md

Contexto para Claude (y para cualquier persona) que trabaje en este repositorio.
Léelo completo antes de tocar código. Responde y documenta **en español**.

## Qué es

**Thorium**: gamemode de roleplay en español para **MTA:SA 1.6**, hecho desde cero.
Lua 5.1 (servidor y cliente), interfaces en **CEF** (HTML/CSS/JS) y dx, y
**MariaDB/MySQL** (XAMPP en local). Todo se guarda **por personaje**, no por cuenta.

- Visión y features: [`README.md`](README.md)
- Exports y comandos de cada recurso: [`RECURSOS.md`](RECURSOS.md)
- Hoja de ruta y prioridades: [`docs/PLAN_MVP.md`](docs/PLAN_MVP.md)
- Montar el entorno local y sincronizar con el servidor: [`docs/ENTORNO_LOCAL.md`](docs/ENTORNO_LOCAL.md)
- Entorno Docker (Mac/Linux) y pruebas del servidor por CLI: [`docs/DOCKER.md`](docs/DOCKER.md)
- Patrones de código, BD y seguridad: [`docs/CONVENCIONES.md`](docs/CONVENCIONES.md)
- Estándar de cinemáticas de misiones: [`docs/CINEMATICAS.md`](docs/CINEMATICAS.md)

## Estructura

```
mtaserver.conf          orden de arranque de los recursos (importa)
acl.xml                 ACL base (sin cuentas personales)
vehiclecolors.conf
docs/                   plan y guías
docker-compose.yml      servidor MTA (Linux) + MariaDB; ver docs/DOCKER.md
docker/mta/             Dockerfile y entrypoint del servidor
scripts/                mta.sh (arrancar, logs, consola) y test.sh (pruebas, código 0/1)
resources/[test]/       rp_test: pruebas de humo del servidor (no arranca con mtaserver.conf)
resources/[roleplay]/   un recurso por sistema
  rp_<sistema>/
    meta.xml            scripts, <include> de dependencias, <file> CEF, <export>
    server/s_*.lua      solo servidor
    client/c_*.lua      solo cliente
    shared/s_*.lua      compartido (config, catálogos)
    html/               index.html + style.css + app.js (CEF)
```

Recursos pequeños pueden tener los `.lua` en la raíz del recurso (`rp_admin`, `rp_needs`...).
Prefijo `s_` = servidor o compartido, `c_` = cliente.

## Recursos actuales (en `main`)

Base: `rp_database` (conexión + esquema), `rp_login` (CEF + bcrypt), `rp_characters`
(3 slots, spawn), `rp_ids`, `rp_notify`. Personaje: `rp_heads` + `bone_attach`
(terceros, ver créditos), `rp_needs`, `rp_injury` (abatido en vez de morir, hospital), `rp_inventory` (I), `rp_clothing` (ropa y toys).
Economía: `rp_bank` (cajeros), `rp_shops`, `rp_vending` (expendedoras: sed/hambre), `rp_dealership`, `rp_payday`.
Comunidad: `rp_factions` (F3, roles con permisos y sueldo), `rp_phone` (P) con la app
de viajes `rp_rides` (Vroom). Mundo: `rp_properties`, `rp_vehicles`, `rp_radio` (radio de vehículos con emisoras de internet), `rp_citizens`
(peatones y tráfico IA), `rp_bikes` (arriendo de bicicletas, 60 min). Interfaz: `rp_hud`, `rp_scoreboard`, `rp_nametags`.
Trabajos: `rp_jobs` (6 trabajos civiles con minijuegos CEF, niveles y mercados dinámicos; API para la agencia en `docs/TRABAJOS.md`).
Licencias: `rp_driving` (autoescuela con medallas y ranking, licencia de conducir como ítem).
Emergencias: `rp_emergency` (`/911`, ambulancia IA con paramédicos).
Drogas: `rp_dealers` (traficantes skin 28/29/30; comprar con un policia mirando da estrella).
Trámites: `rp_agency` (agencia de empleo: turnos, DNI `id_card` y alta en trabajos).
Admin: `rp_admin` (`/freecam`), `rp_adminpanel` (`/adminpanel`, F10: dashboard, jugadores en 3D, cuentas, IAM/RBAC, auditoría y catálogo de comandos; añade ahí cada comando de admin nuevo). `rp_resmanager` (F9, solo super admin).

**En PR abierto, aún no en `main`** (revisa el PR antes de tocar esas áreas):
vehículos con llaves/interacción M/tuning y combustible (#6), panel de ayuda F1 con
reportes (#7), estrellas de búsqueda y policía IA (#8), comandos de admin
`/goto`, `/get`, `/givemoney`, `/kick`... (#9), robo de tiendas 24/7 con miedo, cinemática,
negociación y persecución (`rp_robbery`, se apoya en `rp_wanted` de #8/#17).

## Reglas de arquitectura (no romper)

1. **Una sola conexión MySQL**: `exports.rp_database:getConnection()`. Nunca `dbConnect` en otro recurso.
2. **Consultas asíncronas** con callback (`dbQuery(function(qh) dbPoll(qh, 0) ... end, db, sql, ...)`).
   Nunca `dbPoll(qh, -1)` en el hilo principal: congela el servidor.
3. **Siempre parametrizado** (`?`). Nunca concatenar SQL.
4. **El servidor valida todo**. En handlers de eventos remotos usa `client` (no `source`)
   y vuelve a comprobar distancia, item, dinero, permisos. El cliente solo reenvía.
5. **Cobros atómicos**: `UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?`
   y comprobar las filas afectadas antes de entregar nada.
6. **Esquema solo hacia adelante**: cambios de BD = nueva entrada **al final** de
   `rp_database/schema.lua` (`CREATE TABLE IF NOT EXISTS` / `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`).
   No edites ni reordenes las entradas existentes: ya se aplicaron en otras bases.
7. **Ciclo de vida**: engánchate a `rp:onAccountLogin`, `rp:onCharacterSpawn`, `rp:onCharacterLogout`
   y `rp:onDatabaseReady` en vez de inventar flujos paralelos.
8. **Eventos** con nombre `rp:<sistema>:<accion>`; los que vienen del CEF, `rp:<sistema>:ui:<accion>`.
9. **Exports** declarados en `meta.xml`. No se pueden pasar funciones entre recursos.
10. **Admin**: `(exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1` (columna `accounts.admin_level`).
11. Recurso nuevo: añádelo a `mtaserver.conf` **después** de sus dependencias y con `<include>` en su `meta.xml`.

Detalles y fragmentos de ejemplo en [`docs/CONVENCIONES.md`](docs/CONVENCIONES.md).
Estándar exigible con reglas numeradas: [`docs/ESTANDAR_RECURSOS.md`](docs/ESTANDAR_RECURSOS.md);
se audita con `scripts/auditar-recurso.sh <rp_x>` (o `--todos`) y cada intervención queda en `docs/auditorias/<rp_x>.md`.

## Skills del proyecto

En `.claude/skills/` hay skills compartidas con el estándar del equipo. Úsalas siempre que apliquen:

| Skill | Cuándo |
|---|---|
| `crear-recurso` | Añadir un sistema o recurso `rp_*` nuevo (diseño, API de la GM, plantillas, registro, auditoría) |
| `mejorar-recurso <rp_x> [foco]` | Llevar un recurso existente al estándar o ampliarlo, por fases y con auditoría antes/después |
| `arreglar-recurso <rp_x> [síntoma]` | Arreglar un fallo con diagnóstico, causa raíz, prueba de regresión y registro |
| `migracion-bd` | Cualquier tabla, columna o índice nuevo en `schema.lua` |
| `interfaz-cef` | Cualquier panel o ventana HTML en el juego |
| `comando-admin` | Cualquier `/comando`, y elementos que los admins colocan en el mundo |
| `crear-mision` | Crear, modificar o revisar cualquier misión de `rp_missions` (reúne los estándares de voces, cinemáticas, radio/HUD y estrellas) |
| `voces-gta` | Toda mision o dialogo con voz: genera las voces de los personajes de GTA SA (estandar de voces, ver abajo) |

Si una forma de hacer algo funciona mejor que lo que dice una skill, actualiza la skill en el mismo PR.

## Estándares al crear misiones (obligatorio)

Al crear, modificar o revisar **cualquier misión** de `rp_missions`, usar la skill `crear-mision`, que exige cumplir todo esto:

1. **Voces** clonadas para todo personaje (`voces-gta`, sección "Estándar de voces" abajo): nunca solo subtítulos ni TTS de Windows.
2. **Cinemáticas** con el estándar de `docs/CINEMATICAS.md` (cámara en mano, planos variados, gestos y miradas ligados al diálogo, solapes, salida fluida, sin música). Los personajes se animan con la **biblioteca de mocap `rp_mocap`** (mocap real del juego: gestos e idles por personaje; ver `rp_mocap/MOCAP_CATALOGO.md`); si falta un personaje, ampliar la biblioteca antes de dar la misión por terminada. `rp_mocap` no se reinicia sin `/mocapdescargar`. Las animaciones se diseñan como el juego original (análisis en ese documento): gestos parciales mezclados, actores que se mueven por el espacio, props y efectos; no personajes estáticos repitiendo un bucle.
3. **Radio y HUD**: radio silenciada durante la misión y HUD/chat ocultos en cinemáticas, solo con `setRadioSuppressed` / `setHudSuppressed`.
4. **Estrellas**: no se entra con estrellas y dentro no se acumulan (`setWantedSuspended`).
5. **Verificación**: servidor de prueba sin errores y aviso explícito a Fabián de que el cliente hay que probarlo en juego; no declarar una misión terminada sin voces generadas.

## Estándar de voces en misiones (obligatorio)

Toda misión de `rp_missions` (y cualquier otro diálogo con personajes de GTA SA) **debe llevar voz generada**, no solo subtítulos.
Al crear o modificar una misión, Claude debe, sin que se lo pidan, generar las voces siguiendo este estándar y la skill `voces-gta`:

- **Voz**: clonada con Fish Audio a partir de clips del doblaje latino del juego (nunca TTS de Windows como resultado final; los WAV de `tools/gen_voices.ps1` son solo respaldo temporal). Hoy está registrada **`sweet`** (español latino, 10 clips del banco 301 de `ZAINES`). Personajes sin voz registrada (Ryder, Cesar, Big Smoke...): registrarlos primero con `voz.ps1 registrar` extrayendo clips con `gta-audio.ps1` (ver `catalogo.md` de la skill) antes de dar la misión por terminada.
- **Configuración de referencia (la de Sweet, validada a oído por Fabián)**: modo zero-shot con 8-10 clips de 1,5-3 s del personaje en español; modelo `s2.1-pro-free`; `-Idioma es`; temperatura **0.3**; velocidad 1.0; mp3 128 kbps; el script reintenta solo si el audio sale desbocado (demasiado largo o corto).
- **Texto con ortografía correcta** (tildes, ¿¡, ñ): sin tildes la voz suena a otro idioma. Etiquetas de emoción solo en el texto del TTS (`[shouting]`), no en el subtítulo.
- **Nombres de archivo**: `rp_missions/audio/<clave_mision>_<etapa><c|r><n>.mp3` (`c` = cinemática, `r` = radio, `n` = línea). Las líneas del jugador (`me`) no llevan voz.
- **Después de generar**: ejecutar `rp_missions/tools/build_voice_index.ps1` (actualiza `shared/s_voice.lua` con las duraciones y los `<file>` del `meta.xml`) y reiniciar `rp_missions`.
- **Revisar** que ningún audio pese mucho más de ~1 KB por carácter y avisar a Fabián para que lo escuche; no se da por buena una misión sin voces.
- **Secretos**: la API key de Fish vive solo en `~/.fish-audio-key` o en `FISH_API_KEY`. Nunca en el repo. Las muestras de audio del juego (`muestras/`) tampoco se suben (copyright de Rockstar).

## Estándar de cinemáticas (obligatorio)

Toda cinemática de misión sigue `docs/CINEMATICAS.md`: cámara en mano con planos variados (contrapicados/`roll` para personajes de autoridad, planos detalle y de reacción), actores con bloqueo y animación (`cutscene.actors`), diálogos con voz y solapes/pausas, sin música, y salida fluida al gameplay (la cámara vuela detrás del jugador). Claude debe aplicar la lista de comprobación de ese documento al crear o tocar una cinemática, usar la intro de `grove_turf` como ejemplo y avisar a Fabián para probarla en juego antes de darla por buena.

## Misiones y radio

Mientras un jugador está en una misión, la radio (`rp_radio` y la radio nativa de GTA) queda silenciada para que no se solape con diálogos y llamadas. `rp_missions` lo hace con `exports.rp_radio:setRadioSuppressed("rp_missions", true/false)`; el HUD, el chat y las notificaciones se ocultan en cinemáticas con `exports.rp_hud:setHudSuppressed(...)`. Otros recursos que necesiten silenciar radio o HUD deben usar esas funciones y no tocar `rp:hudHidden` ni la radio nativa directamente. Dentro de una misión tampoco se acumulan estrellas (`exports.rp_wanted:setWantedSuspended`) y no se puede entrar con estrellas.

## Secretos: nunca al repo

- `resources/[roleplay]/rp_database/config.lua` (credenciales MySQL) está en `.gitignore`.
  Se crea copiando `config.example.lua`.
- No subas tu `acl.xml` con cuentas añadidas a grupos (`user.TuCuenta` en Admin),
  `server-id.keys`, `*.db`, logs, backups, `.dll`/`.exe` ni `rp_hud/images/map.png` (material de Rockstar).
- No pongas contraseñas, IPs privadas ni emails en código, commits o PRs.

## Flujo de trabajo

- `main` siempre arranca. Trabaja en una **rama por feature** (`feat/...`, `fix/...`) y abre **PR a `main`**.
- Commits y PRs en español, describiendo qué cambia en el juego.
- Pruebas del servidor: `scripts/test.sh` (Docker) arranca todo, ejecuta `rp_test` y sale
  con 0/1; debe pasar antes de abrir un PR. Si tu cambio toca BD o flujos de servidor,
  añade una prueba en `resources/[test]/rp_test/server/s_tests.lua`.
- El cliente no tiene tests: **prueba en juego antes de fusionar** (consola del servidor
  sin errores, `/debugscript 3` limpio, el flujo probado con al menos un personaje).
- Si cambias comandos, exports o tablas, actualiza `RECURSOS.md` (y el `README.md` si es una feature visible)
  en el mismo PR. Si cierras algo del plan, márcalo en `docs/PLAN_MVP.md`.
- Antes de crear un recurso, mira `docs/PLAN_MVP.md` y los PRs abiertos para no duplicar trabajo.
