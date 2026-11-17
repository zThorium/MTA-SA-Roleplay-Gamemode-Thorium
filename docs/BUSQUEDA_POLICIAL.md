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

### Comportamiento de la policía (CTaskComplexCopInCar, CTaskComplexPolicePursuit, CTaskComplexArrestPed)
- Si vas en un vehículo y te detienes cerca, el policía abre tu puerta y te saca (de una moto te tira). Eso es el arresto.
- A pie, a 1 estrella el policía usa la porra para tirarte al suelo; desde 2 estrellas usa pistola. Te arresta cuando estás en el suelo a menos de 3 m.
- Si vuelves a escapar en un vehículo, el policía que está a menos de 4 m de su patrulla se sube y sigue la persecución en auto; los demás siguen a pie.
- Si el policía que conduce muere, la patrulla queda abandonada.
- Las patrullas que ya circulan por la ciudad también se suman a la persecución, y al estar buscado aparecen muchas más.

- **1 estrella**: una patrulla con un policía. No dispara: intenta arrestarte (porra).
- **2 estrellas**: dos patrullas con dos agentes; disparan cuando te ven.
- **3 estrellas**: helicóptero y controles de carretera; las patrullas te embisten.
- **4 estrellas**: SWAT (Enforcer, MP5) y dos helicópteros.
- **5 estrellas**: FBI (FBI Rancher, MP5).
- **6 estrellas**: ejército (Rhino y Barracks, M4).
- Patrulla según la ciudad: Los Santos, San Fierro, Las Venturas o Ranger en el campo.
- **Busted**: te sacan del vehículo o te reducen en el suelo.

## 2. Plan de implementación en el gamemode

| Pieza | Dónde | Qué hace |
|---|---|---|
| Caos y estrellas | `rp_wanted/server/s_wanted.lua` | Tabla de puntos, cola de 10 s por víctima, decaimiento cada segundo, libertad condicional, Busted: te quitan las armas y vas a la cárcel, Wasted, Pay 'n' Spray. Se conserva 30 min al reconectar o cambiar de personaje (en memoria, sin tocar la base de datos). |
| Detección de delitos | `rp_wanted/client/c_crimes.lua` | Los peatones y el tráfico de `rp_citizens` existen solo en el cliente, así que los delitos contra ellos y contra la policía IA se avisan desde ahí (con límite de avisos en el servidor). Los delitos contra otros jugadores los detecta el servidor con `onPlayerDamage`. |
| Policía IA | `rp_wanted/server/s_units.lua` + `client/c_police.lua` | El servidor crea patrulla, agentes y helicóptero (todos los ven) y hace syncer al buscado, como el auto IA de `rp_rides`. El cliente elige dónde aparecen (en la calle, fuera de la vista, con la red vial de `rp_citizens`) y conduce: A* por la red hasta el jugador, persecución directa cuando lo ve, embestidas desde 3 estrellas, bajarse cuando vas a pie, disparar desde 2 estrellas, volver a la patrulla si te escapas en auto, irse con la sirena apagada al terminar. |
| Tráfico | `rp_citizens/c_citizens.lua` | 15 % del tráfico va en moto. 8 % son patrullas (Police LS/SF/LV o Ranger, y un tercio motos HPV1000) con su agente; cuentan como policía para los delitos y el exceso de velocidad, y prenden la sirena si estás buscado. |
| Cárcel | `rp_wanted/server/s_jail.lua` + `client/c_jail.lua` | Tras el arresto vas a una celda de la comisaría de LS con un timer en pantalla: 90 s por estrella, o la fianza de $750 por estrella con `/fianza` (en efectivo). Al salir quedas en la puerta de la comisaría de Pershing Square. El tiempo se conserva al reconectar. Admin: `/liberar`, `/encarcelar`. |
| Despacho agresivo | `client/c_police.lua` | Las patrullas aparecen a 55-110 m, por delante si vas en vehículo. Si una queda a más de 130 m y no se ve, avanza por su ruta hasta quedar a 80 m (en GTA las patrullas se generan cerca del jugador). Las patrullas del tráfico (`rp_citizens`) se suman a la persecución: hasta 3 a la vez, y con estrellas el 40 % del tráfico es policía. |
| HUD | `rp_hud/c_wanted.lua` | 6 estrellas al estilo de GTA SA (doradas con borde negro, las que faltan oscuras), dibujadas con primitivas (arte propio) debajo de la hora y el dinero. Parpadean al cambiar el nivel y laten mientras ningún policía está cerca. Respetan `/hud`. |
| Policía jugadora | `s_wanted.lua` | Los miembros de la facción 1 de servicio (con uniforme, skins 280-288, o en un vehículo policial) no acumulan búsqueda; de civil sí, reciben el aviso de la central en el chat y ven un punto rojo sobre los buscados en el mapa. Sus patrullas y su presencia cuentan para frenar el decaimiento. |

Ajustes sobre GTA (más fácil, pedido del servidor):
- Todos los puntos valen el **doble** (`CRIME_SCALE = 2`): dos atropellos ya son 1 estrella.
- **Testigo policial**: si un policía (unidad IA, patrulla del tráfico o policía jugador) está a menos de 45 m y te ve, el delito vale el doble otra vez y te da **1 estrella al momento**.
- **Estrella inmediata** sin testigos para delitos graves: disparar o apuñalar a un civil, cualquier agresión a un policía, embestir una patrulla y destruir un vehículo o helicóptero.
- Al subir de nivel el caos queda con margen sobre el umbral (70, 200, 570…) y hay **30 s sin decaimiento** después de cada delito, así no aparece "Perdiste a la policía" apenas ganas la estrella.
- Arresto en un vehículo: el policía llega a la puerta del conductor, la abre (`CAR_open_LHS`), te saca (`CAR_pullout_LHS`) y te deja en el suelo; recién ahí es Busted. Si el auto es del tráfico (solo existe en tu cliente) te saca tu propio cliente.

Persecución más difícil (segunda ronda):
- **Ruta probable**: cada medio segundo se calcula por dónde vas a pasar (en cada cruce, el camino más alineado con tu rumbo, hasta 400 m).
- **Roles**: la patrulla más cercana te persigue; las demás **interceptan**: van por A* a un punto de tu ruta al que llegan antes que tú y se cruzan en la calle.
- **Embestidas desde 2 estrellas** con maniobra PIT (apuntan a la esquina trasera de tu auto) y esquivan el tráfico.
- Las patrullas aparecen **de frente** en tu ruta y tienen mejor motor, agarre y frenos (`WANTED_POLICE_HANDLING`); mientras van detrás aceleran más (rubber band como en GTA).
- **Disparos desde la ventanilla**: el acompañante usa MP5 desde 2 estrellas y apunta a los neumáticos. Cada bala de la policía que pega en tu vehículo puede reventar un neumático.
- **Pinchos** (modelo 2899) en tu ruta, a 90-170 m, con una patrulla al costado: si los pisas revientan los 4 neumáticos.
- Controles de carretera desde 2 estrellas y más patrullas por nivel (2, 3, 4, 4, 5, 5).
- **Tráfico**: 16 autos de día y 9 de noche (antes 7 y 4), 6 más durante una persecución. Yendo rápido, el 70 % aparece por delante.
- **Lag**: si una patrulla no encontraba ruta, repetía el A* cada 50 ms. Ahora hay como mucho una búsqueda por tick y un fallo espera 1,2 s.

Tercera ronda (comparado con el análisis de la wiki):
- **Temporizador de evasión**: la búsqueda solo baja después de 10 s sin que ningún policía te vea (unidad, patrulla del tráfico, helicóptero hasta 140 m o policía jugador). Lo mide tu cliente con línea de visión y cualquier avistamiento lo reinicia.
- **Salir de la ciudad al campo** con 2 o más estrellas quita una (como mucho una vez por minuto).
- **Disparar, apuñalar o atropellar a un policía** deja 2 estrellas al instante; golpearlo, 1.
- **Perseguidores**: 1 a 1 estrella, 2 de 2 a 4 y 3 en 5-6; el resto intercepta.

Cuarta ronda:
- **Testigos obligatorios**: un delito solo cuenta si alguien lo ve. Si es la policía (o el delito es contra un policía) se aplica al momento, vale el doble y da estrella. Si es un civil (peatón o jugador a menos de 30 m con línea de visión, o la víctima cuando le apuntas, le robas el auto o lo chocas), llama a la policía y el delito se aplica a los 3 s. Sin testigos no pasa nada.
- **Tope de estrellas por antigüedad del personaje** (como el progreso de la historia): 4 al crearlo, 5 desde los 3 días y 6 desde los 10. Se lee de `characters.created_at`; `/busquedainfo` lo muestra.
- **Helicóptero desde 4 estrellas**: lleva un tirador SWAT con M4. Las ráfagas (1,6 s cada 4 s) se simulan en el cliente con fogonazo, trazadoras e impactos; la puntería baja si vas rápido o lejos. Si vas a pie o despacio, baja a 14 m y suelta 3 SWAT con M4 a rapel (con cuerda y animación `ABSEIL`), como mucho un equipo cada 45 s.
- **Calibre según estrellas**: la policía común lleva escopeta a 3 estrellas y MP5 a 4; desde 5 estrellas todos llevan M4.

Decisiones:
- **Sin cambios en `schema.lua`**. En `rp_hud` solo se agrega `c_wanted.lua` y una línea en su `meta.xml` (el PR #6 también toca ese `meta.xml`: conflicto de una línea, fácil de resolver).
- **Sin CEF**: el HUD usa dx, así no se crean navegadores.
- Pay 'n' Spray solo repara (no repinta) para no desincronizar el color de los vehículos con dueño guardados en la base de datos.
- Configuración en `rp_wanted/shared/s_config.lua`: puntos, umbrales, unidades por nivel, multa, ubicación de liberación y de los Pay 'n' Spray.

## 3. Comandos
- `/delitosdebug`: muestra en el chat cada delito que detecta tu cliente (para probar).
- `/fianza`: paga la fianza y sales de la cárcel.
- `/busquedainfo`: tus estrellas, puntos de caos y si cuentas como policía de servicio.
- `/busqueda <jugador>` (admin): muestra estrellas y caos.
- `/busqueda <jugador> <0-6>` (admin): fija el nivel (con los valores de caos de GTA: 70, 200, 570, 1220, 2420, 4620).

## 4. Pendiente / ideas
- Saltarse un semáforo en rojo (10 puntos en GTA) y prender fuego (20/80) aún no se detectan.
- Sobornos de policía (estrella que resta un nivel) y que los policías disparen desde la patrulla.
- La facción policial podría tener un `/arrestar` propio que use `bustPlayer`.
