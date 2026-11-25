---
name: arreglar-recurso
description: Arreglar un fallo de un recurso rp_* del gamemode Thorium (MTA:SA) con el estándar del proyecto - diagnóstico con evidencia, causa raíz, arreglo mínimo, prueba de regresión, auditoría antes/después y registro. Recibe el nombre del recurso y, opcionalmente, el síntoma. Úsala cuando algo de un recurso no funciona, da errores en consola o /debugscript, se comporta mal en juego, o cuando hay que corregir las fallas bloqueantes de su auditoría.
argument-hint: <rp_recurso> [descripción del fallo]
---

# Arreglar un recurso: `$ARGUMENTS`

Objetivo: dejar el recurso **funcionando y sin regresiones**, con el arreglo más pequeño que
resuelva la **causa raíz**, y dejar constancia verificable de qué se cambió y por qué.

Estándar: [`docs/ESTANDAR_RECURSOS.md`](../../../docs/ESTANDAR_RECURSOS.md). Auditoría:
`scripts/auditar-recurso.sh`. API de la GM: [`crear-recurso/referencia/API.md`](../crear-recurso/referencia/API.md).

## 0 · Entrada

- El primer argumento es el recurso (`rp_x`); el resto, el síntoma. Si falta el nombre, pídelo.
  Comprueba que existe: `ls "resources/[roleplay]/rp_x"`.
- **Sin síntoma**: el encargo es "arreglar las FALLA [B] de la auditoría". Salta a la fase 2 con
  esas fallas como lista de fallos.
- **Con síntoma**: si es ambiguo (no se sabe qué pasa, cuándo ni qué se esperaba), pregunta **una vez**
  lo imprescindible: pasos para reproducirlo, qué se ve y qué se esperaba, errores de consola.
- Si el recurso es `rp_missions` (misiones, cinemáticas, voces), usa también la skill **crear-mision**.
- Si el fallo resulta estar en **otro** recurso, dilo y arréglalo allí (con su propia auditoría).

## 1 · Línea base (antes de tocar nada)

```bash
git status --short && git log --oneline -5 -- "resources/[roleplay]/rp_x"
scripts/auditar-recurso.sh rp_x            # guarda la NOTA y las FALLA: son el "antes"
```

- Si hay cambios sin commit en el recurso, **no los pises**: pregunta si son trabajo en curso.
- Revisa PRs abiertos que toquen el recurso (`gh pr list`): el arreglo puede estar ya en camino.
- Lee `RECURSOS.md` (fila del recurso), su `docs/<SISTEMA>.md` si existe y `docs/auditorias/rp_x.md`
  (los arreglos anteriores dicen qué es frágil).

## 2 · Diagnóstico con evidencia

No cambies código hasta poder **explicar** el fallo. Fuentes, de más a menos directa:

1. **Errores**: `server/logs/server.log` (o `docker/logs/server.log`), consola del servidor y lo que
   Fabián vea en `/debugscript 3`. Busca `ERROR:`/`WARNING:` con el nombre del recurso y sigue
   `archivo:línea`.
2. **Lectura del flujo**: desde la entrada (tecla `bindKey`, comando, evento CEF `rp:x:ui:*`, evento
   remoto, timer) hasta el efecto. Lee los archivos completos implicados, no fragmentos.
3. **Contratos con otros recursos**: firmas reales en `API.md` (o en el código del recurso dueño).
   Fallos típicos de Thorium:
   - export de un recurso que arranca **después** (orden en `mtaserver.conf`, EST-07) o sin `<include>`;
   - `source` en vez de `client` en un evento remoto (SEG-01);
   - estado por jugador que no se limpia y "se queda pegado" tras reconectar o cambiar de personaje (CIC-01/02);
   - reinicio en caliente que no rehidrata (CIC-03);
   - interior/dimensión no comprobados (el punto "funciona" desde otra dimensión);
   - `dbPoll(qh, 0)` sobre una consulta que aún no terminó (falta el callback);
   - choque de tecla E o de dimensión con otro recurso (INT-05/06);
   - cliente que oculta HUD o congela controles y no los devuelve (CIC-05).
4. **Reproducción**: en el servidor, con `restart rp_x` y comandos; si hace falta el cliente, pide a
   Fabián los pasos exactos o añade un `outputDebugString("[rp_x] ...")` temporal **que luego se quita**.

Escribe la hipótesis así antes de arreglar: **"Falla porque X (archivo:línea); se ve como Y; se
arregla cambiando Z."** Si hay varias hipótesis, ordénalas por evidencia y descarta con pruebas.

## 3 · Arreglo mínimo

- Arregla la **causa**, en la capa responsable. No tapes el síntoma (un `if x then return end` que
  esconde un nil sin saber de dónde viene **no** es un arreglo).
- Cambia lo mínimo: nada de refactors, renombres ni "mejoras de paso". Si ves otros problemas,
  apúntalos para el informe (o para `mejorar-recurso`).
- Todo lo que toques cumple el estándar, aunque el resto del archivo no lo haga todavía.
- Si el arreglo necesita BD: skill **migracion-bd** (nunca editar entradas viejas de `schema.lua`).
- Si el arreglo es una excepción legítima a una regla automática, márcala con
  `-- estandar:<etiqueta> <motivo>` (ver el estándar); no la escondas.

## 4 · Prueba de regresión

- **Servidor**: si el fallo tocaba BD, cobros, exports o validación, añade una prueba en
  `resources/[test]/rp_test/server/` que **habría fallado antes** del arreglo (plantilla en
  `crear-recurso/plantillas/s_tests_sistema.lua`). Ejecuta `scripts/test.sh` (Docker) o `start rp_test`
  / `rptest` en la consola del servidor: `FIN OK`.
- **Arranque**: `restart rp_x` sin errores nuevos en consola (y reiniciar con un jugador dentro si el
  fallo era de ciclo de vida).
- **Cliente**: no hay tests. Prepara para Fabián los pasos exactos para comprobarlo en juego, incluido
  el caso que fallaba y uno de error.

## 5 · Auditoría después

```bash
scripts/auditar-recurso.sh rp_x
```

Condición para darlo por terminado:
- la nota **no baja** y no aparece ninguna FALLA nueva respecto a la línea base;
- si el encargo era la auditoría, **0 FALLA [B]**;
- reglas manuales relacionadas con el fallo revisadas (SEG-02, SEG-04, BD-06, CIC-03... las que apliquen).

## 6 · Registro y entrega

1. Entrada nueva **arriba** en `docs/auditorias/rp_x.md` (créalo si no existe; formato en el estándar)
   con tipo `arreglar`, motivo, nota antes → después, cambios con sus IDs de regla, reglas manuales
   revisadas, pendiente y qué probar en juego. Pega dentro de `<details>` la salida de
   `scripts/auditar-recurso.sh rp_x --md`.
2. Si cambiaste comandos, exports, teclas o tablas: `RECURSOS.md` (y `API.md`/`REGISTROS.md` de
   `crear-recurso` si aplica).
3. Commit en español contando qué cambia **en el juego**, citando las reglas:
   `rp_bank: el cajero ya no cobra dos veces al pulsar rápido (SEG-03)`. Rama `fix/rp-x-<tema>` y
   PR a `main`, salvo que Fabián pida otra cosa.
4. Informe final a Fabián, corto: causa (archivo:línea), arreglo, nota antes → después, qué debe
   probar en el cliente y lo que viste y **no** arreglaste.

Si descubres una forma mejor de diagnosticar o arreglar algo en Thorium, actualiza esta skill o el
estándar en el mismo PR.
