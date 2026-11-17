# Emergencias 911 (`rp_emergency`)

`/911` abre un menú con **Policía**, **Bomberos** y **Ambulancia** (teclas 1, 2, 3). Cada opción es un procedimiento
independiente (`procedures` en `server/s_emergency.lua`). Hoy solo la ambulancia tiene comportamiento; policía y
bomberos disparan el evento de servidor `rp:emergency:onCall` (`source` = jugador, `service`, `x, y, z, interior, dimensión`)
para que `rp_police` / facciones lo implementen.

## Llamar desde el celular

La app **Teléfono** de `rp_phone` (icono verde) trae por defecto **911 Ambulancia**, **912 Policía** y **913 Bomberos**
(tabla `EMERGENCY_NUMBERS` en `rp_phone/server/s_phone.lua`) y un teclado para marcarlos. `rp_phone` valida que tengas
teléfono y no estés abatido, y llama al export `callService(player, servicio)` de `rp_emergency`, que es el mismo punto de
entrada que usa el menú `/911`: mismas validaciones, mismo cooldown y la misma ambulancia IA hacia la posición del que llama.
Devuelve `true` si la central aceptó la llamada; si la rechaza (en un vehículo, en un interior, ya hay una en camino...)
avisa al jugador y el celular muestra "La central no pudo atender tu llamada".

Un jugador **abatido no puede llamar** (ni con `/911` ni con el celular, que se guarda al caer): la ambulancia la tiene que
pedir otra persona, y los paramédicos reaniman a todos los abatidos en 45 m de quien llamó.

## Flujo de la ambulancia

1. **Despacho.** El servidor valida (personaje, exterior, sin llamada activa, cooldown, tope global) y pide al **cliente**
   un punto de un carril a 110-170 m, fuera de la vista y **con ruta** hasta el jugador.
2. Crea la ambulancia (416) con sirena, un conductor y 2 paramédicos con nombre (`PARAMEDIC_NAMES`) y número de unidad.
   El jugador que llamó es el *syncer* **persistente** (`setElementSyncer(..., true)`): sin `persist`, MTA le quita el
   control a más de 100 m del ped y la ambulancia no arrancaba.
3. **Trayecto** (`client/c_graph.lua` + `client/c_driver.lua`): A* sobre la red vial de `rp_citizens` (con los cambios
   del editor `/nodos`), desde el carril en el que está la ambulancia y sin giros en U, hasta el carril más cercano a
   quien llamó. Puntos por el carril derecho con curvas Bézier en los cruces (como el tráfico), pure pursuit con
   asistencia de dirección, frena en curvas, cruza los cruces a `JUNCTION_SPEED`, bocina y desvío si algo la bloquea,
   marcha atrás si se atasca y **recalcula la ruta** si se sale de ella. Se detiene pegada a la acera. Solo se recoloca
   como último recurso, si ningún jugador la ve ni está a menos de 70 m.
   - **Conducción de emergencia**: sirena sonando todo el trayecto (el control `horn` del NPC la apagaba: ya no se usa,
     la bocina es un sonido propio), `CRUISE_SPEED` 85 km/h, adelanta a los lentos por el carril contrario o el arcén y
     puede ir a contramano por una calle de un sentido si le ahorra mucho camino (`WRONG_WAY_FACTOR` en `c_graph.lua`).
   - **Ruta propia fuera de la calle** (`client/c_offroad.lua`): si el paciente no está junto a una calle (parque,
     plaza, estacionamiento), desde el punto de parada arma su propio camino (línea recta si cabe; si no, A* en una
     rejilla de 2,5 m que comprueba suelo, escalones, muros y el ancho de la ambulancia) y se detiene a
     `OFFROAD_STOP` m del paciente, a `OFFROAD_SPEED`. Si no hay calle cerca, sale directamente con su ruta propia.
4. **Llegada.** Radio a la central, se abren las puertas, los paramédicos bajan con la animación de salir (uno por la
   puerta del copiloto, otro por atrás con el equipo) y buscan abatidos en `SEARCH_RADIUS`:
   - **Abatidos**: corren (camino a pie, ver abajo) hacia el paciente y hacen el guion de rol (~20 s): valoración, pulso, RCP contando
     compresiones, parches del desfibrilador, "¡Despejen!", descarga (destello y temblor para el paciente), "¡Tenemos
     pulso!", `revivePlayer` y consejos. Varios: por cercanía, hasta `MAX_PATIENTS`.
   - **Nadie**: se acercan a quien llamó, preguntan, miran alrededor `LOOK_TIME` s y vuelven.
   - **Muerto** (siempre el último): camilla simulada (`attachElements` + animación `CARRY`), sube a la ambulancia,
     traslado con sirena al hospital más cercano (el paciente pasa a ser syncer), entrega en urgencias, pantalla en
     negro `TREAT_TIME` s y reaparece en la cama con `TREAT_HEALTH`.
5. **Partida.** Guardan el equipo, vuelven a sus puertas, suben con la animación de entrar, radio "unidad libre",
   apagan la sirena, se alejan por la red vial y se desvanecen. Cualquier fallo (caller desconectado, no llega en
   `ENROUTE_TIMEOUT`) limpia todo y libera a los pacientes.

**Movimiento a pie de los paramédicos** (`client/c_walk.lua`): el servidor pide al cliente de quien llamó un camino a
pie (`footPath` en `client/c_offroad.lua`: línea recta si está libre, si no A* en rejilla de 1 m que rodea autos, muros,
postes y la propia ambulancia), lo valida, pone la animación de correr (`run_civi`) o caminar sin que la animación mueva
al ped, le quita el syncer y lo envía a todos los jugadores a menos de 250 m con la duración. Cada cliente desplaza el
ped por el camino a la misma velocidad (5 m/s corriendo, 1,45 m/s caminando); al terminar el servidor fija la posición
final (donde ya está) y le devuelve el syncer. No depende de que un cliente controle el ped, que era lo que fallaba y
terminaba en teletransporte.

Los globos de rol (`client/c_bubbles.lua`) se ven sobre la cabeza del paramédico a menos de 32 m y salen en el chat de
quien esté a menos de 20 m: lo que dice (blanco), sus acciones `/me` (morado) y la radio (azul). Las frases están en
`EMERGENCY.LINES` (se elige una al azar).

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
