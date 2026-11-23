# Tuning de rendimiento

Categoría **Rendimiento** del taller (`rp_vehicles`). Código: `shared/s_config.lua` (bloque `PERF`),
`server/s_perf.lua`, `client/c_perf.lua` y el panel en `html/tuning.js`.

## Cómo funciona
- 6 piezas con 3 niveles: **Motor, Turbo, Frenos, Suspensión, Neumáticos, Aligeramiento**.
- Cada nivel suma **beneficios** (aceleración, velocidad máxima, frenos, agarre, dirección) y
  **costos** (peso, consumo de bencina). Ej.: un motor Stage 3 acelera más pero pesa y gasta más;
  el turbo acelera mucho pero desgasta el motor más rápido; aligerar acelera pero resta agarre.
- El handling se recalcula siempre desde `getOriginalHandling` con `setVehicleHandling` por vehículo.
  En BD solo se guardan piezas y desgaste (`vehicles.perf`) y el kilometraje (`vehicles.odometer`).
- El consumo extra se aplica en `s_fuel.lua` (`getPerfFuelFactor`).

## Límite por clase
`PERF.CLASSES`: moto, compacto/sedan, SUV, deportivo, superdeportivo y pesado. Cada clase tiene un
tope por beneficio (suma de todas las piezas) y un multiplicador de precio. El servidor rechaza una
pieza que supere el tope; en el panel sale bloqueada con el motivo. Clase por tipo (`CLASS_BY_TYPE`)
o por modelo (`CLASS_BY_MODEL`). Bicicletas, botes, aviones, helicópteros, trenes, remolques y
monster trucks no se pueden mejorar.

## Desgaste
- Por **kilometraje** (cada pieza tiene su `km`, y más rápido a más velocidad y a mayor nivel) y por **uso**:
  frenazos fuertes (frenos), derrapes (neumáticos), choques (suspensión).
- El desgaste (0-100%) reduce los beneficios de la pieza; al 100% la pieza empeora el vehículo
  (`WORN_PENALTY`). Se avisa al conductor al 70% y al 100%.
- **Mantenimiento** en el taller (por pieza o general): cuesta `precio * desgaste * MAINT_FACTOR`.
  Instalar una pieza nueva reinicia su desgaste.

## Visual
- Suspensión: el auto baja por nivel (`suspensionLowerLimit`).
- Al ver Motor o Turbo en el taller se abre el capó.
- Turbo o motor Stage 3: llamaradas por el escape al soltar el acelerador. Motor o turbo gastado (70%+): humo.
- Sonidos (`sounds/tune_*.wav`): silbido del turbo mientras aceleras (sube con la velocidad y el nivel), soplido (BOV) al soltar el acelerador con turbo cargado, estallido en cada llamarada y ruido de matraca al instalar una pieza o hacer mantenimiento (también al comprar tuning visual).

## Balance
Todo está en `PERF` (`shared/s_config.lua`): bonos y precios por nivel, topes por clase, ritmos de desgaste.
