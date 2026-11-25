# Formato de una misión (`MISSION_DEFS` en `s_missions_data.lua`)

Plantilla comentada: `../templates/mision-plantilla.lua`. Ejemplos reales: `grove_turf` (conducción + tiroteo + aliado), `uncle_sam` (tareas simultáneas: cargar + defender + escolta), `cesar_cargo` (candado + escolta con emboscadas).

## Cabecera
```lua
{
    key = "clave_unica",            -- nombra los audios (<key>_<etapa><c|r><n>.mp3) y el progreso en BD
    title = "Titulo", contact = "sweet",       -- MISSIONS.CONTACTS (sweet, ryder, cesar, smoke, ...)
    desc = "Texto del menu",
    minP = 1, maxP = 4, recommended = 3,
    minLevel = 1, minRespect = 0,               -- requisitos (rp_levels / respeto)
    cash = 2400, respect = 60, xpBonus = 0,     -- recompensas base (se multiplican por dificultad)
    weather = 0, hour = 19,                     -- se aplica en el cliente y se restaura al salir
    interior = 0,                               -- opcional
    roles = { { id = "driver", name = "Conductor", max = 1, weapons = { {22, 80} }, desc = "..." }, ... },
    spawns = { {x, y, z, rot}, ... },           -- uno por integrante (el ultimo se repite)
    snap = {x, y, z, rot},                      -- reaparicion por defecto
    victory = {x, y, z, rot, spread = 1.6},     -- pose de victoria
    victoryCam = { from = P(...), look = P(...) },
    stages = { ... },
}
```

## Componentes de una etapa (una etapa termina cuando TODOS los suyos están hechos)
| Campo | Qué hace |
|---|---|
| `text` | Objetivo que se muestra en el HUD (siempre) |
| `pos = P(x,y,z)` | Punto por defecto del blip |
| `goto = {x,y,z,r, vehicle=true?}` | Todos los vivos deben llegar (radio `r`; `vehicle=true` exige ir dentro de un vehículo) |
| `getin = "clave"` | Todos los vivos dentro del vehículo con esa clave |
| `vehicles = { {key, model, x,y,z, rot, color={a,b}} }` | Crea vehículos (se arrastran entre etapas por `key`) |
| `objects = { {key, model, x,y,z} }` | Props (cajas); se borran al completar el punto con esa `key` |
| `enemies = { {skins={...}, weapon, ammo, x,y,z, radius, count, per, label} }` | Grupos que aparecen al acercarse (ver `mundo.md`: punto central en lugar abierto) |
| `waves = { grupo, grupo, ... }` | Oleadas una tras otra (cada una al limpiar la anterior) |
| `interact = { time, text, anim={block,name}, points={ {x,y,z,key} } }` | Mantener **E** cerca de un punto; progreso compartido, varios jugadores a la vez; acredita "objetivo" al que lo hizo |
| `deliver = { vehicle, x,y,z, r, minHealth, ambush={ {at=P(), group={...}} } }` | Llevar el vehículo a destino sin destruirlo; emboscadas por proximidad |
| `wait = ms` | Esperar |
| `radio = { {who, text} }` | Llamada de un contacto sin bloquear la acción (tarjeta con retrato y ecualizador; voz `r`) |
| `npcs = { {key, contact, skin, rel|x,y,z,rot, ally, weapon, keep} }` | NPC de historia; `ally = true` los hace acompañar y disparar |
| `boardNpc = { "npc", "vehiculo" }` | Sube al NPC a un asiento libre del vehículo |
| `snap = {x,y,z,rot}` | Punto de reaparición a partir de esta etapa |
| `cutscene = {...}` | Cinemática (ver `cinematicas.md`) |
| `timeLimit = ms` | Límite de tiempo de la etapa: cuenta atrás en el HUD (roja y parpadeante con < 30 s), aviso a los 30 s y misión fallida al agotarse |

**Texto de objetivo con color** (`text`): etiquetas `~y~` amarillo (destinos), `~r~` rojo (enemigos), `~b~` azul (vehículos), `~g~` verde (Grove / recogibles), `~w~` blanco. Si no lleva etiquetas se colorea solo con `MISSIONS.TAGWORDS` (`shared/s_config.lua`); añade ahí las palabras nuevas. Blips y marcadores siguen la misma convención (amarillo destino, rojo enemigos, azul vehículos).
**Enemigos atascados**: si quedan ≤ 3 sin moverse ni recibir daño 75 s, el servidor los retira. **Vehículo abandonado**: el destino se oculta y aparece una flecha 3D azul sobre el vehículo.

Etapa de solo texto/radio se completa en el primer ciclo. Los vehículos y props creados en una etapa siguen existiendo en las siguientes.

## Detalles
- Coordenadas: `P(x,y,z)` es `{x,y,z}`. **Las inventadas son aproximadas**: se ajustan en juego con `/mmover <contacto>` (mueve el punto de inicio) y `/mskip` (salta la etapa, admin). No inventes interiores ni alturas sin comprobar.
- Roles: se asignan en la sala (o automáticamente al iniciar); equipo y desc se muestran en el menú.
- El primer plano de cada cinemática usa coordenadas del mundo; el resto relativos al actor (`TalkShots`).
- Dificultad y vidas: Fácil 4 / Normal 2 / Difícil 0 vidas compartidas (`MISSIONS.DIFFICULTY`).
- Nueva misión = añadir el bloque al final de `MISSION_DEFS`; el índice en la lista es el que muestra el menú. No hay que registrar nada más (los contactos tienen marcador propio en `MISSIONS.CONTACT_POINTS`).
