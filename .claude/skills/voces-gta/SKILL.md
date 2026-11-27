---
name: voces-gta
description: Genera audios con las voces de personajes de GTA San Andreas (Sweet y futuras) clonadas con Fish Audio, para los dialogos de rp_missions u otros recursos. Usar cuando haya que crear, regenerar o agregar lineas de voz de un personaje, o registrar una voz nueva a partir de muestras del juego.
---

# Voces de GTA SA (Fish Audio)

Clona la voz de un personaje a partir de clips reales del juego y genera lineas nuevas (mp3/wav) con TTS.
Voces registradas: ver `voces.json` o `scripts/voz.ps1 voces`. Hoy: **sweet** (espanol latino, 10 clips del doblaje), **sweet_en** (ingles original) **anunciadora_tren** (voz publica "Verity" de la biblioteca de Fish, por `id`) y **anunciadora_metrotren** (clonada de 10 fragmentos de una grabacion de megafonia de Metrotren, limpiados con `afftdn`; la que usa `rp_train`).

## Uso rapido

```powershell
$v = ".claude/skills/voces-gta/scripts/voz.ps1"        # ruta desde la raiz del repo
powershell -NoProfile -File $v voces
powershell -NoProfile -File $v hablar -Voz sweet -Texto "Grove Street, home. At least it was before I fell out." -Salida out/sweet_01.mp3
powershell -NoProfile -File $v lote -Voz sweet -Archivo lineas.txt -Carpeta out      # lineas.txt: nombre|texto
```

- Parametros utiles: `-Velocidad 0.5-2.0`, `-Formato mp3|wav`, `-Temperatura 0-1` (mas bajo = mas parecido/estable).
- Etiquetas de emocion entre corchetes en el texto (modelo S2): `[shouting]`, `[angry]`, `[whispering]`, `[laughing]`, `[sighing]`, `[break]`. Ponerlas al inicio de la frase; maximo 3 por frase.
- **Escribir el texto con ortografia correcta (tildes, ¿¡, ñ)**: sin tildes la pronunciacion se degrada y puede sonar a otro idioma. El idioma se fuerza con `-Idioma es` (por defecto). `-Temperatura` por defecto 0.5.
- El script reintenta solo (hasta 4 veces) si Fish "desbarra": audio demasiado largo o demasiado corto para el texto.
- Funciona con texto en espanol o ingles; las muestras de Sweet son en ingles, asi que en espanol conserva el timbre pero el acento sera ingles/neutro.

## Extraer audio del juego (bancos SFX -> WAV)

Los dialogos del juego no son mp3: estan en bancos `AUDIO\SFX\<PAK>` indexados por `AUDIO\CONFIG\BankLkup.dat`.
`scripts/gta-audio.ps1` los lee (ejecutarlo con `&`, no con `powershell -File`, para poder pasar listas en `-Sfx`):

```powershell
$a = ".claude/skills/voces-gta/scripts/gta-audio.ps1"
& $a indice  -Config <AUDIO\CONFIG> -Sfx @("<dir SFX 1>","<dir SFX 2>") [-Pak ZAINES]   # bancos, n sonidos, segundos
& $a durs    -Config ... -Sfx ... -Banco 301                                              # duracion y Hz de cada sonido
& $a extraer -Config ... -Sfx ... -Banco 301 [-Sonidos 1,5,8] -Salida <carpeta>          # sonido_NNN.wav
```

Detalles del formato, que bancos tiene el doblaje latino y como se etiqueta cada personaje: `catalogo.md`.
Flujo para una voz nueva en espanol: ubicar el banco -> etiquetar al personaje (ver catalogo) -> extraer 8-10 clips de 1.5-3 s -> `registrar`.

## Registrar una voz nueva

1. Reunir 5-20 clips cortos del personaje, **sin musica ni ruido**, un solo hablante (mp3/wav/flac). 10-30 s en total basta.
2. Guardarlos en `muestras/<voz>/` (esa carpeta esta en `.gitignore`: es audio con copyright de Rockstar, no se sube al repo).
3. Opcional pero mejora el parecido: un `<clip>.txt` al lado con la transcripcion exacta de lo que dice.
4. `powershell -NoProfile -File $v registrar -Voz ryder -Titulo "GTA SA - Ryder" -Muestras muestras/ryder`

Si hace falta mas material, el audio del juego esta en `Documents\Gta San Andreas\audio\SFX\SPC_*` (dialogos en bancos `.raw` + `.sdt`, no son mp3 sueltos: hay que extraerlos con una herramienta como "GTA SA Audio Toolkit"/SAAT antes de usarlos como muestras).

## Modos de clonacion

- **zero-shot** (`registrar`, por defecto): las muestras viajan en cada peticion (msgpack). No consume cupo de modelos; funciona con la cuenta gratuita. Cada llamada sube unos 200 KB.
- **modelo persistente** (`crear`): sube las muestras una vez y guarda un `reference_id`. Requiere credito en Fish Audio ("API model creation limit reached (0/0)" en cuenta gratis). Para usarlo, `crear` reemplaza la entrada en `voces.json`.

## Configuracion

- API key: variable `FISH_API_KEY` o archivo `~/.fish-audio-key` (una linea). **Nunca** escribirla en el repo, en `voces.json` ni en commits.
- Modelo TTS: cabecera `model`, por defecto `s2.1-pro-free`; se cambia con `$env:FISH_MODEL = "s2.1-pro"`.
- Errores 401 = key mala, 402 = sin credito, 403 = limite de la cuenta.

## Integracion con rp_missions

Los dialogos estan en `resources/[roleplay]/rp_missions/shared/s_missions_data.lua`. Cada linea con voz es un archivo `rp_missions/audio/<mision>_<etapa><c|r><n>.mp3` (`c` = cinematica, `r` = radio, `n` = indice de la linea). Procedencia de las muestras de Sweet y proceso completo: skill `crear-mision`, `references/voces.md`.

Para ponerle voz clonada a una mision:
1. Armar un `lineas.txt` con `<mision>_<etapa><c|r><n>|<texto>` (solo las lineas del personaje; las del jugador, `me`, no llevan voz).
2. `hablar`/`lote -Voz sweet -Carpeta <rp_missions>/audio` (mp3 por defecto).
3. `powershell -File rp_missions/tools/build_voice_index.ps1` reescribe `shared/s_voice.lua` (duracion = bytes/16 ms para mp3 a 128 kbps) y la lista `<file>` de `meta.xml`.
4. Reiniciar `rp_missions` (los clientes descargan los audios nuevos).
5. Revisar a oido: si suena mal en espanol, probar `-Temperatura 0.5`, reescribir la frase o poner la etiqueta de emocion solo en el TTS (el subtitulo no cambia).

Estado: la mision 1 (`grove_turf`, Sweet) usa su voz clonada en espanol latino (`sweet`). `uncle_sam` (Ryder) y `cesar_cargo` (Cesar) estan SIN voz hasta registrar sus voces (no usar TTS de Windows).

## Muestras de Sweet

`muestras/sweet_es/` (voz `sweet`, espanol latino): 10 clips del banco 301 del doblaje (ver `catalogo.md`). `muestras/sweet_gta/` (voz `sweet_en`): 8 clips del banco ingles "Sweet & CJ Talking Random". Sweet se identifica por la casilla del banco (15 kHz en el original); el tono en espanol no separa bien a los dos personajes, asi que si una muestra suena a CJ, borrarla y volver a `registrar`.

## Aviso

Las voces son de personajes de Rockstar clonadas para uso en un servidor privado de rol: no publicar los audios generados ni las muestras ni usarlos comercialmente.
