# Logros (`rp_achievements`)

Sistema central de logros **por personaje**. Todos los recursos lo alimentan, y nadie depende de él.

## Cómo funciona en el juego

1. El jugador hace cosas en la ciudad: trabajar, conducir, explorar, apagar incendios...
2. Cada logro tiene hasta **4 medallas**: bronce, plata, oro y platino. Sube de medalla al llegar a
   cada umbral. Ejemplo: *Pizzero* da bronce a las 10 pizzas, plata a las 50, oro a las 200 y
   platino a las 1.000.
3. Cada medalla da **puntos de logro**: bronce 10, plata 25, oro 50 y platino 100.
4. Al llegar a ciertos puntos se desbloquea un **hito**. Hay 9, de 50 a 3.500 puntos. Cada hito trae
   una recompensa que el jugador **reclama** en el panel:
   - dinero al banco;
   - XP;
   - items (botiquines, mochilas);
   - **cosméticos** para su fila del Tab (`/perfil`): icono 🏅 en el hito 2, icono 🏆 en el 5,
     letras «Oro» en el 7 e icono 🐉 en el 9.
5. Hay **logros únicos**, que tienen una sola medalla (por ejemplo, *Propietario* da oro), y
   **logros secretos**, que salen como «???» hasta conseguirlos.

Al ganar una medalla sale un aviso arriba al centro, debajo de la barra de RP. Usa el mismo lenguaje
visual que `rp_levels`:
- medalla del color que toca, con halo y chispas;
- un sonido distinto para cada medalla.

Si los puntos alcanzan un hito, sale el anuncio central «¡Recompensa de logros!».

**Ficha en el HUD**: en la barra de iconos de arriba a la derecha (junto a inventario, teléfono y
ayuda) hay un trofeo con un **globo rojo** que va sumando novedades: medallas que aún no viste y
recompensas listas para reclamar. Si el jugador nunca abrió los logros, muestra «!». Así se
descubren solos: al ver el contador subir, el jugador lo pulsa (con el cursor, M). Abrir el panel
marca las medallas como vistas; las recompensas cuentan hasta reclamarlas.

**Panel**: clic en la ficha, `/logros` o la app **Logros** del teléfono (P). Tiene:
- arriba, la barra de hitos (los que se pueden reclamar brillan);
- debajo, pestañas por categoría y «Casi lo tienes»;
- tarjetas con la barra de progreso hacia la siguiente medalla.

La primera vez que se abre, un entrenador explica la barra de hitos.

## Cuándo un recurso debe dar logros (regla INT-09, obligatoria)

Todo recurso nuevo o mejorado **revisa si tiene hechos que merecen logro**. Si los tiene, los
añade. Si no, no los inventa y anota el motivo en su auditoría (`INT-09: N/A, motivo`).

**Sí merecen logro** los hechos que el jugador elige hacer y que muestran dedicación, habilidad o
descubrimiento:
- **Repetir algo con esfuerzo**: turnos, entregas, carreras, incendios apagados. Logro escalonado
  de bronce a platino.
- **Ser bueno en algo**: ganar, nota perfecta, oro en una prueba, récord. Mejor con condición de calidad.
- **Progreso con techo**: nivel, % del mapa, músculo, colección. Estadística en modo `max`.
- **Momentos únicos que se recuerdan**: primera licencia, primera casa, objeto legendario. Logro
  de una medalla, a veces secreto.

**No merecen logro**:
- **Infraestructura y herramientas**: base de datos, avisos, HUD, marcadores, IDs, efectos visuales,
  comandos y paneles de admin, herramientas de desarrollo.
- **Lo pasivo o trivial**: abrir un menú, caminar, estar conectado, estar AFK, recibir algo sin hacer nada.
- **Lo que se farmea gratis**: acciones sin coste ni riesgo que se repiten en bucle (ida y vuelta
  del cajero, comprar y revender). Si el hecho vale pero se puede abusar, pon una condición:
  - mínimo de esfuerzo (20 disparos);
  - otra persona de verdad (pool contra otro personaje, carrera con rivales);
  - otro lugar (bajar del tren en otra estación);
  - medir el estado y no el movimiento (saldo, no depósitos).
- **Lo que premia molestar a otros fuera de rol**: matar jugadores, atropellar, abusar de bugs.
  Los delitos de rol sí pueden tener logro (robos, escapar de la policía), mejor como secretos o
  con condición.

**Cómo diseñarlo bien**:
- Primero reutiliza una estadística existente (`ACH.STATS`), si el hecho ya cuenta para otra.
- Umbrales con sentido para el ritmo real del recurso: bronce en la primera sesión, plata en una
  semana, oro en un mes y platino para quien vive en ese sistema.
- Nombre corto y con gracia en español y un icono. La descripción dice exactamente qué contar.
- El aviso va en el servidor **después** de validar y cobrar, nunca desde el cliente.
- Si el recurso es de una facción (policía, bomberos), el logro cuenta lo que hace el miembro de
  servicio, no lo que le pasa.

## Para otros recursos: avisar de un hecho

Basta con **un evento de servidor**. No hace falta `<include>` ni comprobar si el recurso está en marcha:
```lua
triggerEvent("rp:achievements:progress", jugador, "pizza_delivered", 1)
```
- `jugador`: elemento jugador con personaje (si no tiene personaje, se ignora).
- `"pizza_delivered"`: clave de la estadística en `ACH.STATS` (`shared/s_achievements.lua`).
- La cantidad depende del modo de la estadística:
  - en las de modo **`add`** es lo que se suma (1 entrega, 350 dólares ganados...);
  - en las de modo **`max`** es el valor actual (nivel 7, 38 % del mapa, 640 de músculo), y solo
    cuenta si supera el récord.
- La cantidad se acota a `maxPerCall`. Si la clave es desconocida, se ignora con un único aviso en
  `/debugscript`.

Avisa **en el servidor y después de validar** el hecho (después de cobrar o entregar), nunca desde
el cliente.

### Añadir un logro nuevo
1. Si la estadística es nueva, añade una entrada en `ACH.STATS`:
   `mi_stat = { mode = "add", maxPerCall = 1 }`.
2. Añade el logro en `ACH.CATALOG`:
   `{ key, cat, icon, name, stat, tiers = {b, p, o, pt}, desc = "Haz %s cosas" }`.
   - Campos opcionales: `medals = {3}` (único de oro), `unit = "money"|"%"` y `secret = true`.
   - `key` admite hasta 48 letras y **no se cambia nunca**: está guardada en la BD.
3. Pon el `triggerEvent` en el recurso que provoca el hecho.
4. `start rp_test`: la prueba `achievements_recurso_y_catalogo` valida el catálogo (umbrales
   crecientes, estadística existente, logros `max` alcanzables...).

Si cambias umbrales, los jugadores reciben al entrar las medallas que ya les corresponden, sin aviso
pero con un resumen.

### Leer logros desde otro recurso
- `exports.rp_achievements:hasAchievement(p, requisito)` devuelve `true` o `false`. El requisito es
  uno de estos:
  - `"ach:<clave>[:<medalla 1-4>]"`;
  - `"points:<n>"`;
  - `"milestone:<n>"` (hito reclamado).

  `rp_scoreboard` lo usa para los cosméticos (campo `requires` en `SB.ICONS`/`SB.EFFECTS`).
- `getPlayerPoints(p)`, `getPlayerAchievements(p)` (puntos, estadísticas, medallas e hitos).
- `progress(p, stat, n)` hace lo mismo que el evento. `setStat` y `unlock` son para admin y pruebas.

## Estadísticas y de dónde salen

| Estadística | Modo | Fuente |
|---|---|---|
| `jobs_shifts`, `jobs_earned` | add | evento `rp:jobs:onShiftEnd` (oyente en `s_listeners.lua`) |
| `market_sales` | add | evento `rp:jobs:onMarketSale` (oyente) |
| `drugs_bought` | add | evento `rp:shop:onBought` con un item de droga (oyente) |
| `times_downed` | add | evento `rp:onPlayerDowned` (oyente) |
| `job_level` | max | `rp_jobs/server/s_jobs.lua` (`Jobs.xp`) |
| `pizza_delivered`, `pizza_perfect` (nota ≥ 95) | add | `rp_pizzeria/server/s_pizzeria.lua` (`handlers.pickup`) |
| `metal_finds`, `metal_legendary` / `metal_distinct` | add / max | `rp_metaldetector/server/s_metaldetector.lua` (`finishDig`) |
| `driving_license` | max | `rp_driving/server/s_license.lua` (`issueLicense`) y al entrar si ya la tiene |
| `driving_gold` | max | `rp_driving/server/s_runs.lua`: pruebas con oro o platino en su mejor marca |
| `races_finished`, `races_won` | add | `rp_races/server/s_races.lua` (`endRace`); para ganar hace falta otro corredor |
| `train_trips` | add | `rp_train/server/s_passengers.lua`: bajar en otra estación |
| `bike_rentals` | add | `rp_bikes/server/s_bikes.lua` |
| `rides_taken`, `rides_driven` | add | `rp_rides/server/s_rides.lua` (`completeRide`, viaje pagado) |
| `wanted_escapes` | add | `rp_wanted/server/s_wanted.lua`: «Perdiste a la policía», sin estar muerto ni abatido |
| `jailed` | add | `rp_wanted/server/s_jail.lua` (`jailPlayer`) |
| `robberies` | add | `rp_robbery/server/s_robbery.lua`: huida con botín |
| `police_arrests`, `police_fines` | add | `rp_police/server/s_actions.lua` (el agente) |
| `fire_foci`, `fire_rescues` | add | `rp_firefighters/server/s_incidents.lua` |
| `gym_muscle`, `gym_stamina` | max | `rp_gym/server/s_stats.lua` y al entrar (`getBodyStats`) |
| `gym_styles` | max | `rp_gym/server/s_trainers.lua`: estilos aprendidos (0-3) |
| `shooting_sessions` | add | `rp_shootingrange/server/s_session.lua`: sesiones de 20 disparos o más |
| `char_level` | max | `rp_levels/server/s_levels.lua` y al entrar |
| `bank_balance` | max | saldo de `characters.bank_money`, leído al entrar y cada minuto (ir y venir del cajero no cuenta) |
| `payday_count` | add | `rp_payday/s_payday.lua` |
| `vehicles_bought`, `property_bought` | add | `rp_dealership`, `rp_properties` (tras cobrar) |
| `clothes_bought` | add | `rp_clothing` (ropa y accesorios) |
| `meals_eaten` | add | `rp_restaurants/server/s_restaurants.lua` |
| `map_explored`, `places_found` | max / add | `rp_map/server/s_map.lua` (`reveal`) y al entrar |
| `missions_done` | add | `rp_missions/server/s_finish.lua` (`persist`, misión superada) |
| `tinder_dates` | add | `rp_phone/server/s_tinder_npcs.lua`: te dan el número para quedar |
| `pool_wins` | add | `rp_pool/server/s_pool.lua`: solo partidas hasta la 8 contra otro personaje |

## Datos

| Tabla | Qué guarda |
|---|---|
| `character_achievement_stats` | valor de cada estadística por personaje |
| `character_achievements` | medalla actual de cada logro (1-4) |
| `character_achievement_milestones` | hitos reclamados; la PK impide cobrar dos veces |

**Guardado**:
- las estadísticas cambiadas se escriben cada minuto, al cerrar sesión, al salir y al parar el recurso;
- una medalla nueva se escribe al momento, con su estadística.

**Reclamo de un hito**:
1. Se valida en memoria: puntos suficientes, hito sin reclamar y que los items quepan.
2. `INSERT IGNORE` del hito.
3. Solo si se inserta la fila, se paga: `bank_money` más `bank_transactions` de tipo `reward`, XP e items.

## Comandos

| Comando | Quién | Qué hace |
|---|---|---|
| `/logros` | jugador | abre el panel |
| `/probarlogro` | jugador | aviso de las 4 medallas solo en tu pantalla (no da nada) |
| `/verlogros <id>` | admin 1 | puntos, medallas e hitos de un jugador |
| `/darlogro <id> <clave> [1-4]` | admin 2 | da una medalla y sube la estadística al umbral |
| `/statlogro <id> <estadística> <valor>` | admin 2 | fija una estadística |
| `/resetlogros <id> confirmar` | admin 2 | borra todo lo de logros del personaje |
