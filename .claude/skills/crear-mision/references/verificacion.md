# Verificación de una misión (antes de decir "listo")

El **cliente (cámara, HUD, CEF, IA de enemigos, mocap, audio) no se puede probar sin un jugador**: lo que sí se puede es comprobar que el servidor arranca sin errores y que los scripts de cliente compilan. Dilo claro y pide a Fabián que pruebe.

## 1. Servidor de prueba aislado (no tocar el servidor de Fabián, que suele estar abierto)
Hay un `MTA Server.exe` real corriendo con los puertos 22003/22005. Para probar:
1. Copiar `mtaserver.conf` a `mtaserver_test.conf` cambiando `serverport` → **22103**, `httpport` → **22105**, `logfile`/`authfile`/`scriptdebuglogfile` → `logs/test_*.log`, `<ase>` → 0 y `scriptdebugloglevel` → **3** (con 0 los errores de Lua no llegan a ningún log).
2. Lanzar `MTA Server.exe --config mtaserver_test.conf` en una ventana oculta (`Start-Process -WindowStyle Hidden`; el servidor necesita consola real), esperar ~40 s, matar solo ese proceso por su PID.
3. Leer `logs/test_server.log`: debe decir `Resources: N loaded, 0 failed` y no aparecer `ERROR`, `Loading script failed` ni `Couldn't find script(s)`.
4. **Sintaxis de scripts de cliente**: crear un recurso temporal `zz_syntaxcheck` cuyo `meta.xml` cargue como `type="server"` copias de los `.lua` de cliente (`loadstring`/`fileOpen` entre recursos están denegados por ACL). Un error de sintaxis sale como `Loading script failed`; los errores de `guiGetScreenSize`/`bindKey`/`C is nil` son **esperables** (API de cliente en el servidor).
5. Borrar el recurso temporal, `mtaserver_test.conf` y los `logs/test_*` al terminar.
6. Pruebas de lógica pura (catálogo, exports): un recurso `zz_check` con `setTimer` que llame a los exports y escriba `outputServerLog("PRUEBA ...")`.

## 2. Comprobaciones de contenido
- `/mocap lista`: cada personaje de las líneas tiene mocap; las voces existen para todas las líneas no-`me` (`s_voice.lua` regenerado, `<file>` en `meta.xml`, tamaño ~1 KB/carácter).
- Los índices de `lines`/`radio` no cambiaron de orden (los audios dependen de ellos).
- `check-library.ps1` → 0 clips en T-pose si se tocó la biblioteca.
- Esquema/tablas nuevas: `rp_database` dice `Esquema verificado (N sentencias)`.
- `RECURSOS.md` y `rp_adminpanel/server/s_catalog.lua` al día si hay comandos/exports nuevos.

## 3. Qué pedir que pruebe Fabián en juego (siempre entregar esta lista)
Cinemáticas (planos legibles, nadie dentro de un vehículo al empezar, gestos de mocap, sin T-pose, voz sincronizada con el subtítulo), enemigos (aparecen en sitio abierto y se les puede disparar, IA, headshot), objetivos (`E` para interactuar, blips en el borde del radar), radio silenciada, estrellas (no entrar con ellas, no salir con ellas), muerte/vidas/espectador, resultados y recompensas, salida al mundo libre (posición, armas, HUD).

## 4. Entrega
- Informar de qué se hizo, qué está verificado (servidor) y qué NO (cliente), y el comando para reiniciar (`restart rp_missions`; **nunca** `rp_mocap` sin `/mocapdescargar`).
- Actualizar `memory/rp-missions.md` con lo hecho y lo pendiente.
- Subir a `main` solo si Fabián lo pide; el servidor local tiene cambios ajenos sin commitear (gimnasio, `rp_heads`, `schema.lua` con tablas locales): **no commitear a ciegas**, usar un clon limpio en el tmp del job y aplicar solo los parches propios. `CLAUDE.md` está fuera de git. Nunca subir `.ifp`, `muestras/` ni la API key.
