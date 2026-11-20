# Robo de tiendas (`rp_robbery`)

Robo de tiendas 24/7 con interior propio. Todo el ajuste numérico está en
`resources/[roleplay]/rp_robbery/shared/s_config.lua` (`ROBBERY`).

## Flujo

| Fase | Qué pasa | Dónde |
|---|---|---|
| Entrar | Pickup "i" en la puerta, **E** entra. Cada tienda vive en la dimensión `21000 + id` con un cajero tras el mostrador y 0-3 clientes al azar. | `s_stores.lua` |
| Amenaza | Apuntar con un arma de fuego (ids 22-38) al cajero o a un cliente inicia el robo. Cajero con las manos arriba, clientes agachados. | `s_robbery.lua`, `c_robbery.lua` |
| Miedo | Barra arriba a la derecha (bajo las estrellas). Baja 3.2/s, o 1.1/s mientras le apuntas al cajero. **H** amenaza (+30, cada 2.5 s), un disparo de advertencia suma 45. | `ROBBERY.FEAR` |
| Miedo en 0 | **Propuesta elegida:** el cajero saca una escopeta de debajo del mostrador y dispara (lo mueve el cliente del ladrón), y un cliente aprovecha para huir por la puerta: es un rehén menos para negociar. No se puede vaciar la caja con el cajero armado vivo. | `clerkFightsBack` |
| Caja | **E** junto a la caja: el personaje vacía la caja (animación de robo) y el cajero entrega el dinero. Cinemática de 4 planos con franjas negras; el botín sube fardo a fardo (8 x $150-420 x multiplicador de la tienda) y cada fardo entra al dinero en mano al momento. | `c_cinematic.lua` |
| Cerco | Al terminar suena la alarma silenciosa: 3 patrullas con sirena y 6 policías apuntando a la puerta, más el negociador. Aparecen las estrellas (3/4/5) con la persecución **retenida**. | `stagePolice` |
| Negociación | Al salir: turnos con el Sgto. Ramírez en CEF (cuadro de diálogo con máquina de escribir, globos de opciones, exclamaciones gigantes, temblor y zoom exagerado en la cámara). | `c_negotiation.lua`, `html/` |
| Huida | Trato cerrado: libre. Al alejarse 60 m (o a los 2 min) empieza la cuenta regresiva; en 0 se suelta la persecución de `rp_wanted`. | `startCountdown` |

Si sales sin vaciar la caja, el cajero llama a la policía: 2 estrellas normales (o las que
correspondan si mataste a alguien). Si te quedas dentro más de 2 minutos con el botín, la
policía deja de negociar y te persigue en cuanto salgas.

## Negociación

Rehenes = NPC vivos que siguen dentro (cajero incluido, salvo si está armado).

| Opción | Efecto |
|---|---|
| Soltar un rehén: +10 s | Ventaja 5 s base, +10 por rehén, máximo 60 |
| Soltar un rehén: sin pinchos ni barricadas | `rp_wanted` no pone pinchos ni controles de carretera |
| Soltar un rehén: no disparar a las llantas | La policía no revienta neumáticos (balas, ráfagas y helicóptero) |
| Farolear | 40%: consigue lo que falte sin soltar a nadie. Si falla: -3 s y -1 de paciencia. A los 3 fallos: **sin trato** (persecución inmediata, sin condiciones) |
| Cerrar el trato | Fin de la negociación |
| Rendirse | Devuelves el botín (lo que tengas en mano), 4 min de cárcel o fianza de $1.500 |

Máximo 6 rondas; después el sargento cierra el trato con lo que haya. El rehén canjeado sale
por la puerta y camina hacia la policía. Disparar a cualquier policía del cerco rompe el trato:
sin condiciones y +1 estrella.

## Estrellas

3 al robar, 4 si murió un rehén, 5 si murió el cajero. Se ponen con
`setWantedLevel(jugador, n, true)`: el `true` ignora el tope por antigüedad del personaje
(4 estrellas los primeros días). Los daños a NPC del robo no cuentan como delitos normales en
`rp_wanted` (`rp:robberyPed`), así que son las únicas estrellas del robo.

## Cambios en `rp_wanted`

- `setWantedLevel(jugador, nivel, force)`.
- `holdPursuit(jugador, bool)`: las estrellas se ven pero no sale ninguna unidad, el tráfico no se
  suma y la búsqueda no baja. `isPursuitHeld`.
- `setPursuitTerms(jugador, sinTrampas, sinLlantas)` y `getPursuitTerms`: se borran solos al quedar
  en 0 estrellas.
- `c_crimes.lua` ignora a los NPC con `rp:robberyPed`.

## Colocar tiendas

1. Párate en la puerta del 24/7 **por fuera, de espaldas a la puerta y mirando a la calle**
   (ahí se alinean las patrullas): `/crearrobo 247f 24/7 Idlewood`. Tipos: `/tiposrobo`.
2. Entra y corrige los puntos parado en el sitio exacto:
   - `/robopunto <id> cajero` detrás del mostrador mirando a los clientes
   - `/robopunto <id> caja` donde el ladrón se para a vaciarla
   - `/robopunto <id> clientes` y luego `/robopunto <id> cliente` en 1-4 pasillos
   - `/robopunto <id> salida` junto a la puerta de dentro
3. `/resetrobo <id>` para probar otra vez sin esperar los 30 minutos.

La tienda inicial (24/7 Idlewood) y las coordenadas de dentro de los seis tipos son una
primera aproximación: **hay que verificarlas en juego**.
