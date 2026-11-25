# Voces de las misiones

Los audios de voz **no se versionan**: son voces clonadas con IA a partir de audio del juego (Rockstar) y del doblaje latino
de ZainEsc, Magotakon, Huguito y colaboradores (que piden dar crédito y no redistribuir), y este repositorio es público.

Cada desarrollador las genera en local con la skill `voces-gta` / `crear-mision` (`references/voces.md`):
1. registrar la voz (`voz.ps1 registrar`), 2. `voz.ps1 lote` hacia esta carpeta (`<clave>_<etapa><c|r><n>.mp3`),
3. `tools/build_voice_index.ps1` (reescribe `shared/s_voice.lua` y los `<file>` de `meta.xml`).

Sin audios las misiones funcionan igual, solo con subtítulos.
