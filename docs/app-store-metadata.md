# Spiral Journey — App Store Metadata

## URLs
- **Privacy Policy**: https://xaron98.github.io/spiral-journey/privacy-policy.html
- **Support URL**: https://github.com/xaron98/spiral-journey/issues
- **Marketing URL**: https://xaron98.github.io/spiral-journey/

---

## App Information

| Field | Value |
|-------|-------|
| **Name** | Spiral Journey |
| **Subtitle** | Circadian Rhythm Tracker |
| **Category (Primary)** | Health & Fitness |
| **Category (Secondary)** | Medical |
| **Content Rating** | 4+ |
| **Price** | Free (or your chosen price) |
| **Availability** | All countries |

---

## Description (English — 4000 chars max)

```
Spiral Journey visualizes your sleep and wake cycle as a circadian spiral — one of the most intuitive ways to understand your biological clock.

WHAT IS CIRCADIAN RHYTHM?
Your internal clock runs on a ~24-hour cycle, regulating when you feel alert, sleepy, hungry, and focused. When this rhythm is disrupted — by irregular schedules, social jet lag, or shift work — it affects metabolism, mood, and cognition.

HOW SPIRAL JOURNEY WORKS
Each night of sleep is plotted on a 24-hour circular axis. Over days and weeks, your sleep pattern traces a spiral. A tight, regular spiral means a stable rhythm. A wide, wandering spiral reveals disruption.

SCIENTIFIC ANALYSIS
• Cosinor Analysis — fits a cosine curve to your activity data to extract Acrophase (peak time), MESOR (midline), and Amplitude (rhythm strength)
• Phase Response Curves (PRC) — shows how light, melatonin, caffeine, and exercise affect your clock at different times of day
• Two-Process Model — models the interplay between sleep pressure (Process S) and circadian alertness (Process C)
• Sleep Regularity Index (SRI) — quantifies day-to-day consistency of your sleep pattern
• Social Jet Lag detection — measures the mismatch between your biological clock and social schedule

KEY FEATURES
• Circadian spiral visualization — beautiful and scientifically grounded
• Apple Health integration — automatically imports your sleep data
• Apple Watch app — log sleep and events directly from your wrist, with watch face complications
• Rephase Mode — gradually shift your circadian schedule toward a target bedtime
• Coach tab — AI-powered chat for personalized daily insights (100% on-device)
• Analysis tab — trends in rhythm strength, sleep duration, and regularity
• Settings tab — appearance, data management, and sync preferences
• 8 languages: English, Español, Català, Deutsch, Français, 中文, 日本語, العربية
• Dark, Light, and System appearance modes

PRIVACY FIRST
Core sleep/event data is stored locally and can optionally sync through the user's private iCloud account (CloudKit) when enabled by Apple account settings. No ads, no third-party analytics, and no external backend for sleep data. If the user enables on-device AI coach, the model file is downloaded from Hugging Face to the device; chat inference stays on-device.

Scientific terms used in the app (Acrophase, MESOR, Cosinor, SRI, R²) are standard chronobiology terminology.
```

---

## Description (Spanish)

```
Spiral Journey visualiza tu ciclo de sueño y vigilia como una espiral circadiana — una de las formas más intuitivas de entender tu reloj biológico.

QUÉ ES EL RITMO CIRCADIANO
Tu reloj interno funciona en un ciclo de ~24 horas, regulando cuándo te sientes alerta, con sueño, con hambre o concentrado. Cuando este ritmo se altera — por horarios irregulares, jet lag social o trabajo por turnos — afecta al metabolismo, el estado de ánimo y la cognición.

CÓMO FUNCIONA SPIRAL JOURNEY
Cada noche de sueño se representa en un eje circular de 24 horas. A lo largo de días y semanas, tu patrón de sueño traza una espiral. Una espiral compacta y regular significa un ritmo estable. Una espiral abierta y errante revela una perturbación.

ANÁLISIS CIENTÍFICO
• Análisis de Cosinor — ajusta una curva coseno a tus datos de actividad para extraer la Acrofase (hora pico), el MESOR (línea media) y la Amplitud (fuerza del ritmo)
• Curvas de Respuesta de Fase (PRC) — muestra cómo la luz, la melatonina, la cafeína y el ejercicio afectan a tu reloj en distintos momentos del día
• Modelo de Dos Procesos — modela la interacción entre la presión de sueño (Proceso S) y la alerta circadiana (Proceso C)
• Índice de Regularidad del Sueño (SRI) — cuantifica la consistencia día a día de tu patrón de sueño
• Detección de jet lag social — mide el desfase entre tu reloj biológico y tu horario social

CARACTERÍSTICAS PRINCIPALES
• Visualización en espiral circadiana — bella y científicamente fundamentada
• Integración con Apple Health — importa tus datos de sueño automáticamente
• App para Apple Watch — registra el sueño y eventos desde tu muñeca, con complicaciones para la esfera del reloj
• Modo Refase — desplaza gradualmente tu horario circadiano hacia una hora de dormir objetivo
• Pestaña Coach — chat con IA para insights diarios personalizados (100% en el dispositivo)
• Pestaña Análisis — tendencias en fuerza del ritmo, duración del sueño y regularidad
• Pestaña Ajustes — apariencia, gestión de datos y preferencias de sincronización
• 8 idiomas: English, Español, Català, Deutsch, Français, 中文, 日本語, العربية
• Modos de apariencia oscuro, claro y del sistema

PRIVACIDAD ANTE TODO
Los datos principales permanecen en tu dispositivo y pueden sincronizarse opcionalmente mediante iCloud privado (CloudKit) entre tus propios dispositivos Apple. Sin cuentas propias, sin rastreo y sin anuncios. Si activas el coach IA, el modelo se descarga una sola vez al dispositivo y la inferencia se ejecuta localmente.
```

---

## Keywords (100 chars max, comma-separated)

```
sleep,circadian,rhythm,tracker,cosinor,health,insomnia,wake,bedtime,jetlag,chronobiology,spiral
```

*(español)*
```
sueño,circadiano,ritmo,tracker,cosinor,salud,insomnio,despertar,jetlag,cronobiología,espiral
```

---

## What's New (Version 1.0)

```
First release of Spiral Journey.

• Circadian spiral visualization of your sleep/wake cycle
• Cosinor analysis with Acrophase, MESOR, and Amplitude
• Phase Response Curves for light, melatonin, exercise, and caffeine
• Apple Health sleep data integration
• Apple Watch companion app with complications
• Rephase Mode for gradual schedule adjustment
• Coach tab with personalized daily recommendations
• 8 languages: EN, ES, CA, DE, FR, ZH, JA, AR
```

---

## App Review Notes (for Apple reviewers)

```
This app reads sleep data from Apple Health (HealthKit) to analyze circadian rhythm patterns.

The app has four tabs:
1. Spiral tab — the main view. Displays your sleep/wake cycle as a circadian spiral. Swipe left/right to move the cursor through days, pinch to zoom. Tap the 🧬 DNA button to open Sleep DNA Insights (pattern analysis, motif discovery, health markers).
2. Analysis tab — shows trend cards for rhythm strength, sleep duration, consistency, and social jet lag over time.
3. Coach tab — AI-powered chat for personalized sleep insights. Uses on-device models only (Foundation Models on iOS 26+, or Phi-3.5 GGUF fallback).
4. Settings tab — configure appearance, manage data, enable/disable iCloud sync, and reset data.

To test:
- Grant HealthKit sleep access when prompted, or deny it and enter manual sleep episodes from the Spiral tab's "+" button.
- Navigate through days using the cursor on the Spiral tab, then check Analysis and Coach tabs for computed insights.

No login required. No custom backend. Sleep/event data is stored locally via SwiftData, with optional private iCloud sync via CloudKit. The on-device AI model download (Phi-3.5) requires an internet connection on first setup only. The app does NOT write to HealthKit.
```

---

## Screenshot Sizes Required

| Device | Size |
|--------|------|
| iPhone 6.7" (required) | 1290 × 2796 px |
| iPhone 6.5" (optional) | 1284 × 2778 px |
| iPhone 5.5" (optional) | 1242 × 2208 px |
| iPad Pro 12.9" (if supporting iPad) | 2048 × 2732 px |

**Suggested screenshot sequence:**
1. Spiral view (main screen, full spiral visible)
2. DNA Insights (🧬 button — motifs, health markers)
3. Analysis tab (trend cards)
4. Coach tab (AI chat)
5. Apple Watch (spiral or stats view)

---

## HealthKit Review Justification

> Spiral Journey uses HealthKit exclusively to **read** the following data types:
>
> - **Sleep Analysis** (HKCategoryTypeIdentifierSleepAnalysis) — sleep stages (deep, REM, core, awake) used to compute circadian rhythm metrics (acrophase, MESOR, amplitude), detect patterns, and power the Sleep DNA engine.
> - **Heart Rate Variability** (HKQuantityTypeIdentifierHeartRateVariabilitySDNN) — nightly SDNN measurements used to compute HRV trends as part of the sleep health profile.
>
> All HealthKit data is processed entirely on-device. No health data is transmitted to external servers. The app does **not** write any data to HealthKit.
