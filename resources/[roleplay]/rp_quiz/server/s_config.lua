--[[
    rp_quiz / server/s_config.lua  (solo servidor: el cliente nunca ve las respuestas)

    Preguntas del cuestionario de rol. Cada una: texto, opciones y `answer` (índice correcto),
    más `why`, que se enseña si se falla. Se barajan las opciones al enviarlas.
]]

QUIZ = {
    PASS = 7,               -- aciertos para aprobar (de #QUIZ.QUESTIONS)
    RETRY_SECONDS = 30,     -- espera tras suspender
    QUESTIONS = {
        { text = "¿Qué es el MetaGaming (MG)?", answer = 2,
          options = { "Jugar mucho tiempo seguido", "Usar en el rol información que tu personaje no conoce", "Hablar por el chat OOC", "Robar un banco" },
          why = "MG es usar información OOC (Discord, nametags, lo que viste en un stream) dentro del rol." },
        { text = "¿Qué es el PowerGaming (PG)?", answer = 1,
          options = { "Forzar acciones irreales o no dar opción al otro jugador", "Subir de nivel rápido", "Tener mucho dinero", "Conducir un auto potente" },
          why = "PG es hacer lo imposible (seguir corriendo con un disparo) o imponer el resultado al otro." },
        { text = "¿Qué diferencia hay entre IC y OOC?", answer = 3,
          options = { "Ninguna, es lo mismo", "IC es el chat de admins", "OOC es lo que hace tu personaje", "IC es lo que hace y dice tu personaje; OOC es lo que dices tú como jugador" },
          why = "IC (In Character) es el personaje; OOC (Out Of Character) eres tú, y se escribe con /b." },
        { text = "Un desconocido pasa a tu lado sin hacerte nada. ¿Puedes dispararle?", answer = 2,
          options = { "Sí, si tienes un arma", "No: matar sin un motivo de rol previo es DeathMatch (DM)", "Sí, si nadie te ve", "Solo de noche" },
          why = "Toda agresión necesita un rol previo y suficiente. Sin motivo es DM y se sanciona." },
        { text = "¿Cuál de estos nombres de personaje es válido?", answer = 4,
          options = { "xX_Killer_Xx", "Carl_Johnson", "Pedro", "Lucia_Fernandez" },
          why = "Nombre_Apellido realista; nada de famosos, personajes del juego ni apodos." },
        { text = "Te apuntan con un arma y tú vas desarmado. ¿Qué haces?", answer = 1,
          options = { "Cooperar y temer por tu vida (Fear RP)", "Correr en zigzag", "Desconectarte", "Insultarle por el chat OOC" },
          why = "Valora tu vida: si te superan o te apuntan, actúa con miedo y coopera." },
        { text = "Estás en medio de un rol que va mal para ti. ¿Puedes salir del juego?", answer = 3,
          options = { "Sí, cuando quieras", "Solo si es de noche", "No: desconectarse para evitar consecuencias es evadir rol", "Sí, si avisas por /b" },
          why = "Salir, ir AFK o usar comandos para escapar de un rol en curso es evadir rol." },
        { text = "Te enteras por Discord de dónde vive otro personaje. ¿Puedes ir a buscarlo en el rol?", answer = 2,
          options = { "Sí, la información es pública", "No, eso es MG: tu personaje no lo sabe", "Sí, si llevas amigos", "Solo si es policía" },
          why = "Lo que sabes fuera del juego no lo sabe tu personaje. Usarlo es MetaGaming." },
    },
}
