# Spiral Journey

> Your day and sleep, visualized in spirals

iOS + watchOS app that visualizes your complete 24-hour cycle on a spiral. Not a simple sleep tracker — a chronobiological instrument based on circadian science.

## What is it

Spiral Journey models your sleep using **3 natural states** instead of the conventional 5 AASM stages. Research with 155+ subjects across 2 independent datasets reveals that sleep naturally organizes into an active pole (Wake + REM), a continuous NREM depth gradient, and REM as a distinct consciousness state geometrically close to wakefulness.

## Features

- **Circadian spiral** — 2D and 3D visualization of your sleep/wake cycle from Apple Health
- **DNA Insights** — your sleep encoded as a double helix with motifs, mutations, and sequence alignment
- **NeuroSpiral 4D** — sleep trajectory on a Clifford torus with 16 tesseract micro-states
- **3D double helix** — interactive RealityKit comparison between nights (Yesterday / Week / My Best)
- **Continuous depth gradient** — NREM depth measured by winding number, not discrete N1/N2/N3
- **AI Coach** — 100% on-device (Foundation Models on iOS 26+, Phi-3.5 GGUF fallback)
- **Apple Watch** — standalone app with spiral, stats, and NeuroSpiral minicard
- **Widgets** — spiral widget (last 7 nights) + circadian state widget
- **8 languages** — English, Spanish, Catalan, German, French, Japanese, Chinese, Arabic

## The science

The app is built on ongoing research applying Clifford torus geometry to sleep signals.

| | |
|---|---|
| **Subjects** | 155+ across 2 datasets |
| **Datasets** | HMC (142 subjects, C4-M1) and Sleep-EDF (13 recordings, Fpz-Cz) |
| **Natural states** | 3 (not 5) |
| **Wake-REM separation** | < 3.5 degrees on the Clifford torus |

**Key findings (based on ongoing research):**

- Sleep has two geometric poles: Active (Wake + REM, < 3.5 degrees apart) and Deep (NREM continuum, 12-14 degrees apart)
- NREM is a continuous depth gradient, not discrete N1/N2/N3 categories
- REM is geometrically almost identical to Wake — it belongs to the active pole
- The structure is universal across electrode locations and datasets

## Privacy

- All analysis runs on your device
- No accounts, no tracking, no ads
- No data sent to third-party servers
- Optional iCloud sync (your private CloudKit database)
- AI coach runs 100% on-device

[Full Privacy Policy](https://xaron98.github.io/spiral-journey/privacy-policy.html)

## Requirements

- iOS 17.0+
- watchOS 10.0+
- iPhone with Apple Health
- Apple Watch recommended (for sleep stage data)
- 3D features require iOS 18.0+

## Tech stack

Swift, SwiftUI, SpiralKit, SpiralGeometry, RealityKit, CoreML, HealthKit, WatchConnectivity, CloudKit, Foundation Models

## Contact

Carlos Javier Perea Gallego
[xaron98@gmail.com](mailto:xaron98@gmail.com)

## License

All rights reserved. Source code is private.
