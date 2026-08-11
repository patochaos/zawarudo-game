# ZAWARUDO — Documento de diseño de juego

> Documento vivo · Versión 0.1 · 10 de agosto de 2026

Este documento define la intención de diseño de **ZAWARUDO**. Su función no es
describir cómo está construido, sino ayudar a decidir qué conservar, qué cambiar
y qué ideas pertenecen al juego.

Las cifras concretas representan el estado actual y pueden cambiar con pruebas.
Los pilares y contratos de experiencia deben cambiar sólo de forma deliberada.

---

## 1. Visión

**ZAWARUDO es un duelo táctico 1 contra 1 en el que ambos combatientes detienen
el tiempo, componen una fracción breve de movimiento y un lanzamiento, y luego
observan cómo sus planes chocan dentro de un mundo que conserva todas las
consecuencias.**

La fantasía central no es simplemente «ser hábil con cuchillos». Es sentirse
como un duelista capaz de estudiar un instante imposible, preparar una jugada y
pronunciar una sentencia sobre el futuro. Cuando el tiempo vuelve, el jugador
ya no corrige: descubre si entendió bien la situación.

### Promesa al jugador

> **Detén el mundo. Lee el peligro. Compón 0,75 segundos. Fija tu destino.
> Observa cómo ambos planes colisionan.**

### Género y formato

- Duelo táctico 2D de vista lateral.
- Planificación simultánea por turnos y resolución física en tiempo real.
- Partidas cortas, al mejor de tres impactos.
- Un jugador contra IA, dos jugadores en local, o un todos-contra-todos de
  cuatro participantes con P1 humano y tres IAs independientes.
- Precisión, lectura espacial y anticipación por encima de la velocidad de
  reacción.

---

## 2. Experiencia objetivo

Una buena partida debería producir repetidamente estas sensaciones:

1. **Lectura:** «Veo el peligro suspendido y entiendo qué podría ocurrir».
2. **Autoría:** «Esta trayectoria, este salto y este momento de disparo son mi
   plan».
3. **Tensión:** «Ya confirmé; ahora no puedo corregirlo».
4. **Revelación:** «Eso es lo que realmente provocaron ambos planes».
5. **Consecuencia:** «La situación siguiente existe porque hicimos aquello».
6. **Relectura:** «Ahora el mismo espacio significa otra cosa».

El juego debe permitir que el jugador se sienta inteligente tanto al acertar
como al comprender, después del resultado, por qué su lectura falló.

### Emociones secundarias deseadas

- Asombro ante colisiones emergentes pero explicables.
- Temor frente a cuchillos que siguen vivos durante varios turnos.
- Satisfacción por ejecutar una jugada preparada con antelación.
- Alivio cuando dos amenazas se neutralizan entre sí.
- Picardía al utilizar rutas de portal, coberturas frágiles o el propio impulso.
- Espectáculo breve durante la resolución, seguido de silencio analítico.

---

## 3. Pilares de diseño

### 3.1 Planificar es pilotar

El jugador no selecciona una orden abstracta ni dibuja un destino. Controla una
versión fantasma de su luchador, registra una secuencia concreta y coloca el
lanzamiento en un punto exacto de esa secuencia.

Esto debe conservar la expresividad de un juego de plataformas —carrera, salto,
inercia, espera y puntería— sin convertir la fase decisiva en una prueba de
reflejos.

**Implicación:** las nuevas acciones deberían poder ensayarse, leerse y
comprometerse durante la planificación.

### 3.2 Compromiso antes de consecuencia

La resolución tiene valor porque llega después de renunciar al control. El
jugador estudia, confirma y luego observa. Permitir correcciones durante la
ejecución debilitaría la tensión y haría menos legible la relación entre plan y
resultado.

**Implicación:** la ejecución es una revelación, no una segunda fase de control.

### 3.3 El mundo recuerda

Posición, velocidad, cuchillos en vuelo y daño al escenario sobreviven al final
de una ventana. Un turno no limpia el tablero: añade historia física.

Una amenaza puede quedar suspendida durante varias planificaciones, ser
desviada, volver a chocar y cambiar el significado de una zona. La profundidad
surge de acumular consecuencias, no de acumular excepciones en las reglas.

**Implicación:** una mecánica nueva debería enriquecer el estado persistente o
interactuar con él, no vivir aislada como un minijuego.

### 3.4 Caos determinista y explicable

Las colisiones pueden parecer espectaculares o sorprendentes, pero el mismo
estado y los mismos planes deben producir el mismo desenlace. El jugador puede
estimar mal; no debería sentir que el juego cambió el resultado arbitrariamente.

**Implicación:** se favorecen sistemas físicos consistentes, señales claras y
variaciones deterministas. La aleatoriedad que decide un impacto contradice el
contrato táctico.

### 3.5 Información suficiente, no certeza total

El juego muestra el estado conocido, la ruta propia y referencias útiles sobre
los proyectiles. No promete revelar el resultado completo. El jugador debe
interpretar arcos, velocidades, coberturas y posibles intenciones rivales.

La interfaz responde «¿qué estoy intentando hacer?» y «¿qué peligros conozco?»,
no «¿qué ocurrirá exactamente?».

**Implicación:** mejorar legibilidad es deseable; automatizar la solución o
mostrar una predicción perfecta elimina la habilidad central.

### 3.6 Cada arena es una pregunta táctica

Los niveles no son decorados ni simples obstáculos. Cambian qué significa una
línea directa, cuándo conviene un arco alto, por dónde puede llegar una amenaza
y qué cobertura merece ser destruida.

**Implicación:** cada arena necesita una tesis propia y varias respuestas
viables. La geometría debe generar decisiones, no ruido visual.

---

## 4. Bucle principal

### 4.1 Leer el estado

El tiempo se detiene. El jugador inspecciona:

- posiciones y velocidades actuales;
- cuchillos suspendidos y su dirección;
- coberturas intactas, dañadas o destruidas;
- rutas directas, arcos y portales;
- puntuación, invulnerabilidad, SUPER y aparición del Núcleo Temporal;
- en multijugador local, el plan visible del rival.

### 4.2 Componer una intención

El jugador gasta un presupuesto limitado de movimiento para pilotar su fantasma.
Puede correr, saltar con altura variable, dejar pasar tiempo sin dirigir y
detenerse para cargar y apuntar. Puede efectuar una única descarga, fijada a un
momento de su ruta.

La porción no pilotada de la ventana sigue obedeciendo a impulso y gravedad. La
falta de control futura también forma parte del plan.

### 4.3 Confirmar

Cada jugador acepta su plan. Una breve pausa de compromiso separa claramente
«todavía puedo editar» de «esto va a ocurrir».

### 4.4 Ejecutar

El tiempo fluye durante una ráfaga breve. Ambos planes se reproducen a la vez;
jugadores, cuchillos y escenario resuelven sus interacciones sin intervención.

### 4.5 Heredar las consecuencias

El mundo vuelve a detenerse con su nuevo estado intacto. Si hubo impacto, la
víctima reaparece en la siguiente planificación con protección temporal. Si no
lo hubo, aumenta la presión hacia el Núcleo Temporal. El siguiente turno
comienza como lectura de las consecuencias del anterior.

---

## 5. Verbos y decisiones del jugador

| Verbo | Decisión que expresa |
|---|---|
| Leer | Qué amenazas son inmediatas y cuáles madurarán después. |
| Correr | Ganar posición a cambio de control disponible e inercia futura. |
| Saltar | Cambiar de altura, cruzar geometría o preparar un disparo, aceptando una trayectoria más comprometida. |
| Esperar | Consumir tiempo sin dirigir para sincronizar una caída o un lanzamiento. |
| Apuntar | Elegir ruta, altura y dirección de la amenaza. |
| Cargar | Intercambiar amplitud y control de espacio por velocidad y concentración. |
| Disparar | Fijar una descarga a un instante concreto de la ruta. |
| Confirmar | Renunciar voluntariamente a editar y aceptar la consecuencia. |
| Rehacer | Corregir la intención antes del compromiso, sin castigar la experimentación. |
| Activar SUPER | Convertir un recurso acumulado en una amenaza excepcional y anunciada. |

### Economía de una acción normal

- **Movimiento limitado:** obliga a elegir qué parte de la ventana merece
  control directo.
- **Una descarga por turno:** hace que momento, potencia y dirección importen.
- **Potencia variable:** baja potencia crea un abanico más lento y ancho para
  controlar espacio; alta potencia crea una línea rápida y estrecha.
- **Consecuencia inercial:** terminar de pilotar no detiene al personaje ni al
  mundo durante la ejecución.

---

## 6. Combate y resolución

### Condición de victoria

El primer combatiente que consigue tres impactos gana la partida. Cada impacto
es un punto; no reinicia el escenario ni elimina los proyectiles existentes.

### Filosofía del daño

- Los cuchillos son la única fuente de daño a combatientes.
- El terreno puede alterar posición y seguridad, pero no daña directamente.
- Un impacto retira a la víctima durante el resto de esa ventana para evitar
  cadenas poco legibles.
- La invulnerabilidad breve al reaparecer protege la continuidad de la partida
  sin borrar las amenazas persistentes.

### Cuchillos persistentes

Cada descarga normal lanza un abanico de dos cuchillos. Continúan existiendo
mientras sigan dentro del mundo y no hayan sido detenidos por una interacción
válida. Pueden:

- recorrer varias ventanas de ejecución;
- quedar suspendidos durante cada planificación;
- chocar con cuchillos rivales;
- desviarse, perder energía y girar;
- volver a chocar después de una desviación;
- dañar o destruir cobertura;
- convertirse en amenazas diferidas al caer.

La complejidad debe provenir de estas interacciones combinables. Se debe evitar
añadir tipos de proyectil que sólo introduzcan una regla aislada o una excepción
difícil de leer.

### Cobertura destructible

La cobertura temporal hace que el mapa evolucione durante la partida. Su estado
debe ser legible antes de comprometer un plan. Destruirla debería abrir líneas,
eliminar seguridad o provocar una caída interesante; no cerrar el juego ni
crear estancamiento.

Que una plataforma se rompa durante la ejecución puede invalidar la ruta que el
fantasma había previsto. Esta discrepancia es intencional: representa la
interferencia legítima del rival sobre un mundo compartido.

---

## 7. Ritmo de partida y mecanismos contra el estancamiento

El duelo permite paciencia, pero no debe premiar la pasividad indefinida. Dos
sistemas convierten los intercambios largos en presión creciente.

### SUPER

Los choques limpios entre cuchillos cargan el medidor cuando su propietario está
en movimiento. La regla une defensa y riesgo: protegerse activamente también
acerca una ofensiva futura.

Al llenarse, el jugador puede anunciar y preparar una descarga especial de
varias oleadas estrechas. La SUPER:

- es un clímax ganado, no una salida aleatoria;
- requiere decisión explícita antes del disparo;
- conserva las reglas fundamentales de trayectoria e interacción;
- puede ser desviada por cuchillos rivales;
- se gasta cuando empieza a dispararse, no al considerarse durante la
  planificación.

### Núcleo Temporal

Una secuencia de ventanas sin impacto anuncia y después materializa un objetivo
espacial temporal. Recogerlo llena la SUPER.

El Núcleo cumple tres funciones:

1. rompe posiciones estáticas;
2. crea un conflicto por territorio que no depende de acertar directamente;
3. transforma una partida prudente en una carrera hacia un clímax ofensivo.

Debe aparecer con anticipación suficiente para ser una decisión táctica y no un
premio fortuito.

---

## 8. Información, predicción y justicia

### Lo que el juego debe comunicar

- El plan propio y su parte controlada.
- El tramo posterior gobernado por inercia y gravedad.
- El punto y momento aproximado del disparo.
- Dirección, abanico y potencia de la descarga.
- Estado y velocidad de amenazas ya existentes.
- Estado de cobertura, puntuación, protección, SUPER y Núcleo.
- Transiciones inequívocas entre planificación, compromiso y ejecución.

### Lo que el juego no debe resolver por el jugador

- El punto final exacto de cada disparo como garantía.
- La respuesta futura del oponente en modos de información oculta.
- El desenlace completo de colisiones encadenadas.
- La «mejor» acción disponible.

### Modelos de información por modo

- **Contra IA:** la intención rival permanece oculta. La IA juega con las mismas
  reglas y estima posibles movimientos; no conoce el plan real del jugador.
- **Dos jugadores local:** la información es deliberadamente abierta. Como ambos
  comparten pantalla, el diseño convierte observar y contrarrestar el plan
  rival en parte del duelo, en vez de fingir secreto.
- **Juego libre:** elimina turnos, puntuación y presión para evaluar sensación de
  movimiento y lanzamiento. Es una herramienta de experimentación, no el modo
  que define la experiencia principal.

---

## 9. Diseño de arenas

### Principios comunes

- Amplio volumen de aire para que los cuchillos persistan y se acumulen.
- Geometría interior suficiente para crear rutas y negar tiros triviales.
- Al menos una solución de arco o ruta alternativa frente a la cobertura
  central.
- Apariciones sostenidas y sin impacto gratuito inmediato.
- Distribución de cuatro esquinas: P1/P2 abajo y P3/P4 en extremos superiores,
  nunca dos combatientes adyacentes sobre el mismo piso inicial.
- Una columna vertebral vertical permanente que conecte las apariciones bajas y
  altas aun después de destruir toda la cobertura temporal.
- Cobertura rompible fuera del corredor principal de lanzamiento, de modo que
  destruirla abra posibilidades.
- Diferenciación visual inmediata entre estructura permanente y cobertura
  temporal.
- Espacios para el Núcleo que expongan al jugador a decisiones reales.

### Tesis actuales

| Arena | Pregunta táctica principal |
|---|---|
| Shattered Sanctum | ¿Subo o bajo por las galerías de tres alturas para rodear el santuario y alcanzar el portal lateral elevado? |
| Flight | ¿Qué carril vertical uso alrededor del pilar cuando combatientes y cuchillos pueden regresar por ambos ejes? |

### Portales y continuidad espacial

Cuando un borde conecta con el opuesto, jugadores y cuchillos obedecen la misma
regla. El portal no es un teletransporte especial, sino continuidad del espacio.
Debe ofrecer dos rutas comprensibles hacia el rival, incluida una amenaza «por
la espalda», sin regalar impactos desde la aparición.

---

## 10. Identidad audiovisual

### Dirección visual

- Duelo sobrenatural y teatral, con fuerte contraste entre violeta, negro y oro.
- Siluetas pequeñas pero expresivas, legibles sobre fondos contenidos.
- El tiempo detenido debe sentirse distinto del tiempo activo, no sólo indicado
  por texto.
- Líneas, fantasmas y marcadores existen para explicar intención, no para llenar
  la pantalla.
- La fase de ejecución retira ayudas de planificación para devolver protagonismo
  al choque físico.

### Ritmo audiovisual

- **Planificación:** suspensión, análisis, tensión contenida.
- **Compromiso:** breve golpe de anticipación.
- **Ejecución:** liberación rápida, impactos nítidos, espectáculo concentrado.
- **Nueva congelación:** énfasis en el nuevo tablero y sus amenazas.

El audio debe priorizar acontecimientos con valor táctico: disparo, choque,
impacto, destrucción, aparición de objetivo y clímax de SUPER.

### Tono

Serio, estilizado y ligeramente grandilocuente. El juego puede abrazar el drama
de «detener el mundo» sin perder claridad competitiva.

---

## 11. Contratos de diseño

Estas reglas expresan la identidad actual. Cambiarlas puede ser válido, pero
equivale a revisar la visión del juego, no sólo a ajustar contenido.

1. Ambos planes se resuelven simultáneamente.
2. El jugador no interviene durante la ejecución.
3. El estado físico importante persiste entre ventanas.
4. La simulación es determinista bajo las mismas condiciones.
5. La planificación muestra la intención propia, no una garantía del resultado.
6. El rival puede interferir con una predicción válida mediante el mundo
   compartido.
7. Las mismas reglas espaciales importantes se aplican a ambos jugadores.
8. Una acción normal ofrece una descarga; su valor nace de dónde y cuándo se
   coloca.
9. El terreno cambia el duelo pero no sustituye al cuchillo como fuente de daño.
10. Los sistemas contra el estancamiento crean conflicto visible y anticipable.

---

## 12. Límites y antiobjetivos actuales

ZAWARUDO no intenta ser:

- un juego de acción basado principalmente en reflejos;
- una simulación con predicción perfecta y solución automática;
- un juego de azar donde una desviación aleatoria decide la partida;
- un juego de plataformas continuo con pausas tácticas ocasionales;
- un arsenal de muchas habilidades inconexas;
- un combate donde cada punto reinicia el tablero;
- un escenario recargado que entierra rápidamente todos los proyectiles;
- un multijugador local que finge ocultar información visible en la misma
  pantalla.

Estos límites son una defensa contra la pérdida gradual de identidad, no una
prohibición de experimentar.

---

## 13. Marco para tomar decisiones

Antes de incorporar una mecánica, arena, interfaz o cambio de reglas, puntuar de
0 a 2 cada criterio:

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Refuerza la fantasía de detener y componer el tiempo | No se relaciona | La acompaña | La hace más profunda |
| Crea una decisión legible | Añade ruido u obviedad | Depende del contexto | Genera alternativas con costes claros |
| Interactúa con el mundo persistente | Vive aislada | Tiene alguna interacción | Recombina varios sistemas existentes |
| Conserva autoría y justicia | Resultado arbitrario | Explicable con esfuerzo | Puede anticiparse y aprenderse |
| Mejora el ritmo del duelo | Lo ralentiza o trivializa | Impacto neutro | Aumenta tensión, revelación o relectura |

### Interpretación

- **8–10:** encaja con fuerza; prototipar y validar costes secundarios.
- **5–7:** idea prometedora, pero necesita una relación más clara con los
  pilares.
- **0–4:** probablemente pertenece a otro juego o resuelve un problema no
  demostrado.

Además de la puntuación, toda propuesta debe responder:

1. ¿Qué decisión nueva toma el jugador?
2. ¿Qué información necesita para tomarla?
3. ¿Cómo puede responder el rival?
4. ¿Qué consecuencia persiste en el siguiente turno?
5. ¿Qué comportamiento indeseado podría dominar si esta opción es óptima?
6. ¿Qué pilar se sacrifica y por qué vale la pena?

---

## 14. Criterios para ajustes de balance

Las cifras deben evaluarse por la experiencia que producen, no por simetría
matemática aislada.

### Planificación

Debe haber tiempo para leer, componer y corregir una vez, pero no tanto como
para eliminar la presión. Si los jugadores suelen confirmar de inmediato, puede
sobrar tiempo o faltar profundidad. Si vencen sin plan, puede faltar claridad o
tiempo.

### Ejecución

Debe ser suficientemente larga para que ocurra una consecuencia significativa y
suficientemente corta para que un plan siga siendo una unidad comprensible. Una
ventana demasiado larga diluye la autoría; una demasiado corta impide que el
mundo evolucione.

### Movimiento

El presupuesto debe obligar a elegir entre posición, altura y sincronización.
No debería permitir corregir todos los riesgos ni resultar tan escaso que la
mejor opción sea quedarse quieto.

### Proyectiles

La carga baja y la alta necesitan funciones distintas. Si una potencia domina
todas las distancias y situaciones, el sistema pierde una decisión. La
persistencia debe crear amenazas futuras sin saturar el tablero hasta volverlo
ilegible.

### SUPER y Núcleo

Deben aparecer lo bastante tarde para sentirse ganados, pero antes de que una
partida prudente pierda tensión. Su función principal es producir un clímax y
movimiento territorial, no garantizar un punto.

---

## 15. Preguntas de playtest

### Comprensión inicial

- ¿El jugador entiende que primero compone y después observa?
- ¿Distingue ruta pilotada, inercia posterior y punto de disparo?
- ¿Comprende por qué un cuchillo sigue presente en el turno siguiente?
- ¿Puede explicar una derrota sin atribuirla a azar invisible?

### Calidad de decisión

- ¿Existen al menos dos planes razonables en la mayoría de turnos?
- ¿Moverse, esperar y disparar en distintos momentos tienen utilidad real?
- ¿El jugador mira el estado del mundo antes de construir su ruta?
- ¿Las amenazas antiguas cambian decisiones futuras?
- ¿La información abierta en local produce contra-lectura interesante o parálisis?

### Ritmo y tensión

- ¿Cuánto tarda el jugador en confirmar y por qué?
- ¿La ejecución se observa con atención o se siente como un trámite?
- ¿Las ventanas sin impacto siguen generando progreso dramático?
- ¿El Núcleo obliga a abandonar una posición segura?
- ¿La SUPER crea un momento memorable sin decidir automáticamente la partida?

### Arenas

- ¿Puede el jugador describir la pregunta única de cada nivel?
- ¿Hay rutas o potencias dominantes que anulen el resto del espacio?
- ¿Romper cobertura abre decisiones o sólo elimina interés?
- ¿Los portales producen jugadas intencionales o impactos que parecen accidentes?

### Señales de alarma

- El jugador pide controlar durante la ejecución porque no entendió su plan.
- Gana sin mirar cuchillos suspendidos ni estado del escenario.
- Siempre dispara con la misma potencia y en el mismo momento.
- Evita moverse porque el riesgo supera cualquier recompensa.
- Una partida se decide por información que la interfaz no podía comunicar.
- El espectáculo visual oculta la causa del resultado.

---

## 16. Hipótesis abiertas

Estas cuestiones necesitan evidencia de juego, no una respuesta teórica:

1. ¿Cinco segundos de planificación producen presión productiva en jugadores
   nuevos y expertos?
2. ¿La información abierta del modo local genera un buen juego de contra-planes
   o incentiva esperar hasta el último instante?
3. ¿La estimación manual de trayectorias es satisfactoria o existe una brecha de
   comprensión demasiado grande al empezar?
4. ¿La acumulación de cuchillos alcanza un punto de saturación visual o táctica
   en partidas largas?
5. ¿El Núcleo aparece con suficiente frecuencia para evitar estancamiento sin
   desplazar el duelo de cuchillos?
6. ¿La condición de carga de SUPER por choque en movimiento se entiende y genera
   el comportamiento agresivo deseado?
7. ¿La cobertura destruida aumenta posibilidades o hace que el final de cada
   partida converja siempre en el mismo espacio abierto?
8. ¿Las arenas con portales son aprendibles mediante consistencia visual antes
   de exigir memorización?

Registrar cada sesión con observaciones relacionadas con estas hipótesis. No
cambiar una regla central por una reacción aislada: buscar patrones entre
jugadores, niveles de experiencia y arenas.

---

## 17. Resumen de decisión

Cuando haya dudas, priorizar en este orden:

1. **Claridad de causa y efecto.**
2. **Calidad de la decisión durante la planificación.**
3. **Persistencia e interacción entre consecuencias.**
4. **Tensión del compromiso y placer de la revelación.**
5. **Espectáculo audiovisual.**
6. **Cantidad de contenido.**

La pregunta rectora es:

> **¿Esta decisión hace más interesante leer un instante detenido, comprometer
> una intención y vivir con lo que ocurre cuando el tiempo vuelve?**

Si la respuesta es no, la idea necesita cambiar o no pertenece a ZAWARUDO.
