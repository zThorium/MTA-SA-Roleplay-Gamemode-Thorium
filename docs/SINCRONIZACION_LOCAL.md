# Sincronización automática del servidor local

`tools/sync-local.ps1` mantiene la carpeta del servidor MTA de tu PC (Windows) al día con `main`.
Lo ejecuta el Programador de tareas cada 2 minutos.

## Qué hace

Cada ejecución hace `git fetch` en el repositorio git de la propia carpeta del servidor (`mods\deathmatch`; si esa carpeta no
es un repo, usa un clon aparte en `Documents\mta-rp-sync\repo`). **Nunca hace checkout ni `reset --hard`**: lee los
archivos nuevos directamente del commit de `main`. Si `main` no
cambió, termina sin hacer ni escribir nada. Si cambió:

1. Respalda lo que va a tocar en `mods\deathmatch\backups\sync-AAAA-MM-DD_HHMMSS`.
2. Copia los archivos nuevos o cambiados a `mods\deathmatch` **sin pisar tus cambios locales**:
   - si tu archivo es igual al de la versión anterior de `main`, lo reemplaza;
   - si tiene cambios tuyos, los fusiona (fusión de 3 vías); si chocan, deja **tu** versión y guarda la de `main`
     como `<archivo>.main-nuevo` para que la revises;
   - si un archivo es nuevo en `main` y ya existía distinto en el servidor, toma el de `main` (el tuyo queda en el respaldo);
   - los archivos borrados en `main` se mueven al respaldo, nunca se eliminan.
3. **Nunca toca** `acl.xml`, `vehiclecolors.conf`, `rp_database\config.lua` ni nada fuera de `resources\`, `docs\`,
   `.claude\` y los `.md` de la raíz. `mtaserver.conf` solo recibe líneas nuevas (ver abajo).
4. Registra en `mtaserver.conf` los recursos nuevos con `startup="1"`, después de sus dependencias (`<include>` del
   `meta.xml`) y respetando el orden del repositorio.
5. Escribe `ultimo-sync.txt` (resumen legible de la última sincronización, con **qué reiniciar**) y agrega al historial
   `sync-local.log`.

Qué reiniciar, según el log:

| Cambió | Qué hacer |
|---|---|
| `schema.lua` o hay recursos nuevos | Reiniciar el **servidor completo** (el esquema se aplica al arrancar) |
| Solo archivos de recursos existentes | En la consola: `refresh` y luego `restart <recurso>` por cada uno que liste |
| Solo documentos | Nada |

El script nunca reinicia el servidor ni sus recursos: eso lo decides tú.

## Instalación (una sola vez)

Requisitos: Git instalado y acceso al repositorio (el mismo que usa `git` o `gh` en tu PC).

1. Copia el script a una carpeta tuya (o usa el que viene en el repo) y márcalo como "ya aplicado". Esto **no copia nada**:
   Con `-BaseSha <commit>` indicas hasta qué commit de `main` está aplicado tu servidor (por defecto, el `main` actual):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<ruta>\sync-local.ps1" -Init
   ```

   Por defecto los logs y el estado van en `%USERPROFILE%\Documents\mta-rp-sync`, y el servidor es
   `C:\Program Files (x86)\MTA San Andreas 1.6\server\mods\deathmatch`. Se cambian con `-Root` y `-Server`;
   `-Repo` fuerza otro repo git.

2. Prueba en seco (no copia nada, solo muestra lo que haría):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<ruta>\sync-local.ps1" -DryRun
   ```

3. Crea la tarea programada (cada 2 minutos, con tu usuario, solo si tienes sesión iniciada):

   ```powershell
   schtasks /Create /TN "MTA-RP-Sync" /SC MINUTE /MO 2 /F /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"<ruta>\sync-local.ps1\""
   ```

Para quitarla: `schtasks /Delete /TN "MTA-RP-Sync" /F`. Para forzar una ejecución ahora: `schtasks /Run /TN "MTA-RP-Sync"`.

## Notas

- Solo se sincroniza `main`. Lo que esté en una rama o PR sin fusionar no llega hasta que se fusione.
- Si dos ejecuciones se solapan, la segunda sale sola (archivo `sync.lock`; se ignora si tiene más de 15 minutos).
- Si no hay red, el fallo de `fetch` queda en `sync-local.log` y reintenta en la siguiente ejecución.
- Si algo sale mal, restaura desde la carpeta de respaldo que indica `ultimo-sync.txt`.
- El clon de trabajo es solo del script: no edites nada dentro de `repo\`, se reinicia en cada sincronización.
