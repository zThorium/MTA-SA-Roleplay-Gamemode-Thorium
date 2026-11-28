# Auditoría de rp_properties

## 2026-11-27 · arreglar (propiedades duplicadas)
- **Síntoma**: las casas sembradas salían dos veces en el mismo sitio (139-146, copias de las 1-8), con una «en venta» encima de otra con dueño.
- **Causa raíz**: `loadProperties` puede ejecutarse dos veces seguidas (al arrancar y en `rp:onDatabaseReady` de un reinicio de `rp_database`) y la siembra no era atómica: las dos ejecuciones veían la tabla vacía.
- **Arreglo**: `seedProperty` inserta con `INSERT ... SELECT ... WHERE NOT EXISTS` (mismo nombre y misma puerta). Además, al cargar, `DEDUPE_SQL` borra las copias sin dueño y sin muebles, miembros, estilo ni registro (nunca una con dueño). En la BD local se borraron las 139-146, con respaldo previo.
- **Probar en juego**: `restart rp_properties`: en Grove Street, Ganton e Idlewood hay una sola puerta por casa; la consola muestra 138 propiedades.


## 2026-11-28 · arreglar (#150, /vendercasa reembolsaba dos veces)
- **Síntoma**: mandar `/vendercasa` dos veces seguidas pagaba el 50 % de reembolso dos veces (dupeo de dinero).
- **Causa raíz**: el dueño se comprobaba solo en memoria (`p.row.owner_id`), el `UPDATE properties SET owner_id = NULL` no exigía el dueño en SQL y el reembolso se pagaba siempre; `refresh(id)` relee la casa de forma asíncrona, así que la segunda llamada aún la veía como propia.
- **Arreglo**: `UPDATE ... WHERE id = ? AND owner_id = ?` con `dbQuery`; el reembolso, el movimiento bancario, la expulsión de ocupantes y `rp:prop:sold` solo ocurren si esa sentencia afectó una fila (mismo patrón que la compra). Además se suelta el dueño en memoria al instante.
- **Prueba de regresión**: `rp_test` › `properties_vender_es_atomico` (la segunda venta afecta 0 filas). SQL validado en la BD local dentro de una transacción con rollback.
- **Probar en juego**: comprar una casa, `bind k vendercasa` y pulsar K dos veces rápido: un solo ingreso en el banco; la segunda pulsación responde «Debes estar en la puerta o dentro de una propiedad tuya».
- **INT-09**: N/A, arreglo de seguridad sin hecho lograble nuevo.
