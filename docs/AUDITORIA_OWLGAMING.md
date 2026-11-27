# Auditoría comparativa: OwlGaming vs Thorium

Fecha: 2026-11-26. Base de referencia: `C:\Users\Coke\Downloads\MTA-main\MTA-main`
(código liberado de **OwlGaming MTA**, heredero de **Valhalla Gaming / mta.vg**, ~10 años en línea).

> **Licencia**: OwlGaming es **GPL v2**. Copiar su código obliga a publicar Thorium bajo GPL.
> Replicamos **ideas y diseño**, no código. Además su código es antiguo (SQL concatenado,
> consultas síncronas, GUI nativa): no cumple nuestras reglas de arquitectura.

## 1. Cifras

| | OwlGaming | Thorium |
|---|---|---|
| Recursos | ~150 | 66 `rp_*` |
| Comandos | ~1.080 | ~220 |
| Tablas BD | ~110 | ~60 |
| Interfaz | GUI nativa MTA (vieja) | CEF moderno |
| Edad | ~10 años, decenas de devs | proyecto nuevo, 322 commits |

## 2. El componente esencial: por qué OwlGaming duró años

**Los jugadores son el contenido.** OwlGaming casi no tiene contenido "de juego" (misiones, IA,
minijuegos). Lo que tiene son **herramientas para que unos jugadores generen rol para otros**, y
un sistema que obliga a que ese rol tenga consecuencias. Son cuatro piezas que se sostienen entre sí:

### 2.1 Filtro de entrada (calidad del rol)
- Tutorial obligatorio + **cuestionario de rol** (`account/c_tutorial_quiz.lua`: MG, PG, IC/OOC, nombres).
- **Solicitudes revisadas por staff** (`apps/`, tablas `applications`, `applications_questions`):
  el staff aprueba o rechaza antes de jugar. `serial_whitelist`.
- Resultado: la comunidad se autoselecciona. Quien entra quiere rolear, y eso retiene a los demás.

### 2.2 Facciones con poder real (el motor de interacción)
- Policía con **MDC** completo (`mdc_criminals`, `mdc_crimes`, `mdc_apb`, `mdc_impounds`, `mdc_dmv`),
  multas, cárcel (`prison-system`), radares (`speedcams`), K9, controles (`roadblock-system`, `spike-system`).
- Bomberos/médicos (`es-system`: revivir, cargar heridos, recetas, facturas), noticias (`san`),
  gobierno con **elecciones** (`elections`), aeropuerto con controladores (`sfia`), transporte público
  (`sapt-system`), grúa y depósito (`tow-system`, `leo_impound_lot`), seguros (`insurance`).
- Clave: **cada facción legal necesita a las ilegales y viceversa**. El policía tiene trabajo porque
  hay criminales; el criminal necesita que el policía sea un jugador con herramientas, no una IA.

### 2.3 Economía y mundo propiedad de los jugadores, con escasez
- Todo interior es comprable o alquilable (`interiors`), con **negocios** cuyos dueños surten la
  tienda NPC (`shop_products`: stock, precio, reabastecimiento) y escriben su nota (`interior_business`).
- **Escáner de inactividad** (`payday/s_payday.lua`): casas y autos de jugadores inactivos vuelven al
  mercado; alquileres impagos se pierden. Impuestos a vehículos e interiores.
- Ítems en el mundo persistentes (`worlditems`), texturas personalizadas en interiores e ítems
  (`texture-system`, `item-texture`), mapeos de interiores a medida (`map_manager`, tabla `maps`).
- Resultado: siempre hay algo que conseguir, perder o defender. El mapa cambia con los jugadores.

### 2.4 Identidad del personaje y comunicación entre jugadores
- Descripción física (`description`, `/look`, `/editlook`), **idiomas** del personaje (`language-system`),
  **CK** voluntario/administrativo (`selfck-system`): la muerte permanente da peso a las decisiones.
- Teléfono con **llamadas, SMS, guía y teléfonos públicos** (`phone_sms`, `phone_history`, `publicphones`),
  **radios por frecuencia** (`restricted_freqs`), **anuncios** `/ad` y subastas, email e internet in-game
  (`computers-system`).

### 2.5 El soporte que lo mantiene en pie
- Staff con historial (`adminhistory`, `staff_changelogs`), reportes, baneos, logs exhaustivos
  (`logs` → Elasticsearch), anti-cheat, foro integrado (`forums`, `ipb`) y panel web (UCP).
- **Donaciones** (`donators`, GameCoins): +slots, matrícula personalizada, protección contra inactividad,
  sin impuestos... **Ninguna da poder en combate**: pagan comodidad. Eso financió 10 años de servidor.

### En una frase
> OwlGaming no ganó por tener más sistemas, ganó porque **sus sistemas obligan a que los jugadores
> se necesiten entre sí**, filtró a quién entraba y tuvo un staff con herramientas para cuidar la comunidad.

## 3. Diagnóstico de Thorium

Thorium es **mucho mejor en presentación y contenido PvE**: CEF moderno, misiones con voces y
cinemáticas, policía IA, peatones y tráfico IA, minijuegos de trabajos, mapa F11, muebles estilo Sims,
gimnasio, trenes, tinder... Es el tipo de servidor que **impresiona el primer día**.

El riesgo es el contrario al de OwlGaming: **mucho contenido para jugar solo y poca infraestructura
para que los jugadores se necesiten**. Cuando un jugador termina las misiones y sube los trabajos,
lo único que lo retiene son otros jugadores. Ejemplos concretos:

- La policía IA (`rp_wanted`) hace innecesaria a la policía jugadora para el criminal.
- El teléfono tiene redes sociales y tinder pero **no llamadas ni SMS** entre jugadores.
- No hay forma de que un jugador **sea dueño de un negocio** ni de que su casa se libere si se va.
- No hay filtro de entrada ni CK: el rol no tiene consecuencias.

**Regla propuesta para todo lo nuevo**: cada sistema debe tener un jugador al otro lado.
Que la IA sea el **respaldo** cuando no hay jugadores (de noche, servidor vacío) y no el reemplazo.
Ej.: si hay policías jugadores de servicio, la policía IA no persigue; si no hay, sí.

## 4. Comparativa por área

Leyenda: ✅ tenemos (igual o mejor) · 🟡 parcial · ❌ falta

| Área | OwlGaming | Thorium | Estado |
|---|---|---|---|
| Login / personajes | `account` | `rp_login`, `rp_characters` (CEF, cabezas, altura) | ✅ mejor |
| Tutorial + cuestionario de rol | `account/c_tutorial_quiz` | — (solo guía en F1) | ❌ |
| Solicitud con revisión staff / whitelist | `apps`, `serial_whitelist` | — | ❌ |
| Chat RP (`/me`, `/do`, `/b`, gritar, susurrar, PM) | `chat-system` | `rp_chat` | ✅ |
| Idiomas del personaje | `language-system` | — | ❌ |
| Descripción del personaje / vehículo / casa | `description` | — | ❌ |
| CK (muerte permanente) | `selfck-system` | solo definido en F1 | ❌ |
| Inventario y soltar ítems | `item-system`, `item-world` | `rp_inventory` (soltar/recoger, mochilas) | 🟡 falta persistir ítems del suelo y protegerlos |
| Facciones con rangos | `factions` | `rp_factions` (roles con permisos) | ✅ mejor |
| Policía jugadora | `pd-system`, `mdc`, `prison-system` | `rp_police` (MDT, ALPR, multas, menú) | 🟡 falta antecedentes completos, cárcel IC por facción, radares, controles, K9 |
| Médicos jugadores | `es-system` | `rp_injury` + IA en `rp_emergency` | 🟡 falta facción jugadora (ya en PLAN_MVP) |
| Bomberos | `LSFD` | `rp_firefighters` | ✅ mejor |
| Noticias / periodistas | `san` | — | ❌ |
| Gobierno, elecciones, impuestos | `elections`, impuestos en payday | — | ❌ |
| Justicia (juicios, abogados) | vía facciones + MDC | — | ❌ |
| Mecánicos / grúa / depósito | `tow-system`, `leo_impound_lot` | tuning en `rp_vehicles` | 🟡 falta grúa y depósito |
| Seguros | `insurance` | — | ❌ (fase posterior) |
| Transporte público jugador | `sapt-system`, `sfia` | `rp_rides` (Vroom), `rp_train` | 🟡 |
| Teléfono: llamadas, SMS, guía, cabinas | `phone` | `rp_phone` sin llamadas ni SMS | ❌ **crítico** |
| Radios por frecuencia | `item-system` + `restricted_freqs` | — | ❌ |
| Anuncios `/ad` y subastas | `advertisements` | — | ❌ |
| Casas | `interior_system` | `rp_properties`, `rp_furniture` | ✅ mejor |
| Interiores genéricos creados por admin | `interior_system` | — (PLAN_MVP #9) | ❌ |
| **Negocios de jugadores** con stock | `business-system`, `shop_products` | — (PLAN_MVP #10) | ❌ **crítico** |
| Escáner de inactividad (casas/autos vuelven al mercado) | `payday` | — | ❌ **crítico** |
| Impuestos (casas, autos, payday) | `payday` | — (PLAN_MVP #16) | ❌ |
| Licencias | `license-system` | DNI + conducir | 🟡 falta armas, pesca, vuelo |
| Armas como ítems | `weapon`, `weaponcap` | `rp_ammunation` | ✅ |
| Drogas | ítems | `rp_dealers` | 🟡 falta producción por jugadores |
| Combustible | `vehicle_fuel` | `rp_vehicles` (bencina) | ✅ |
| Animaciones | `animation-system` | `rp_anims`, `rp_mocap` | ✅ mejor |
| Reportes | `report` | `rp_help` | ✅ |
| Panel admin | `admin-system` | `rp_adminpanel` (IAM/RBAC, auditoría) | ✅ mejor |
| Logs de economía (dinero, ítems, vehículos) | `logs`, `vehicle_logs`, `interior_logs` | solo `admin_log` | ❌ **crítico** |
| Baneos con historial | `bans`, `adminhistory` | `/ban` en `rp_admin` | 🟡 falta historial por cuenta visible al staff |
| Anti-cheat / anti-spam | `anticheat`, `anti-cmdspam` | validación de servidor | 🟡 |
| Panel web de cuenta (UCP) y foro | `usercontrolpanel`, `forums` | Discord en F1 | 🟡 |
| Donaciones | `donators` | — | ❌ |
| Contenido PvE (misiones, IA, minijuegos) | casi nada | muy amplio | ✅ ventaja nuestra |

## 5. Plan de acción

Ordenado por impacto en retención. Cada fase deja el servidor jugable. Las fases 0 y 1 son
**requisito para abrir al público**.

### Fase 0 — Cimientos para moderar (antes de abrir)
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 0.1 | Logs de economía: dinero, transferencias, ítems dados/soltados, compras, ventas de casas y autos | `rp_logs` (nuevo, export `log(tipo, ...)`) | Sin esto no se investiga un dupeo ni un abuso. OwlGaming lo tenía todo. |
| 0.2 | Historial de sanciones por cuenta (avisos, jail OOC, kicks, bans temporales) visible en `rp_adminpanel` | `rp_admin` + `rp_adminpanel` | El staff necesita contexto para sancionar parejo. |
| 0.3 | Anti-spam de comandos y eventos remotos | `rp_admin` | Protección básica del servidor. |

### Fase 1 — Filtro de entrada y peso del personaje
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 1.1 | Tutorial jugable + **cuestionario de rol** al crear la cuenta (MG, PG, IC/OOC, nombres) | `rp_login` / `rp_help` | Pilar 2.1. Barato y filtra mucho. |
| 1.2 | **Solicitud de cuenta** con 3-5 preguntas abiertas que aprueba el staff (configurable: on/off) | `rp_applications` (nuevo) + pestaña en `rp_adminpanel` | Pilar 2.1. Se puede desactivar al principio para no frenar el crecimiento. |
| 1.3 | **CK** (muerte permanente) solicitado por el jugador o aplicado por staff; personaje queda como cadáver/historial | `rp_characters` | Da consecuencias al rol. |
| 1.4 | Descripción del personaje (`/examinar`) y de vehículos/casas | `rp_characters`, `rp_vehicles`, `rp_properties` | Barato, mucho rol. |

### Fase 2 — Comunicación entre jugadores (crítico)
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 2.1 | **Llamadas y SMS** entre números, guía telefónica, historial; llamar a facciones (911 a policía/médicos jugadores) | `rp_phone` | Sin llamadas no hay rol a distancia: ni negocios, ni bandas, ni citas. |
| 2.2 | **Radio** como ítem con frecuencias; frecuencias reservadas por facción | `rp_radio` o `rp_inventory` | Las facciones coordinan por radio. |
| 2.3 | **Anuncios** (`/ad` con costo y espera) y app de clasificados en el teléfono | `rp_phone` | Mueve la economía entre jugadores. |
| 2.4 | Idiomas del personaje (`/idioma`, chat ininteligible para quien no lo habla) | `rp_chat` | Barato; da identidad a bandas y comunidades. |

### Fase 3 — Economía propiedad de los jugadores (el corazón de la fórmula)
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 3.1 | **Interiores genéricos** creados por admin (entrada/salida, dueño, cerradura, precio) | `rp_interiors` (PLAN_MVP #9) | Base de negocios, sedes de facción y edificios públicos. |
| 3.2 | **Negocios de jugadores**: comprar local, poner NPC vendedor, surtir stock desde mayorista, fijar precios, caja con ganancias | `rp_business` (PLAN_MVP #10), reusa `rp_shops` | Pilar 2.3. Un jugador puede vivir de otros jugadores. |
| 3.3 | **Escáner de inactividad**: casas, negocios y autos de personajes sin conectar en N días vuelven al mercado (con aviso previo) | `rp_payday` | Escasez y movimiento: siempre hay algo que comprar. |
| 3.4 | **Impuestos** a casas, autos y payday que van a los fondos del gobierno | `rp_payday`, `rp_factions` (PLAN_MVP #16) | Retira dinero de la economía y financia facciones de estado. |
| 3.5 | Ítems del suelo persistentes y protegidos (con dueño y caducidad) | `rp_inventory` | Rol de robos, pruebas policiales, alijos. |

### Fase 4 — Facciones de estado completas (el motor de interacción)
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 4.1 | **Policía IA solo como respaldo**: si hay policías jugadores de servicio, la IA no persigue | `rp_wanted` | Que el criminal necesite al policía jugador. |
| 4.2 | Antecedentes en el MDT (delitos, órdenes de búsqueda/APB, vehículos incautados), cárcel IC por facción | `rp_police` | Pilar 2.2. |
| 4.3 | Médicos jugadores (reanimar con `revivePlayer`, facturas, recetas) | `rp_medic` (PLAN_MVP #3) | Ya está en el plan. |
| 4.4 | Grúa y **depósito** de vehículos (policía incauta, dueño paga para retirar) | `rp_vehicles` / `rp_mechanic` | Consecuencia económica de la ley. |
| 4.5 | Gobierno: fondos de impuestos, sueldos de facciones de estado, licencias de armas | `rp_factions` + `rp_driving` | Cierra el circuito de la economía. |
| 4.6 | Noticias (facción con `/noticia`, app en el teléfono) | `rp_news` (nuevo) | Da visibilidad a lo que pasa en el servidor. |

### Fase 5 — Sostener el servidor en el tiempo
| # | Qué | Recurso | Por qué |
|---|---|---|---|
| 5.1 | **Donaciones solo de comodidad**: +slot de personaje, matrícula personalizada, protección de inactividad, número de teléfono personalizado, cosméticos. **Nunca dinero, armas ni ventaja de combate.** | `rp_premium` (nuevo) | Financió 10 años de OwlGaming. Revisar términos de MTA antes. |
| 5.2 | Elecciones a gobierno | `rp_factions` | Rol político a largo plazo. |
| 5.3 | Panel web de cuenta (personajes, propiedades, sanciones) | fuera del juego | Comunidad fuera del juego. |
| 5.4 | Mapeos de interiores a medida pedidos por jugadores | `rp_furniture` ya cubre buena parte | Bajo prioridad: lo tenemos casi. |

### Lo que NO hay que hacer
- No copiar código de OwlGaming (GPL v2, SQL concatenado, consultas síncronas).
- No seguir agregando contenido PvE (misiones, minijuegos) hasta cerrar fases 0-3:
  ya tenemos más que suficiente para el primer día; lo que falta es lo que retiene al día 30.

## 6. Orden recomendado (resumen)

1. `rp_logs` + historial de sanciones (fase 0).
2. Llamadas y SMS en `rp_phone` (2.1).
3. Tutorial + cuestionario + CK + descripción (fase 1).
4. `rp_interiors` → `rp_business` → inactividad → impuestos (fase 3).
5. Policía IA como respaldo + MDT con antecedentes + médicos jugadores + depósito (fase 4).
6. Radio, anuncios, idiomas (resto de fase 2).
7. Donaciones de comodidad y gobierno (fase 5).
