# Auditoría de rp_firefighters

## 2026-11-26 · crear
- **Motivo**: facción de bomberos con servicio, emergencias dinámicas (incendio en altura con focos y civiles atrapados con temporizador) y recompensas/fallos. `rp_emergency` tenía `fire` sin implementar y `docs/EVENTOS_DINAMICOS.md` lo pedía.
- **Nota**: nuevo → 100/100 (0 FALLA B).
- **Diseño**:
  - Facción = cualquier facción de tipo `bomberos` (nuevo en `FACTION_TYPES`, pagada por el Estado). `collectPaydaySalary` solo paga de servicio, como a la policía.
  - Servidor autoritativo: vida de focos y aire de civiles en el servidor con un solo timer de 1 s por incidente; resumen compacto a los clientes (`rp:firefighters:tick`).
  - `createFire` es solo de cliente: cada cliente dibuja llamas y humo con `createEffect` y renueva un `createFire` nativo mientras el servidor diga que el foco vive. El cliente informa a qué foco apunta (cono de la cámara) y el servidor revalida arma 42 o autobomba 407 conducida, distancia, servicio, cadencia (≥ 0,25 s) y máximo 3 focos por envío (SEG-02).
  - Sitios colocados por admins (`/fdsitio`) en vez de coordenadas fijas: no se pueden verificar azoteas accesibles sin el juego.
  - Civiles: daño cancelado en todos los clientes (`onClientPedDamage`): su vida la lleva el servidor.
- **Reglas manuales revisadas**: SEG-02 ✔ (`client`, tipos, cercanía con interior/dimensión, servicio, estado), SEG-03 ✔ (cooldown por jugador), SEG-04 ✔ (todos los comandos `FD.isAdmin(p, 1)`), BD-06 ✔ (no cobra; los ingresos al banco siguen el patrón de `rp_payday`), BD-07 ✔ (`firefighter_stats` con FK y escritura en el momento), CIC-03 ✔ (rehidrata stats y puntos; quita uniforme y equipo al parar), CIC-06 ✔ (abatido, muerte, salida o cambio de personaje sueltan al civil; con civil a hombros no se sube a vehículos), INT-07 ✔ (rp_factions, rp_levels, rp_notify, rp_markers, rp_characters:restoreCharacterLook), UX-01 ✔ (E, clic y Ctrl dibujados), UX-02 ✔ (la guía muestra un solo paso; prioriza al civil que se ahoga), UX-03/05 ✔ (guía resaltada las 2 primeras emergencias; entrenador en el vestuario la primera vez), UX-06 ✔ (sonido por evento, cuenta de dinero, tarjeta de resultado), UX-07 ✔ (globo `!`/feliz/cruz y barra de aire sobre cada civil), UX-09 ✔ (el HUD es un panel lateral, no pantalla completa: no oculta `rp_hud`), UX-10 ✔ (`CREDITOS.md`), PRU-02: servidor con `scripts/test.sh`; **el cliente lo debe probar Fabián en juego**.
- **Pendiente**:
  - Sitios: no hay ninguno hasta que un admin los cree (`/fdsitio crear`, `foco`, `civil`).
  - Coordenadas por defecto de la estación aproximadas (Doherty, SF): ajustar con `/fdmover`.
  - Chorro sin línea de visión (`shortcut:` en `c_fire.lua`): atraviesa paredes.
  - `/911` → Bomberos sigue desactivado en `rp_emergency`; se puede enganchar a `rp:emergency:onCall` en otro PR.
  - Offsets del civil a hombros copiados de `rp_injury`: afinar en juego si queda mal.
- **Probar en juego**: crear facción `/crearfaccion bomberos SFFD Bomberos de San Fierro` y entrar; vestuario (E) → servicio con cada uniforme; garaje (E) sacar/guardar; `/fdsitio crear`, 3 focos y 2 civiles; `/fdincendio`: alerta, blip, apagar con extintor y con autobomba, cargar civiles y dejarlos en la ambulancia, éxito con pago y XP; repetir dejando morir a un civil (fallo); quedar abatido con un civil a hombros; salir de servicio en mitad; `restart rp_firefighters` con un incendio activo. `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 137614c)

**Nota: 100/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 2 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
