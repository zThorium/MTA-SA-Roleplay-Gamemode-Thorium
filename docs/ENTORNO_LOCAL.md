# Entorno local

Cómo levantar Thorium en Windows para desarrollar y probar.

> ¿Mac o Linux, o solo quieres probar el servidor por consola? Usa el entorno Docker
> (servidor MTA de Linux + MariaDB, con pruebas automáticas): [`DOCKER.md`](DOCKER.md).

## Requisitos

- **MTA:SA 1.6** con su servidor. Ruta habitual:
  `C:\Program Files (x86)\MTA San Andreas 1.6\server` (en adelante `SERVER`).
- **MariaDB/MySQL 10.4+**. XAMPP sirve (solo hace falta el módulo MySQL). Docker con `mariadb` también.
- Git. El repo se clona **fuera** de `SERVER` (por ejemplo `Documents\thorium`) y se sincroniza.

## 1. Base de datos

Arranca MySQL (XAMPP Control Panel → **Start** en MySQL). Luego, como root (phpMyAdmin o `mysql -u root`):

```sql
CREATE DATABASE mtarp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'mtarp'@'127.0.0.1' IDENTIFIED BY 'una-contraseña-larga';
GRANT ALL PRIVILEGES ON mtarp.* TO 'mtarp'@'127.0.0.1';
```

No importes ningún `.sql`: `rp_database` crea y migra las tablas solo al arrancar
(`schema.lua`). Cada persona tiene su propia base local; los datos no se comparten.

## 2. Credenciales

```
copy "resources\[roleplay]\rp_database\config.example.lua" "resources\[roleplay]\rp_database\config.lua"
```

Edita `password` en `config.lua` (en la copia del servidor). Este archivo está en `.gitignore`.

## 3. Sincronizar el repo con el servidor

El servidor lee de `SERVER\mods\deathmatch`. Copia encima lo del repo (PowerShell como
administrador, porque está en `Program Files`):

```powershell
$repo = "$HOME\Documents\thorium"
$dm   = "C:\Program Files (x86)\MTA San Andreas 1.6\server\mods\deathmatch"
robocopy "$repo\resources\[roleplay]" "$dm\resources\[roleplay]" /E
copy "$repo\mtaserver.conf" "$dm\mtaserver.conf"
```

- `/E` copia sin borrar, así no pisa tu `config.lua` ni tu `map.png`. Si se elimina un
  archivo en el repo, bórralo a mano en el servidor.
- `acl.xml` solo cópialo la primera vez; después tendrás cuentas propias en él que no se suben.
- Alternativa: trabajar directamente con un clon dentro de `resources\[roleplay]`, cuidando
  no commitear nada del servidor.

## 4. Minimapa

`rp_hud/images/map.png` no está en el repo (es de Rockstar). Genéralo desde tu `gta3.img`
con `rp_hud/tools/RadarExtract.cs`. Sin él el HUD funciona pero sin mapa.

## 5. Arrancar y probar

1. Ejecuta `SERVER\MTA Server.exe`. En consola debe salir
   `[rp_database] Esquema verificado (...). Base de datos lista.`
2. Conéctate a `127.0.0.1:22003`, registra una cuenta y crea un personaje.
3. Hazte admin del gamemode:
   ```sql
   UPDATE accounts SET admin_level = 1 WHERE username = 'TuUsuario';
   ```
4. Para ver errores de cliente con `/debugscript 3`, añade tu cuenta MTA al grupo `Admin`
   de **tu** `acl.xml` local (`<object name="user.TuCuenta" />`). No subas ese cambio.

Comandos útiles en la consola del servidor tras sincronizar:

| Comando | Para qué |
|---|---|
| `refresh` | Detecta archivos/recursos nuevos o cambiados |
| `restart rp_x` | Reinicia un recurso (los jugadores conectados pueden quedar sin estado: reloguea si algo falla) |
| `start rp_x` / `stop rp_x` | Arrancar o parar un recurso |

Si cambias `rp_database/schema.lua`, reinicia `rp_database` (o el servidor) para aplicar la migración,
y revisa la consola: una sentencia que falla se registra y el resto sigue.

## Problemas típicos

- **"No se pudo conectar a MySQL"**: MySQL no está encendido o `config.lua` tiene datos mal.
- **Pantalla negra al entrar**: un recurso de la cadena (`rp_login`, `rp_characters`) no arrancó; mira la consola.
- **Cambios que no se ven**: no sincronizaste, o falta `refresh` + `restart` del recurso.
