-- Generado por tools/build_voice_index.ps1: duracion en ms y extension de cada linea con voz
VOICE_LEN = {
}

VOICE_EXT = {
}

for _, def in ipairs(MISSION_DEFS) do
    for si, st in ipairs(def.stages) do
        for i, l in ipairs((st.cutscene and st.cutscene.lines) or {}) do
            local n = ("%s_%d%s%d"):format(def.key, si, "c", i)
            if VOICE_LEN[n] then l.voice, l.vlen = "audio/" .. n .. "." .. (VOICE_EXT[n] or "wav"), VOICE_LEN[n] end
        end
        for i, l in ipairs(st.radio or {}) do
            local n = ("%s_%d%s%d"):format(def.key, si, "r", i)
            if VOICE_LEN[n] then l.voice, l.vlen = "audio/" .. n .. "." .. (VOICE_EXT[n] or "wav"), VOICE_LEN[n] end
        end
    end
end
