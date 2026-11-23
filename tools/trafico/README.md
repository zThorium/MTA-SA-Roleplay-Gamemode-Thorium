# Herramientas del trafico (rp_citizens)

Cuatro piezas para entender y probar la IA de conduccion sin adivinar. Requieren [Bun](https://bun.sh) (o Node 18+),
sin dependencias. Se ejecutan desde la raiz del repo.

| Pieza | Que hace | Necesita el juego |
|---|---|---|
| `audit.js` | Analiza TODA la red vial: genera la ruta de cada giro como lo hace `rp_citizens`, mide el radio minimo, simula un auto y puntua. Escribe `out/audit.md`, `out/audit.json` y las imagenes de los 12 peores cruces. | No |
| `view.js` | Dibuja UNA maniobra (ruta, trayectoria simulada, red, nodos) en un PNG. | No |
| `/trafico_test` + `compare.js` | Prueba en el juego cada giro de un cruce con la IA real y lo compara con el simulador. | Si |
| `/trafico_tel` + `replay.js` + `collector.js` | Telemetria de fallos en vivo: el cliente los manda al servidor, que los guarda en `telemetry/*.jsonl`; `replay.js` los dibuja. | Si |

## 1. Auditoria offline

```
bun tools/trafico/audit.js            # toda la red (~2 s)
bun tools/trafico/audit.js --top 60 --img 20
bun tools/trafico/audit.js --bbox 2600,-2100,2800,-1800   # solo una zona
bun tools/trafico/audit.js --no-fillet                    # sin el redondeo de esquinas (para medir cuanto aporta)
```

Lee `c_nodes_ls.lua` y aplica los cambios del editor `/nodos` (ultimo `backups/paths_*.txt`). Cada maniobra es una
terna `A -> B -> C` (entra por A a B y sale por C) con contexto de ~40 m antes y ~45 m despues. Puntuacion: radio minimo
< 4 m +100, < 4.5 m +70, < 6 m +20; el simulador se pierde +90, no llega +60, desvio > 3 m +40..80; tramo < 4 m con giro
>= 30 grados +15. Un radio minimo de ~4.5 m es lo que puede girar un auto.

```
bun tools/trafico/view.js 3643 1308 4937      # una maniobra por nodos
bun tools/trafico/view.js --pos 2712 -1936    # la mas cercana a unas coordenadas (las del juego)
bun tools/trafico/view.js A B C --no-fillet   # sin redondeo
```

En las imagenes: amarillo = ruta planeada (los puntos naranjas son de curva), verde oscuro = carriles con su sentido,
la linea gruesa de colores = trayectoria del auto simulado (azul lento, verde medio, rojo rapido), X roja = desvio maximo.

**Limites del simulador**: es un modelo cinematico (bicicleta con limite de volante segun la velocidad y limite de agarre
lateral) con la misma logica de control que el Lua. No tiene la fisica de GTA, ni obstaculos, semaforos ni otros autos.
Sirve para ver geometria imposible y control inestable; la verdad la dan las pruebas en juego (seccion 2) y
`compare.js` mide cuanto se parecen.

> `lib/geometry.js` es un PORT del Lua (`computeTurnPoints`, `planSegment` sin la comprobacion de colision,
> `filletCorners`). Si cambias esas funciones en `c_citizens.lua`, cambia tambien el port.

## 2. Pruebas en juego (`/trafico_test`, admin)

Quedate cerca del cruce (el suelo solo existe cerca de ti; con `/freecam` puede no cargarse).

```
/trafico_test                  giros del cruce mas cercano (hasta 12 maniobras)
/trafico_test radio 80         todos los cruces a menos de 80 m (hasta 24 maniobras)
/trafico_test 3643 1308 4937   una maniobra concreta; opcional 4o argumento = modelo (463 = moto)
/trafico_test stop             termina y devuelve el trafico normal
```

Pone UN auto a la vez, ya en marcha (50 km/h), 40 m antes de cada giro; le fuerza la salida C y lo deja conducir con la IA
real. Resultado por maniobra: OK si llega a C con desvio <= 4 m y sin retroceder; si no, el motivo (`desvio`, `retrocedio`,
`se_perdio`, `tiempo`, `abandonado`...). Se imprime en el chat y se manda a `telemetry/` con la trayectoria.

```
bun tools/trafico/compare.js            # juego vs simulador (coinciden? donde discrepan?)
bun tools/trafico/replay.js --render all
```

## 3. Telemetria de fallos en vivo

- El cliente (con `/trafico_tel`, activo por defecto) detecta cuando un auto se sale de la linea tras una curva o choca con
  algo fijo, y escribe una linea `[rp_citizens][TEL]` en `clientscript.log`. Ademas, si el envio esta activo
  (`/trafico_tel send`), manda el evento (ruta, ultimas ~2 s con posiciones) al servidor.
- `s_telemetry.lua` (solo admins) lo guarda en `resources/[roleplay]/rp_citizens/telemetry/trafico_AAAAMMDD.jsonl`.
- `bun tools/trafico/replay.js` lista los eventos; `--render last|all|N` dibuja el fallo: ruta del auto, su trayectoria real
  (por velocidad) y el punto de desvio.
- `/trafico_tel dump` fuerza el registro del auto de la poblacion mas cercano.

### Colector opcional (consultas con curl mientras juegas)

```
bun tools/trafico/collector.js 22100
# en rp_citizens/meta.xml:  <setting name="collector_url" value="http://127.0.0.1:22100/tel" />   (y reinicia el recurso)
curl http://127.0.0.1:22100/stats     # fallos por motivo y nodos con mas fallos
curl http://127.0.0.1:22100/hot       # ranking de nodos -> bun tools/trafico/view.js --pos X Y
curl http://127.0.0.1:22100/recent?n=5
```

Escucha solo en 127.0.0.1. El servidor de MTA lo alimenta con `fetchRemote`.

## Archivos generados (no se suben al repo)

`tools/trafico/out/` y `resources/[roleplay]/rp_citizens/telemetry/` estan en `.gitignore`.
