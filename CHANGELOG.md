# Changelog

All notable changes to Spiral Journey will be documented in this file.

---

## [1.1.0] — Partial Unreleased

### New Features
- **Sleep Triangle**: Barycentric triangle visualization of sleep architecture. Three poles (Wake, Active, Deep) based on empirical data from 155+ subjects. Each epoch maps to a point inside the triangle — showing your brain's position between wakefulness, dreaming, and deep rest. Animated trajectory with playback controls. Accessible from DNA Insights (triangle icon).
- **NeuroSpiral 4D**: Clifford torus sleep analysis with 16 tesseract micro-states, animated trajectory, per-night history sparklines, and CSV export for research validation.
- **3D Torus Visualization**: Interactive RealityKit torus with stereographic 4D→3D projection, drag/pinch/4D angle slider. Toggle 2D/3D in both torus detail and trajectory views.
- **3D Double Helix Redesign**: Molecular DNA model with smooth cylindrical backbones (gold = current period, silver = comparison), phase-colored connector bars, 3 comparison modes (Yesterday / Week / My Best), tap-to-inspect with phase tooltip.
- **Natural Sleep Model**: 3 states (Wake, NREM gradient, REM) replace 5 AASM stages. Colors reflect geometric poles — gold (wake), violet (REM), blue gradient (NREM light→deep). Validated with HMC (142 subjects) and Sleep-EDF (13 recordings).
- **DNA Info Sheet**: 12-section educational guide explaining Sleep DNA metaphor, with macro/micro bridge connecting DNA and NeuroSpiral.
- **Torus Comparison Metrics**: Jensen-Shannon divergence for vertex distribution similarity, torus consistency as 6th sub-metric in SpiralConsistencyCalculator.
- **Watch NeuroSpiral Card**: Tab 5 on Apple Watch showing stability %, dominant vertex, and winding ratio from iPhone analysis.
- **CSV Export + Python Loader**: Export sleep epochs with torus coordinates. Python `watch_loader.py` integrates with the NeuroSpiral research pipeline.

### Bug Fixes
- **Cursor sleep/awake detection**: Fixed false "Sleep" labels during awake hours. Now uses absolute hours for day-boundary comparison and shows specific phase (Deep sleep, Light sleep, REM, Brief awakening) with correct colors.
- **Weekly notification score**: Notification now reschedules after every analysis recompute, showing the current score instead of the value from when notifications were first enabled.
- **Spiral zoom after reset**: After "Reset All Data" + reimport, the spiral now resets zoom to 7 turns instead of staying at 1 turn with 60 turns of data (appeared as wrong period/zoom).
- **HealthKit sync retry**: Foreground sync now retries at 5s, 15s, and 30s (was single retry at 10s) to handle slow Watch Bluetooth transfers. Shows "Updating..." indicator.
- **Force unwrap crashes**: Fixed 4 production force unwraps in DiscoveryDetector, PredictionFeatureBuilder, and LearnTab.
- **Consistency weight sum**: Fixed pre-existing bug where weights summed to 1.0125 instead of 1.0.
- **Helix rebuild on mode change**: Fixed entity collection mutation during iteration that caused connector bars to disappear when switching comparison modes.

### Improvements
- **Coaching nocebo audit**: 13 string fixes replacing negative predictions with positive prescriptions. "Disorganized" → "Building", removed unqualified health claims, added reversibility language.
- **Phase colors**: Wake = gold, REM = soft violet, NREM = blue gradient. Consistent across spiral, DNA helix, NeuroSpiral torus, and all 5 themes.
- **Phase legend**: Added below the 3D helix with strand identity (gold = today, silver = yesterday) and phase color key.
- **NSHealthUpdateUsageDescription**: Added to iOS and Watch Info.plist.
- **Privacy policy**: Updated with NeuroSpiral processing and email contact.
- **GitHub Pages**: Complete redesign with features grid, science section, and privacy box.
- **Localization**: ~60 new keys across 8 languages for NeuroSpiral, triangle, tooltips, and helix comparison modes.

---

## [1.0.0] — March 2026

Initial release.

- Circadian spiral visualization (2D/3D, archimedean/logarithmic)
- Sleep DNA Engine with motifs, mutations, sequence alignment
- 3D double helix (RealityKit)
- AI Coach (Foundation Models + Phi-3.5 GGUF, 100% on-device)
- ML sleep prediction with on-device retraining
- Apple Watch companion app
- Home screen widgets (spiral + state)
- Coaching system with context-aware recommendations
- Peer comparison via Multipeer Connectivity
- 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans)
- CloudKit sync (optional)
- HealthKit integration with background delivery
