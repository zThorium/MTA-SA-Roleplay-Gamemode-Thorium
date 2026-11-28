---
name: mapeado-3d
description: Crear modelos 3D y mapeados propios para MTA:SA (Thorium) a partir de fotos de referencia - edificios, terminales, monumentos, mobiliario o una manzana que reemplaza parte del mapa original. Blender 4.2 + DragonFF sin ventana, molde del mapa original sacado de gta3.img, texturas nativas del juego reutilizadas (sin repartir material de Rockstar), prelight de día y noche horneado en colores de vértice, colisión, LOD, createBuilding y todas las trampas ya resueltas en juego. Úsala SIEMPRE que haya que modelar algo nuevo en 3D, reemplazar un edificio o zona del mapa, o corregir cómo se ve un modelo propio en el juego (brillos, parpadeos, transparencias, objetos que desaparecen).
---

# Modelos 3D y mapeados a partir de imágenes

Caso completo de referencia: **`rp_turbus`** (Terminal Turbus en Unity Station). Script: `resources/[roleplay]/rp_turbus/tools/build_terminal.py`.
Otros ejemplos: `rp_train/tools/build_metro_pole.py` (objeto suelto con 2DFX), `rp_relojflores/tools/build_flower_clock.py`
(TXD con DXT y mipmaps), `rp_metaldetector/tools/build_detector.py` (objeto de mano).

El objetivo es que el modelo **parezca de Rockstar**: mismas texturas, misma luz, mismo grano, y que el borde con el
mapa original no se note. Todo se genera con un script reproducible: nada de retoques a mano que se pierdan.

## 0. Entorno

- **Blender 4.2**: `C:\Users\fabia\Documents\blender-4.2.23-windows-x64\blender-4.2.23-windows-x64\blender.exe`
  (su Python 3.11 en `4.2\python\bin\python.exe` sirve para leer DFF/TXD/COL con `gtaLib` de DragonFF).
- **DragonFF** (GPL, github.com/Parik27/DragonFF): en el scratchpad, **nunca en el repo**. En el script:
  `sys.path.insert(0, <carpeta que contiene DragonFF/>); import DragonFF; DragonFF.register()` antes de usar `obj.dff`.
- **GTA SA**: `C:\Users\fabia\Documents\Gta San Andreas` (registro de MTA, `GTA:SA Path`).
- Ejecutar sin ventana: `blender.exe --background --factory-startup --python build_x.py -- <dragonff> <recurso> <ref> [--quick]`.
  Los builds largos (horneado) van en segundo plano. **Usa rutas Windows explícitas**: `$(pwd)` en Git Bash da `/c/...` y
  Blender o PowerShell no la encuentran.
- Comprobar `.lua` con la memoria «verificar-sintaxis-lua» (lua5.1.dll con PowerShell de 32 bits).

## 1. Leer el sitio original (molde)

Antes de modelar nada, **mide el lugar real**. Nunca adivines alturas ni huellas.

1. **Qué hay ahí**:
   - IPL de texto: `data/maps/**/*.ipl` (`inst`), filtrando por caja de coordenadas.
   - Objetos en stream (bancas, faroles, árboles, props): están en IPL **binarios** dentro de `models/gta3.img`.
     Se listan con `scripts/leer-ipl-interior.ps1 -Img gta3.img -IdeDir data/maps -MinX .. -MaxZ ..`.
   - Modelo → TXD: los `.ide` (`id, nombre, txd, distancia, flags`).
   - El LOD de un edificio suele estar en la misma posición con prefijo `LOD`/`lod`.
2. **Sacar el molde**:
   - Comando: `powershell -ExecutionPolicy Bypass -File rp_turbus/tools/extraer-img.ps1 -Img gta3.img -Out <scratchpad>/ref -Names a.dff,b.dff,x.txd`.
   - Hay que sacar los DFF del edificio, del suelo y de lo vecino, y sus TXD. Va **solo al scratchpad**: es material de Rockstar.
3. **Analizar el molde** con `plantillas/analizar_molde.py`. Importa los DFF en su posición del mundo y genera:
   - vistas cenitales y en perspectiva con textura;
   - un **mapa de alturas ASCII** a 1 m: suelo, bordillos, setos/jardineras, muros y **huecos**;
   - las estadísticas del prelight vecino (día p90 ≈ 171,155,146 en Los Santos);
   - una hoja de contacto de cada TXD.
4. **Conclusiones que hay que sacar** (en rp_turbus decidieron todo el diseño):
   - **Qué modelo contiene qué.** El suelo (`BTOLAND2_LAS`) traía jardineras y muros que no se pueden quitar sin rehacer el
     suelo, y **tenía huecos** donde iba el edificio. Si quitas el edificio, tu modelo debe tapar esos huecos (losa de piso).
   - **Z exacta**: baldosa 12.58, asfalto 12.39, bordillos. Tu piso va 0–12 cm encima: nunca debajo, que se ve el hueco.
   - **Libres**: puntos de aparición (`rp_characters SPAWN`), escaleras y vías de rp_train, marcadores, cajeros, tiendas.
   - Si el diseño choca con lo que no se puede quitar, **adapta el diseño** al hueco (el hall de 26 m cabe justo entre las
     jardineras) en vez de rehacer la manzana entera: con eso evitas grietas con las calles vecinas.

Pregunta al usuario lo que cambie el plan: qué reemplaza (solo edificio / edificio + explanada / manzana entera), si es
solo mapa o también tiene función, y la marca de los letreros (real o parodia estilo GTA).

## 2. Texturas: nativas primero, propias pocas

**Reutiliza las texturas del juego sin repartirlas.** Las piezas «nat» del DFF solo guardan el NOMBRE de la textura
(`concretenewb256`, `Bow_sub_walltiles`...). En el cliente el modelo apunta al TXD del juego que las contiene:

```lua
local slot = engineGetModelTXDID(4881)          -- un modelo del juego que use ese TXD (aquí railway_las)
engineSetModelTXDID(id, slot)                   -- lanza error si falla: envolver en pcall y avisar en /debugscript
```

- Un modelo tiene **un solo TXD**. Por eso cada pieza se parte por tipo de material:
  - `nat`: texturas del juego;
  - `x`: texturas propias, en `<recurso>.txd`;
  - `glass`: vidrio con alpha;
  - `lod`: su propio TXD.

  Cada tipo es un DFF distinto en la misma posición.
- Elige **un** TXD nativo que tenga casi todo lo que necesitas. `railway_las` traía hormigón, baldosa blanca, estuco
  claro, chapa ondulada oscura, asfalto y pared con zócalo.
- **Mira la hoja de contacto**: los nombres engañan. En `railway_las`, `lasunion994` es **ladrillo rojo** y el estuco claro
  es `lasunion7`; `ws_rooftarmac1` es moteado y queda muy cargado en techos grandes. En el bandejón de Unity el **césped**
  es `hedge2` (TXD `union_las`, del suelo `BTOLAND2_LAS` 4821; 1,4 m por repetición y prelight cálido ~(185, 170, 150)):
  `sjmhoodlawn41`, que suena a césped, es una **losa gris** (rp_relojflores).
- **Qué textura hay en un punto**: carga los DFF cercanos en su posición (IPL de texto y binarios) y lista los triángulos cuyo
  centro cae en la caja del sitio, con su textura, m/UV y prelight, filtrando las caras que miran hacia arriba
  (rp_relojflores lo hizo así; el `analizar_molde.py` da lo mismo en vistas).
- **Pasto o suelo nativo en un modelo aparte**: un modelo tiene un solo TXD, así que la loma con el césped del juego va en su
  propio DFF (`engineSetModelTXDID`) y las piezas propias en otro, en la misma posición. Para hornear y para la vista previa,
  el script lee la textura de `gta3.img`, pero las vistas previas que la muestran **no van al repo**, y en el `.blend` el
  pasto se queda como un color plano.
- **Texel density**: metros por repetición por textura (baldosa 2,4 m; hormigón 3–4 m; asfalto ~8 m), igual que el suelo
  vecino. UV planares en coordenadas del mundo (ver `planar_uv`); los muros con zócalo usan `v = (z - piso) / alto`.
- **Propias**: solo lo que no existe en el juego (verde de marca, vidrio, letreros, pantallas, asientos). Se generan con
  numpy en el script (ruido fbm suave). Usa **potencias de 2, 32–256 px**, y **mipmaps siempre**.
  - Para los letreros, el texto se rasteriza con Workbench a doble resolución y se reduce (`text_image` de rp_turbus).
    La fuente no se distribuye.
  - Para la vegetación, mejor tarjetas renderizadas con Cycles: el ruido estampado no parece flores.
- **TXD**: DragonFF exporta RGBA8888 **sin mipmaps**, lo que pesa y parpadea de lejos. Escribe tu TXD con `make_native`
  (rp_turbus): mipmaps hasta 4 px, `RASTER_888` (D3D 22) si es opaca y `RASTER_8888` con flag alpha solo si tiene alpha.
  Para DXT1/DXT3, ver `rp_relojflores` (`mip_chain`, `dxt_encode`).
- En el `.blend` que va al repo **no deben quedar texturas de Rockstar**: cámbialas por placeholders antes de guardar.

## 3. Geometría

- Modela en **coordenadas del mundo**, con el molde cargado, y al exportar resta `ORIGIN`. El modelo se coloca en ORIGIN
  con giro 0.
- **Subdivide** las caras grandes en celdas de ~2 m (`Piece.quad(..., cell=2.0)`): la luz vive en los vértices, y un plano
  de 4 vértices no puede tener un degradado de sombra.
- **Orientación de caras**: las caras verticales salen de `vquad(pa, pb, z0, z1, normal)`, que ordena los vértices según la
  normal. Las cajas de `box()` ya salen bien.
- **Nada de caras en el mismo plano (z-fighting)**: de lejos la profundidad de GTA no distingue unos pocos cm y dos
  texturas «se mezclan» o parpadean al mover la cámara. Mínimos probados en rp_turbus:
  - pintura y franjas: ≥ 3 cm sobre su piso;
  - sobre el **asfalto original** (que varía ±3 cm): ≥ 7 cm;
  - losa propia sobre el suelo original: ≥ 8 cm;
  - luminarias bajo un cielo raso: 5 cm;
  - paneles sobre un muro: ≥ 5 cm.
  Una franja de color en un borde se hace con **caras separadas** (verde abajo y blanco arriba), nunca con una cara
  encima de otra. Cuidado con las piezas que **topan con una fachada de vidrio**: la cara lateral de la marquesina quedó
  en el plano exacto de la cristalera y salía como una franja verde borrosa sobre el vidrio. Las caras de una caja que
  tocan otra superficie se quitan (`skip=("-x",)` en la marquesina contra el hall, `skip=("top",)` en la viga bajo la
  marquesina, `skip=("bottom",)` en una base apoyada).
- Las texturas que se repiten por panel (vidrio) van **sin dibujo**: un reflejo o degradado se corta en cada repetición.
- Detalle que da vida (rp_turbus): montantes cada 3 m, zócalo, pilares en V, filas de asientos respaldo con respaldo, isla
  central, pantallas colgadas, boleterías con mampara, franjas guía en el piso, marquesina con viga de borde, soleras y
  topes amarillos, números de andén.
- **Props nativos** (palmeras, faroles, bancas `1280`, conos `1238`) con `createObject` desde la config del servidor.
  Las bancas nativas siguen funcionando con `rp_worldobjects`.
- **Interiores recorribles** (rp_pronto): la estructura (piso, muros, cielo raso, mesones) va en tu modelo y los muebles
  son **modelos del juego** (góndolas `CJ_SS_*` 2539-2557, refrigeradores 2012/2443/2452, cajas 2369, cafeteras 2500,
  congelador 2361, canastos 1885) creados en el cliente con `createBuilding`: traen su propia luz de interior y no
  cambian de tono. Su frente mira a **-y local** (rot 180 = mira al norte, 90 = al este). Mide su caja con DragonFF
  y deja la lista en el script, que la escribe en `shared/s_props.lua` y los importa en la vista previa.
- **Un modelo puede traer más de lo que parece**: en las gasolineras (`laepetrol1a`) la tienda, el techo de surtidores
  y los letreros son un solo DFF, mientras que los surtidores (`washgaspump`), los cepillos del lavado
  (`carwashalphas_lae`) y la expendedora son aparte. Lista los materiales por posición antes de decidir qué se quita.

## 4. Prelight: día y noche en colores de vértice

Los modelos de GTA no reciben luz en tiempo real: el volumen va **horneado**.

- **Día**: hornea con Cycles, `bake(type="DIFFUSE", pass_filter={"DIRECT","INDIRECT"}, target="VERTEX_COLORS")`.
  - Usa sol más cielo, con **el suelo original del molde** como oclusor y rebote.
  - Oculta el vidrio y el LOD mientras horneas lo demás.
  - Normaliza con **una sola referencia** (el percentil 96 de la primera pieza) para que todas las piezas queden parejas.
  - Calibra al vecindario: luces ≈ 175–205 en gris cálido y sombras ≈ 70–100. Nunca blanco puro: el motor multiplica el
    color y se quema.
- **Interiores bajo techo**: dales una luz artificial pareja que conserve la oclusión
  (`0.40 + 0.32 × lum_local`).
  La máscara del interior debe **incluir el cielo raso** (`z ≤ CEIL + ε`): si la prueba es `z ≤ CEIL - ε`, el cielo
  raso queda horneado como exterior a la sombra y sale gris oscuro.
- **Noche**:
  - paredes ≈ (40,45,60), es decir `día × (0.21, 0.23, 0.30)`;
  - interior y bajo marquesinas con luz cálida de lámparas;
  - vidrio, luminarias, pantallas y letreros encendidos ≈ (255,240,200), por máscara de material (`GLOW`).
- Escribe con `color_srgb` en los atributos `day`/`night` y marca `obj.dff.day_cols = night_cols = True`.
- **Sin luces 2DFX en estructuras grandes**: la luz nocturna ya va en el prelight. Un 2DFX aislado solo vale para un poste.
- **Vista previa** antes del juego: material de emisión = textura × color de vértice × 1,7, más el suelo original con su
  `Col`/`Col.001`. Renderiza de día y de noche desde la entrada, el interior y en vuelo, y **muéstraselas al usuario**.

## 5. Materiales y exportación (DragonFF)

```python
m.dff.ambient, m.dff.diffuse, m.dff.specular = 1.0, 1.0, 0.0   # DragonFF trae 0.5/0.5/0.5
```

- **specular 0,5** hace que las caras brillen más o menos según el ángulo de la cámara.
- Base Color blanco, con el color en la textura. Metallic 0.
- **Nunca env map** (`export_env_map`): en MTA el material sale blanco.
- Exporta con `bpy.ops.export_dff.scene(filepath, directory, only_selected=True, export_coll=False, export_version="0x36003")`.
  Después borra los nodos de imagen vacíos que crea el exportador (`drop_empty_image_nodes`).

## 6. Colisión y límites

- Usa cajas COL (`col_box`) con la **superficie de SA** (`data/surfinfo.dat`): 4 pavimento, 46 vidrio grande, 56 viga,
  68 plástico, 41 seto, 43 madera. El exportador es `col_exporter.export_col` sobre una colección `CMN` con empties `COL`.
  Las piezas inclinadas se aproximan con una caja vertical en la base.
- **Todo modelo de `engineRequestModel` necesita su propio COL, aunque no tenga colisión.** GTA recorta el dibujo con los
  límites del COL. Si no lo reemplazas, hereda el del modelo base (1 m) y la pieza **desaparece al acercarte**.
- Las piezas sin colisión llevan un **COL de solo límites**: una caja que lo abarca todo y luego, en el COL3, `numBoxes = 0`
  (byte 74) y `flags = 0` (byte 80). Así sirve para edificios sin crear una pared invisible.

## 7. Cargar en MTA (cliente)

Cada pieza:
1. `engineRequestModel("object")`.
2. TXD: nativo (`engineSetModelTXDID`) o propio (`engineLoadTXD` + `engineImportTXD`).
3. **Marcas del modelo ANTES de `engineReplaceModel`**.
4. `engineLoadDFF` + `engineReplaceModel`.
5. `engineLoadCOL` + `engineReplaceCOL`.
6. `engineSetModelLODDistance` (≤ 325, que es el tope con fundido; el LOD usa ×5).

- **Crea las piezas con `createBuilding`, no con `createObject`.** Un objeto recibe luz dinámica (faroles, efectos
  cercanos) y el modelo entero cambia de tono al mover la cámara. Un edificio usa solo su prelight y rinde mejor.
  - `meta.xml` debe pedir `<min_mta_version client="1.6.0-9.22470" />`; si no, da error al usar funciones sobre edificios.
  - Los edificios aparecen en todas las dimensiones.
  - Libera en `onClientResourceStop`: destruye los elementos y llama a `engineFreeModel`, porque no se deshace solo.
- **El vidrio NO va como modelo de GTA.** Se intentó todo y en juego falla según la cámara y el momento:
  - como edificio sale opaco;
  - como objeto con alfa, GTA no garantiza el orden con los edificios: el vidrio tapaba el interior (solo siluetas)
    o el interior lo borraba (parecía que no había vidrio);
  - `draw_last` trae el corte por alpha y las franjas, y `no_zbuffer_write` no se respeta;
  - un shader con `ZWriteEnable = false` tampoco arregla el orden.

  **Solución que funciona**: el script exporta los triángulos del vidrio a `client/c_glass_data.lua` (coordenadas del
  mundo, `write_glass_data()` en rp_turbus) y el cliente los dibuja cada cuadro en `onClientRender` con
  `dxDrawPrimitive3D("trianglelist", "prefx", unpack(verts))`. Va después del mundo y con profundidad.
  - El color es un tinte con alfa, por ejemplo `{70,100,105,95}` de día y `{150,140,110,70}` de noche, interpolado con
    `getTime()` (`c_glass.lua`).
  - Solo se dibuja cerca y en el interior 0.
  - Una sola cara por panel. El vidrio no va en el DFF ni en el TXD.
- **LOD**: una caja simple con su TXD de 16–32 px. Se crea con `createBuilding` y se liga con
  `setLowLODElement(hall, lod)`. Quita también el LOD original (`removeWorldModel` del `LOD...`).

**Servidor**: `removeWorldModel(modelo, radio, x, y, z)` de lo original (edificio, su LOD, detalles con alpha y los
árboles/faroles que estorben). Vuelve con `restoreWorldModel` en `onResourceStop`. Los props nativos se crean ahí.

## 8. Diagnóstico de problemas vistos en juego

| Síntoma | Causa | Arreglo |
|---|---|---|
| La pieza desaparece de cerca o desde dentro | Hereda el COL de 1 m del modelo base | COL propio o de solo límites |
| Brillo que cambia según el ángulo de cámara | specular 0,5 de DragonFF | ambient 1, diffuse 1, specular 0 |
| Todo el modelo cambia de tono al moverte | Es objeto y recibe luz dinámica | `createBuilding` |
| **Toda la escena** (también el mapa original) sube y baja de brillo | Algo con efecto 2DFX pegado al jugador o cerca: el accesorio «Puro» usaba 1485 `CJ_CIGGY` (trae `cigarette_smoke`; 3044 también) | Revisa accesorios y props antes de culpar al modelo. Si el mapa original también cambia, **no es tu modelo** |
| Vidrio opaco, sin interior visible, o que desaparece al rato | El vidrio es un modelo y GTA no garantiza el orden de dibujo con los edificios | Vidrio como primitivas 3D (`dxDrawPrimitive3D`, sección 7) |
| El vidrio (u otra pieza que va como objeto) parpadea o brilla con los focos de los autos | Los objetos reciben luz dinámica de los vehículos (el auto averiado de `rp_citizens` prende y apaga los focos cada segundo) | Flags `ignore_lighting` y `dont_receive_shadows` en esa pieza |
| Dos texturas que «se mezclan» o parpadean en una zona, sobre todo de lejos | z-fighting: caras superpuestas o a pocos cm | Separar según los mínimos de la sección 3, o quitar la cara oculta |
| Vidrio con bloques o degradados diagonales | Textura con reflejo que se corta en cada panel | Tinte parejo sin dibujo |
| Vidrio con franjas o invisible (si aún fuera modelo) | Corte por alpha de GTA con `draw_last` | Pasarlo a primitivas 3D |
| Muro o techo blanco y manchas (z-fighting) de cerca, solo desde cierto ángulo | El LOD aparece sobre el modelo: GTA dibuja el LOD de una pieza cuando **esa pieza** queda fuera de cuadro, y un LOD único colgado de otra pieza cubría también esta | **Un LOD por pieza con colisión** (`setLowLODElement` a su pieza) y cajas del LOD unos cm hacia dentro de las caras reales (rp_pronto) |
| Interior que brilla de noche | Prelight nocturno del interior ≈ día y vidrio con tinte claro que lo «lava» | Noche del interior ≈ día × (0,62, 0,57, 0,48) y tinte del vidrio oscuro de noche (rp_pronto) |
| Errores «min_mta_version … target is building» | meta.xml antiguo | `client="1.6.0-9.22470"` |
| Texturas nativas blancas | `engineSetModelTXDID` falló | Revisa el aviso en `/debugscript 3` y el modelo fuente del TXD |
| Ladrillo o color inesperado | El nombre de la textura nativa engaña | Mira la hoja de contacto del TXD |

Para buscar 2DFX en un DFF: el bloque `0x0253F2F8` (bytes `f8 f2 53 02`), con entradas `pos(12) tipo(4) tamaño(4)`
(0 = luz, 1 = partícula con su nombre).

## 9. Recurso y entrega

- Estructura como `rp_turbus`:
  - `shared/s_config.lua`: ORIGIN, PARTS, LOD, REMOVE, PROPS y la caja del edificio;
  - `server/s_*.lua`: quitar y restaurar el original, props y un export de info;
  - `client/c_*.lua`: carga de modelos;
  - `models/`;
  - `tools/`: `build_*.py`, `extraer-img.ps1` y `.blend`;
  - `CREDITOS.md`.
- Regístralo en `mtaserver.conf` después de sus dependencias. Documenta en `RECURSOS.md` y `CLAUDE.md`, y actualiza
  `rp_map` si cambia un lugar. Añade una prueba de humo en `rp_test`: que corre, que quita lo original y que el punto de
  aparición queda fuera del edificio.
- Logros: `INT-09: N/A, decorado` (salvo que el lugar tenga actividad propia).
- **Entrega**:
  1. renders de día y de noche, y vista cenital;
  2. los `.lua` compilados;
  3. pide a Fabián la **prueba en juego**: acercarse y entrar, mirar en todas direcciones, de día y de noche, conducir por
     encima, comprobar que no queda rastro del original (de cerca ni con el LOD), que no hay grietas con la acera, el
     vidrio desde todos los ángulos y `/debugscript 3` limpio.
- Si descubres una trampa nueva, **añádela a esta skill** en el mismo PR.
