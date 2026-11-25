---
name: mejorar-recurso
description: Mejorar un recurso rp_* existente del gamemode Thorium (MTA:SA) hasta el estándar del proyecto - auditoría, plan priorizado (estándar, seguridad, integración con la GM, robustez, rendimiento, experiencia de juego), ejecución por fases verificables y registro antes/después. Recibe el nombre del recurso y, opcionalmente, el foco de la mejora. Úsala para modernizar, endurecer, ampliar o pulir un sistema que ya existe.
argument-hint: <rp_recurso> [foco: seguridad | integracion | rendimiento | ux | "añadir X"...]
---

# Mejorar un recurso: `$ARGUMENTS`

Objetivo: llevar el recurso al estándar de Thorium y hacerlo mejor para el jugador, **sin romper lo
que funciona**, con cada cambio medible (auditoría antes/después) y trazable (registro y commits
que citan reglas).

Estándar: [`docs/ESTANDAR_RECURSOS.md`](../../../docs/ESTANDAR_RECURSOS.md) · auditoría:
`scripts/auditar-recurso.sh` · API y registros de la GM: [`crear-recurso/referencia/`](../crear-recurso/referencia/).
Si en el camino aparece un fallo, se arregla con el método de **arreglar-recurso** (causa raíz + prueba).

## 0 · Entrada

- Primer argumento: el recurso (`rp_x`); el resto, el **foco** (opcional). Si falta el nombre, pídelo.
- Sin foco: mejora general (estándar + robustez + integración), sin funcionalidad nueva.
- Con foco de funcionalidad nueva ("añadir X"): diséñala con la fase 1 de **crear-recurso** y trátala
  como una fase más del plan.
- `rp_missions` → también la skill **crear-mision**. Interfaces → **interfaz-cef**. Comandos →
  **comando-admin**. Tablas → **migracion-bd**.

## 1 · Conocer el recurso (línea base)

```bash
git status --short && git log --oneline -10 -- "resources/[roleplay]/rp_x"
scripts/auditar-recurso.sh rp_x            # NOTA y FALLA de partida
```

- Lee **todo** el recurso (meta.xml, config, servidor, cliente, html), su fila de `RECURSOS.md`,
  `docs/<SISTEMA>.md` y `docs/auditorias/rp_x.md` si existen. No propongas cambios sobre código que no leíste.
- Mira quién depende de él: `grep -rn "exports.rp_x" resources/` y quién escucha sus eventos.
  Sus exports y eventos son un **contrato**: no cambies firmas sin actualizar a todos los que llaman.
- Revisa PRs abiertos que lo toquen (`gh pr list`).
- Revisa a mano las reglas **manuales** del estándar (SEG-02, SEG-04, BD-06, CIC-03, CIC-06,
  INT-07...): es donde suelen estar los problemas que el script no ve.

## 2 · Plan priorizado

Presenta a Fabián un plan corto, en este orden de prioridad, con cada punto ligado a una regla o a
un beneficio concreto en el juego:

| Prioridad | Qué | Ejemplos |
|---|---|---|
| P0 · Bloqueante | FALLA [B] de la auditoría y reglas B manuales rotas | `source` en evento remoto, cobro no atómico, SQL concatenado, sin validación de distancia |
| P1 · Robustez | Ciclo de vida y estado | limpieza al salir/cambiar de personaje, rehidratar al reiniciar, abatido/esposado/en misión |
| P2 · Integración | Usar la GM en vez de duplicarla | `rp_notify` en vez de chat, `rp_inventory`, `rp_levels`, `rp_wanted`, HUD/radio con supresión, dimensiones y teclas sin choques |
| P3 · Calidad | FALLA [I], AVISOS, config centralizada, documentación, pruebas en `rp_test` | |
| P4 · Experiencia | Lo que nota el jugador | feedback claro, textos de rol, menos pasos, rendimiento (onClientRender, timers) |
| P5 · Funcionalidad | Solo si el foco lo pide | |

Para cada punto: **qué** se cambia, **por qué** (regla o beneficio), **riesgo** (qué podría romper)
y **cómo se verifica**. Si el plan es grande, pregunta con qué fases seguir; si es pequeño y el
encargo era claro, sigue sin preguntar.

## 3 · Ejecutar por fases

Cada fase es un bloque coherente que deja el recurso funcionando:

1. Cambia solo lo de esa fase.
2. `restart rp_x` sin errores (si hay servidor disponible) y `scripts/auditar-recurso.sh rp_x`:
   la nota **no baja** y no aparecen FALLA nuevas.
3. Si tocaste BD, cobros o exports: prueba en `rp_test` (`scripts/test.sh` → `FIN OK`).
4. Un commit por fase, en español, contando qué cambia en el juego y citando reglas:
   `rp_shops: las compras validan distancia e interior en el servidor (SEG-02)`.

Reglas de oro:
- **Compatibilidad**: no renombres eventos, exports, comandos, tablas ni columnas sin migrar a sus
  usuarios en el mismo cambio. Columnas nuevas con `ADD COLUMN IF NOT EXISTS` y valor por defecto.
- **Datos de jugadores**: nunca un cambio que pierda dinero, items o progreso existentes.
- Excepciones legítimas a reglas automáticas: `-- estandar:<etiqueta> <motivo>`, nunca silenciadas.
- Nada de reescribir "porque sí": si funciona y cumple el estándar, se deja.

## 4 · Verificación final

```bash
scripts/auditar-recurso.sh rp_x
```

- Nota final ≥ nota inicial; **0 FALLA [B]** salvo que Fabián acepte dejar alguna (queda en "Pendiente").
- Reglas manuales revisadas y anotadas.
- Lista concreta de qué probar en el cliente (Claude no puede): flujo principal, errores
  (sin dinero, lejos, sin permiso), abatido a mitad, salir a mitad, `restart` con gente dentro.

## 5 · Registro y entrega

1. Entrada **arriba** en `docs/auditorias/rp_x.md` (formato en el estándar) con tipo `mejorar`,
   foco, nota antes → después, cambios por fase con IDs de regla, reglas manuales revisadas,
   pendiente y qué probar en juego, más el informe `--md` dentro de `<details>`.
2. `RECURSOS.md` si cambian comandos, exports, teclas o tablas; `README.md` si cambia algo visible;
   `docs/<SISTEMA>.md` si cambian reglas de diseño; `API.md`/`REGISTROS.md` de `crear-recurso` si
   cambian exports, dimensiones, teclas o blips.
3. Rama `feat/rp-x-<tema>` y PR a `main` (salvo que Fabián pida otra cosa) con el antes/después de
   la auditoría en la descripción.
4. Informe final corto: qué mejoró (en el juego), nota antes → después, qué queda pendiente y qué
   debe probar Fabián.

Si una mejora revela un patrón útil para todos los recursos, llévalo al estándar, al script de
auditoría o a las plantillas de `crear-recurso` en el mismo PR.
