# Voces con IA (Fish Audio) para personajes de GTA SA

Estándar: **toda línea de un personaje (no `me`) lleva voz clonada**. Nunca solo subtítulos y **nunca TTS de Windows** (Fabián no los quiere).
Herramientas en la skill `voces-gta` (`scripts/voz.ps1`, `scripts/gta-audio.ps1`, `catalogo.md`). Este documento explica el proceso completo y **de dónde salieron los assets**.

## De dónde salieron las muestras de la voz de Sweet en español (procedencia)

1. **Doblaje latino del juego, ya instalado por Fabián** (carpetas `zainesc-magotakon-huguito-gta-sa-espanol-latino-pc-part1/part2` en Descargas: mod de doblaje al español latino de ZainEsc, Magotakon, Huguito y colaboradores; "mod gratuito no apto para su venta, dar todo crédito a los creadores"; el reparto incluye voces humanas y **doblaje por IA**). Son los bancos de audio del juego (`AUDIO\SFX\ZAINES`, etc.), sin extensión: no son mp3.
2. **Se extrajeron los bancos con `gta-audio.ps1`** (formato verificado contra los tamaños reales: `AUDIO\CONFIG\PakFiles.dat` = nombres de pak, `BankLkup.dat` = 12 B por banco {pak, offset, longitud}; cada banco = cabecera de 4804 B {n sonidos + 400 × {offset, loop, rate, headroom}} + PCM 16 bit mono sin cabecera). El doblaje reemplaza `SCRIPT`→`ZAINES` (diálogos de misiones, bancos 147-364), `PAIN_A`→`MAGOTA`, `SPC_FA`→`HUGUIT`, `SPC_PA`→`FLOREN`; los streams `CUTSCENE`/`BEATS` van en `ZAINESCA`/`ARANT` (cifrados con XOR, **sin extraer**). Los 218 bancos de `ZAINES` son distintos byte a byte del inglés **pero con el mismo número de sonidos, orden y duración** (IA alineada en el tiempo).
3. **Quién es Sweet**: los clips no tienen etiqueta de personaje. Fabián aportó además una carpeta en **inglés** (`missionaudios2`, clips sueltos de misiones, también suyos) con una carpeta "Sweet & CJ Talking Random" = banco **301** del `SCRIPT` original. En el original, cada hablante tiene su propia frecuencia de muestreo: **CJ = 12000 Hz, el otro personaje = 15000 Hz** (y Sweet tiene el tono más grave: mediana ~165 Hz frente a ~215 Hz de CJ). Eso da 19 sonidos de Sweet: **1,5,7,8,10,12,13,15,17,19,21,23,24,25,26,27,43,46,47**.
4. **Transferencia por posición**: como el banco 301 del doblaje (`ZAINES`) conserva el orden y la duración, esas mismas posiciones son Sweet en español. (El tono en español separa mal a los dos personajes —179 Hz vs 205 Hz—: la etiqueta se apoya en la posición, no en el tono.)
5. **Se eligieron los 10 mejores clips** (los más largos y limpios, 1,4-2,8 s, ~22 s en total): sonidos **27, 8, 5, 15, 24, 10, 25, 13, 47, 1** del banco 301, extraídos a WAV (15 kHz) en `muestras/sweet_es/` (carpeta en `.gitignore`: audio de Rockstar, no se sube).
6. **Fish Audio** recibe esos 10 WAV como `references` de cada petición (clonación *zero-shot*, sin transcripciones; la cuenta gratuita no permite crear modelos persistentes: "API model creation limit reached 0/0") y devuelve mp3 con el texto nuevo.

Antes de eso hubo una versión en inglés (`sweet_en`): 8 mp3 sueltos que Fabián aportó (`a-hole.mp3`, `grove-street.mp3`…) y luego 8 clips del banco inglés 301. Se descartó por el acento.

Límites honestos: la etiqueta "Sweet" no está verificada de oído por Claude (Fabián sí validó el resultado final); es un clon de un clon (el doblaje ya es en parte IA); falta animación facial. **Crédito**: al usar audio del doblaje latino hay que acreditar a ZainEsc, Magotakon, Huguito y colaboradores, y los audios generados **no se publican ni se venden**.

## Configuración validada (la de Sweet, aprobada a oído por Fabián)
- Modo zero-shot con 8-10 clips de 1,5-3 s del personaje **en español**; modelo `s2.1-pro-free` (cabecera `model`); `-Idioma es`; **temperatura 0.3**; velocidad 1.0; mp3 128 kbps; `normalize` activo.
- **Texto con ortografía correcta** (tildes, ¿¡, ñ): sin tildes la pronunciación se degrada y suena a otro idioma ("turco"). Etiquetas de emoción solo en el texto del TTS (`[shouting]`), nunca en el subtítulo.
- El script reintenta solo (hasta 4 veces) si Fish **desbarra** (audio de 46 s para una frase de 4 s: demasiado largo > 2,3 KB/carácter, o recortado < 0,7 KB/carácter).
- Los `.ifp`/muestras/ API key nunca al repo (la key vive en `~/.fish-audio-key` o `FISH_API_KEY`).

## Procedimiento para una misión
1. Para cada personaje de la misión (no `me`): `voz.ps1 voces`. Si no está registrado → "Registrar una voz nueva" (abajo).
2. `lineas.txt` con `<clave>_<etapa><c|r><n>|<texto con tildes>` (c = cinemática, r = radio, n = índice de la línea en `cutscene.lines`/`radio`; los índices **no se reordenan**; `me` no lleva voz).
3. `voz.ps1 lote -Voz <personaje> -Archivo lineas.txt -Carpeta rp_missions/audio`.
4. `rp_missions/tools/build_voice_index.ps1` (reescribe `shared/s_voice.lua` con duraciones —mp3 a 128 kbps: bytes/16 ms— y los `<file>` de `meta.xml`).
5. Reiniciar `rp_missions`; avisar a Fabián para escucharlas.

## Registrar una voz nueva (p. ej. Ryder, Cesar, Smoke)
1. Localizar el banco del personaje (`catalogo.md`: bancos 305-307 = Ryder; 301 = Sweet; 316/308 vienen todo a 12 kHz y no se separan por frecuencia).
2. `gta-audio.ps1 extraer -Config <mod>\AUDIO\CONFIG -Sfx @("<part1 SFX>","<part2 SFX>") -Banco <n> -Sonidos <lista> -Salida muestras/<voz>` (ejecutarlo con `&`, no con `-File`).
3. Elegir 8-10 clips de 1,5-3 s **solo del personaje** (por casilla, ver arriba); opcional `<clip>.txt` con la transcripción (mejora el parecido).
4. `voz.ps1 registrar -Voz <personaje> -Titulo "GTA SA - <Personaje>" -Muestras muestras/<voz>`; probar con `hablar` y que Fabián lo escuche antes de generar la misión.

## Trampas
- `Invoke-WebRequest -OutFile` interpreta `[corchetes]` (p. ej. `resources/[roleplay]`) como comodines: el script descarga a un temporal y mueve con `-LiteralPath`.
- `references` solo acepta msgpack (no JSON): `voz.ps1` incluye un codificador msgpack mínimo.
- Invocar scripts con arrays desde PowerShell con `&`, no con `-File`.

## Los audios de voz NO se suben al repo (es público)
Los `.mp3` de `rp_missions/audio/` (y las muestras y los `.ifp`) son derivados de audio de Rockstar y del doblaje latino: están en `.gitignore`; cada desarrollador los genera en local. El repo lleva `audio/LEEME.md` y un `shared/s_voice.lua` vacío; **no commitear los mp3 aunque `git status` los muestre**. Tras generar voces en local, `build_voice_index.ps1` deja `s_voice.lua` y `meta.xml` modificados: no subir ese cambio.
