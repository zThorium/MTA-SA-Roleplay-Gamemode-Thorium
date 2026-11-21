# Agencia de Empleo y Registro Civil (`rp_agency`)

Edificio: Ayuntamiento de Los Santos (Pershing Square). Puerta con `E`; dentro es el
interior 3 (*Planning Department*) en la dimensión `30001`.

## Flujo del jugador

1. Entra y se acerca al **dispensador rojo** (`E`). Elige motivo con `1`/`2` o clic:
   *Obtención de DNI* (`D-xx`) u *Obtención de trabajo* (`T-xx`). Sale el ticket (sonido + animación).
2. HUD de turnos arriba a la derecha: número que atiende cada mostrador, su turno y cuántos tiene delante.
3. Cuando un mostrador queda libre se llama al primero de la cola: sonido, cartel y flecha.
   Tiene `CALL_TIMEOUT` s para sentarse; si no, el turno expira.
4. Si intenta salir con turno, aparece la alerta: `E` otra vez para salir y perderlo.
   También lo pierde si muere, cae abatido o se desconecta.
5. En el mostrador: cinemática (se sienta, plano lateral → plano central de la trabajadora) y diálogo.
   - **DNI**: preguntas (nombre, edad, sexo, origen, estatura) que se escriben en la ficha, foto,
     firma con el ratón, la trabajadora se levanta, sale de plano a imprimir (sonidos) y vuelve a entregarlo.
     Ítem `id_card` al inventario. Primero gratis; duplicado `DNI_DUPLICATE_PRICE` en efectivo si lo perdió.
   - **Trabajo**: lista de ofertas → *Más información* (cinemática de la zona con subtítulos), *Volver* o
     *Confirmar*. Requiere DNI (`REQUIRE_DNI_FOR_JOB`).
   - Al terminar: *¿Desea hacer algo más?* → otro trámite o marcharse.

Todo lo ajustable (posiciones, tiempos, precios, mostradores) está en `shared/s_config.lua`.
El mobiliario se coloca relativo a `AGENCY.ORIGIN`: si en juego algo choca con el edificio,
mueve `ORIGIN` o el offset del elemento.

## DNI (mismo patrón que la licencia de `rp_driving`)

- Registro en `identity_cards` (uno por personaje: `number`, `signature`, `copies`, `issued_at`).
- El ítem `id_card` es solo el papel. Usarlo muestra la tarjeta al propio jugador.
- `/mostrardni [jugador]` la enseña a alguien a menos de 3 m. `/consultardni <jugador>` para la
  facción de tipo `policia` (consulta el registro aunque no lo lleve encima).
- Número: 8 cifras derivadas del id del personaje (únicas) + letra de control módulo 23.
- Exports (servidor): `hasPlayerDNI(player) -> bool`, `getPlayerDNI(player) -> tabla | false`
  (`number, name, gender, birth, origin, height, issued, expires, signature, copies`).

## Contrato con `rp_jobs`

La agencia no guarda trabajos. Si `rp_jobs` está arrancado usa sus exports de servidor:

| Export | Uso en la agencia |
|---|---|
| `getJobList()` | Array de `{ id, name, icon, description, pay, howTo, requirements?, locationName?, location = {x,y,z,interior,dimension}, cinematic? }`. `cinematic` es una lista de planos `{ cam={x,y,z}, look={x,y,z}, ms, text }` (máx. 8) para *Más información*; si falta, la agencia genera 3 planos alrededor de `location`. |
| `getPlayerJob(player)` | Marca el trabajo actual en la lista. |
| `setPlayerJob(player, jobId)` | Al confirmar. Devuelve `true` o `false, motivo` (el motivo lo dice la trabajadora). |
| `showJobLocation(player, jobId)` | Tras contratar, `rp_jobs` pone blip + GPS hasta la sede. |

Sin `rp_jobs`, la agencia usa `AGENCY.FALLBACK_JOBS`, pone el element data `"rp:job"` (no persistente)
y marca ella misma la ubicación con blip y checkpoint.
