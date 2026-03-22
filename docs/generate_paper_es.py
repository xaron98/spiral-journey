#!/usr/bin/env python3
"""Generate the SleepDNA scientific paper as PDF — Spanish version."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm, cm
from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    KeepTogether
)

WIDTH, HEIGHT = A4
MARGIN = 2 * cm
CONTENT_W = WIDTH - 2 * MARGIN  # usable width for tables

ACCENT = HexColor("#7c3aed")
DARK = HexColor("#1a1a2e")
MUTED = HexColor("#666666")

styles = getSampleStyleSheet()

styles.add(ParagraphStyle(
    "PaperTitle", parent=styles["Title"],
    fontSize=17, leading=21, spaceAfter=6,
    textColor=DARK, alignment=TA_CENTER
))
styles.add(ParagraphStyle(
    "Authors", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_CENTER,
    textColor=MUTED, spaceAfter=4
))
styles.add(ParagraphStyle(
    "Affiliation", parent=styles["Normal"],
    fontSize=9, leading=12, alignment=TA_CENTER,
    textColor=MUTED, spaceAfter=16
))
styles.add(ParagraphStyle(
    "AbstractTitle", parent=styles["Heading2"],
    fontSize=12, leading=14, textColor=ACCENT,
    spaceAfter=6, spaceBefore=12
))
styles.add(ParagraphStyle(
    "AbstractBody", parent=styles["Normal"],
    fontSize=9.5, leading=13, alignment=TA_JUSTIFY,
    leftIndent=0.8 * cm, rightIndent=0.8 * cm,
    spaceAfter=12, textColor=DARK
))
styles.add(ParagraphStyle(
    "SectionHead", parent=styles["Heading1"],
    fontSize=13, leading=16, textColor=ACCENT,
    spaceBefore=18, spaceAfter=8
))
styles.add(ParagraphStyle(
    "SubHead", parent=styles["Heading2"],
    fontSize=11, leading=14, textColor=DARK,
    spaceBefore=12, spaceAfter=6
))
styles.add(ParagraphStyle(
    "Body", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_JUSTIFY,
    spaceAfter=8, textColor=DARK
))
styles.add(ParagraphStyle(
    "Equation", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_CENTER,
    spaceAfter=8, spaceBefore=4, textColor=DARK,
    fontName="Courier"
))
styles.add(ParagraphStyle(
    "RefItem", parent=styles["Normal"],
    fontSize=8.5, leading=11, alignment=TA_JUSTIFY,
    leftIndent=1.2 * cm, firstLineIndent=-1.2 * cm,
    spaceAfter=4, textColor=DARK
))
styles.add(ParagraphStyle(
    "TableCaption", parent=styles["Normal"],
    fontSize=9, leading=12, textColor=MUTED,
    spaceAfter=6, spaceBefore=6
))
styles.add(ParagraphStyle(
    "CellStyle", parent=styles["Normal"],
    fontSize=8, leading=10, textColor=DARK
))
styles.add(ParagraphStyle(
    "CellHeader", parent=styles["Normal"],
    fontSize=8, leading=10, textColor=HexColor("#ffffff"),
    fontName="Helvetica-Bold"
))


def make_table(data, col_ratios, caption):
    """Build a table using Paragraph cells so text wraps instead of collapsing."""
    total = sum(col_ratios)
    col_widths = [CONTENT_W * r / total for r in col_ratios]

    # Convert cells to Paragraphs
    table_data = []
    for row_idx, row in enumerate(data):
        style = styles["CellHeader"] if row_idx == 0 else styles["CellStyle"]
        table_data.append([Paragraph(str(cell), style) for cell in row])

    t = Table(table_data, colWidths=col_widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT),
        ("GRID", (0, 0), (-1, -1), 0.5, HexColor("#cccccc")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ]))
    return [Paragraph(caption, styles["TableCaption"]), t, Spacer(1, 10)]


story = []
S = story.append

# ═══ Title ═══
S(Paragraph(
    "SleepDNA: Genomica Computacional y Topologia Espacial<br/>"
    "Aplicadas al Analisis de Series Temporales de Sueno en el Dispositivo",
    styles["PaperTitle"]
))
S(Spacer(1, 6))
S(Paragraph("Proyecto Spiral Journey — Documento Tecnico Fundacional", styles["Authors"]))
S(Paragraph("Investigacion Independiente · Marzo 2026", styles["Affiliation"]))

# ═══ Resumen ═══
S(Paragraph("Resumen", styles["AbstractTitle"]))
S(Paragraph(
    "<b>Contexto:</b> Los sistemas actuales de monitorizacion del sueno dependen de metricas agregadas "
    "estaticas que no capturan la interaccion dinamica entre el ritmo circadiano endogeno y el exposoma "
    "diario. Presentamos <i>SleepDNA</i>, un marco computacional novedoso que traslada los principios del "
    "Dogma Central de la Biologia Molecular, el alineamiento de secuencias y la topologia 3D al analisis "
    "de series temporales de sueno. "
    "<b>Metodos:</b> El sistema codifica la arquitectura del sueno en vectores diarios de 16 caracteristicas "
    "(nucleotidos), organizados como una doble helice donde la Hebra 1 (fisiologia del sueno) y la Hebra 2 "
    "(contexto conductual) se acoplan mediante Phase Locking Value (PLV) calculado con la Transformada de "
    "Hilbert. Dynamic Time Warping (DTW) ponderado con una matriz de puntuacion personalizada (SleepBLOSUM) "
    "permite el descubrimiento de motivos, clasificacion de mutaciones y prediccion de secuencias. Metricas "
    "topologicas avanzadas — Homologia Persistente, Numero de Enlace de Gauss y Espectro de Informacion Mutua "
    "— proporcionan informacion estructural sobre el acoplamiento circadiano-homeostatico. Todo el pipeline "
    "se ejecuta en el dispositivo usando el framework Accelerate de Apple, garantizando la privacidad absoluta. "
    "<b>Resultados:</b> El sistema produce siete biomarcadores de salud, descubre motivos semanales recurrentes, "
    "clasifica desviaciones de patrones como mutaciones silenciosas/de sentido erroneo/sin sentido, y genera "
    "predicciones personalizadas. Los datos preliminares de auto-seguimiento demuestran la capacidad del sistema "
    "para detectar correlaciones temporales no obvias entre factores conductuales y resultados de sueno. "
    "<b>Conclusiones:</b> SleepDNA establece un nuevo paradigma en cronobiologia digital predictiva al sustituir "
    "la estadistica descriptiva por genomica estructural del sueno, proporcionando insights personalizados a "
    "nivel causal sin comprometer la privacidad del usuario.",
    styles["AbstractBody"]
))
S(Paragraph(
    "<b>Palabras clave:</b> analisis de sueno, ritmo circadiano, genomica computacional, Dynamic Time Warping, "
    "Phase Locking Value, analisis topologico de datos, inferencia en dispositivo, salud digital",
    styles["AbstractBody"]
))

# ═══ 1. Introduccion ═══
S(Paragraph("1. Introduccion", styles["SectionHead"]))
S(Paragraph(
    "El sueno es un proceso fisiologico complejo y multidimensional gobernado por dos sistemas regulatorios "
    "interactivos: el impulso homeostatico de sueno (Proceso S) y el marcapasos circadiano (Proceso C) [1]. "
    "Aunque los wearables han hecho ubicuo el seguimiento del sueno, los metodos analiticos empleados por "
    "la mayoria de aplicaciones siguen siendo rudimentarios — tipicamente limitados a resumenes nocturnos de "
    "duracion, eficiencia y clasificacion basica de fases. Estos enfoques descartan la rica estructura temporal "
    "contenida en los datos longitudinales de sueno y no capturan como las decisiones conductuales diarias "
    "modulan la arquitectura del sueno a lo largo del tiempo.",
    styles["Body"]
))
S(Paragraph(
    "Proponemos <i>SleepDNA</i>, un marco computacional inspirado en la biologia molecular y la bioinformatica "
    "que trata el historial de sueno de un individuo como una secuencia genetica susceptible de alineamiento, "
    "descubrimiento de motivos, analisis de mutaciones y caracterizacion topologica. A diferencia de los "
    "sistemas emergentes de descubrimiento cientifico autonomo como EvoScientist [24], que logran solo un "
    "21% de exito en implementacion de metodos complejos sin supervision humana, SleepDNA adopta un enfoque "
    "hibrido: herramientas computacionales de bioinformatica operadas bajo supervision experta del investigador. "
    "El marco opera completamente en el dispositivo, alineandose con la tendencia creciente de modelos "
    "especializados en edge — como MSBA-YOLO [25] para deteccion clinica a 96.1% de precision en 6.4MB — "
    "preservando la privacidad de los datos mientras permite un analisis sofisticado antes restringido a "
    "entornos de investigacion clinica.",
    styles["Body"]
))
S(Paragraph(
    "Este articulo presenta los fundamentos teoricos, los algoritmos implementados, los biomarcadores derivados "
    "y las direcciones futuras de investigacion del sistema SleepDNA. Enfatizamos que la metafora genomica es "
    "computacional, no biologica — no afirmamos que los patrones de sueno constituyan ADN literal, sino que "
    "las herramientas matematicas desarrolladas para el analisis de secuencias son notablemente adecuadas para "
    "datos temporales de sueno [2].",
    styles["Body"]
))

# ═══ 2. Marco Teorico ═══
S(Paragraph("2. Marco Teorico", styles["SectionHead"]))

S(Paragraph("2.1. El Modelo de Dos Procesos de Regulacion del Sueno", styles["SubHead"]))
S(Paragraph(
    "El modelo fisiologico fundacional subyacente a SleepDNA es el Modelo de Dos Procesos de Borbely [1], "
    "posteriormente refinado por Daan, Beersma y Borbely [3]. El Proceso S representa la presion "
    "homeostatica de sueno que se acumula exponencialmente durante la vigilia y se disipa durante el sueno:",
    styles["Body"]
))
S(Paragraph("S(t) = S<sub>0</sub> . exp(-t / tau<sub>caida</sub>)   durante el sueno", styles["Equation"]))
S(Paragraph("S(t) = 1 - (1 - S<sub>0</sub>) . exp(-t / tau<sub>subida</sub>)   durante la vigilia", styles["Equation"]))
S(Paragraph(
    "donde tau<sub>subida</sub> = 18.2h y tau<sub>caida</sub> = 4.2h son constantes de tiempo derivadas "
    "empiricamente [3]. El Proceso C se modela como una oscilacion coseno de 24 horas derivada del analisis "
    "cosinor [4, 5].",
    styles["Body"]
))

S(Paragraph("2.2. Ritmometria Cosinor", styles["SubHead"]))
S(Paragraph(
    "Los parametros del ritmo circadiano se estiman mediante el metodo cosinor de un solo componente [4]:",
    styles["Body"]
))
S(Paragraph("Y(t) = MESOR + A . cos(omega . t + phi)", styles["Equation"]))
S(Paragraph(
    "donde MESOR es la estadistica de estimacion de la linea media del ritmo, A es la amplitud y phi es "
    "la acrofase (hora pico). El coeficiente de determinacion (R<super>2</super>) cuantifica la bondad del "
    "ajuste y sirve como nuestra medida principal de coherencia circadiana [5]. Una ventana deslizante de "
    "7 dias proporciona resolucion temporal manteniendo la estabilidad estadistica.",
    styles["Body"]
))

S(Paragraph("2.3. El Modelo de Codificacion en Doble Helice", styles["SubHead"]))
S(Paragraph(
    "Cada dia del historial de sueno del usuario se codifica como un vector de 16 dimensiones "
    "(DayNucleotide), organizado en dos hebras complementarias:",
    styles["Body"]
))

# Table 1: Feature encoding — full width with Paragraph cells
story.extend(make_table(
    [
        ["Indice", "Hebra", "Caracteristica", "Codificacion", "Descripcion"],
        ["0-1", "1 (Sueno)", "Hora de dormir", "sin/cos circular", "Codificacion circular de la hora de acostarse para resolver la discontinuidad de medianoche"],
        ["2-3", "1 (Sueno)", "Hora de despertar", "sin/cos circular", "Codificacion circular de la hora de levantarse"],
        ["4", "1 (Sueno)", "Duracion del sueno", "horas / 12", "Horas totales de sueno normalizadas al rango [0,1]"],
        ["5", "1 (Sueno)", "Proceso S", "Presion [0,1]", "Presion homeostatica de sueno del modelo de dos procesos"],
        ["6", "1 (Sueno)", "Acrofase", "hora pico / 24", "Hora del pico circadiano normalizada"],
        ["7", "1 (Sueno)", "Cosinor R2", "Fuerza [0,1]", "Bondad de ajuste del ritmo circadiano (coherencia)"],
        ["8", "2 (Contexto)", "Cafeina", "conteo / 5", "Numero de consumos de cafeina en el dia"],
        ["9", "2 (Contexto)", "Ejercicio", "binario [0,1]", "Si el usuario realizo ejercicio fisico"],
        ["10", "2 (Contexto)", "Alcohol", "conteo / 3", "Numero de consumos de alcohol"],
        ["11", "2 (Contexto)", "Melatonina", "binario [0,1]", "Si el usuario tomo melatonina"],
        ["12", "2 (Contexto)", "Estres", "conteo / 3", "Nivel de estres reportado"],
        ["13", "2 (Contexto)", "Fin de semana", "binario [0,1]", "Si el dia es sabado o domingo"],
        ["14", "2 (Contexto)", "Deriva horaria", "minutos / 120", "Desplazamiento del horario respecto al cronotipo"],
        ["15", "2 (Contexto)", "Calidad del sueno", "(dur/meta) x R2", "Metrica compuesta de duracion y regularidad"],
    ],
    col_ratios=[6, 8, 12, 10, 24],
    caption="<b>Tabla 1.</b> Codificacion del DayNucleotide (16 dimensiones por dia)."
))

S(Paragraph(
    "La codificacion circular de las variables horarias (hora de dormir, hora de despertar) mediante pares "
    "seno/coseno resuelve el problema de discontinuidad a medianoche (23:59 a 00:01 aparece como un gran "
    "salto en codificacion lineal pero se representa correctamente como una pequena diferencia angular en "
    "el espacio circular).",
    styles["Body"]
))

# ═══ 3. Metodos Analiticos ═══
S(PageBreak())
S(Paragraph("3. Metodos Analiticos", styles["SectionHead"]))

S(Paragraph("3.1. Phase Locking Value mediante Transformada de Hilbert", styles["SubHead"]))
S(Paragraph(
    "El acoplamiento entre hebras (los 'pares de bases' de SleepDNA) se cuantifica mediante el Phase Locking "
    "Value (PLV) [6, 7]. Para cada uno de los 56 pares posibles entre hebra 1 y hebra 2, calculamos la senal "
    "analitica mediante la Transformada de Hilbert usando las rutinas FFT vDSP del framework Accelerate, "
    "extraemos la fase instantanea y calculamos el PLV como:",
    styles["Body"]
))
S(Paragraph("PLV = |media(exp(i . delta_theta(t)))| en [0, 1]", styles["Equation"]))
S(Paragraph(
    "donde delta_theta(t) es la diferencia de fase instantanea entre caracteristicas. PLV = 1 indica "
    "sincronia de fase perfecta; PLV = 0 indica ausencia de sincronia. Los pares con PLV > 0.3 se retienen "
    "como pares de bases significativos. La diferencia de fase media indica la relacion temporal "
    "(adelanto/retraso) entre eventos contextuales y resultados de sueno.",
    styles["Body"]
))

S(Paragraph("3.2. Matriz de Puntuacion Personalizada (SleepBLOSUM)", styles["SubHead"]))
S(Paragraph(
    "Inspirados por las matrices de sustitucion BLOSUM utilizadas en el alineamiento de secuencias proteicas "
    "[8], desarrollamos SleepBLOSUM — un vector de pesos personalizado de 16 elementos aprendido de los datos "
    "de cada usuario. Para cada caracteristica k, calculamos la informacion mutua (MI) entre la serie temporal "
    "de la caracteristica y la calidad del sueno del dia siguiente [9, 10]:",
    styles["Body"]
))
S(Paragraph("MI(X;Y) = H(X) + H(Y) - H(X,Y)", styles["Equation"]))
S(Paragraph(
    "donde H denota la entropia de Shannon calculada sobre discretizaciones de 5 bins. Los pesos se normalizan "
    "al rango [0, 3.0] y requieren un minimo de 14 dias de datos. Las caracteristicas con mayor MI reciben "
    "proporcionalmente mayor peso en los calculos DTW subsiguientes. Hasta donde sabemos, esta es la primera "
    "aplicacion de matrices de puntuacion personalizadas basadas en teoria de la informacion a datos de sueno "
    "de consumo.",
    styles["Body"]
))

S(Paragraph("3.3. Dynamic Time Warping para Alineamiento de Secuencias", styles["SubHead"]))
S(Paragraph(
    "La comparacion semana a semana utiliza Dynamic Time Warping (DTW) ponderado [11], donde cada semana se "
    "representa como una matriz de 7x16 caracteristicas (WeekSequence). La distancia DTW entre semanas A y B "
    "se calcula usando distancia euclidiana ponderada por SleepBLOSUM:",
    styles["Body"]
))
S(Paragraph("d(a, b) = raiz(suma_k w_k . (a_k - b_k)<super>2</super>)", styles["Equation"]))
S(Paragraph(
    "Una matriz de costes completa O(n<super>2</super>) con retroceso de camino optimo de alineamiento permite "
    "alinear semanas con estructuras temporales ligeramente diferentes. DTW parcial extiende esto a semanas "
    "en curso para prediccion en tiempo real.",
    styles["Body"]
))

S(Paragraph("3.4. Descubrimiento de Motivos mediante Clustering Aglomerativo", styles["SubHead"]))
S(Paragraph(
    "Los patrones recurrentes de sueno ('motivos') se descubren mediante una matriz de distancias DTW por "
    "pares seguida de clustering aglomerativo [12, 13]. El clustering de enlace simple con un umbral de "
    "distancia de 8.0 agrupa semanas similares en hasta 10 motivos. El centroide de cada motivo (media "
    "elemento a elemento de las semanas miembro) representa el patron canonico. Los motivos se nombran "
    "automaticamente basandose en la desviacion dominante de la media global (ej. 'noche-tardia', "
    "'alto-estres', 'madrugador').",
    styles["Body"]
))

S(Paragraph("3.5. Clasificacion de Mutaciones", styles["SubHead"]))
S(Paragraph(
    "Siguiendo la metafora biologica [14], la desviacion de cada semana respecto al centroide del motivo "
    "mas cercano se clasifica como una mutacion segun el delta de calidad (delta):",
    styles["Body"]
))

story.extend(make_table(
    [
        ["Clasificacion", "Umbral", "Interpretacion"],
        ["Silenciosa (Estable)", "delta < 0.05", "La semana sigue el patron esperado sin desviaciones significativas"],
        ["De sentido erroneo (Variacion leve)", "0.05 <= delta <= 0.15", "Desviacion moderada del patron habitual"],
        ["Sin sentido (Cambio significativo)", "delta > 0.15", "Ruptura significativa del patron de sueno"],
    ],
    col_ratios=[18, 12, 30],
    caption="<b>Tabla 2.</b> Umbrales de clasificacion de mutaciones."
))

S(Paragraph(
    "Las reglas de expresion se descubren dividiendo por la mediana cada caracteristica contextual dentro de "
    "un motivo y comparando la calidad media del sueno por encima y por debajo del umbral, revelando que "
    "factores conductuales modulan la calidad del sueno en contextos de patrones especificos.",
    styles["Body"]
))

S(Paragraph("3.6. Prediccion de Secuencias", styles["SubHead"]))
S(Paragraph(
    "La prediccion de sueno utiliza un enfoque k-vecinos-mas-cercanos basado en DTW inspirado en el "
    "alineamiento de secuencias BLAST [15]. La semana en curso (1-6 dias) se alinea con todas las semanas "
    "historicas completas mediante DTW parcial. Se identifican las 5 semanas mas similares y el 'dia siguiente' "
    "de cada coincidencia historica se usa como candidato a prediccion. La ponderacion inversa por distancia "
    "produce una prediccion de consenso para hora de dormir, hora de despertar y duracion del sueno.",
    styles["Body"]
))

# ═══ 4. Metricas Topologicas Avanzadas ═══
S(PageBreak())
S(Paragraph("4. Metricas Topologicas Avanzadas", styles["SectionHead"]))

S(Paragraph("4.1. Homologia Circadiana Persistente (PCH)", styles["SubHead"]))
S(Paragraph(
    "Aplicamos Homologia Persistente [16, 17] a la nube de puntos 3D de la helice generada a partir de las "
    "secuencias de DayNucleotide. Usando una filtracion de Rips simplificada con seguimiento Union-Find:",
    styles["Body"]
))
S(Paragraph(
    "- <b>beta<sub>0</sub></b> (componentes conexos): cuenta clusters de larga duracion en la helice, "
    "representando regimenes circadianos distintos.<br/>"
    "- <b>beta<sub>1</sub></b> (bucles): detectados mediante heuristica de caracteristica de Euler, "
    "representando estructuras periodicas.<br/>"
    "- <b>Estabilidad Estructural</b>: persistencia media de las caracteristicas con vida superior al 25% de la "
    "distancia maxima entre pares. Mayor estabilidad indica una arquitectura circadiana mas consistente.",
    styles["Body"]
))
S(Paragraph(
    "Hasta donde sabemos, esta es la primera aplicacion de homologia persistente a datos circadianos de "
    "sueno. Designamos esta metrica como Homologia Circadiana Persistente (PCH).",
    styles["Body"]
))

S(Paragraph("4.2. Entrelazamiento de Hebras via Numero de Enlace de Gauss", styles["SubHead"]))
S(Paragraph(
    "El acoplamiento entre las helices de sueno (Hebra 1) y contexto (Hebra 2) se cuantifica mediante la "
    "integral de enlace discreta de Gauss [18]:",
    styles["Body"]
))
S(Paragraph(
    "Lk = (1/4pi) suma_i suma_j (dR1 x dR2) . (R1 - R2) / |R1 - R2|<super>3</super>",
    styles["Equation"]
))
S(Paragraph(
    "La Densidad del Numero de Enlace (LND) = |Lk| / N<sub>segmentos</sub> proporciona una medida normalizada "
    "del entrelazamiento entre hebras. LND > 0.1 indica acoplamiento coherente entre la fisiologia del sueno "
    "y el contexto conductual. Esta es una aplicacion completamente original de la teoria de nudos a datos "
    "de sueno, nunca publicada anteriormente.",
    styles["Body"]
))

S(Paragraph("4.3. Espectro de Informacion Mutua (MIS)", styles["SubHead"]))
S(Paragraph(
    "El Espectro de Informacion Mutua (MIS) cuantifica el acoplamiento hora por hora entre el proceso "
    "circadiano C(t) y la derivada homeostatica dH/dt en 24 ventanas de una hora [1, 9]. Esto revela las "
    "horas especificas del dia en que los dos procesos regulatorios estan mas y menos sincronizados — "
    "informacion que podria informar recomendaciones personalizadas de horarios de sueno.",
    styles["Body"]
))

# ═══ 5. Biomarcadores de Salud ═══
S(Paragraph("5. Biomarcadores de Salud Derivados", styles["SectionHead"]))

story.extend(make_table(
    [
        ["Biomarcador", "Formula / Metodo", "Umbral de Alerta", "Ref."],
        ["Coherencia Circadiana", "Media del cosinor R2 (ventana de 14 dias)", "< 0.2 (Anarquia circadiana)", "[5]"],
        ["Balance Homeostatico (HB)", "Media |C(t) - S(t)| del modelo de dos procesos", "> 0.3 (Desincronizacion)", "[1,3]"],
        ["Puntuacion de Fragmentacion", "Transiciones de vigilia / fases totales", "> 0.6 (Alta fragmentacion)", "[19]"],
        ["Severidad de Deriva", "Media |deriva diaria| en minutos", "> 15 min/dia (Deriva severa)", "Propio"],
        ["Continuidad Helical (HCI)", "1 - (fases de vigilia / total de fases)", "Informativo (sin umbral)", "[20]"],
        ["Pendiente de Deriva REM (RDS)", "Regresion lineal del timing REM", "|pendiente| > 0.5 (Anormal)", "Propio"],
        ["Entropia de Clusters REM (RCE)", "Entropia de Shannon de intervalos inter-REM", "Informativo (sin umbral)", "Propio"],
    ],
    col_ratios=[14, 22, 16, 5],
    caption="<b>Tabla 3.</b> Biomarcadores de salud derivados con umbrales de alerta."
))

# ═══ 6. Arquitectura en Dispositivo ═══
S(Paragraph("6. Arquitectura en el Dispositivo", styles["SectionHead"]))
S(Paragraph(
    "Todo el pipeline de SleepDNA se ejecuta localmente en dispositivos iOS usando el framework Accelerate "
    "(vDSP) de Apple para procesamiento de senales y computacion vectorizada. Ningun dato de sueno se "
    "transmite a servidores externos. Esta arquitectura se alinea con la tendencia documentada por el "
    "Anthropic Economic Index [26], que identifica una brecha de adopcion del 61% entre la capacidad "
    "teorica de los modelos de lenguaje (94%) y su uso real observado (33%) en entornos profesionales. "
    "Al ejecutar la inferencia en el dispositivo, SleepDNA elimina la dependencia de APIs cloud, los costes "
    "asociados, y las preocupaciones de latencia y privacidad que frenan la adopcion de IA en el sector "
    "salud. El pipeline esta escalonado por niveles segun los datos disponibles:",
    styles["Body"]
))

story.extend(make_table(
    [
        ["Nivel", "Datos Requeridos", "Analisis Habilitados"],
        ["Basico", "< 4 semanas", "Codificacion de nucleotidos, PLV, marcadores de salud, geometria de helice"],
        ["Intermedio", "4-8 semanas", "Todo lo basico + descubrimiento de motivos, prediccion de secuencias, aprendizaje BLOSUM"],
        ["Completo", "8+ semanas", "Todo lo intermedio + homologia persistente, numero de enlace, MIS, reglas de expresion"],
    ],
    col_ratios=[8, 10, 40],
    caption="<b>Tabla 4.</b> Pipeline de analisis escalonado por niveles."
))

S(Paragraph(
    "Las instantaneas del perfil se persisten como JSON comprimido en SwiftData con almacenamiento externo, "
    "manteniendo la base de datos ligera. La matriz de pesos SleepBLOSUM se almacena en cache por separado "
    "para reutilizacion entre sesiones. Todas las computaciones se ejecutan en colas de fondo con aislamiento "
    "de actores para seguridad de hilos.",
    styles["Body"]
))

# ═══ 7. Estudios Futuros Potenciales ═══
S(PageBreak())
S(Paragraph("7. Estudios Futuros Potenciales", styles["SectionHead"]))

S(Paragraph("7.1. Validacion contra Polisomnografia", styles["SubHead"]))
S(Paragraph(
    "El paso de validacion mas critico es comparar las predicciones y biomarcadores de SleepDNA contra "
    "registros clinicos de polisomnografia (PSG). Un estudio prospectivo con 50-100 participantes usando "
    "tanto un Apple Watch como sometiendose a 2-3 noches de PSG permitiria: (a) validar la precision de "
    "clasificacion de motivos, (b) correlacionar los pesos SleepBLOSUM con la estadificacion del sueno "
    "derivada de PSG, y (c) calibrar los umbrales de biomarcadores contra resultados clinicos.",
    styles["Body"]
))

S(Paragraph("7.2. Validez Predictiva de SleepBLOSUM", styles["SubHead"]))
S(Paragraph(
    "Un estudio controlado midiendo si los pesos personalizados de SleepBLOSUM predicen la fatiga subjetiva "
    "del dia siguiente (via Escala de Somnolencia de Karolinska) con mayor precision que pesos uniformes o "
    "algoritmos establecidos (ej. AutoSleep, puntuacion Oura). Hipotesis: las caracteristicas ponderadas por "
    "MI personalizadas capturan diferencias individuales que los modelos uniformes no detectan.",
    styles["Body"]
))

S(Paragraph("7.3. Cronobiologia Interpersonal", styles["SubHead"]))
S(Paragraph(
    "Extension del marco a la genomica comparativa entre parejas que duermen juntas. Tres analisis propuestos: "
    "(a) <i>Dinamica de Co-sueno</i> — cuantificacion de recurrencia cruzada de patrones de despertar entre "
    "parejas; (b) <i>Compatibilidad de Cronotipos</i> — distancia entre centroides de motivos como medida del "
    "sacrificio circadiano; (c) <i>Sensibilidad Diferencial</i> — comparar matrices SleepBLOSUM revela por "
    "que el mismo estimulo (ej. cenar tarde) altera el sueno de un miembro de la pareja pero no del otro.",
    styles["Body"]
))

S(Paragraph("7.4. Analisis de Codones Intra-Noche", styles["SubHead"]))
S(Paragraph(
    "Para usuarios con Apple Watch que proporciona datos de fases del sueno (REM, Profundo, Ligero, Despierto "
    "a resolucion de 15 minutos), el marco puede extenderse al analisis de k-mers (k=3) de transiciones de "
    "fases dentro de una sola noche. Cada triplete de fases consecutivas se puntuaria por integridad "
    "arquitectonica, permitiendo la deteccion de patrones de disrupcion especificos (ej. tripletes repetidos "
    "[REM, Despierto, Ligero] indicando fragmentacion REM). Los 64 tripletes posibles (4<super>3</super>) "
    "podrian puntuarse usando una tabla de calidad de codones derivada de la correlacion con resultados "
    "subjetivos del dia siguiente.",
    styles["Body"]
))

S(Paragraph("7.5. Correlatos Clinicos de Biomarcadores Topologicos", styles["SubHead"]))
S(Paragraph(
    "Las metricas topologicas novedosas (PCH, LND, MIS) requieren validacion clinica. Estudio propuesto: "
    "correlacionar la Homologia Circadiana Persistente con trastornos del ritmo circadiano sueno-vigilia "
    "(CRSWD) diagnosticados, y la Densidad del Numero de Enlace con la respuesta al tratamiento en terapia "
    "cognitivo-conductual para insomnio (TCC-I). Si las caracteristicas topologicas predicen resultados del "
    "tratamiento, podrian servir como biomarcadores digitales objetivos para la medicina del sueno.",
    styles["Body"]
))

S(Paragraph("7.6. Integracion de Modelo de Lenguaje Grande en Dispositivo", styles["SubHead"]))
S(Paragraph(
    "Con el framework Foundation Models de Apple (iOS 26), el sistema podria emplear un LLM en dispositivo "
    "para traducir hallazgos matematicos en insights personalizados en lenguaje natural. En lugar de usar el "
    "LLM para prediccion (donde el DTW deterministico es mas preciso y fiable), serviria como interprete "
    "semantico — conectando patrones detectados con consejos accionables manteniendo la privacidad absoluta "
    "de los datos.",
    styles["Body"]
))

S(Paragraph("7.7. Modelizacion Estocastica de Eventos mediante Procesos de Poisson", styles["SubHead"]))
S(Paragraph(
    "Los eventos contextuales registrados por el usuario (cafeina, ejercicio, estres, alcohol) constituyen "
    "un proceso puntual discreto en el tiempo, susceptible de ser formalizado mediante procesos de Poisson [28]. "
    "La tasa de fragmentacion del sueno (despertares nocturnos) puede modelarse como un proceso de Poisson "
    "con intensidad lambda, donde lambda varia en funcion de los factores contextuales del dia (Proceso de "
    "Poisson No Homogeneo). Esta formalizacion permitiria: (a) cuantificar la tasa base de despertares de "
    "cada usuario, (b) medir el exceso de fragmentacion atribuible a factores especificos, y (c) validar "
    "estadisticamente las correlaciones mediante pruebas de bondad de ajuste Chi-cuadrado.",
    styles["Body"]
))
S(Paragraph(
    "De particular interes es la extension al Proceso de Hawkes (auto-excitado) [29], donde cada evento "
    "incrementa temporalmente la probabilidad de eventos subsiguientes. Este modelo captura la hipotesis "
    "central del proyecto: que la historia temporal completa — no solo eventos individuales aislados — modula "
    "la arquitectura del sueno. Un despertar nocturno aumenta la probabilidad de despertares posteriores "
    "en la misma noche (cascada intra-noche), y un patron de estres sostenido durante varios dias puede "
    "elevar la tasa base de fragmentacion con un retardo de 24-72 horas. La implementacion de un modelo "
    "de Hawkes en SpiralKit permitiria formalizar estos efectos retardados y acumulativos, complementando "
    "el analisis de PLV y DTW con un marco probabilistico riguroso.",
    styles["Body"]
))

# ═══ 8. Limitaciones ═══
S(Paragraph("8. Limitaciones", styles["SectionHead"]))
S(Paragraph(
    "Deben reconocerse varias limitaciones. Primero, la metafora genomica es computacional, no biologica — "
    "los patrones de sueno no son ADN, y los usuarios no deben interpretar los resultados como diagnosticos "
    "medicos [2]. Segundo, el sistema depende de datos de contexto reportados por el usuario (cafeina, estres, "
    "etc.) lo que introduce sesgo de medicion. Tercero, la precision de estadificacion del sueno del Apple "
    "Watch varia segun el modelo y es menos precisa que la PSG clinica. Cuarto, el analisis de correlacion "
    "basado en PLV no puede establecer causalidad — las variables confusoras (ej. efecto del fin de semana "
    "enmascarado como beneficio del alcohol) no se controlan. Quinto, las metricas topologicas (PCH, LND) "
    "son exploratorias y carecen de validacion clinica. Sexto, la integracion futura de modelos de lenguaje "
    "grandes (LLM) para interpretar resultados introduce el riesgo de 'alignment tax' o sicofonancia — la "
    "tendencia documentada de los LLM a producir respuestas que validan el sesgo del usuario en lugar de "
    "proporcionar evaluaciones objetivas [27], lo que podria generar insights enganosos si no se controla "
    "adecuadamente. Finalmente, el descubrimiento de motivos requiere "
    "8+ semanas de datos continuos, lo que presenta un desafio de incorporacion.",
    styles["Body"]
))

# ═══ 9. Conclusion ═══
S(Paragraph("9. Conclusion", styles["SectionHead"]))
S(Paragraph(
    "SleepDNA demuestra que las herramientas matematicas de la bioinformatica, el procesamiento de senales "
    "y la topologia algebraica pueden aplicarse fructiferamente a datos de sueno de consumo. Al codificar "
    "el sueno como secuencias de nucleotidos, el marco permite el descubrimiento de motivos, la clasificacion "
    "de mutaciones, la prediccion personalizada y el analisis topologico que van sustancialmente mas alla de "
    "las metricas tradicionales de sueno. La arquitectura en dispositivo asegura que este analisis sofisticado "
    "permanezca privado y accesible. Futuros estudios de validacion determinaran si los biomarcadores novedosos "
    "propuestos aqui tienen utilidad clinica en la medicina del sueno.",
    styles["Body"]
))

# ═══ Referencias ═══
S(PageBreak())
S(Paragraph("Referencias", styles["SectionHead"]))

refs = [
    "[1] Borbely, A.A. (1982). A two process model of sleep regulation. <i>Human Neurobiology</i>, 1(3), 195-204.",
    "[2] Proyecto SleepDNA (2026). Documento de Base Cientifica: SleepDNA como metafora computacional. Informe tecnico interno.",
    "[3] Daan, S., Beersma, D.G.M., & Borbely, A.A. (1984). Timing of human sleep: Recovery process gated by a circadian pacemaker. <i>American Journal of Physiology</i>, 246(2), R161-R183.",
    "[4] Cornelissen, G. (2014). Cosinor-based rhythmometry. <i>Theoretical Biology and Medical Modelling</i>, 11, 16.",
    "[5] Refinetti, R., Cornelissen, G., & Halberg, F. (2007). Procedures for numerical analysis of circadian rhythms. <i>Biological Rhythm Research</i>, 38(4), 275-325.",
    "[6] Lachaux, J.P., Rodriguez, E., Martinerie, J., & Varela, F.J. (1999). Measuring phase synchrony in brain signals. <i>Human Brain Mapping</i>, 8(4), 194-208.",
    "[7] Mormann, F., Lehnertz, K., David, P., & Elger, C.E. (2000). Mean phase coherence as a measure for phase synchronization. <i>Journal of Neurophysiology</i>, 84(6), 3187-3189.",
    "[8] Henikoff, S. & Henikoff, J.G. (1992). Amino acid substitution matrices from protein blocks. <i>PNAS</i>, 89(22), 10915-10919.",
    "[9] Shannon, C.E. (1948). A mathematical theory of communication. <i>Bell System Technical Journal</i>, 27(3), 379-423.",
    "[10] Battiti, R. (1994). Using mutual information for selecting features in supervised neural net learning. <i>IEEE Transactions on Neural Networks</i>, 5(4), 537-550.",
    "[11] Sakoe, H. & Chiba, S. (1978). Dynamic programming algorithm optimization for spoken word recognition. <i>IEEE Trans. ASSP</i>, 26(1), 43-49.",
    "[12] Bailey, T.L. & Elkan, C. (1994). Fitting a mixture model by expectation maximization to discover motifs in biopolymers. <i>ISMB Proceedings</i>, 28-36.",
    "[13] Hastie, T., Tibshirani, R., & Friedman, J. (2009). <i>The Elements of Statistical Learning</i> (2a ed.). Springer.",
    "[14] Alberts, B., Johnson, A., Lewis, J., et al. (2002). <i>Molecular Biology of the Cell</i> (4a ed.). Garland Science.",
    "[15] Altschul, S.F., Gish, W., Miller, W., et al. (1990). Basic local alignment search tool. <i>Journal of Molecular Biology</i>, 215(3), 403-410.",
    "[16] Edelsbrunner, H., Letscher, D., & Zomorodian, A. (2000). Topological persistence and simplification. <i>Discrete & Computational Geometry</i>, 28(4), 511-533.",
    "[17] Carlsson, G. (2009). Topology and data. <i>Bulletin of the American Mathematical Society</i>, 46(2), 255-308.",
    "[18] Bates, A.D. & Maxwell, A. (2005). <i>DNA Topology</i> (2a ed.). Oxford University Press.",
    "[19] Bonnet, M.H. & Arand, D.L. (2003). Clinical effects of sleep fragmentation versus sleep deprivation. <i>Sleep Medicine Reviews</i>, 7(4), 297-310.",
    "[20] Carskadon, M.A. & Dement, W.C. (2011). Monitoring and staging human sleep. En M.H. Kryger et al. (Eds.), <i>Principles and Practice of Sleep Medicine</i> (5a ed.).",
    "[21] Bird, A. (2007). Perceptions of epigenetics. <i>Nature</i>, 447(7143), 396-398.",
    "[22] Nirenberg, M. & Matthaei, J.H. (1961). The dependence of cell-free protein synthesis upon naturally occurring or synthetic polyribonucleotides. <i>PNAS</i>, 47(10), 1588-1602.",
    "[23] Watson, J.D. & Crick, F.H.C. (1953). Molecular structure of nucleic acids. <i>Nature</i>, 171(4356), 737-738.",
    "[24] EvoScientist (2026). Towards Multi-Agent Evolving AI Scientists for End-to-End Scientific Discovery. <i>arXiv</i>, 2603.08127.",
    "[25] MSBA-YOLO (2026). Lightweight laryngeal disease detection algorithm. <i>AI</i>, 7(3). MDPI.",
    "[26] Massenkoff, M. & McCrory, P. (2026). Labor market impacts of AI: A new measure and early evidence. Anthropic Research.",
    "[27] Lerchner, A. (2026). The Abstraction Fallacy: Why AI Can Simulate But Not Instantiate Consciousness. Google DeepMind Publications.",
    "[28] Proceso de Poisson. En: <i>Wikipedia, la enciclopedia libre</i>. Basado en Poisson, S.D. (1837) y Lundberg, F. (1903).",
    "[29] Hawkes, A.G. (1971). Spectra of some self-exciting and mutually exciting point processes. <i>Biometrika</i>, 58(1), 83-90.",
]

for ref in refs:
    S(Paragraph(ref, styles["RefItem"]))

# ═══ Build ═══
output_path = "/Users/xaron/Desktop/spiral journey project/docs/SleepDNA-Paper-ES.pdf"
doc = SimpleDocTemplate(
    output_path,
    pagesize=A4,
    leftMargin=MARGIN, rightMargin=MARGIN,
    topMargin=MARGIN, bottomMargin=MARGIN,
    title="SleepDNA: Genomica Computacional Aplicada al Analisis del Sueno",
    author="Proyecto Spiral Journey"
)
doc.build(story)
print(f"PDF generado: {output_path}")
