# SleepDNA — Marco Teórico, Cálculos y Bibliografía

**Estado:** Experimental — framework computacional, no validado por estudios peer-reviewed.
**Fecha:** 2026-03-21

---

## 1. Visión General

SleepDNA es un framework computacional que codifica datos diarios de sueño como vectores de características (nucleótidos), los agrupa en secuencias semanales, y aplica técnicas de genómica computacional para descubrir patrones, clasificar desviaciones y predecir el sueño futuro.

**No es:** un test genético, un análisis de ADN biológico, ni una herramienta médica.
**Sí es:** una metáfora computacional que toma prestadas técnicas de bioinformática (DTW, matrices de sustitución, descubrimiento de motivos) y las aplica al análisis de series temporales de sueño.

---

## 2. Pipeline de Análisis (12 pasos)

### 2.1. Codificación: DayNucleotide (16 features por día)

Cada día se codifica como un vector de 16 dimensiones normalizado a [0,1] o [-1,1]:

| # | Feature | Strand | Cálculo | Normalización |
|---|---------|--------|---------|---------------|
| 0 | Bedtime (sin) | Sleep | sin(2π × bedtimeHour/24) | [-1, 1] |
| 1 | Bedtime (cos) | Sleep | cos(2π × bedtimeHour/24) | [-1, 1] |
| 2 | Wake (sin) | Sleep | sin(2π × wakeHour/24) | [-1, 1] |
| 3 | Wake (cos) | Sleep | cos(2π × wakeHour/24) | [-1, 1] |
| 4 | Duration | Sleep | sleepDuration / 12.0 | [0, 1] |
| 5 | Process S | Sleep | computeContinuous(hour) | [0, 1] |
| 6 | Cosinor amplitude | Sleep | R² de cosinor fit | [0, 1] |
| 7 | Cosinor acrophase | Sleep | sin(acrophase) | [-1, 1] |
| 8 | Caffeine | Context | 1 si hay evento cafeína, 0 si no | {0, 1} |
| 9 | Exercise | Context | 1 si hay evento ejercicio, 0 si no | {0, 1} |
| 10 | Alcohol | Context | 1 si hay evento alcohol, 0 si no | {0, 1} |
| 11 | Melatonin | Context | 1 si hay evento melatonina, 0 si no | {0, 1} |
| 12 | Stress | Context | 1 si hay evento estrés, 0 si no | {0, 1} |
| 13 | Weekend | Context | 1 si sábado/domingo, 0 si no | {0, 1} |
| 14 | Drift | Context | |midSleep - chronotypeMean| / 4.0 | [0, 1] |
| 15 | Sleep quality | Context | (duration - fragmentation) / 10.0 | [0, 1] |

**Codificación circular:** Bedtime y wake se codifican con sin/cos para evitar la discontinuidad 23:59→00:00. Esto es estándar en análisis circadiano.

**Base científica:** La codificación circular de tiempos circadianos está establecida en cronobiología (Refinetti, 2006). El Process S se basa en el Two-Process Model de Borbély (1982).

### 2.2. Secuencias Semanales (WeekSequence)

- Ventana deslizante de 7 días → matriz 7×16
- Cada semana es una "secuencia" análoga a una secuencia de ADN
- Se generan todas las ventanas posibles del historial

**Hipótesis:** El ciclo semanal es la unidad natural de análisis porque captura tanto días laborables como fines de semana, que constituyen el principal factor de variabilidad social del sueño (social jet lag).

**Referencia:** Wittmann et al. (2006) — Social jet lag y el ritmo semanal.

### 2.3. Dynamic Time Warping (DTW)

**Qué hace:** Compara dos semanas midiendo la distancia óptima entre ellas, permitiendo deformación temporal (un lunes puede alinearse con un martes si los patrones son similares).

**Fórmula:**
```
DTW(A, B) = min Σ d(aᵢ, bⱼ) sobre todos los warping paths
d(a, b) = √(Σₖ wₖ × (aₖ - bₖ)²)  (Euclidean ponderada por BLOSUM)
```

**Base científica:** DTW es una técnica establecida en procesamiento de señales desde Sakoe & Chiba (1978). Se usa ampliamente en biosignals, reconocimiento de voz, y alineamiento de secuencias biológicas.

**Hipótesis nuestra:** DTW es más adecuado que la distancia Euclidiana para comparar semanas de sueño porque tolera pequeñas variaciones en el timing (social jet lag, cambios de horario) sin penalizar excesivamente.

### 2.4. SleepBLOSUM (Matriz de Pesos Personalizada)

**Inspiración:** BLOSUM62 (Henikoff & Henikoff, 1992) — matrices de sustitución para alineamiento de proteínas. En bioinformática, diferentes posiciones tienen diferente importancia para la función biológica.

**Nuestro enfoque:** Para cada usuario, calculamos qué features de los 16 son más importantes para predecir la calidad de sueño del día siguiente.

**Algoritmo:**
1. Para cada feature k (0-15):
   - Discretizar valores en 5 bins de igual ancho
   - Calcular información mutua MI(feature_k, quality_tomorrow)
   - MI = H(X) + H(Y) - H(X,Y)
2. Normalizar MI a pesos [0, 3.0]
3. Usar pesos en la función de costo del DTW

**Base científica:** La información mutua es un concepto fundamental de teoría de la información (Shannon, 1948). Su uso para selección de features es estándar en ML (Battiti, 1994).

**Hipótesis nuestra:** Los factores que afectan el sueño son altamente individuales. La cafeína puede devastar el sueño de una persona y no afectar a otra. SleepBLOSUM captura esta personalización aprendiendo qué features importan para CADA usuario.

### 2.5. Hilbert Phase Locking Value (PLV)

**Qué hace:** Mide la sincronización de fase entre las features del strand 1 (sueño) y strand 2 (contexto). Son 8×8 = 64 pares posibles.

**Algoritmo:**
1. Extraer serie temporal de cada feature (14+ días)
2. Aplicar Transformada de Hilbert (vía FFT + Accelerate framework) para obtener señal analítica
3. Calcular fase instantánea: φ(t) = arg(señal_analítica(t))
4. PLV = |1/N × Σ exp(i(φ₁(t) - φ₂(t)))|
5. PLV ∈ [0, 1]: 0 = sin sincronización, 1 = perfectamente sincronizados

**Umbral:** Solo se reportan pares con PLV > 0.3

**Base científica:** La Transformada de Hilbert y el PLV se usan ampliamente en neurociencia para medir acoplamiento entre oscilaciones cerebrales (Lachaux et al., 1999; Mormann et al., 2000). La técnica está bien establecida para señales oscilatorias.

**Hipótesis nuestra:** Las features circadianas (bedtime, duration) y las contextuales (caffeine, exercise) pueden tener acoplamientos de fase significativos — por ejemplo, el ejercicio a cierta hora puede estar sincronizado con mejor duración de sueño. El PLV cuantifica esto de forma no lineal, capturando relaciones que la correlación lineal de Pearson no detecta.

**Representación en la hélice:** Los pares con alto PLV determinan el ángulo de torsión (twist) entre los dos strands de la doble hélice. Mayor PLV = mayor torsión = strands más entrelazados.

### 2.6. Descubrimiento de Motivos

**Qué hace:** Agrupa semanas similares para descubrir patrones recurrentes ("sleep genes").

**Algoritmo:**
1. Calcular matriz de distancias DTW entre todas las semanas (O(n²))
2. Clustering jerárquico aglomerativo (single-linkage)
3. Umbral de corte: 8.0 (calibrado para vectores de 16 features)
4. Para cada cluster ≥ 2 miembros: calcular centroide (media element-wise)
5. Auto-naming basado en la feature dominante que más desvía de la media global

**Muestreo:** Si hay > 200 secuencias, se toman 200 aleatorias (DTW es computacionalmente costoso).

**Nombres generados:** "Late-night", "Active-week", "Caffeine-heavy", "Good-sleep", "Weekend-mode", etc.

**Base científica:** El descubrimiento de motivos en secuencias es fundamental en bioinformática (Bailey & Elkan, 1994 — MEME). El clustering jerárquico es una técnica estándar (Hastie et al., 2009).

**Hipótesis nuestra:** Los patrones de sueño de una persona tienden a repetirse en ciclos (semanas laborales similares, fines de semana similares). Estos "motivos" son análogos a genes — patrones recurrentes que definen el comportamiento del sistema.

### 2.7. Clasificación de Mutaciones

**Qué hace:** Compara cada semana contra su motivo más cercano y clasifica la desviación.

**Tipos:**
| Tipo | Umbral (quality delta) | Analogía biológica |
|------|----------------------|-------------------|
| Silent | < 0.05 | Mutación sinónima — no afecta función |
| Missense | 0.05 – 0.15 | Mutación de sentido erróneo — efecto moderado |
| Nonsense | > 0.15 | Mutación sin sentido — efecto severo |

**Umbrales adaptativos:** Más estrictos para patrones nocturnos-dominantes, más flexibles para diurnos.

**Base científica:** La clasificación de mutaciones (silent/missense/nonsense) proviene de genética molecular (Alberts et al., Molecular Biology of the Cell). Es una metáfora directa — no afirmamos que las desviaciones de sueño sean mutaciones biológicas.

**Hipótesis nuestra:** Clasificar las desviaciones del patrón habitual permite al usuario entender qué cambios afectan su calidad de sueño y cuáles son irrelevantes.

### 2.8. Reglas de Expresión

**Qué hace:** Para cada motivo con ≥ 4 instancias, analiza qué features del contexto (strand 2) se asocian con mejor o peor calidad.

**Algoritmo:**
1. Para cada feature de contexto (8-15):
   - Dividir instancias del motivo en "alta" y "baja" (median split)
   - Comparar calidad media en ambos grupos
   - Si |qualityHigh - qualityLow| > 0.05 → regla significativa

**Base científica:** La regulación de expresión génica (cómo los genes se activan/desactivan según el ambiente) es un concepto central en biología molecular. Aquí es metáfora: ¿qué factores contextuales "activan" un patrón de sueño mejor o peor?

### 2.9. Marcadores de Salud (7 indicadores)

| Marcador | Sigla | Cálculo | Rango | Interpretación |
|----------|-------|---------|-------|----------------|
| Circadian Coherence | HB | Media de R² cosinor (14 días) | [0, 1] | Ritmo circadiano estable |
| Fragmentation Score | — | Transiciones awake / total fases | [0, 1] | Sueño fragmentado |
| Drift Severity | RDS | Media de \|drift\| en minutos | ≥ 0 | Desviación del cronotipo |
| Homeostasis Balance | HB | Media de \|C - S\| del Two-Process Model | [0, 1] | Equilibrio homeostático |
| REM Drift Slope | RDS | Pendiente de regresión lineal del timing REM | ℝ | Arquitectura REM estable |
| Helical Continuity | HCI | 1 - (fases awake / total fases) | [0, 1] | Continuidad del sueño |
| REM Cluster Entropy | RCE | Entropía de Shannon de intervalos inter-REM | ≥ 0 | Regularidad del patrón REM |

**Alertas automáticas:**
- Circadian Anarchy: HB < 0.3
- High Fragmentation: score > 0.4
- Severe Drift: > 90 min media
- High Desynchrony: HB < 0.4
- REM Drift Abnormal: |slope| > 0.5

**Base científica:**
- Cosinor: Refinetti et al. (2007) — método establecido para analizar ritmos circadianos
- Fragmentación: Bonnet & Arand (2003) — índice de calidad del sueño
- Two-Process Model: Borbély (1982) — Process S (homeostático) + Process C (circadiano)
- Arquitectura REM: Carskadon & Dement (2011) — ciclos REM progresivos

**Hipótesis nuestra:** Estos 7 marcadores, computados desde datos pasivos de HealthKit, pueden servir como proxies de la calidad circadiana global del usuario. No están validados clínicamente como biomarcadores.

### 2.10. Geometría de la Hélice 3D

**Qué hace:** Mapea datos de sueño a parámetros de una doble hélice 3D (RealityKit).

| Parámetro | Fuente | Cálculo |
|-----------|--------|---------|
| Twist angle | PLV promedio | meanPLV × π/3 (0 a 60°) |
| Helix radius | Desviación de midSleep | \|midSleep - chronoMean\| / 4.0 |
| Strand thickness | Proporción de sueño profundo (N3) | N3 phases / total sleep phases |
| Surface roughness | Fragmentación | awake phases / total phases |

**Representación visual:**
- Strand púrpura: datos de sueño (strand 1)
- Strand naranja: contexto diario (strand 2)
- Torsión: grado de sincronización entre ambos strands
- Radio: estabilidad del timing
- Grosor: calidad del sueño profundo
- Rugosidad: fragmentación

### 2.11. Métricas Topológicas Avanzadas

#### Persistent Circadian Homology (PCH)

**Qué hace:** Análisis topológico de la nube de puntos 3D generada por la hélice.

**Algoritmo:**
1. Convertir DayHelixParams a coordenadas cilíndricas 3D
2. Filtración de Rips simplificada con Union-Find
3. Tracking de nacimientos/muertes de componentes
4. β₀ = componentes conexas de larga vida
5. β₁ = ciclos/loops estimados (heurística de característica de Euler)
6. Estabilidad estructural = persistencia media normalizada

**Base científica:** La homología persistente es una técnica establecida en TDA (Topological Data Analysis) — Edelsbrunner et al. (2000), Carlsson (2009). Su aplicación a datos circadianos es **novedosa y no validada**.

**Hipótesis nuestra:** La topología de la hélice de sueño puede revelar patrones estructurales que las métricas estadísticas convencionales no capturan — por ejemplo, si el sueño tiene "agujeros" (periodos de desregulación) o forma loops estables.

#### Linking Number Density (LND)

**Qué hace:** Mide cuán entrelazados están los dos strands (sueño + contexto).

**Algoritmo:** Integral de Gauss discreta:
```
Lk = (1/4π) Σᵢ Σⱼ (dR₁ × dR₂) · (R₁ - R₂) / |R₁ - R₂|³
Density = |Lk| / numSegments
isCoherent = density > 0.1
```

**Base científica:** El Linking Number es un invariante topológico del ADN usado en biología molecular para medir supercoiling (Bates & Maxwell, 2005). Su aplicación a series temporales de sueño es **completamente novedosa**.

**Hipótesis nuestra:** Un linking number alto indica que los factores contextuales (ejercicio, cafeína) están estrechamente acoplados con los patrones de sueño — el "ADN" del usuario es coherente.

#### Mutual Information Spectrum (MIS)

**Qué hace:** Calcula la información mutua entre la señal circadiana (C) y la derivada homeostática (dH/dt) para cada hora del día.

**Algoritmo:**
1. Para cada hora h (0-23): recoger C(h) y dH/dt(h) de todos los días
2. Discretizar en 5 bins
3. Calcular MI = H(X) + H(Y) - H(X,Y)
4. Identificar hora pico (máximo acoplamiento) y hora valle

**Base científica:** La interacción entre Process C y Process S es fundamental en el Two-Process Model (Borbély, 1982; Daan et al., 1984). El MIS es una forma novedosa de visualizar CUÁNDO durante el día estos procesos están más acoplados.

**Hipótesis nuestra:** Las horas de máximo acoplamiento C-S podrían indicar las ventanas óptimas de sueño del usuario.

### 2.12. Predicción por Alineamiento de Secuencias

**Qué hace:** Predice el sueño de esta noche alineando la semana en curso contra semanas históricas similares.

**Algoritmo:**
1. DTW parcial: comparar semana incompleta (1-6 días) contra todas las históricas
2. Seleccionar top 5 más similares
3. Para cada match: tomar el día N+1 histórico como predicción
4. Ponderar por inversas de distancia DTW
5. Decodificar bedtime/wake desde codificación circular (atan2)
6. Confianza = mejor similitud mapeada a alta/media/baja

**Base científica:** El alineamiento de secuencias (BLAST, Smith-Waterman) es la técnica fundamental de bioinformática para buscar similitudes (Altschul et al., 1990). Adaptar esta idea a series temporales de sueño es **novedoso**.

**Hipótesis nuestra:** "Semanas similares producen noches similares." Si tu semana actual se parece a una semana pasada, tu sueño de esta noche debería parecerse al de aquella semana.

---

## 3. Tiers de Datos

| Tier | Semanas | Análisis disponible |
|------|---------|-------------------|
| Basic | < 4 | Codificación, PLV básico |
| Intermediate | 4-8 | + Predicción por alineamiento, BLOSUM reusado |
| Full | 8+ | + Motivos, mutaciones, expresión, métricas topológicas |

---

## 4. Bibliografía

### Fundamentos directos

1. **Borbély, A.A.** (1982). A two process model of sleep regulation. *Human Neurobiology*, 1(3), 195-204.
   - Modelo fundacional Process S + Process C. Base para features 5 (Process S) y marcador HB.

2. **Sakoe, H. & Chiba, S.** (1978). Dynamic programming algorithm optimization for spoken word recognition. *IEEE Transactions on Acoustics, Speech, and Signal Processing*, 26(1), 43-49.
   - DTW original. Base del motor de comparación de secuencias.

3. **Henikoff, S. & Henikoff, J.G.** (1992). Amino acid substitution matrices from protein blocks. *PNAS*, 89(22), 10915-10919.
   - BLOSUM62 original. Inspiración para SleepBLOSUM.

4. **Lachaux, J.P., Rodriguez, E., Martinerie, J., & Varela, F.J.** (1999). Measuring phase synchrony in brain signals. *Human Brain Mapping*, 8(4), 194-208.
   - PLV original. Base del análisis de sincronización de fase.

5. **Refinetti, R., Cornélissen, G., & Halberg, F.** (2007). Procedures for numerical analysis of circadian rhythms. *Biological Rhythm Research*, 38(4), 275-325.
   - Método cosinor. Base del marcador de coherencia circadiana.

6. **Shannon, C.E.** (1948). A mathematical theory of communication. *Bell System Technical Journal*, 27(3), 379-423.
   - Entropía e información mutua. Base de SleepBLOSUM y RCE.

### Sueño y ritmos circadianos

7. **Daan, S., Beersma, D.G.M., & Borbély, A.A.** (1984). Timing of human sleep: Recovery process gated by a circadian pacemaker. *American Journal of Physiology*, 246(2), R161-R183.
   - Extension del Two-Process Model. Interacción C-S.

8. **Wittmann, M., Dinich, J., Merrow, M., & Roenneberg, T.** (2006). Social jetlag: Misalignment of biological and social time. *Chronobiology International*, 23(1-2), 497-509.
   - Social jet lag. Justificación del ciclo semanal como unidad de análisis.

9. **Carskadon, M.A. & Dement, W.C.** (2011). Normal human sleep: An overview. In *Principles and Practice of Sleep Medicine* (5th ed.), pp. 16-26.
   - Arquitectura del sueño normal. Contexto para REM drift.

10. **Bonnet, M.H. & Arand, D.L.** (2003). Clinical effects of sleep fragmentation versus sleep deprivation. *Sleep Medicine Reviews*, 7(4), 297-310.
    - Efectos de la fragmentación. Base del índice de fragmentación.

11. **Rasch, B. & Born, J.** (2013). About sleep's role in memory. *Physiological Reviews*, 93(2), 681-766.
    - Consolidación de memoria durante el sueño.

12. **Stickgold, R. & Walker, M.P.** (2013). Sleep-dependent memory triage. *Nature Neuroscience*, 16(2), 139-145.
    - Procesamiento de memoria durante el sueño.

### Herencia y epigenética (contexto de la metáfora)

13. **Barclay, N.L., Eley, T.C., Buysse, D.J., et al.** (2010). Diurnal preference and sleep quality: Same genes? *Chronobiology International*, 27(2), 278-296.
    - Contribución genética a los patrones de sueño.

14. **Lane, J.M., Vlasac, I., Anderson, S.G., et al.** (2016). Genome-wide association analysis identifies novel loci for chronotype. *Nature Communications*, 7, 10889.
    - GWAS linking sleep traits with genetics.

15. **Chen, Q., Yan, M., Cao, Z., et al.** (2016). Sperm tsRNAs contribute to intergenerational inheritance of an acquired metabolic disorder. *Science*, 351(6271), 397-400.
    - Herencia epigenética vía RNAs pequeños en esperma. Contexto (no base directa).

16. **Gapp, K., Jawaid, A., Sarkber, P., et al.** (2014). Implication of sperm RNAs in transgenerational inheritance of the effects of early trauma in mice. *Nature Neuroscience*, 17(5), 667-669.
    - Transmisión transgeneracional de fenotipo via RNA. Contexto.

### Topología y métodos avanzados

17. **Carlsson, G.** (2009). Topology and data. *Bulletin of the American Mathematical Society*, 46(2), 255-308.
    - Introducción a TDA. Base teórica de la homología persistente.

18. **Edelsbrunner, H., Letscher, D., & Zomorodian, A.** (2000). Topological persistence and simplification. *Discrete & Computational Geometry*, 28(4), 511-533.
    - Homología persistente original.

19. **Bates, A.D. & Maxwell, A.** (2005). *DNA Topology* (2nd ed.). Oxford University Press.
    - Linking Number en ADN biológico. Inspiración para LND.

### Bioinformática general

20. **Altschul, S.F., Gish, W., Miller, W., et al.** (1990). Basic local alignment search tool. *Journal of Molecular Biology*, 215(3), 403-410.
    - BLAST. Inspiración conceptual para el alineamiento de secuencias.

21. **Bailey, T.L. & Elkan, C.** (1994). Fitting a mixture model by expectation maximization to discover motifs in biopolymers. *ISMB*, 28-36.
    - MEME motif discovery. Inspiración para nuestro descubrimiento de motivos.

22. **Battiti, R.** (1994). Using mutual information for selecting features in supervised neural net learning. *IEEE Transactions on Neural Networks*, 5(4), 537-550.
    - MI para selección de features. Base de SleepBLOSUM.

---

## 5. Hipótesis Centrales (No Validadas)

### H1: La metáfora genómica es útil para el análisis de sueño
Los patrones de sueño tienen propiedades análogas a secuencias biológicas: recurrencia (motivos/genes), variación (mutaciones), y modulación ambiental (expresión). Usar herramientas de bioinformática para analizarlos puede revelar insights que las métricas estadísticas simples no capturan.

**Estado:** Sin validar. No hay estudios que comparen este enfoque contra métodos convencionales de análisis de sueño.

### H2: SleepBLOSUM captura personalización relevante
Los pesos aprendidos por información mutua reflejan los factores individuales que más afectan el sueño de cada usuario. Dos personas con el mismo patrón de sueño pero diferentes sensibilidades (a cafeína, ejercicio, etc.) tendrán matrices BLOSUM diferentes.

**Estado:** Testable. Se podría medir si personalizar los pesos mejora la predicción vs. pesos uniformes.

### H3: El PLV entre strands revela acoplamientos significativos
La sincronización de fase entre features de sueño y contexto (medida por Hilbert PLV) detecta relaciones no lineales que la correlación de Pearson no captura.

**Estado:** Parcialmente testable. El PLV es una técnica validada para señales neuronales, pero su aplicación a features discretas de sueño (binarias como caffeine/exercise) es novedosa y no validada.

### H4: Los motivos son estables y predictivos
Los patrones recurrentes descubiertos por DTW+clustering son consistentes en el tiempo (un motivo descubierto en semanas 1-8 reaparece en semanas 9-16) y útiles para predecir el sueño futuro.

**Estado:** Testable. Requiere datos longitudinales de múltiples usuarios.

### H5: Las métricas topológicas (PCH, LND) capturan estructura relevante
La homología persistente y el linking number de la hélice 3D proporcionan información sobre la estabilidad circadiana que las métricas escalares (media, varianza) no pueden expresar.

**Estado:** Altamente especulativo. TDA aplicado a sueño es novedoso. No hay literatura previa.

### H6: La predicción por alineamiento supera a la predicción por ML simple
Buscar semanas similares históricas (nearest-neighbor en espacio DTW) y usar el día siguiente como predicción es más preciso que un modelo ML entrenado en features agregadas.

**Estado:** Testable. Se podría comparar contra el SleepPredictionModel CoreML existente.

---

## 6. Lo Que la Evidencia NO Soporta

| Afirmación | Evidencia |
|------------|-----------|
| El contenido de los sueños puede codificarse en ADN | Ninguna |
| Las experiencias de sueño específicas se heredan | Ninguna |
| Las marcas epigenéticas sobreviven la reprogramación en mamíferos de forma fiable | Muy limitada |
| "Sleep genes" literales existen para patrones específicos | Ninguna |
| SleepDNA proporciona diagnóstico médico | Ninguna — no es un dispositivo médico |

---

## 7. Direcciones Futuras de Investigación

### Validables con datos del app
- ¿SleepBLOSUM personalizado mejora predicción vs. pesos uniformes? (A/B test)
- ¿Los motivos son estables en el tiempo? (split-half validation)
- ¿Los marcadores de salud correlacionan con calidad subjetiva? (cuestionario semanal)
- ¿La predicción por alineamiento supera al CoreML model? (backtesting)

### Requieren colaboración académica
- ¿Los pesos BLOSUM correlacionan con genética del cronotipo?
- ¿La disrupción de motivos predice onset de trastornos del sueño?
- ¿RCE correlaciona con outcomes de salud mental?

### Fuera de alcance (sin base científica)
- Transmisión hereditaria de contenido onírico
- Codificación genética de experiencias de sueño
- Memoria transgeneracional vía sueño
