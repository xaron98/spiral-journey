# Scientific Validation Plan — Spiral Journey

**Date:** 2026-03-18
**Goal:** Validate the most promising metrics for scientific publication and clinical credibility.

---

## Phase 1: Internal Validation (puedes hacer tú solo, 0 coste)

### 1.1 Prediction Accuracy Tracking

**Qué:** Medir el error real del modelo de predicción con datos de usuario.

**Cómo:**
- El app ya registra `errorBedtimeMinutes` y `errorWakeMinutes` por cada predicción evaluada
- `PredictionMetricsTracker` calcula MAE rolling 14 días
- Acumular datos durante 3+ meses con usuarios beta

**Métricas a reportar:**
- MAE (Mean Absolute Error) en minutos
- Accuracy@30 (% predicciones dentro de ±30 min)
- Accuracy@15 (% dentro de ±15 min)
- Comparación: ML engine vs Heuristic vs Sequence Alignment
- Mejora tras personalización (pre vs post SleepBLOSUM)

**Target para publicación:**
- MAE < 25 min → comparable con literatura existente
- MAE < 15 min → state of the art para consumer devices
- Accuracy@30 > 75% → clínicamente útil

**Acción inmediata:** Añadir un export de métricas (CSV/JSON) para análisis offline. Esto ya se puede hacer con los datos de SwiftData.

---

### 1.2 SleepBLOSUM Convergence

**Qué:** Demostrar que la scoring matrix personalizada mejora la predicción respecto a pesos uniformes.

**Cómo:**
- Para cada usuario con 8+ semanas: comparar DTW accuracy con BLOSUM vs sin BLOSUM
- Metric: "BLOSUM lift" = (MAE_uniform - MAE_blosum) / MAE_uniform × 100%
- Si lift > 10%, la personalización tiene valor real

**Target:** BLOSUM lift > 15% → publicable como contribución original.

---

### 1.3 Motif Stability

**Qué:** Verificar que los motifs descubiertos son estables en el tiempo (no cambian cada semana).

**Cómo:**
- Calcular motifs con N semanas, luego con N+4 semanas
- Medir Jaccard similarity entre los dos sets de motifs
- Si Jaccard > 0.6, los motifs son estables

**Target:** Jaccard > 0.7 → motifs son features robustas del usuario.

---

## Phase 2: Estudio con Usuarios Beta (TestFlight, ~20-50 usuarios)

### 2.1 Protocolo

**Duración:** 8 semanas mínimo (para alcanzar tier completo).

**Población:**
- 20-50 usuarios con Apple Watch
- Mix de: trabajadores diurnos, shift workers, estudiantes, personas con sueño irregular
- Criterio de inclusión: usar la app al menos 5 noches/semana

**Datos recogidos (todo on-device, exportado voluntariamente):**
- Todas las predicciones + errores
- SleepDNAProfile snapshots semanales
- Health markers (HB, HCI, RDS, RCE)
- Motifs descubiertos
- SleepBLOSUM weights finales

**Consentimiento:** Informar que los datos se usarán para investigación. No compartir datos brutos de salud — solo métricas agregadas.

### 2.2 Cuestionarios complementarios

Añadir un mini cuestionario semanal in-app (5 preguntas, 1 minuto):

1. **PSQI abreviado** (Pittsburgh Sleep Quality Index): "¿Cómo calificarías tu calidad de sueño esta semana?" (1-5)
2. **ESS abreviado** (Epworth Sleepiness Scale): "¿Te has sentido somnoliento durante el día?" (1-5)
3. **Percepción subjetiva:** "¿El patrón que muestra la app refleja cómo te sientes?" (sí/no/parcialmente)
4. **Jet lag social:** "¿Has dormido diferente en el fin de semana que entre semana?" (sí/no)
5. **Eventos relevantes:** "¿Algo inusual esta semana?" (viaje, enfermedad, estrés, texto libre)

### 2.3 Análisis

**Correlaciones a buscar:**
- HB alto ↔ ESS alto (fatiga subjetiva)
- HCI bajo ↔ PSQI bajo (mala calidad percibida)
- Drift > 15 min/día ↔ jet lag social reportado
- Motif "Poor-sleep" ↔ PSQI bajo
- SleepBLOSUM lift ↔ mejora en accuracy individual

**Si estas correlaciones son significativas (p < 0.05), tienes un paper.**

---

## Phase 3: Validación Externa (requiere colaboración)

### 3.1 Comparación con PSG (gold standard)

**Qué:** Validar las fases del Apple Watch y las métricas derivadas contra polisomnografía.

**Cómo:**
- Colaborar con un laboratorio del sueño o universidad
- 20-30 participantes hacen 1 noche de PSG con Apple Watch
- Comparar: fases Watch vs fases PSG, HCI Watch vs HCI PSG, RDS Watch vs RDS PSG

**Target:** Correlación > 0.7 entre métricas Watch y PSG → las métricas son clínicamente significativas.

**Dónde buscar colaboración:**
- Unidades del sueño de hospitales universitarios
- Departamentos de cronobiología
- Grupos de investigación en wearables/mHealth

### 3.2 Comparación con apps existentes

**Qué:** Benchmark contra Oura, WHOOP, AutoSleep.

**Cómo:**
- 20 usuarios usan Spiral Journey + Oura/WHOOP simultáneamente durante 4 semanas
- Comparar: predicción accuracy, detección de irregularidad, facilidad de uso
- Publicar como estudio comparativo

---

## Phase 4: Publicación

### 4.1 Targets de publicación por métrica

| Métrica | Journal/Conferencia target | Tipo de paper |
|---|---|---|
| SleepBLOSUM | *Sleep* / *Journal of Sleep Research* | Technical note + validation |
| Predicción por DTW alignment | *JMIR mHealth* / *npj Digital Medicine* | Original research |
| Motif discovery en sueño | *Chronobiology International* | Methods paper |
| HB como predictor de fatiga | *Sleep Medicine* | Short communication |
| App completa (validación) | *JMIR mHealth* / *Digital Health* | Full paper |
| Persistent Homology en sueño | *Scientific Reports* / *PLOS ONE* | Exploratory research |

### 4.2 Paper principal propuesto

**Título:** "SleepDNA: A Personalized Sequence Alignment Approach for Sleep Pattern Analysis Using Consumer Wearables"

**Abstract structure:**
- Background: sleep regularity predicts health outcomes but current apps use simple metrics
- Method: encode daily sleep as 16-feature nucleotides, DTW alignment, adaptive SleepBLOSUM scoring
- Results: N users, MAE X min, BLOSUM lift Y%, correlation with PSQI/ESS
- Conclusion: personalized sequence alignment improves sleep prediction and pattern detection

**Autores:** Tú + colaborador académico (si consigues uno) + equipo si lo hay.

### 4.3 Aspectos novedosos para el paper

Lo que ningún otro paper/app ha hecho:
1. **SleepBLOSUM** — scoring matrix adaptativa per-user (inspirada en BLOSUM62 de bioinformática)
2. **Motif discovery** en series temporales de sueño con nomenclatura genómica
3. **Hilbert phase synchrony** entre factores de contexto y outcomes de sueño
4. **Predicción por alineamiento de secuencias** (no ML, no estadístico — sequence-based)
5. **HB continuous** — Process S con carry-over de deuda aplicado a consumidor

---

## Phase 5: Acciones inmediatas (esta semana)

### Para empezar la validación interna:

1. **Data export:** Añadir botón en Settings que exporte a CSV:
   - predictions.csv (date, predicted, actual, error, engine)
   - healthmarkers.csv (date, HB, HCI, RDS, RCE, coherence, drift)
   - motifs.csv (name, instances, avgQuality)
   - blosum.csv (feature, weight)

2. **Tracking dashboard** (solo para developer/debug):
   - MAE rolling chart
   - Engine comparison (ML vs heuristic vs alignment)
   - BLOSUM weights evolution over time

3. **TestFlight beta:**
   - Preparar la app para beta testing
   - Reclutar 20-50 usuarios con Apple Watch
   - Incluir el mini cuestionario semanal

---

## Resumen de valor científico por métrica

| Métrica | Base científica | Novedad | Publicabilidad | Acción necesaria |
|---|---|---|---|---|
| SRI / Regularidad | Fuerte (JAMA 2020) | Baja (existe) | Media | Validar vs PSQI |
| SleepBLOSUM | Media (MI + BLOSUM analogy) | **Alta** | **Alta** | Demostrar lift > 15% |
| DTW Prediction | Media (DTW validado en TS) | **Alta** | **Alta** | MAE < 25 min |
| Motif Discovery | Media (clustering validado) | **Alta** | Alta | Estabilidad Jaccard > 0.7 |
| HB | Fuerte (Borbély 1982) | Media | Alta | Correlación con ESS |
| HCI | Fuerte (fragmentación) | Baja | Media | Correlación con PSQI |
| RDS | Media (REM drift) | Media | Media | Validar vs PSG |
| PCH | Emergente (TDA 2021) | **Muy alta** | Alta (si funciona) | Estudio exploratorio |

**Lo más publicable con menor esfuerzo:** SleepBLOSUM + DTW Prediction en un solo paper.
