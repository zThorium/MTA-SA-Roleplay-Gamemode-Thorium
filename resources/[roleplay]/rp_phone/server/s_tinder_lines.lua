--[[
    rp_phone / s_tinder_lines.lua  (solo servidor)
    Frases del chat de los NPC de Tinder. Se escriben con ortografia correcta: el motor
    (s_tinder_npcs.lua) las "ensucia" segun como escribe cada persona (sin tildes, abreviaturas,
    risas, emojis, mayusculas), asi que una misma frase suena distinta en cada NPC.

    Grupos con lo / mid / hi = segun el interes que el NPC tiene en el jugador (bajo, medio, alto).
    Marcas: {p} nombre del jugador, {n} nombre del NPC, {o} terminacion del NPC (o/a),
    {pe} terminacion del jugador (o/a), {i1} {i2} gustos del NPC, {si} gusto compartido,
    {pi} gusto del jugador, {z} barrio, {c} ciudad, {job} trabajo, {age} edad, {now} lo que
    esta haciendo ahora, {seek} lo que busca, {spot} lugar de la cita, {num} su numero.
]]

TINDER_LINES = {
    -- Primer mensaje del NPC tras el match (si es de los que escriben primero)
    opener = {
        plain = { "Hola {p}! qué tal tu día?", "Holaa, me alegra el match 😊", "Hey {p}! cómo va todo?",
                  "Bueno, alguien tenía que escribir primero jaja. Hola!", "Hola! vi tu perfil y tenía que saludar",
                  "Holi {p} 👋", "Hola! qué tal? yo acá {now}" },
        interest = { "Vi que te gusta {si}! eso ya es un buen comienzo jaja", "Hola! alguien más a quien le gusta {si} 🙌 qué tal?",
                     "Ok, {si} en tu perfil = match automático jaja. Hola {p}!" },
        bio = { "Me hizo gracia tu bio jaja. Hola!", "Hola {p}, tu perfil me dio curiosidad. Cuéntame algo de ti" },
        player = { "Hola! me gustó que pusieras {pi} en tu perfil, desde cuándo te gusta?" },
    },

    greet = {
        lo = { "hola", "hola, qué tal", "hey" },
        mid = { "Hola {p}! qué tal?", "Holaa", "Hola! cómo estás?", "Hey! qué tal tu día?" },
        hi = { "Holaaa {p}! 😊", "Hola! justo pensaba en escribirte", "Hola hola! te estaba esperando jaja" },
    },
    greet_again = { "Hola de nuevo jaja", "Ya nos saludamos jaja", "Hola otra vez 😅" },

    howareyou = {
        lo = { "bien, {now}", "bien" },
        mid = { "Bien! acá {now}", "Todo bien, {now}. Y tú?", "Bien bien, {now}" },
        hi = { "Mejor ahora que me escribes jaja. Acá {now}", "Muy bien! {now}. Y tú, cómo estás?" },
    },
    askback = { "y tú?", "y tú qué tal?", "y tu día cómo va?", "tú qué cuentas?" },

    job = { "{jobtalk}", "{jobtalk}. Y tú a qué te dedicas?", "{jobtalk}. Tú qué haces?" },
    hobbies = { "Me encanta {i1} y {i2}, lo puedes ver en mi perfil jaja", "Sobre todo {i1}. También {i2}. Y a ti qué te gusta?",
                "Mi vida es {i1}, {i2} y dormir jaja" },
    zone = { "Vivo en {z}, en {c}. Y tú?", "En {z}! conoces?", "En {z}, {c}. Tú de dónde eres?" },
    age = { "{age}, sale en mi perfil jaja", "Tengo {age}. Y tú?", "{age} 😅 por?" },
    seek = { "{seek}", "Mmm {seek}. Y tú qué buscas?", "Sinceramente {seek}" },
    now = { "Acá {now}", "{now} jaja, y tú?", "Nada especial, {now}" },
    name = { "{n} jaja, sale en mi perfil 😅", "Me llamo {n}, mucho gusto {p}" },
    bot = { "jajaja no soy un bot", "un bot escribiría así de mal? jaja", "no 🙄 soy de carne y hueso, en {z}",
            "jaja todos preguntan lo mismo. Soy real, lo prometo" },
    thanks = { "de nada 😊", "nada que agradecer", "jaja de nada" },

    compliment = {
        lo = { "jaja gracias", "ok gracias", "gracias..." },
        mid = { "Jaja gracias 😊", "Ay gracias! tú también tienes lo tuyo jaja", "Qué lindo, gracias {p}" },
        hi = { "Me vas a hacer sonrojar 🙈", "Gracias! tú me gustaste desde la primera foto", "Ay {p}, así me vas a enamorar jaja" },
    },
    flirt = {
        bad = { "jaja tranqui, recién nos conocemos", "wow, vamos más lento", "mmm ok... 😅" },
        mid = { "jaja coquet{pe} 😏", "Me gusta por dónde va esto jaja", "Ah sí? cuéntame más 😏" },
        hi = { "Me encanta cuando me hablas así 😏", "Ya quiero conocerte en persona", "Cuidado que me la creo jaja" },
    },
    laugh = { "jajaja", "me muero 😂", "jajaja no puede ser", "jaja eres un caso", "jajaja me hiciste reír",
              "jaja ok ese estuvo bueno" },
    shared = { "{si}?? NO PUEDE SER, a mí también!!", "En serio te gusta {si}? por fin alguien!",
               "{si}? ok ya me caes bien jaja", "Ok, {si} en común. Esto va bien jaja", "Amo {si}! sabía que había algo jaja" },
    mention = { "Ah mira, {mi}. Yo no sé mucho de eso", "{mi}? cuéntame más, no sé nada de eso jaja" },
    about = {
        lo = { "ah ok", "ya", "mm ok" },
        mid = { "Qué bueno!", "Ah mira, me gusta eso", "Interesante jaja", "Qué buena!" },
        hi = { "Me encanta eso de ti", "Cada vez me caes mejor jaja", "Ok eso suma muchos puntos" },
    },
    vague = {
        lo = { "jaja", "ok", "ya", "ah" },
        mid = { "jaja sí", "ah mira", "jaja verdad", "jaja ya veo", "puede ser jaja" },
        hi = { "jaja me encanta hablar contigo", "jaja sí! totalmente", "jajaja eres lo máximo" },
    },
    question = { "mmm buena pregunta jaja", "eso te lo cuento en persona 😏", "jaja no sé qué responder a eso",
                 "difícil pregunta jaja, déjame pensarlo" },
    low_effort = { "...", "jaja ok", "y?", "mm", "eso es todo? jaja" },
    hola_only = { "hola, y?", "otro hola jaja", "se te acabaron las palabras? 😅" },
    rude = { "Qué asco. Chao.", "No me hables así. Adiós.", "Wow. No.", "Eso no se le dice a nadie. Chao." },
    too_fast = { "wow tranqui, recién nos conocemos", "eh... vamos más lento", "jaja no, calma" },

    date_accept = { "Dale! qué tal {spot}?", "Me encantaría! conoces {spot}? podríamos ir ahí",
                    "Sí! llevaba rato esperando que me lo pidieras jaja. Qué tal {spot}?",
                    "Ok me convenciste. {spot}?" },
    date_soon = { "jaja me gusta la idea, pero hablemos un poco más primero", "todavía no te conozco tanto, pero quizás pronto 😊",
                  "mmm dame un poco más de tiempo jaja" },
    date_no = { "mmm no sé, mejor no", "no creo, perdón", "jaja no, gracias" },
    number_give = { "Bueno, te paso mi número: {num}. Llámame cuando vayas para allá y nos vemos 😊",
                    "Toma, mi número: {num}. Llámame y te alcanzo donde estés",
                    "Mi número es {num}. Llámame cuando quieras que nos veamos" },
    number_soon = { "jaja todavía no, primero conozcámonos un poco más acá", "mi número se gana jaja", "pronto, quizás 😏" },
    number_given = { "Ya tienes mi número jaja, llámame", "Llámame al {num} cuando quieras vernos 😊" },
    npc_date = { "Oye, y si nos vemos en persona? me gustaría conocerte", "Ya hablamos harto por acá, no crees? vamos por algo",
                 "Te invito a {spot}. Qué dices?" },
    followup = { "Hola? jaja", "Sigues viv{pe}? 😅", "Te comió el lobo?", "Bueno, aquí sigo jaja", "Me dejaste en visto eh" },
    goodnight = { "Bueno, me voy a dormir. Hablamos mañana 😴", "Me caigo de sueño, mañana sigo. Buenas noches!",
                  "Me voy a dormir, que descanses 🌙" },

    -- Preguntas que hace el NPC para seguir la charla
    ask = {
        job = { "Y tú a qué te dedicas?", "En qué trabajas?", "Qué haces de la vida?" },
        weekend = { "Qué hiciste el fin de semana?", "Cuál sería tu plan perfecto un sábado?" },
        music = { "Qué música te gusta?", "Qué canción tienes pegada estos días?" },
        food = { "Cuál es tu comida favorita?", "Burger Shot o Cluckin' Bell? piénsalo bien jaja" },
        zone = { "De qué parte de San Andreas eres?", "Dónde vives?" },
        travel = { "Si pudieras ir a cualquier lado ahora mismo, dónde irías?", "Has ido a Las Venturas?" },
        pets = { "Tienes mascotas?", "Perros o gatos?" },
        seek = { "Y tú qué buscas por acá?", "Qué te trajo a Tinder?" },
        place = { "Cuál es tu lugar favorito de San Andreas?", "Dónde te gusta ir para despejarte?" },
        pi = { "Vi que te gusta {pi}, desde cuándo?", "Así que te gusta {pi}... cuéntame" },
    },
    ack = {
        lo = { "ah ok", "ok", "ya veo" },
        mid = { "Qué buena!", "Ah mira, me gusta", "Jaja buena respuesta", "Interesante" },
        hi = { "Me encanta eso", "Ok tenemos que hablar más de eso en persona", "Jaja eres justo mi tipo" },
    },
}

-- Palabras que activa cada intencion (texto sin tildes y en minusculas)
TINDER_INTENTS = {
    greet = { "^hola", "^holi", "^hey", "^buenas", "^wena", "^ola", "^hi$", "^hello", "^saludos", "^que tal$", "^buen dia", "^buenos dias", "^buenas noches" },
    howareyou = { "como estas", "como andas", "como te va", "como va", "que tal tu", "como estuvo tu", "todo bien%?", "como te fue" },
    job = { "a que te dedicas", "en que trabajas", "de que trabajas", "que haces de la vida", "que estudias", "donde trabajas", "tu trabajo" },
    hobbies = { "que te gusta hacer", "que te gusta", "hobbies", "hobby", "pasatiempo", "tiempo libre", "tus gustos" },
    zone = { "de donde eres", "donde vives", "de que parte", "por donde vives", "en que barrio", "eres de" },
    age = { "cuantos anos", "que edad", "edad tienes" },
    seek = { "que buscas", "que estas buscando", "buscas algo", "que quieres encontrar", "algo serio" },
    now = { "que haces%?", "que estas haciendo", "en que andas", "que haces ahora", "que hacias" },
    name = { "como te llamas", "tu nombre" },
    bot = { "eres un bot", "eres bot", "sos un bot", "eres real", "eres una ia", "inteligencia artificial", "eres npc", "%f[%a]npc%f[%A]" },
    thanks = { "gracias" },
    compliment = { "linda", "lindo", "guapa", "guapo", "hermosa", "hermoso", "bonita", "bonito", "preciosa", "precioso", "bella",
                   "que ojos", "tu sonrisa", "me encantas", "me gustas", "atractiv", "sexy", "bombon", "mamacita", "papacito" },
    flirt = { "beso", "besar", "carino", "mi amor", "bebe", "mi reina", "mi rey", "te imagino", "abrazo", "coquet" },
    rude = { "puta", "zorra", "perra", "pene", "verga", "tetas", "culo", "sexo", "coger", "follar", "chupa", "mamada", "desnud",
             "nudes", "pack", "maricon", "idiota", "estupid", "imbecil", "fea%f[%A]", "feo%f[%A]", "gorda", "gordo", "callate", "pendej", "mierda" },
    laugh = { "jaja", "jeje", "jsjs", "jiji", "lol", "xd", "😂", "🤣", "chiste" },
    date = { "salir conmigo", "quieres salir", "salgamos", "salimos", "una cita", "vernos", "juntarnos", "tomar algo", "un cafe", "ir a cenar", "te invito",
             "conocernos", "en persona", "quedamos", "nos juntamos" },
    number = { "numero", "whatsapp", "wsp", "telefono", "celular", "tu cel" },
    bye = { "^chao", "^adios", "buenas noches", "me voy a dormir", "hablamos manana", "nos hablamos" },
}
