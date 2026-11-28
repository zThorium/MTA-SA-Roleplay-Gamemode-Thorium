# Créditos de rp_turbus

- Modelo del Terminal Turbus (`models/*.dff`, `turbus.txd`, `turbus_lod.txd`, `*.col`, `tools/terminal.blend`): propio, generado con
  `tools/build_terminal.py` en Blender 4.2 a partir de fotos de referencia del terminal Turbus de Santiago (Chile).
- Texturas propias (verde, vidrio, acero, cielo raso, asientos, seto, pintura amarilla, letreros y pantallas): procedurales, hechas por el script.
- Texturas del hall y los andenes (hormigón, baldosa, estuco, chapa ondulada): son las del **propio juego** (TXD `railway_las`).
  El recurso solo guarda sus nombres; cada cliente usa las de su GTA SA, así que no se reparte material de Rockstar.
  `tools/extraer-img.ps1` saca de `gta3.img` los modelos y texturas originales de Unity Station **al scratchpad** (nunca al repo),
  solo como molde para el horneado de luz y las vistas previas.
- Exportación a DFF/TXD/COL con el addon DragonFF (GPL, github.com/Parik27/DragonFF). Es solo herramienta: no está en el repo ni en el recurso.
- Letreros «turbus», «BOLETERÍA», «ANDENES» y pantallas: texto rasterizado con las fuentes Arial Rounded MT Bold y Segoe UI Bold
  (Windows); las fuentes no se distribuyen. «Turbus» es una marca de su dueño; se usa como homenaje en un servidor de roleplay.
