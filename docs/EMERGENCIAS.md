# Emergencias 911 (`rp_emergency`)

`/911` abre un menú con **Policía**, **Bomberos** y **Ambulancia** (teclas 1, 2, 3). Cada opción es un procedimiento
independiente (`procedures` en `server/s_emergency.lua`). Hoy solo la ambulancia tiene comportamiento; policía y
bomberos disparan el evento de servidor `rp:emergency:onCall` (`source` = jugador, `service`, `x, y, z, interior, dimensión`)
para que `rp_police` / facciones lo implementen.

## Flujo de la ambulancia

1. El servidor valida (personaje, exterior, sin llamada activa, cooldown, tope global) y pide al **cliente** un punto de la calle a 120-200 m fuera de la vista.
2. Crea ambulancia (416) + conductor + 2 paramédicos. El jugador que llamó es el *syncer*: su cliente conduce con el A* de `rp_rides`/`rp_citizens`.
3. Al llegar, los paramédicos bajan y buscan abatidos en `SEARCH_RADIUS`:
   - **Abatidos**: caminan (el cliente camina, el servidor teletransporta si se atascan), RCP `REVIVE_TIME` s y `revivePlayer`. Varios: por cercanía, hasta `MAX_PATIENTS`.
   - **Nadie**: miran alrededor `LOOK_TIME` s, vuelven al vehículo y esperan a que ambos estén dentro antes de irse.
   - **Muerto** (siempre el último): camilla simulada (se pega al paramédico con `attachElements` y animación `CARRY`), sube a la ambulancia, viaja al hospital más cercano (el paciente pasa a ser syncer), se entrega en la puerta, pantalla en negro `TREAT_TIME` s y reaparece en la cama con `TREAT_HEALTH`.
4. Se van y se desvanecen. Cualquier fallo (caller desconectado, no llega en `ENROUTE_TIMEOUT`, atasco) limpia todo y libera a los pacientes.

## Contrato con el sistema de abatidos

El estado "abatido" lo implementa `rp_injury`, que cumple este contrato (claves editables en `shared/s_config.lua`):

| Qué | Cómo |
|---|---|
| Jugador abatido (reanimable) | `setElementData(player, "rp:downed", true)` |
| Muerto sin reanimar | `setElementData(player, "rp:dead", true)` o muerto de MTA |
| Reanimar | `rp_emergency` dispara `triggerEvent("rp:emergency:revive", player, motivo)`; el sistema de abatidos debe escucharlo y limpiar su estado. Si no hay nadie escuchando, hace el mínimo él mismo (borra las claves, vida, controles, `spawnPlayer` si estaba muerto) |
| Entrega en hospital | evento `rp:emergency:onPatientDelivered` (`source` = paciente, nombre del hospital) |

Con `rp_injury`, un jugador abatido tiene 2 minutos (`INJURY.DOWNED_TIME`) para que lleguen los paramédicos; `rp_injury`
escucha `rp:emergency:revive` y cancela su temporizador. Si se desangra, a los 5 s aparece en el hospital y paga la tarifa,
así que el traslado de muertos casi no se usa. Un jugador abatido no puede usar `/911` (tiene que llamar otro).

## Pendiente / a verificar en juego

- Coordenadas de `HOSPITALS` (carretera, puerta, cama) y `CARRY_OFFSET` de la camilla: están puestas de memoria.
- Llamar desde interiores no está soportado (hay que salir).
- Animaciones: `MEDIC/CPR`, `BOMBER/BOM_Plant_Loop`, `CARRY/liftup|crry_prtial`, `CRACK/crckdeth2`, `COP_AMBIENT/Coplook_loop`.
- Sin pruebas en juego todavía.
