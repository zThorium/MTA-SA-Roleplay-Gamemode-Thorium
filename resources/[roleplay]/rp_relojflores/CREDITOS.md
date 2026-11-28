# Créditos de rp_relojflores

- Modelo del Reloj de Flores (`models/*.dff`, `reloj_flores.txd`, `*.col`, `tools/reloj_flores.blend`): propio, generado con
  `tools/build_flower_clock.py` en Blender 4.2 a partir de fotos de referencia del Reloj de Flores de Viña del Mar (Chile).
  Texturas propias: renders de plantas modeladas en 3D en el mismo script (flores, seto) y procedurales (piedra, pintura).
- El césped de la loma es la textura `hedge2` del propio juego (TXD `union_las`): el modelo solo guarda su nombre y el cliente
  la toma del GTA SA del jugador con `engineSetModelTXDID`. No se distribuye material de Rockstar.
- Exportación a DFF/COL con el addon DragonFF (GPL, github.com/Parik27/DragonFF); el TXD (DXT con mipmaps) lo escribe el propio script. DragonFF es solo herramienta: no está en el repo ni en el recurso.
- Números y letras del cantero: contornos de la fuente Segoe UI Bold (Windows) convertidos en geometría; la fuente no se distribuye.
