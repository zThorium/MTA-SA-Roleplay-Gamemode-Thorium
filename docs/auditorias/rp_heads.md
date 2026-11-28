# Auditoría de rp_heads

## 2026-11-27 · arreglar (cabeza propia enorme en pantalla por un instante al caminar)
- **Motivo**: Fabián ve cada cierto tiempo, caminando, su propia cabeza (y los toys) ocupando media pantalla durante unos milisegundos.
- **Causa**: cuando la cámara choca con una pared o un poste y queda pegada al personaje, GTA deja de dibujar el cuerpo del jugador local, pero la cabeza de `rp_heads` y los accesorios de `rp_clothing` son objetos aparte (`bone_attach`) y se seguían dibujando a centímetros de la cámara.
- **Nota**: rp_heads 87 → 87 · rp_clothing 95 → 95 (sin fallas nuevas; EST-02 de rp_heads e INT-03 de rp_clothing ya estaban).
- **Cambios**:
  - `rp_heads/c_heads.lua`: la cabeza propia se oculta (alfa 0) con la cámara a menos de 0,6 m del hueso de la cabeza. La comprobación de visibilidad pasa de `onClientRender` a `onClientPedsProcessed` (después de la cámara y antes de dibujar) para ocultarla en el mismo fotograma.
  - `rp_clothing/client/c_headlink.lua`: lo mismo para los accesorios propios; solo cambia el alfa al entrar o salir de ese estado, restaura solo los que ocultó, no actúa con el estudio abierto y los vuelve a mostrar al parar el recurso (CIC-05).
- **Reglas manuales revisadas**: CLI-02 ✔ (por fotograma solo una distancia; el recorrido de objetos se hace al cambiar de estado) · CIC-05 ✔.
- **Pendiente**: si GTA esconde el cuerpo a más de 0,6 m todavía podría verse un destello; subir `CAMERA_NEAR_HEAD`/`CAMERA_NEAR`.
- **Probar en juego**: caminar pegado a paredes, postes y esquinas girando la cámara hacia el personaje (no debe aparecer la cabeza gigante); apuntar con rifle y francotirador; abrir el estudio de ropa; los demás jugadores siguen viendo tu cabeza y tus toys.

