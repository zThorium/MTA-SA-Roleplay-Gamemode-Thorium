# Auditoría de rp_restaurants

## 2026-11-25 · crear
- **Motivo**: habilitar los restaurantes de comida rápida de Los Santos con su interior original, empleados y la compra de menús con la animación de GTA SA.
- **Nota**: — → 100.
- **Cambios**:
  - 6 locales (Burger Shot Marina y Temple, Cluckin' Bell Market, Willowfield y East LS, Well Stacked Pizza Idlewood) con puerta `E`, interior original (10, 9 y 5) y dimensión propia `25000+id`.
  - Empleado congelado tras el mostrador (skins 205/167/155), inmune al daño en el cliente y reaparece si muere.
  - Menú dx con los platos originales del juego (clic o 1-4). El servidor valida local, interior, dimensión, distancia al mostrador, cooldown y efectivo; cobra antes de entregar y guarda con `saveCharacter`.
  - Se come en el mostrador con `FOOD/EAT_Burger|EAT_Chicken|EAT_Pizza`, comida en la mano (`bone_attach`, hueso 12), empleado con `SHP_Tray_Out` y `SHP_Thank`. Con hambre ≥ 90 se vomita (`EAT_Vomit_P`) y no alimenta, como en SA.
  - Blips 10/14/29 con PNG propio en `rp_hud`.
- **Reglas manuales revisadas**: SEG-02 ✔ (el cliente solo manda id de local e índice; precio y efectos los decide el servidor), SEG-04 ✔ (cooldown de 1,5 s por jugador y bloqueo mientras come), BD-06 N/A (efectivo con `takePlayerMoney` tras comprobar saldo, sin BD propia), CIC-06 ✔ (al salir, cambiar de personaje, quedar abatido, morir o parar el recurso se destruye la comida, se descongela y se devuelven los controles). PRU-02: pendiente de probar en juego.
- **Verificación**: servidor aislado (puertos 22103/22105): `Resources: 63 loaded, 0 failed`, 6 empleados y 6 blips creados, `isPlayerEating` responde; el cliente compila.
- **Pendiente**: ajustar en juego las coordenadas de puertas, empleados y mostrador (`shared/s_config.lua`, salen de los enex de SA) y el offset de la comida en la mano.
- **Probar en juego**: entrar y salir de cada local; pedir con clic y con 1-4; sin dinero; pedir lejos del mostrador; comer con hambre alta (vómito); salir del juego o quedar abatido mientras comes; `restart rp_restaurants` con alguien comiendo.
<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
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
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 25000 |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
