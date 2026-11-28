# Auditoría de rp_carwash

## 2026-11-28 · crear (suciedad por terreno y lavado de autos, issue #144)
- **Motivo**: backlog #144 [F7.3]: los autos se ensucian según el terreno (tierra, arena, pasto) y se lavan en el túnel de `rp_pronto`.
- **Cambios**:
  - Recurso nuevo `rp_carwash`: el cliente del conductor mide la superficie (material de GTA bajo el vehículo) y suma suciedad; el servidor limita el aporte a la tasa máxima por tiempo transcurrido y la publica en `rp:dirt`.
  - Shader `fx/dirt.fx` sobre `vehiclegrunge256`: manchas de barro (ruido 3D en espacio del modelo) que suben desde los bajos; solo se aplica con suciedad >= 3 % para no quitar el brillo nativo a los autos limpios.
  - Lavado: marcador fijo registrado en `rp_markers` (movible), E con la tecla dibujada, $40 en efectivo, auto congelado 9 s con salpicaduras de agua y barra de progreso.
  - BD: `vehicles.dirt` (nueva entrada al final de `schema.lua`); `rp_vehicles` la carga al crear el auto; `rp_carwash` la guarda cuando cambia >= 0,05 y al lavar.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el servidor valida conductor, distancia al marcador, dimensión, suciedad mínima y efectivo; el aporte de suciedad del cliente se recorta a la tasa máxima (es cosmético, el terreno solo lo ve el cliente).
  - SEG-04 ✔: un lavado por vehículo; aportes de suciedad limitados por tiempo.
  - BD-05: las consultas solo ocurren al manejar o lavar, cuando la BD ya está lista.
  - BD-06 ✔: `UPDATE` parametrizado por id.
  - PRU-02 ✔: `rp_test/server/s_tests_carwash.lua` (marcador y límites de `setVehicleDirt`). Pasa en Docker.
  - CIC-03 ✔: el lavado termina si el conductor se baja (queda limpio, ya pagó), si el auto se destruye o si se para el recurso. Al descongelar se respetan freno de mano y cepo de `rp_vehicles`.
  - INT-09: N/A, servicio cosmético de pago; no hay esfuerzo ni habilidad que premiar.
  - UX-01 ✔ E dibujada sobre el lavado con el % de suciedad. UX-02 ✔ un solo aviso. UX-06 ✔ sonidos al empezar, terminar y si no alcanza el dinero; agua y suciedad que baja. UX-10 ✔ `CREDITOS.md`.
- **Pendiente** [A]:
  - Afinar en juego los colores y el umbral del shader, y los IDs de superficie de arena y pasto.
- **Probar en juego**:
  - Manejar por la playa, el pasto y caminos de tierra: el auto se ensucia (otro jugador lo ve igual).
  - Entrar al túnel de la Pronto en Idlewood, E, pagar $40: agua, la suciedad baja y queda limpio. Sin dinero: aviso y sonido de error.
  - Reiniciar el servidor: un auto con dueño conserva su suciedad.
