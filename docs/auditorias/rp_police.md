# Auditoría de rp_police

## 2026-11-25 · arreglar
- **Motivo**: `c_police.lua:279: Bad argument @ 'dxDrawText' [Expected string at argument 1, got boolean]` repetido con el radar de la patrulla.
- **Causa**: el radar dibuja `getVehiclePlateText(...)`, que devuelve `false` en vehículos sin placa (y el dato del ALPR puede no traerla).
- **Nota**: 87 → 87.
- **Cambios**: si la matrícula no es un texto, se muestra "Sin matrícula".
- **Reglas manuales revisadas**: — (cambio de una línea en el cliente).
- **Pendiente**: FALLA I y avisos de la auditoría (ver informe).
- **Probar en juego**: radar de la patrulla apuntando a una bici o vehículo sin placa; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 10eb4a1)

**Nota: 87/100** · OK 27 · FALLA B 0 · FALLA I 1 · AVISO 4

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_vehicles |
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /pir ; /plista |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_police.md |
| AVISO | I | PRU-01 | Pruebas en rp_test | usa la BD y rp_test no lo menciona |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
