# Entorno Docker (Mac / Linux, sin cliente de juego)

Servidor MTA:SA 1.6 para Linux + MariaDB en contenedores, con los recursos del repo
montados en vivo. Sirve para **hostear y probar el servidor por consola y logs** sin
instalar XAMPP ni el servidor de Windows. Para jugar hace falta un cliente MTA (Windows)
que se conecte a tu máquina.

Piezas:

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Servicios `db` (MariaDB 11.4) y `mta` (servidor MTA) |
| `docker/mta/Dockerfile` | Imagen del servidor: descarga el build oficial de Linux (x64 o arm64 nativo) |
| `docker/mta/entrypoint.sh` | Copia `mtaserver.conf`/`acl.xml`, genera `rp_database/config.lua` desde `.env` y abre la consola por FIFO |
| `.env.example` | Credenciales y puertos. Se copia a `.env` (ignorado por git) |
| `scripts/mta.sh` | Arrancar, parar, logs, enviar comandos a la consola |
| `scripts/test.sh` | Levanta todo, ejecuta `rp_test` y devuelve 0 (OK) o 1 (fallo) |
| `resources/[test]/rp_test` | Pruebas de humo del lado servidor (PASS/FAIL en el log) |

## 1. Requisitos (Mac)

- **Docker Desktop** (o OrbStack / colima). En Apple Silicon la imagen usa el binario
  **arm64** nativo del servidor, sin emulación.
- Git y una terminal. Nada más: no hace falta MySQL ni XAMPP.

## 2. Primera vez

```bash
git clone https://github.com/zthorium/mta-sa-roleplay-gamemode-thorium.git
cd mta-sa-roleplay-gamemode-thorium
cp .env.example .env          # cambia DB_PASSWORD y DB_ROOT_PASSWORD
scripts/mta.sh up             # construye la imagen y arranca MariaDB + servidor
scripts/mta.sh logs -f        # Ctrl+C para salir del log (el servidor sigue)
```

En el log debe salir `[rp_database] Esquema verificado (...). Base de datos lista.`
La base se crea vacía y `rp_database` aplica `schema.lua` solo, igual que en Windows.

Al arrancar, el contenedor:

- Genera `resources/[roleplay]/rp_database/config.lua` con los datos de `.env` (host `db`).
  Si ya tenías un `config.lua` propio (sin la marca `GENERADO POR DOCKER`) lo respeta y avisa.
- Si falta `rp_hud/images/map.png` (no está en el repo, es material de Rockstar) pone un
  PNG gris de relleno para que `rp_hud` cargue. El minimapa sale vacío; si tienes el
  `map.png` real, cópialo ahí y se usa ese.
- Copia `mtaserver.conf`, `acl.xml` y `vehiclecolors.conf` del repo. Los cambios que el
  servidor haga en `acl.xml` (p. ej. `aclrequest`) se pierden al recrear el contenedor.

## 3. Uso diario

```bash
scripts/mta.sh status                    # contenedores en marcha
scripts/mta.sh logs                      # server.log completo (también en docker/logs/server.log)
scripts/mta.sh logs -f                   # seguir el log en vivo
scripts/mta.sh restart-res rp_bank       # refresh + restart de un recurso tras editarlo
scripts/mta.sh start rp_x / stop rp_x    # refresh + start/stop
scripts/mta.sh cmd "help"                # cualquier comando de consola; imprime la respuesta
scripts/mta.sh db                        # consola mysql en la base del gamemode
scripts/mta.sh restart                   # reinicia el servidor MTA (la base sigue)
scripts/mta.sh down                      # shutdown limpio y para los contenedores
scripts/mta.sh reset-db                  # borra todos los datos (pide confirmación)
```

Los recursos se montan desde `resources/` del repo: editas en el Mac y haces
`restart-res`. No hay que copiar nada como en Windows.

`cmd` escribe en una FIFO (`/tmp/mta-console` dentro del contenedor) que hace de
teclado de la consola, y muestra las líneas nuevas del log tras `WAIT` segundos
(2 por defecto: `WAIT=5 scripts/mta.sh cmd "start rp_x"`).

La base también se puede abrir con TablePlus/DBeaver en `127.0.0.1:3307`
(usuario y contraseña de `.env`; el puerto se cambia con `DB_HOST_PORT`).

## 4. Pruebas automáticas

```bash
scripts/test.sh             # con los datos que ya hay
scripts/test.sh --fresh     # borra la base antes: prueba una instalación limpia
scripts/test.sh --down      # para los contenedores al terminar
```

Recrea el contenedor del servidor, espera a que `rp_database` esté lista, arranca
`rp_test`, imprime el resultado y sale con **0** si todo pasa o **1** si algo falla.
También falla si la consola tiene alguna línea `ERROR:` desde el arranque (recurso que
no carga, error de script del servidor, sentencia del esquema que falla).

Salida típica:

```
  INICIO 13 pruebas
  PASS  bd_conectada_y_esquema_aplicado - rp_database:isReady() = true
  PASS  recursos_roleplay_arrancados - 28 recursos en marcha
  PASS  esquema_tablas_y_columnas - 24 tablas y 18 columnas añadidas por ALTER
  ...
  RESULTADO: 13 PASS, 0 FAIL
  FIN OK
```

Qué comprueba `rp_test` (todo del lado servidor, sin jugadores):

| Prueba | Qué valida |
|---|---|
| `bd_conectada_y_esquema_aplicado` | `rp_database:isReady()` y una consulta real |
| `recursos_roleplay_arrancados` | Todos los recursos de `[roleplay]` en estado `running` (dice cuál falla y por qué) |
| `esquema_tablas_y_columnas` | Cada `CREATE TABLE` y `ADD COLUMN` de `schema.lua` existe en la base |
| `bcrypt_hash_y_verificacion` | `passwordHash`/`passwordVerify` como en `rp_login` |
| `registro_de_cuenta`, `registro_duplicado_rechazado`, `login_de_cuenta` | Mismas consultas que `rp_login` (+ `login_log`) |
| `creacion_de_personaje`, `nombre_de_personaje_duplicado_rechazado` | Mismo `INSERT` que `rp_characters`, valores por defecto |
| `inventario_dar_y_quitar_items` | Upsert de `giveItem`, quitar sin dejar negativos |
| `banco_deposito_y_cobro_atomico` | Depósito y cobro atómico (`bank_money >= ?`, filas afectadas) |
| `borrar_cuenta_en_cascada` | La cuenta de prueba se borra y no deja filas huérfanas |

La cuenta de prueba se llama `rptest_<timestamp>` y se borra al final (y al principio,
si quedó alguna de una ejecución cortada). Para volver a ejecutar las pruebas con el
servidor ya en marcha: `scripts/mta.sh cmd "start rp_test"` o, si ya está arrancado,
`scripts/mta.sh cmd "rptest"`.

Para añadir una prueba, ver `resources/[test]/rp_test/server/s_tests.lua`:
`test("nombre", function(t, ctx) ... t.pass() / t.fail("motivo") end)`.

## 5. Conectarse con un cliente

El servidor publica `22003/udp` (juego), `22005/tcp` (descargas HTTP) y `22126/udp` (ASE).
Desde un PC con Windows y MTA en la misma red: `IP-del-Mac:22003`. En Mac no hay
cliente de MTA, así que desde el propio Mac solo se prueba por consola.

## Limitaciones

- **No se prueba nada del cliente**: `c_*.lua`, CEF (`html/`), dx, teclas, sonidos. Un
  error de script de cliente no aparece en este log; solo con un cliente y `/debugscript 3`.
- Los handlers que necesitan un jugador (`client`, distancia a un cajero, CEF) no se
  ejecutan: `rp_test` reproduce sus consultas SQL, no sus eventos.
- El build de Linux no lee las cosas de Windows (`MTA Server.exe`, `.dll`). Los recursos y
  la base son los mismos.
- En Apple Silicon el binario arm64 del servidor es oficial pero menos usado. Si diera
  problemas, fuerza x86 (Docker Desktop con Rosetta activado):
  `DOCKER_DEFAULT_PLATFORM=linux/amd64 scripts/mta.sh up`.

## Problemas típicos

- **`Falta DB_PASSWORD en .env`**: no copiaste `.env.example` a `.env`.
- **El puerto 3307 o 22003 está ocupado**: cambia `DB_HOST_PORT` / `MTA_PORT` en `.env`.
- **`config.lua ya existe y no es de Docker`**: tienes un `config.lua` con `host = "127.0.0.1"`;
  bórralo o renómbralo para que el contenedor lo genere.
- **`Querying MTA master server... failed`**: solo afecta a salir en la lista pública; se ignora.
- **Cambios en `docker/mta/`**: `scripts/mta.sh up` reconstruye la imagen sola.
