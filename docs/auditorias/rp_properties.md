# Auditoría de rp_properties

## 2026-11-27 · arreglar (propiedades duplicadas)
- **Síntoma**: las casas sembradas salían dos veces en el mismo sitio (139-146, copias de las 1-8), con una «en venta» encima de otra con dueño.
- **Causa raíz**: `loadProperties` puede ejecutarse dos veces seguidas (al arrancar y en `rp:onDatabaseReady` de un reinicio de `rp_database`) y la siembra no era atómica: las dos ejecuciones veían la tabla vacía.
- **Arreglo**: `seedProperty` inserta con `INSERT ... SELECT ... WHERE NOT EXISTS` (mismo nombre y misma puerta). Además, al cargar, `DEDUPE_SQL` borra las copias sin dueño y sin muebles, miembros, estilo ni registro (nunca una con dueño). En la BD local se borraron las 139-146, con respaldo previo.
- **Probar en juego**: `restart rp_properties`: en Grove Street, Ganton e Idlewood hay una sola puerta por casa; la consola muestra 138 propiedades.

