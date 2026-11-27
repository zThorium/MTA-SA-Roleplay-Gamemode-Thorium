# Auditoría de rp_worldobjects

## 2026-11-27 · crear
- **Motivo**: interactuar con los objetos del mapa original de GTA SA; primera interacción: sentarse en bancas, sillas, sofás y taburetes con E.
- **Diseño**: posiciones offline desde los IPL del juego (`tools/generar-objetos.ps1`, sin material de Rockstar en el repo: solo números); la altura del asiento y el respaldo se miden en el cliente con raycasts sobre el modelo real (perfil de alturas a lo ancho del fondo); el servidor valida objeto, plaza, interior, distancia y ocupación.
- **Reglas manuales revisadas**: SEG-02 ✔ (evento con `client`, cooldown, números convertidos y acotados, plaza dentro del radio del objeto, distancia, interior, abatido/esposado/vehículo); SEG-04 ✔ (no hay dinero ni items); BD-06 N/A; PRU-02 ✔ (`s_tests_worldobjects.lua`); UX-01 ✔ (tecla E dibujada sobre la plaza y abajo para levantarse); UX-02 ✔ (solo la plaza más cercana); UX-06 ✔ (sonido suave al sentarse); UX-10 ✔ (`CREDITOS.md`).
- **Pendiente**: ajustar en juego `WO.KINDS.sit.zOffset` y `back` si el personaje queda alto o bajo; ampliar a otros tipos (`WO.KINDS`): apoyarse, papeleras, cabinas...
- **Probar en juego**: banca de parque, banca de piedra (estación Cranberry), silla de interior y sofá; dos jugadores en la misma plaza; abatido sentado; `restart rp_worldobjects` sentado; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 3042b26)

**Nota: 98/100** · OK 28 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_worldobjects.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
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
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
