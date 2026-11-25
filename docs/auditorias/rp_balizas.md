# Auditoría de rp_balizas

## 2026-11-25 · arreglar
- **Motivo**: `c_balizas.lua:109: attempt to index upvalue 'C' (a nil value)` en cada fotograma; las balizas no se veían.
- **Causa**: `local C = BALIZAS` al cargar el script. `client/c_balizas.lua` es `cache="false"` y `shared/s_config.lua` está cacheado, así que el cliente puede ejecutar primero el script y `BALIZAS` aún no existe.
- **Nota**: 98 → 98 (la regla nueva CLI-04 marcaba el fallo: FALLA I → OK).
- **Cambios**: la config se lee en `onClientResourceStart` y el render no hace nada hasta tenerla (CLI-04). Regla CLI-04 añadida al estándar y al script de auditoría.
- **Reglas manuales revisadas**: CIC-05 ✔ (las luces se destruyen al salir del rango o destruirse el vehículo).
- **Pendiente**: CLI-02 (recorre `getElementsByType("vehicle")` cada fotograma; medir FPS con varias patrullas).
- **Probar en juego**: `restart rp_balizas`, sirena encendida (O o H) junto a una pared; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 10eb4a1)

**Nota: 98/100** · OK 24 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_balizas.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-04 | Los timers se pueden cancelar |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
