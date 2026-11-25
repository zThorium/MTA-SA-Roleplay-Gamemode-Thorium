# Registros de auditoría

Un archivo por recurso (`rp_x.md`) con la historia de calidad del recurso: cada vez que se crea,
mejora o arregla, se añade una entrada **arriba** con la nota antes → después, los cambios citando
las reglas de [`docs/ESTANDAR_RECURSOS.md`](../ESTANDAR_RECURSOS.md), las reglas manuales revisadas,
lo pendiente y qué probar en juego.

Las skills `crear-recurso`, `mejorar-recurso` y `arreglar-recurso` escriben estas entradas solas.
Para ver el estado de todos los recursos:

```bash
scripts/auditar-recurso.sh --todos
```
