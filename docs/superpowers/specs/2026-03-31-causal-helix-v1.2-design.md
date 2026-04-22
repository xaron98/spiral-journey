# Causal Helix — v1.2 Design Spec

**Date:** 2026-03-31
**Status:** CONCEPT — not for implementation yet

## The Insight

The helix currently compares night-vs-night (result vs result). It should compare day-vs-night (cause vs effect). The user doesn't need to see "anoche dormí parecido a antes de ayer." They need to see "esto es lo que hiciste y esto es lo que le hizo a tu sueño."

## Architecture

### Two hebras with DIFFERENT roles (like real DNA)

**Gold helix (Day strand):** Events from the user's day, positioned by clock hour.
```
07:00 🏃 Gym (45min)
09:00 ☕ Café
15:00 ☕ Café  ← Hawkes: α=0.35, decay=4h
20:00 📱 Screen
22:00 📱 Screen  ← Hawkes: α=0.20, decay=2h
```

Each event is a node on the gold backbone. Color = event type. Size = Hawkes excitation strength.

**Silver helix (Night strand):** Sleep phases as continuous depth gradient (not discrete W/L/D/R).
```
23:00 ████ Light
23:30 ████████ Deep (good — morning gym effect)
00:00 ████ Light (bad — 15:00 café effect)
00:30 ████████ Deep (recovery)
01:00 ████ REM
```

Color = depth gradient from Watch phases (gold→indigo). Size = depth intensity.

### Connector bars: CAUSAL LINKS (not phase comparison)

Each bar connects a day event to a night phase it affects:
```
Gym 07:00 ──────────── Deep 23:30   (PLV=0.72, GREEN)
Café 15:00 ─────────── Light 00:00  (PLV=0.82, RED)
Screen 22:00 ──────── REM delay     (PLV=0.45, AMBER)
```

**Bar color** = impact direction:
- Green = beneficial (event correlates with more Deep/better sleep)
- Red = harmful (event correlates with more fragmentation/less Deep)
- Amber = moderate/unclear

**Bar thickness** = PLV strength (0.3-1.0 → thin to thick)

**Bar length** = Hawkes decay (how far the impact reaches into the night)

### Tap interaction

Tap a bar → tooltip shows:
```
"☕ Café a las 15:00 → Primer Deep retrasado 40 min"
"Últimas 3 semanas: café después de las 14:00 reduce tu Deep un 31%"
"PLV = 0.82 (conexión fuerte)"
```

## Data sources (all already exist)

### Day strand
- `CircadianEvent` array with `.absoluteHour` and `.type` (coffee, exercise, alcohol, melatonin, stress)
- `DayHealthProfile` with steps, exercise minutes, calories, resting HR, workouts
- `EventKit` calendar with context blocks (work, study, commute)

### Night strand
- `SleepRecord.phases` — 15-min intervals with Watch phase (deep/light/rem/awake)
- `NightlyHRV.meanSDNN` — proxy for sleep depth quality

### Causal links
- `HawkesEventModel.analyze()` → per-event α (excitation), delay (hours), significance
- `HilbertPhaseAnalyzer.analyze()` → per-pair PLV score, lag in days
- `BasePairSynchrony` → feature indices + PLV + meanPhaseDiff

## What exists vs what needs building

```
EXISTS (in SpiralKit):
  ✅ DayNucleotide with 16 features (8 sleep + 8 context)
  ✅ HilbertPhaseAnalyzer → PLV for 64 pairs
  ✅ HawkesEventModel → α, decay, significance per event type
  ✅ CircadianEvent logs with timestamps
  ✅ SleepRecord.phases with Watch data
  ✅ DayHealthProfile with 13 signals

NEEDS BUILDING:
  ❌ New HelixSceneBuilder mode: day-vs-night (not night-vs-night)
  ❌ Event nodes on gold backbone (positioned by hour, colored by type)
  ❌ Causal connector bars (color=impact, thickness=PLV, length=decay)
  ❌ Cascade tooltip ("Your 15:00 coffee delayed Deep by 40 min")
  ❌ Aggregation engine: "café after 14:00 reduces Deep by 31% over 3 weeks"
  ❌ Visual: Hawkes decay curve overlay (how impact fades over hours)
```

## The DNA metaphor alignment

```
Real DNA:                         Causal Helix:
─────────                         ──────────────
Sense strand (template)           Day strand (cause)
Antisense strand (complement)     Night strand (effect)
Codons = 3 bases → 1 amino acid  Codons = day pattern → sleep effect
Genetic code TRANSLATES           App DISCOVERS the personal
  one strand to the other           "sleep code" for each user
```

## Event type colors (for day strand nodes)

```
☕ Caffeine:  #8B4513 (brown)
🏃 Exercise:  #22c55e (green)
🍷 Alcohol:   #dc2626 (red)
💊 Melatonin: #6366f1 (indigo)
😰 Stress:    #f97316 (orange)
📱 Screen:    #3b82f6 (blue)
📅 Work:      #64748b (slate)
🧘 Mindful:   #14b8a6 (teal)
```

## Impact bar colors

```
Beneficial (more Deep, less fragmentation): #22c55e (green)
Harmful (less Deep, more fragmentation):    #ef4444 (red)
Neutral/moderate:                           #f59e0b (amber)
```

## Causal Codons — Personal Sleep Code

In real DNA, a codon is 3 consecutive bases that encode 1 amino acid.
In the Causal Helix, a codon is a **combination of 2-3 day events** that
together predict a specific sleep outcome better than any single event alone.

### Examples of personal sleep codons

```
BENEFICIAL CODONS:
  [gym_morning, no_café_afternoon, no_screen_night] → Deep excellent (+40%)
  [daylight_30min, exercise, early_dinner]           → REM duration +25%
  [meditation, no_alcohol, consistent_bedtime]       → Fragmentation -50%

HARMFUL CODONS:
  [no_exercise, café_16h, screen_23h]                → Deep poor (-35%)
  [alcohol, late_dinner, stress]                     → Fragmentation +60%
  [weekend_sleep_in, no_daylight, caffeine]          → Drift +45 min
```

### How to detect them

Hawkes and PLV measure INDIVIDUAL event→sleep links. Codons are COMBINATIONS.

**Detection algorithm:**
1. For each night, encode the day as a binary vector of events:
   `[gym=1, café_after_14=1, screen_after_22=0, alcohol=0, stress=1, ...]`
2. Encode the night outcome as a quality vector:
   `[deep_minutes, rem_minutes, fragmentation_count, sleep_efficiency]`
3. Find 2-3 event combinations that predict night quality better than
   singles using interaction terms in a simple regression:
   ```
   deep_minutes ~ café_after_14 * screen_after_22
                  (interaction = the COMBINATION effect)
   ```
4. If the interaction coefficient is significant (p<0.05) AND its effect
   is larger than either individual effect → that's a codon.
5. Rank codons by effect size. Top 3-5 = the user's "sleep code."

### What the user sees

In the helix view, codons appear as **grouped connector bars** — multiple
day events converging on the same night region:

```
  ☕ Café 15:00 ──┐
                   ├──── Deep 00:00 (40 min shorter)
  📱 Screen 22:00 ─┘

  "Codón detectado: Café tarde + Pantalla noche
   → reduce tu sueño profundo un 35%.
   Ocurrió 8 de las últimas 14 noches."
```

In the DNA Insights codons section (DNACodonSection), the triplet alphabet
evolves from phase transitions (LDR, DDR) to cause→effect patterns.

### Data requirements

- Minimum 14 nights with event logs to detect significant interactions
- At least 4 occurrences of a combination to establish pattern
- SleepBLOSUM weights can inform which features matter most per user

### Existing infrastructure to reuse

- `DayNucleotide.features[8-15]` — already encodes day events as 0/1 or normalized
- `HawkesEventModel.eventImpacts` — individual event strengths (baseline)
- `HilbertPhaseAnalyzer` — PLV for timing relationships
- `SleepBLOSUM.learn()` — personalized feature weights
- `MotifDiscovery` — can cluster similar day→night patterns into recurring codons

## Implementation priority

1. Add event nodes to gold backbone (CircadianEvent → position by hour)
2. Change silver backbone from "previous night" to "current night depth gradient"
3. Add causal bars using Hawkes α + PLV
4. Tap tooltip with cascade description
5. Weekly aggregation ("café after 14:00 always hurts your Deep")
6. Codon detection: interaction terms in day→night regression
7. Codon visualization: grouped bars + "sleep code" summary card

## NOT in scope for v1.2

- Real ω₁ from EEG (needs hardware)
- Continuous depth from raw PPG (Apple doesn't expose)
- Screen time (needs ScreenTime API entitlement)
- Predictive: "if you drink coffee now, your Deep will..." (v2.0)
- Causal inference (Granger, do-calculus) — regression interaction is sufficient for v1.2
