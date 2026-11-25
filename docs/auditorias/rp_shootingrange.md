# Auditoría de rp_shootingrange

## 2026-11-25 · crear
- **Motivo**: campo de tiro de Ammu-Nation (solo Market): entrena la habilidad nativa de arma (stats 69-79) con armas y balas reales del inventario.
- **Nota**: — → 98 (sin FALLA B; AVISO DOC-04 resuelto con este archivo).
- **Cambios**: recurso nuevo; tabla `weapon_skills`; exports `suspendWeapons/resumeWeapons` en `rp_ammunation`; CEF con menú, HUD de esquina y resultados; sesiones aisladas en dimensión `23000+n`; cada disparo descuenta 1 bala (`takeItem`); impactos por rayo propio del servidor contra zonas (cabeza/torso/piernas), un impacto por blanco y tope de 120 puntos de habilidad por sesión; stat restaurada al valor entrenado tras cada disparo (los fallos no suben habilidad).
- **Reglas manuales revisadas**: SEG-02 ✔ (arma, balas y puntos salen de config e inventario), SEG-04 ✔, BD-06 ✔, PRU-02 ✔ (tabla y recurso en `rp_test`).
- **Pendiente**: coordenadas del campo (`RANGE.FIRE`, `RANGE.DESK`, interior 7) sin verificar en juego; las otras 6 armerías (faltan coordenadas); `scripts/test.sh` no pudo ejecutarse en Windows (entrypoint de Docker con CRLF), pasarlo en Mac/Linux.
- **Probar en juego**: E en el mostrador de Ammu-Nation Market; sin armas (mensaje); con arma y balas; las balas bajan al disparar y no se duplican al salir; blancos en su sitio y de cara; impactos por zona; las 3 rondas; F2 abandona; habilidad sube solo con aciertos y persiste tras reconectar; dos jugadores a la vez; abatido y desconexión dentro del campo; el arma de antes se vuelve a equipar al salir.
