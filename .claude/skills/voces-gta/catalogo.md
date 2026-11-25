# Catalogo de bancos de audio (GTA SA)

Doblaje latino: carpetas `zainesc-magotakon-huguito-...-part1/2` (AUDIO\CONFIG + AUDIO\SFX). Se leen con `scripts/gta-audio.ps1`
(no hace falta convertir a mp3: se extrae a WAV; Fish Audio acepta WAV y el script de voces devuelve mp3).

## Que reemplaza el doblaje
| Pak del mod | Original | Contenido |
|---|---|---|
| ZAINES (part2) | SCRIPT | Dialogos de misiones: bancos 147-364 (218 bancos). **Todos** distintos al ingles, pero con **la misma cantidad de sonidos, orden y duracion** (IA alineada) |
| FLOREN | SPC_PA | Voz ambiental (jugador) |
| HUGUIT | SPC_FA | Voz ambiental femenina |
| MAGOTA | PAIN_A | Gritos de dolor |
| STREAMS: ZAINESCA / ARANT | CUTSCENE / BEATS | Cinematicas / beats. Archivos cifrados con XOR; **no extraidos** todavia |

Como el orden coincide con el ingles, las etiquetas de personaje de las carpetas `missionaudios2` (ingles) se transfieren por indice de sonido.

## Etiquetado por banco (SCRIPT, indice = banco en BankLkup.dat)
En los bancos de dialogo ingles cada hablante tiene una frecuencia de muestreo: **CJ = 12000 Hz**, el otro personaje = 15000 Hz.

| Banco | Carpeta origen | Hablantes | Como separar |
|---|---|---|---|
| 301 | Sweet & CJ Talking Random | Sweet (15 kHz, 19 sonidos) y CJ (12 kHz) | sonidos 1,5,7,8,10,12,13,15,17,19,21,23,24,25,26,27,43,46,47 = Sweet |
| 305, 306, 307 | Ryder & CJ / CJ & Ryder 3 | Ryder (15 kHz) y CJ (12 kHz) | por frecuencia |
| 308, 316 | CJ & Ryder 4 / Big Smoke & CJ | todo a 12 kHz | no se puede separar por frecuencia |
| 302, 303, 312, 313, 314, 315, 309 | Los Desperados, End Of The Line, OG LOC, Running Dog, Bank_168, Just Business, 555 WE TIP | varios | 15 kHz mezcla varios personajes: no usar sin revisar a oido |

Para listar la frecuencia del banco ingles: `gta-audio.ps1 durs -Config "<juego>\audio\CONFIG" -Sfx "<juego>\audio\SFX" -Banco 301`.
Los sonidos en espanol de un banco: mismo comando con `-Config <mod>\AUDIO\CONFIG -Sfx <mod part1 SFX>,<mod part2 SFX>`.

## Voces registradas
- `sweet`: espanol latino, 10 clips del banco 301 (ZAINES) en `muestras/sweet_es/` (indices 27,8,5,15,24,10,25,13,47,1).
- `sweet_en`: ingles original (8 clips de `missionaudios2`).
