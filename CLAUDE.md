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
- Patrones de código, BD y seguridad: [`docs/CONVENCIONES.md`](docs/CONVENCIONES.md)

## Estructura

```
mtaserver.conf          orden de arranque de los recursos (importa)
acl.xml                 ACL base (sin cuentas personales)
vehiclecolors.conf
docs/                   plan y guías
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
Economía: `rp_bank` (cajeros), `rp_shops`, `rp_dealership`, `rp_payday`.
Comunidad: `rp_factions` (F3, roles con permisos y sueldo), `rp_phone` (P) con la app
de viajes `rp_rides` (Vroom). Mundo: `rp_properties`, `rp_vehicles`, `rp_radio` (radio de vehículos con emisoras de internet), `rp_citizens`
(peatones y tráfico IA), `rp_bikes` (arriendo de bicicletas, 60 min). Interfaz: `rp_hud`, `rp_scoreboard`, `rp_nametags`.
Emergencias: `rp_emergency` (`/911`, ambulancia IA con paramédicos).
Admin: `rp_admin` (`/freecam`), `rp_adminpanel` (`/adminpanel`, F10: lista de comandos de admin; añade ahí cada comando de admin nuevo).

**En PR abierto, aún no en `main`** (revisa el PR antes de tocar esas áreas):
vehículos con llaves/interacción M/tuning y combustible (#6), panel de ayuda F1 con
reportes (#7), estrellas de búsqueda y policía IA (#8), comandos de admin
`/goto`, `/get`, `/givemoney`, `/kick`... (#9).

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

## Skills del proyecto

En `.claude/skills/` hay skills compartidas con el estándar del equipo. Úsalas siempre que apliquen:

| Skill | Cuándo |
|---|---|
| `crear-recurso` | Añadir un sistema o recurso `rp_*` nuevo (estructura, `meta.xml`, plantilla de servidor, registro, checklist de PR) |
| `migracion-bd` | Cualquier tabla, columna o índice nuevo en `schema.lua` |
| `interfaz-cef` | Cualquier panel o ventana HTML en el juego |
| `comando-admin` | Cualquier `/comando`, y elementos que los admins colocan en el mundo |

Si una forma de hacer algo funciona mejor que lo que dice una skill, actualiza la skill en el mismo PR.

## Secretos: nunca al repo

- `resources/[roleplay]/rp_database/config.lua` (credenciales MySQL) está en `.gitignore`.
  Se crea copiando `config.example.lua`.
- No subas tu `acl.xml` con cuentas añadidas a grupos (`user.TuCuenta` en Admin),
  `server-id.keys`, `*.db`, logs, backups, `.dll`/`.exe` ni `rp_hud/images/map.png` (material de Rockstar).
- No pongas contraseñas, IPs privadas ni emails en código, commits o PRs.

## Flujo de trabajo

- `main` siempre arranca. Trabaja en una **rama por feature** (`feat/...`, `fix/...`) y abre **PR a `main`**.
- Commits y PRs en español, describiendo qué cambia en el juego.
- No hay tests automáticos: **prueba en juego antes de fusionar** (consola del servidor
  sin errores, `/debugscript 3` limpio, el flujo probado con al menos un personaje).
- Si cambias comandos, exports o tablas, actualiza `RECURSOS.md` (y el `README.md` si es una feature visible)
  en el mismo PR. Si cierras algo del plan, márcalo en `docs/PLAN_MVP.md`.
- Antes de crear un recurso, mira `docs/PLAN_MVP.md` y los PRs abiertos para no duplicar trabajo.
