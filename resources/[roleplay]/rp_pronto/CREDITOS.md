# Créditos de rp_pronto

- Modelo de la bencinera (`models/*.dff`, `pronto.txd`, `pronto_lod.txd`, `*.col`, `tools/pronto.blend`): propio, generado con
  `tools/build_pronto.py` en Blender 4.2 a partir de fotos de referencia de tiendas Pronto Express de Copec (Chile).
- Texturas propias (lamas, estuco, travertino, baldosa, cielo raso, rojo de marca, fascia Copec, logos, mascota, pantallas,
  afiches, tótem de precios, iconos, pintura de estacionamiento): procedurales, hechas por el script.
- Texturas de la cubierta, la isla, el metal y la rejilla del lavado (`roof06L256`, `concretenewgery256`, `gen_chrome`,
  `metpat64`): son las del **propio juego** (TXD `barrio1_lae`). El recurso solo guarda sus nombres; cada cliente usa las
  de su GTA SA, así que no se reparte material de Rockstar. Los muebles del interior (góndolas, refrigeradores, cajas,
  café) también son modelos del juego, creados por su número.
- `tools/extraer-img.ps1` saca de `gta3.img` los modelos y texturas originales **al scratchpad** (nunca al repo), solo como
  molde para el horneado de luz y las vistas previas.
- Exportación a DFF/TXD/COL con el addon DragonFF (GPL, github.com/Parik27/DragonFF). Es solo herramienta: no está en el repo ni en el recurso.
- Letreros: texto rasterizado con Century Gothic, Segoe Script, Segoe UI y Bahnschrift (Windows); las fuentes no se distribuyen.
  «Pronto Express» y «Copec» son marcas de sus dueños; se usan como homenaje en un servidor de roleplay.
