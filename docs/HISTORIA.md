# Historia de Thorium: "Sangre de Grove"

Documento vivo de la narrativa. Aquí se escribe la historia en prosa y se marca **qué tramo corresponde a cada misión**
de `rp_missions` (`resources/[roleplay]/rp_missions/shared/s_missions_data.lua`). Si cambias la historia, cambia primero
este documento y luego los diálogos de la misión (los diálogos con voz tienen reglas: ver "Cómo editar" al final).

**Protagonista (`me`)**: un recién llegado a Grove Street. No habla con voz; sus líneas solo salen como subtítulo.

## Personajes

| Clave | Quién es | Papel en la historia | Voz |
|---|---|---|---|
| `sweet` | Sweet Johnson, líder de Grove | Ancla moral. Exigente, leal, le duele la traición | Clon del doblaje latino |
| `ryder` | Ryder, de la pandilla | Vende las armas a los Ballas por una deuda; luego se redime | Clon del doblaje latino |
| `cesar` | Cesar Vialpando, amigo de la banda | Alivio cómico y ojos de la calle; descubre a Ryder | **Provisional** (biblioteca de Fish) |
| Kendl | Hermana de CJ | No aparece ni habla: es el motor de las dos misiones cómicas | Sin voz |
| Ballas | Banda rival (skins 102-104) | Antagonista constante | Sin voz |

## Mapa de la historia (cadena de desbloqueo)

```
grove_turf → uncle_sam → cesar_cargo → cesar_viagra → humo_grove
          → sombra_ryder → trato_sucio → redencion → pastel_kendl → grove_siempre
```

Cada misión tiene `requires = { "<la anterior>" }`: no se puede jugar hasta completar la previa.

| Acto | Misiones | Tono |
|---|---|---|
| I. Calentar motores | 1, 2, 3 | Acción de barrio; se siembran los secretos |
| II. Risa y sospecha | 4, 5 | Comedia, luego los Ballas aparecen con rifles del ejército |
| III. La traición | 6, 7 | Descubren a Ryder y lo enfrentan |
| IV. Redención | 8, 9 | Ryder repara el daño; calma antes de la tormenta |
| V. Final | 10 | Defensa de Grove con los tres aliados |

---

## Acto I

### Misión 1 · `grove_turf` · "Ojo por ojo" (Sweet) · 6 etapas
**Requiere**: nada (primera misión).
Los Ballas pintaron los muros de Grove. Sweet recluta al protagonista: subir al Greenwood, ir a Jefferson y limpiar la esquina de los Ballas.
Cierra con Sweet agradeciendo: *"Grove Street para siempre"*.
**Conexión**: presenta el conflicto Grove–Ballas y el lema que cierra la historia en la misión 10.

### Misión 2 · `uncle_sam` · "El almacén del Tío Sam" (Ryder) · 5 etapas
**Requiere**: `grove_turf`.
Ryder tiene un soplo: un almacén del puerto lleno de cajas de armas del ejército. Unos cargan el camión, otros cubren a la Guardia Nacional.
Al final Ryder reparte la parte y dice: *"Ni una palabra a Sweet"*.
**Conexión**: las armas robadas son el origen del problema. Que Ryder pida silencio es la primera pista de que oculta algo.

### Misión 3 · `cesar_cargo` · "Cargamento de Cesar" (Cesar) · 5 etapas
**Requiere**: `uncle_sam`.
Cesar necesita piezas de un taller del centro. Abrir el candado de la reja, cargar la furgoneta y escoltarla con emboscadas.
Cesar: *"Con esto ya eres de la familia"*.
**Conexión**: presenta a Cesar, que dos misiones después será quien descubra a Ryder, y establece su confianza con el protagonista.

---

## Acto II

### Misión 4 · `cesar_viagra` · "Una emergencia delicada" (Cesar) · 7 etapas · *misión cómica*
**Requiere**: `cesar_cargo`.
Etapas: (1) cinemática de Cesar · (2) subir a la scooter · (3) ir a la farmacia de Idlewood · (4) echar a los ladrones · (5) buscar "la cajita azul" · (6) volver antes de que llegue Kendl · (7) cinemática de cierre.

**Narrativa**: Cesar, sudando y avergonzado, confiesa con rodeos que *el amigo no se le paró*, y justo hoy llega Kendl. Pide al protagonista
ir de urgencia a la farmacia. Allí hay unos ladrones, y por la radio Cesar entra en pánico en cada paso. Al volver, Cesar se toma la pastilla,
tarda en leer la caja ("si dura más de cuatro horas, llame a un médico") y, ya con Kendl en la puerta, suelta la pista que importa:
*vio la camioneta de Ryder del lado de los morados, y Ryder le dijo que estaba en casa.*
**Conexión**: el chiste recurrente ("nada de pastillas") reaparece en las misiones 6, 9 y 10. La pista sobre Ryder arranca la subtrama de traición.

### Misión 5 · `humo_grove` · "Humo en Grove" (Sweet) · 5 etapas
**Requiere**: `cesar_viagra`.
Etapas: (1) Sweet ve la casa quemada · (2) ir al callejón · (3) tres oleadas de Ballas · (4) examinar el rifle · (5) cinemática de cierre.

**Narrativa**: los Ballas quemaron la casa de la vieja Jackson. Tras el ataque, el protagonista examina un rifle que dejaron: tiene el número de serie
del ejército. Sweet lo reconoce: *salió del almacén del puerto*. Alguien vendió las armas. Sweet manda al protagonista a hablar con Cesar.
**Conexión**: une la misión 2 (el almacén) con la 4 (la pista de Cesar) y envía al jugador a la 6.

---

## Acto III

### Misión 6 · `sombra_ryder` · "La sombra de Ryder" (Cesar) · 8 etapas
**Requiere**: `humo_grove`.
Etapas: (1) Cesar cuenta lo que vio · (2) subir al Blade · (3) ir a Jefferson · (4) vigilar el intercambio (mantener E, con vigías Ballas) ·
(5) cinemática: Ryder repartiendo cajas · (6) los Ballas los descubren · (7) volver a Grove · (8) cinemática con Sweet.

**Narrativa**: Cesar y el protagonista vigilan el motel de Jefferson y ven a Ryder entregando cajas del ejército a los Ballas. Los descubren y huyen.
En Grove, Sweet se resiste a creerlo (*"Ryder y yo crecimos en la misma calle"*), pero los rifles no mienten. Cita para esa noche: otra entrega en el puerto.
**Conexión**: confirma la sospecha y deja a Sweet decidido a confrontarlo (misión 7).

### Misión 7 · `trato_sucio` · "Trato sucio" (Sweet) · 7 etapas
**Requiere**: `sombra_ryder`.
Etapas: (1) plan de Sweet · (2) subir al Greenwood · (3) ir al puerto · (4) emboscar a los Ballas (3 oleadas) · (5) cinemática: confrontación con Ryder · (6) volver · (7) cinemática de cierre.

**Narrativa**: llegan antes que Ryder y emboscan el intercambio. Ryder aparece y confiesa: **debía dinero a los Ballas**, lo tenían agarrado del cuello y
amenazaron a su familia. Sweet le da **una sola oportunidad**. En el cierre, Sweet admite que aún no sabe si perdonarlo o enterrarlo.
**Conexión**: la "oportunidad" de Ryder es el gancho de la misión 8.

---

## Acto IV

### Misión 8 · `redencion` · "Redención" (Ryder) · 7 etapas
**Requiere**: `trato_sucio`.
Etapas: (1) Ryder propone el plan · (2) subir al Sentinel · (3) ir a Jefferson · (4) limpiar la calle (3 oleadas) · (5) colocar tres cargas (mantener E) ·
(6) huir en el coche con emboscadas · (7) cinemática de cierre.

**Narrativa**: Ryder sabe dónde guardan el resto de los rifles. Volar el arsenal deja a los Ballas desarmados. Ryder cubre al protagonista y esta vez cumple.
Al final pide perdón y el protagonista lo invita a la fiesta de Kendl.
**Conexión**: cierra la subtrama de la traición y lleva a todos a la fiesta de la misión 9.

### Misión 9 · `pastel_kendl` · "Pastel para Kendl" (Cesar) · 6 etapas · *misión cómica*
**Requiere**: `redencion`.
Etapas: (1) Cesar explica · (2) subir al Blade · (3) ir a la panadería de Willowfield · (4) cargar el pastel · (5) llevarlo sin dañar el coche, con emboscadas · (6) cinemática de cierre.

**Narrativa**: es el cumpleaños de Kendl y falta el pastel (*"esta vez es de pasteles, no de pastillas"*). Ryder y Sweet llegan a la fiesta y se saludan sin matarse.
En plena fiesta, Sweet llama por teléfono (su línea suena sobre la cinemática): *los Ballas vienen a Grove con todo lo que tienen.*
**Conexión**: la calma antes de la tormenta; el gancho de la misión 10.

---

## Acto V

### Misión 10 · `grove_siempre` · "Grove Street, para siempre" (Sweet) · 4 etapas
**Requiere**: `pastel_kendl`.
Etapas: (1) Sweet reúne a Sweet, Ryder y Cesar · (2) ocupar posiciones · (3) cinco oleadas de Ballas desde norte, oeste y sur · (4) cinemática final.

**Narrativa**: defensa final del barrio. Ryder demuestra que no se esconde; Cesar cuida el flanco derecho. Tras la última oleada, Sweet dice que los Ballas no pisarán
Grove por mucho tiempo. Ryder agradece que no lo hayan matado; Sweet responde que aún puede cambiar de opinión. Cesar ofrece el último trozo de pastel,
el protagonista cierra el chiste (*"Y nada de pastillas"*) y Sweet remata: ***"Grove Street, hermanos. Para siempre."***
**Conexión**: cierra todos los hilos (Ballas, Ryder, el almacén, Kendl) y devuelve el lema de la misión 1.

---

## Posibles continuaciones (ideas, aún no escritas)
- Consecuencias para Ryder frente a su familia y los Ballas que le prestaron el dinero.
- Un nuevo enemigo tras los Ballas (la Guardia Nacional busca las armas robadas en la misión 2).
- Misiones de Big Smoke (necesita registrar su voz primero: su banco no se separa por frecuencia).
- Una misión con Kendl como personaje con voz.

## Cómo editar la historia

- **Dónde está el texto jugable**: `s_missions_data.lua`. Cada misión es un bloque con `key`, `requires` y `stages`. Los diálogos son `cutscene.lines` (cinemática)
  y `radio` (llamadas); los de `me` no llevan voz.
- **No reordenes las líneas de diálogo**: los audios se llaman `<clave>_<etapa><c|r><n>.mp3` (c = cinemática, r = radio, n = número de línea).
  Si añades o quitas líneas hay que regenerar las voces afectadas.
- **Añadir un capítulo**: copia el bloque al final de `MISSION_DEFS`, ponle `requires = { "<misión anterior>" }` y actualiza este documento
  (acto, etapas, conexión). Usa la skill `crear-mision` (estándar de voces, cinemáticas, radio/HUD y estrellas).
- **Voces nuevas**: skill `voces-gta` (`voz.ps1`). Los audios generados no se suben al repo (derechos de Rockstar y del doblaje latino).
- **Coordenadas**: las de las misiones 4 a 10 son aproximadas; se ajustan en juego con `/mmover <contacto>` y `/mskip`.
- **Crédito**: el doblaje latino es de ZainEsc, Magotakon, Huguito y colaboradores.
