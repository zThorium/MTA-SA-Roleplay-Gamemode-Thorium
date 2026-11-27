--[[
    rp_npcrel / server / s_lines.lua  (solo servidor)
    Banco de dialogos del sistema de vinculos. Solo lo usa el servidor (el cliente
    recibe la frase ya elegida), asi no se descarga ni se puede leer desde el juego.

    Marcas dentro de las frases (las sustituye s_npcrel.lua):
        {n}  nombre de pila de la persona        {p}  nombre de pila del jugador
        {o}  final segun el genero de la persona  (cansad{o} -> cansado / cansada)
        {e}  final segun el genero del jugador    (atrevid{e} -> atrevido / atrevida)

    Niveles de confianza (se eligen por etapa):
        lo  = Desconocido / Conocido      mid = Amigo / Coqueteo      hi = Pareja
    Un grupo puede ser una lista simple o una tabla { any = {...}, lo = {...}, mid = {...}, hi = {...} }:
    se mezclan "any" y el nivel actual.
]]

NPCREL_LINES = {}
local L = NPCREL_LINES

----------------------------------------------------------------
-- Saludos al abrir la conversacion
----------------------------------------------------------------
L.greet = {
    stranger = {
        "¿Sí? ¿Te puedo ayudar en algo?",
        "Hola… ¿nos conocemos?",
        "Eh, hola. ¿Pasa algo?",
        "¿Me hablas a mí? Hola.",
        "Hola, perdona, voy un poco apurad{o}… pero dime.",
        "¿Sí? Si buscas una dirección, no soy de por aquí.",
        "Hola. Qué raro, la gente aquí no suele saludar.",
        "Buenas. ¿Todo bien?",
    },
    known = {
        "¡Hola de nuevo! Te recuerdo.",
        "Ah, eres tú. ¡Hola, {p}!",
        "¡Qué casualidad encontrarte otra vez!",
        "Hola, {p}. ¿Qué tal te trata la ciudad?",
        "¡Ey! Ya me parecía conocida esa cara.",
        "Hola otra vez. ¿Vives por aquí cerca?",
    },
    friend = {
        "¡{p}! Justo estaba pensando en ti.",
        "¡Hola, amig{e}! ¿Qué cuentas?",
        "¡Ey, {p}! Qué bueno verte.",
        "¡Mira quién apareció! ¿Cómo estás?",
        "¡Hola! Tenía ganas de contarte algo.",
        "Ya era hora de que aparecieras, ¿eh?",
    },
    crush = {
        "Hola… qué sorpresa verte.",
        "Ay, hola, {p}. Justo hoy me arreglé un poco más.",
        "¡Hola! Me alegra mucho que me hables.",
        "Hola, {p}… ¿me estabas buscando?",
        "Vaya, qué casualidad. Bueno… o no tanto, ¿verdad?",
        "Hola. Ya te estaba echando de menos, la verdad.",
    },
    couple = {
        "¡Mi amor! Ven aquí.",
        "Hola, guap{e}. Te extrañé.",
        "¡{p}! Por fin. El día se me hizo eterno.",
        "Hola, cariño. ¿Cómo te fue hoy?",
        "Ahí estás. Ya me hacías falta.",
        "Hola, corazón. ¿Me invitas a algo o te invito yo?",
    },
    morning = {
        "Buenos días… todavía no me tomo el café, ten paciencia.",
        "¡Buenos días! Qué temprano andas.",
        "Buen día. Las mañanas en Los Santos son lo único tranquilo.",
    },
    night = {
        "¿Tú también de noche por aquí? Buenas noches.",
        "Buenas noches. A estas horas la ciudad es otra cosa.",
        "Hola… no esperaba encontrarme a nadie a estas horas.",
    },
    visit = {
        "¡Ya llegué! Me dijiste que viniera, ¿no?",
        "Aquí estoy. Vine lo más rápido que pude.",
        "¡Hola! Me alegró mucho que me llamaras.",
        "Bueno, ya estoy aquí. ¿Qué planes tenemos?",
        "Perdón la tardanza, el tráfico de esta ciudad es imposible.",
    },
    absent = {
        "¡Cuánto tiempo! Pensé que te habías olvidado de mí.",
        "Vaya, desapareciste varios días… ¿todo bien?",
        "Hola, extrañ{e}. Ya casi no te reconocía.",
        "Mira quién vuelve. Te escribí y no contestabas.",
    },
}

----------------------------------------------------------------
-- Lo que dice el jugador al elegir una accion (se muestra como "Tú:")
----------------------------------------------------------------
L.player = {
    talk = {
        any = { "¿Qué tal tu día?", "¿A qué te dedicas?", "Hace un calor tremendo hoy, ¿no?" },
        lo  = { "¿Eres de por aquí?", "Perdona, ¿tienes un minuto?", "¿Cómo está el barrio últimamente?" },
        mid = { "Cuéntame algo, ¿qué has hecho estos días?", "¿Supiste lo que pasó en Grove Street?", "¿Ya probaste el Cluckin' Bell nuevo?" },
        hi  = { "Cuéntame todo, ¿cómo te fue hoy?", "¿Te acuerdas de la primera vez que hablamos?", "¿Qué te gustaría hacer este fin de semana?" },
    },
    joke = {
        "¿Sabes por qué los taxis de Los Santos nunca llegan? Porque siempre hay una persecución en medio.",
        "Me dijeron que en San Fierro hay tanta niebla que los peces usan faros.",
        "Fui al gimnasio de Ganton. Bueno, pasé por fuera. Cuenta igual, ¿no?",
        "Mi auto es tan viejo que la radio solo agarra emisoras de 1992.",
        "Dicen que en Las Venturas hasta las palomas apuestan.",
        "Intenté cocinar ayer. Los bomberos ya me conocen por mi nombre.",
        "¿Qué le dijo un semáforo a otro? No me mires, que me estoy cambiando.",
        "Me compré un mapa de San Andreas y ahora sé exactamente dónde estoy perdid{e}.",
    },
    compliment = {
        any = { "Tienes una sonrisa muy bonita.", "Me encanta tu estilo.", "Hablar contigo me pone de buen humor." },
        lo  = { "Qué bien te queda esa ropa.", "Tienes buena vibra, se nota." },
        mid = { "Eres de las pocas personas sinceras que conozco.", "Tienes una forma de reír que contagia." },
        hi  = { "Cada día me gustas más.", "Eres lo mejor que me pasó en esta ciudad." },
    },
    flirt = {
        any = { "¿Siempre eres así de interesante o es solo hoy?", "Si sonríes así, voy a tener que quedarme más rato." },
        lo  = { "Perdona, pero tenía que hablarte. No te podía dejar pasar.", "¿Te han dicho que tienes una mirada peligrosa?" },
        mid = { "Me haces olvidar todo lo que iba a decir.", "Creo que ya sabes por qué vengo tanto por aquí." },
        hi  = { "Ven acá, que todavía no me das mi beso de hoy.", "Sigues poniéndome nervios{e}, como el primer día." },
    },
    gift = {
        "Te traje algo. Vi esto y pensé en ti.",
        "Toma, un pequeño detalle.",
        "Cierra los ojos… ahora ábrelos. Es para ti.",
        "No es gran cosa, pero lo escogí pensando en ti.",
    },
    hug = {
        "Ven, dame un abrazo.",
        "Me alegra mucho verte. ¡Abrazo!",
        "Necesito un abrazo de los buenos.",
    },
    number = {
        "¿Me pasas tu número? Así hablamos más seguido.",
        "Oye, ¿y si me das tu número?",
        "Me gustaría seguir hablando contigo. ¿Me das tu número?",
    },
    askout = {
        "Oye… ¿quieres salir conmigo? En serio.",
        "Ya no quiero ser solo tu amig{e}. ¿Salimos?",
        "Me gustas mucho. ¿Quieres ser mi pareja?",
    },
    kiss = {
        "Ven aquí…",
        "No digas nada.",
        "Me debes un beso.",
    },
    bye = {
        any = { "Bueno, me tengo que ir. Nos vemos.", "Fue un gusto hablar contigo." },
        hi  = { "Me voy, amor. Te llamo luego.", "Ya me voy… pero no me olvides." },
    },
}

----------------------------------------------------------------
-- Respuestas por accion: good (salio bien), great (salio muy bien), bad (salio mal)
----------------------------------------------------------------
L.talk = {
    good = {
        any = {
            "Pues ahí vamos, la ciudad está difícil pero se sobrevive.",
            "Me gusta cómo cuentas las cosas.",
            "¿En serio? No tenía idea. Cuéntame más.",
            "Ja, eso mismo pensaba yo el otro día.",
            "El calor de Los Santos me tiene derretid{o}, pero bien.",
            "Trabajando, como siempre. Algún día me tomo unas vacaciones en Las Venturas.",
            "Vi una persecución en la autopista esta mañana. Esta ciudad nunca se aburre.",
            "Ayer fui a la playa de Santa María. Había más gente que arena.",
        },
        lo = {
            "Soy de por aquí, sí. Bueno, de Ganton, pero casi lo mismo.",
            "No suelo hablar con desconocidos, pero pareces buena gente.",
            "Pues nada especial, haciendo mandados. ¿Y tú?",
            "Me mudé hace poco. Todavía me pierdo en estas calles.",
            "El barrio está tranquilo… dentro de lo que cabe.",
        },
        mid = {
            "¿Sabes qué? Contigo puedo hablar de cualquier cosa.",
            "Me pasó algo buenísimo esta semana, pero te lo cuento con un café.",
            "Mi jefe sigue igual de insoportable. Gracias por escucharme, en serio.",
            "Estoy pensando en aprender a manejar moto. ¿Me enseñarías?",
            "Siempre que hablamos se me pasa el tiempo volando.",
        },
        hi = {
            "Hoy fue largo, pero ahora que estás aquí ya no importa.",
            "Estuve pensando en nosotros. Me gusta lo que tenemos.",
            "Te guardé la mitad de mi sándwich. Bueno… un cuarto.",
            "¿Sabes que les hablo de ti a mis amigos? Ya están hartos.",
            "Algún día deberíamos irnos de viaje. Solo tú y yo.",
        },
    },
    great = {
        any = {
            "¡Hacía tiempo que no tenía una conversación así!",
            "¡Me encanta hablar contigo, de verdad!",
            "Podría quedarme aquí hablando horas.",
            "¡No puedo creer que pensemos tan parecido!",
        },
        hi = { "Eres mi persona favorita para hablar, ¿lo sabías?" },
    },
    bad = {
        "Eh… perdona, estaba distraíd{o}.",
        "Ajá… sí, sí. Perdón, ¿qué decías?",
        "Mmm. Bueno. No sé qué decirte a eso.",
        "Lo siento, hoy no tengo cabeza para charlar.",
        "Ah… ya. Qué interesante. Creo.",
    },
}

L.joke = {
    good = {
        "¡Jajaja! Qué bueno, no me lo esperaba.",
        "Ay, qué tont{e} eres. Pero me hiciste reír.",
        "Jaja, ese estuvo bueno. ¿Te lo inventaste tú?",
        "¡Jajaja! Ya, ya, me ganaste.",
        "Pfff… jajaja, ¡qué malo! Pero me río igual.",
        "Te voy a robar ese chiste, que lo sepas.",
        "Jaja, tienes un humor muy raro. Me gusta.",
    },
    great = {
        "¡Jajajaja! ¡Para, para, que me duele la panza!",
        "¡JAJAJA! Casi me ahogo, ¡no hagas eso!",
        "¡Me muero de risa! Hacía mucho que no me reía así.",
        "¡Jajaja! ¡Eres lo máximo!",
    },
    bad = {
        "Ehm… no entendí el chiste.",
        "Ja. Ja. Muy gracioso.",
        "¿Eso era un chiste? Ah.",
        "Creo que ese chiste ya lo escuché… en 1995.",
        "No me hizo gracia, la verdad. Perdona.",
    },
}

L.compliment = {
    good = {
        any = {
            "Ay, gracias, qué amable.",
            "Me haces sonrojar…",
            "Gracias, me alegraste el día.",
            "Vaya, no me lo esperaba. Gracias.",
            "Qué bonito lo que dices.",
        },
        lo = { "Gracias… eres muy amable con alguien que acabas de conocer." },
        mid = { "Tú siempre sabes qué decir.", "Viniendo de ti, vale el doble." },
        hi = { "Y tú eres lo más lindo que tengo.", "Ya me derretiste otra vez." },
    },
    great = {
        "Nadie me había dicho algo tan lindo en mucho tiempo.",
        "Ay… ahora no sé dónde meterme. ¡Gracias!",
        "Me lo voy a guardar en el corazón, de verdad.",
    },
    bad = {
        "Gracias… supongo.",
        "Ajá, eso se lo dices a todos, ¿no?",
        "Mmm. Qué frase tan ensayada.",
        "No hace falta que me adules.",
    },
}

L.flirt = {
    good = {
        any = {
            "Vaya, qué atrevid{e}. Me gusta.",
            "Sigue así y me vas a convencer…",
            "¿Ah, sí? Pues tú tampoco estás nada mal.",
            "Mira que me pongo nervios{o}…",
            "Eres un peligro, ¿lo sabías?",
        },
        lo = { "¿Y eso? Ni siquiera sabes mi nombre… es {n}, por cierto." },
        mid = { "Llevas días así. Y no me quejo.", "Me estás conquistando, y lo sabes." },
        hi = { "Todavía me pones nervios{o}, ¿cómo lo haces?", "Ven acá, coquet{e}." },
    },
    great = {
        "Uf… se me aceleró el corazón.",
        "¡Ay! Ya, me ganaste. Estoy roj{o} como un tomate.",
        "No me mires así que me derrito.",
    },
    bad = {
        "Oye, ¿qué te pasa? Tranquil{e}.",
        "Eso fue demasiado, ¿no crees?",
        "Uy, no. Así no.",
        "Ja, buen intento. No.",
        "Mejor bájale un poco, ¿eh?",
    },
}

L.gift = {
    good = {
        "¡No tenías que molestarte! Gracias.",
        "Qué detalle más lindo.",
        "¡Un regalo! ¿Y eso? Gracias.",
        "Me encanta que pienses en mí.",
        "Lo voy a guardar con cariño.",
    },
    great = {
        "¡Me encanta! No me lo esperaba para nada.",
        "¡Es justo lo que quería! ¿Cómo lo supiste?",
        "¡Eres increíble! Ven, déjame darte las gracias como se debe.",
    },
    bad = {
        "Ehm… gracias, supongo.",
        "Ah… otro de estos. Gracias.",
        "No hacía falta, de verdad. No me gusta recibir regalos de cualquiera.",
    },
}

L.hug = {
    good = {
        any = { "Qué abrazo más cálido.", "Necesitaba esto, gracias.", "Tus abrazos son de los buenos." },
        hi = { "Me quedaría aquí todo el día.", "Aquí es donde me siento en casa." },
    },
    great = {
        "No me sueltes todavía…",
        "Ese abrazo me arregló la semana.",
        "Gracias. De verdad lo necesitaba.",
    },
    bad = {
        "Mejor no, ¿vale? Aún no hay tanta confianza.",
        "Uy… mejor la próxima.",
        "Eh… no soy mucho de abrazos.",
    },
}

L.kiss = {
    good = {
        "Mmm… ¿otra vez?",
        "Me encanta cuando haces eso.",
        "Eso no me lo esperaba… pero me gustó.",
        "Ahora sí empezó bien el día.",
    },
    great = {
        "Podría quedarme así todo el día.",
        "Wow… todavía me tiemblan las piernas.",
        "Ese fue el mejor beso de mi vida.",
    },
    bad = {
        "Ahora no, de verdad.",
        "Aquí no, nos está mirando todo el mundo.",
        "Hoy no estoy de humor, perdona.",
    },
}

L.number = {
    good = {
        "Está bien, apunta mi número. Llámame.",
        "Claro, toma. Pero no me llames a las tres de la mañana.",
        "Aquí tienes. Más te vale escribirme.",
        "Va. Te lo doy, pero no lo pierdas.",
    },
    bad = {
        "Mmm, todavía no te conozco lo suficiente.",
        "Perdona, no le doy mi número a cualquiera.",
        "Quizás otro día, cuando nos conozcamos mejor.",
        "Uy, no. Mejor no.",
    },
    have = {
        "Ya tienes mi número, bob{e}.",
        "¡Pero si ya lo tienes! Llámame cuando quieras.",
        "¿Otra vez? Revisa tus contactos, está ahí.",
    },
}

L.askout = {
    great = {
        "Sí. Sí quiero. ¡Salgamos!",
        "¡Pensé que nunca me lo ibas a pedir! ¡Sí!",
        "¿En serio? ¡Claro que sí!",
        "Llevaba semanas esperando que me lo dijeras. Sí.",
    },
    bad = {
        "Me caes muy bien, pero aún no… dame tiempo.",
        "Es muy pronto, ¿no crees? Vamos con calma.",
        "Necesito pensarlo un poco más. No te enojes.",
    },
}

L.bye = {
    good = {
        any = { "Cuídate, ¡hablamos!", "Nos vemos por ahí.", "¡Chao! Que te vaya bien." },
        lo  = { "Bueno, un gusto. Adiós.", "Ok, nos vemos." },
        mid = { "¡Escríbeme, eh! No desaparezcas.", "Me alegró verte. ¡Hasta pronto!" },
        hi  = { "Te quiero. Avísame cuando llegues.", "Ya te estoy extrañando.", "Un beso, mi amor. Llámame." },
    },
}

----------------------------------------------------------------
-- Situaciones especiales
----------------------------------------------------------------
L.tired = {
    any = {
        "Tengo que irme, me esperan. Llámame luego.",
        "Uy, mira la hora. Me tengo que ir.",
        "Me encantaría seguir, pero tengo cosas que hacer.",
    },
    hi = { "Me voy, amor, que llego tarde. Hablamos luego." },
}

L.repeat_ = {
    "Eso ya me lo dijiste hace un rato…",
    "Ya, ya, tranquil{e}, no repitas lo mismo.",
    "¿Eres disco rayado o qué?",
    "Cambia de tema, que me aburro.",
}

L.notInterested = {
    "Eres una buena persona, pero solo te veo como amig{e}.",
    "Lo siento, no busco eso contigo.",
    "Me caes bien, pero no me gustas de esa forma.",
    "Mejor quedemos como amigos, ¿sí?",
}

-- Al subir de etapa (por numero de etapa nueva)
L.stageUp = {
    [2] = { "Oye, me caes bien. Me acordaré de ti.", "Bueno, ya no eres un desconocid{e}. Un gusto." },
    [3] = { "¿Sabes? Creo que ya somos amigos de verdad.", "Me alegra mucho haberte conocido, {p}." },
    [4] = { "No sé qué me pasa contigo, pero me gusta…", "Creo que me estás empezando a gustar." },
    [5] = { "Somos pareja… ¡qué bonito suena!", "No te imaginas lo feliz que estoy." },
    [6] = { "Contigo me veo a largo plazo, {p}.", "Eres mi lugar seguro. Te quiero." },
}

-- Rasgos: a veces la reaccion sale con el caracter de la persona (cualquier accion)
L.traits = {
    romantica = {
        good = { "Ay, esto es como en las películas.", "Me encantan estos momentos." },
        bad  = { "Esperaba algo más… especial." },
    },
    timida = {
        good = { "Eh… je, gracias… no sé qué decir.", "Me da un poco de vergüenza, pero me gustó." },
        bad  = { "Eh… me pones nervios{o}… mejor no." },
    },
    fiestera = {
        good = { "¡Eso merece celebrarse! Un día salimos de noche por Las Venturas.", "¡Me encanta tu energía!" },
        bad  = { "Qué aburrido, despierta un poco." },
    },
    ambiciosa = {
        good = { "Me gusta la gente que sabe lo que quiere.", "Tú vas a llegar lejos, se nota." },
        bad  = { "Mmm. Esperaba más de ti, la verdad." },
    },
    seria = {
        good = { "Está bien. Me gusta la gente que habla claro.", "Valoro eso, de verdad." },
        bad  = { "No me gustan los juegos. Ve al grano." },
    },
    amable = {
        good = { "Eres un sol, ¿lo sabías?", "Qué bonito que existan personas como tú." },
        bad  = { "No pasa nada, otro día será." },
    },
}

-- Telefono
L.phonePickup = {
    any = { "¡Hola! Voy para allá, dame un momento.", "¡Hey! Claro, ya salgo para allá." },
    mid = { "¡Qué bueno que llamas! Voy volando.", "¿Me extrañabas? Ya voy." },
    hi  = { "¡Amor! Voy para allá ahora mismo.", "Ya me estoy arreglando, llego en nada." },
}
L.phoneNoAnswer = {
    "{n} no contesta.",
    "Suena y suena… {n} no contesta.",
    "Te sale el buzón de voz de {n}.",
}
