# Búsqueda policial (rp_wanted)

Sistema de estrellas de búsqueda que replica la mecánica de GTA San Andreas. Los números salen del código reconstruido del juego (`CWanted` y `CEventDamage` del proyecto gta-reversed), no de memoria.

## 1. Cómo funciona en GTA SA

### Puntos de caos
GTA no cuenta estrellas directamente: cada delito suma **puntos de caos** y las estrellas dependen del total.

| Estrellas | Caos mínimo | Patrullas a la vez | Policías en persecución | Helicópteros | Control de carretera |
|---|---|---|---|---|---|
| 1 | 50 | 1 | 1 | 0 | 0 % |
| 2 | 180 | 2 | 3 | 0 | 0 % |
| 3 | 550 | 2 | 4 | 1 | 12 % |
| 4 | 1200 | 2 (SWAT) | 6 | 2 | 18 % |
| 5 | 2400 | 3 (FBI) | 8 | 2 | 24 % |
| 6 | 4600 | 3 (ejército) | 10 | 2 | 30 % |

El caos tiene un tope de 9200.

### Delitos y sus puntos
| Delito | Puntos |
|---|---|
| Golpear a un peatón | 5 |
| Golpear a un policía | 45 |
| Apuñalar a un peatón / policía | 35 / 100 |
| Disparar (o explosivo) a un peatón / policía | 30 / 80 |
| Atropellar o embestir a un peatón / policía | 18 / 80 |
| Embestir o dañar una patrulla | 80 |
| Robar un auto ocupado | 15 |
| Destruir un vehículo | 70 |
| Derribar un helicóptero | 400 |
| Explosión | 25 |
| Exceso de velocidad (con la policía cerca) | 5 |
| Chocar un auto | 2 |
| Apuntar con un arma | 2 |
| Disparar al aire | 0 |

Reglas de la cola de delitos:
- El mismo delito contra la **misma víctima** solo cuenta una vez cada **10 s**. Golpear diez veces al mismo peatón vale 5; golpear a diez peatones distintos vale 50.
- El delito se aplica medio segundo después de cometerlo.
- Si a la policía "no le importa" la víctima (pandilleros), el delito vale un **tercio**.

Ejemplos: atropellar 3 peatones da 1 estrella (54). Golpear a un policía y a un peatón da 1 estrella (50). Embestir 3 patrullas durante una persecución sube a 2 estrellas (240+).

### Cómo sube con el tiempo
No sube solo por el tiempo: sube porque en una persecución sigues cometiendo delitos (chocas patrullas, atropellas policías que se bajan, disparas). Cada patrulla embestida vale 80, así que una persecución agresiva escala rápido.

### Cómo se pierde
- **Decaimiento**: cada segundo **sin ningún policía (a pie o en vehículo) a menos de 18 m**, el caos baja 1 punto (2 si estás fuera de la ciudad o en un interior). Con policías encima no baja nunca. Ejemplo: con 2 estrellas (200) hay que esconderse unos 20 s para volver a 1 estrella y unos 2 minutos más para limpiarla.
- **Pay 'n' Spray**: pintura y reparación por $100; borra la búsqueda si la policía no te ve entrar.
- **Wasted** (morir) o **Busted** (arresto): se borra todo.
- **Libertad condicional**: si cometes otro delito en los 20 s siguientes a un arresto, vuelves al nivel que tenías.
- A partir de 2 estrellas, en zonas apartadas y dentro de un vehículo policial, el caos no baja.

### Comportamiento de la policía
- **1 estrella**: una patrulla con un policía. No dispara: intenta arrestarte (porra).
- **2 estrellas**: dos patrullas con dos agentes; disparan cuando te ven.
- **3 estrellas**: helicóptero y controles de carretera; las patrullas te embisten.
- **4 estrellas**: SWAT (Enforcer, MP5) y dos helicópteros.
- **5 estrellas**: FBI (FBI Rancher, MP5).
- **6 estrellas**: ejército (Rhino y Barracks, M4).
- Patrulla según la ciudad: Los Santos, San Fierro, Las Venturas o Ranger en el campo.
- **Busted**: un policía te alcanza a pie, o te detienes en un vehículo con un policía al lado.

## 2. Plan de implementación en el gamemode

| Pieza | Dónde | Qué hace |
|---|---|---|
| Caos y estrellas | `rp_wanted/server/s_wanted.lua` | Tabla de puntos, cola de 10 s por víctima, decaimiento cada segundo, libertad condicional, Busted (multa de $250 por estrella en efectivo, quita armas, te deja en la puerta de la comisaría de Pershing Square), Wasted, Pay 'n' Spray. Se conserva 30 min al reconectar o cambiar de personaje (en memoria, sin tocar la base de datos). |
| Detección de delitos | `rp_wanted/client/c_crimes.lua` | Los peatones y el tráfico de `rp_citizens` existen solo en el cliente, así que los delitos contra ellos y contra la policía IA se avisan desde ahí (con límite de avisos en el servidor). Los delitos contra otros jugadores los detecta el servidor con `onPlayerDamage`. |
| Policía IA | `rp_wanted/server/s_units.lua` + `client/c_police.lua` | El servidor crea patrulla, agentes y helicóptero (todos los ven) y hace syncer al buscado, como el auto IA de `rp_rides`. El cliente elige dónde aparecen (en la calle, fuera de la vista, con la red vial de `rp_citizens`) y conduce: A* por la red hasta el jugador, persecución directa cuando lo ve, embestidas desde 3 estrellas, bajarse cuando vas a pie, disparar desde 2 estrellas, volver a la patrulla si te escapas en auto, irse con la sirena apagada al terminar. |
| Tráfico | `rp_citizens/c_citizens.lua` | 15 % del tráfico va en moto. 8 % son patrullas (Police LS/SF/LV o Ranger, y un tercio motos HPV1000) con su agente; cuentan como policía para los delitos y el exceso de velocidad, y prenden la sirena si estás buscado. |
| HUD | `rp_hud/c_wanted.lua` | 6 estrellas al estilo de GTA SA (doradas con borde negro, las que faltan oscuras), dibujadas con primitivas (arte propio) debajo de la hora y el dinero. Parpadean al cambiar el nivel y laten mientras ningún policía está cerca. Respetan `/hud`. |
| Policía jugadora | `s_wanted.lua` | Los miembros de la facción 1 de servicio (con uniforme, skins 280-288, o en un vehículo policial) no acumulan búsqueda; de civil sí, reciben el aviso de la central en el chat y ven un punto rojo sobre los buscados en el mapa. Sus patrullas y su presencia cuentan para frenar el decaimiento. |

Decisiones:
- **Sin cambios en `schema.lua`**. En `rp_hud` solo se agrega `c_wanted.lua` y una línea en su `meta.xml` (el PR #6 también toca ese `meta.xml`: conflicto de una línea, fácil de resolver).
- **Sin CEF**: el HUD usa dx, así no se crean navegadores.
- Pay 'n' Spray solo repara (no repinta) para no desincronizar el color de los vehículos con dueño guardados en la base de datos.
- Configuración en `rp_wanted/shared/s_config.lua`: puntos, umbrales, unidades por nivel, multa, ubicación de liberación y de los Pay 'n' Spray.

## 3. Comandos
- `/delitosdebug`: muestra en el chat cada delito que detecta tu cliente (para probar).
- `/busquedainfo`: tus estrellas, puntos de caos y si cuentas como policía de servicio.
- `/busqueda <jugador>` (admin): muestra estrellas y caos.
- `/busqueda <jugador> <0-6>` (admin): fija el nivel (con los valores de caos de GTA: 70, 200, 570, 1220, 2420, 4620).

## 4. Pendiente / ideas
- Saltarse un semáforo en rojo (10 puntos en GTA) y prender fuego (20/80) aún no se detectan.
- Sobornos de policía (estrella que resta un nivel) y que los policías disparen desde la patrulla.
- La facción policial podría tener un `/arrestar` propio que use `bustPlayer`.
