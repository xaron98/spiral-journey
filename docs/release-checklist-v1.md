# Release Checklist — Spiral Journey v1.0

**Target:** Lunes 23 o Martes 24 de marzo 2026
**Status:** Pre-submission

---

## Viernes 21 marzo — Testing & Fixes

### Functional Testing (en dispositivo real)

- [ ] **Fresh install** — borrar app, instalar desde Xcode, verificar:
  - [ ] Onboarding aparece con disclaimer médico
  - [ ] Selección de idioma funciona
  - [ ] Sin HealthKit la app funciona (sin datos, sin crash)
  - [ ] Con HealthKit importa datos correctamente

- [ ] **Espiral** — probar cada modo:
  - [ ] Archimedean 2D: cursor, zoom, path visible
  - [ ] Archimedean 3D: cursor, zoom, autoFitScale, sin fragmentos
  - [ ] Logarithmic 2D: visualmente distinta de archimedean
  - [ ] Logarithmic 3D: cursor, zoom, sin fragmentos
  - [ ] Cursor al pasado: datos NO desaparecen
  - [ ] Cursor al futuro: vigilia se extiende, zoom se adapta
  - [ ] Tap en path: muestra info correcta (sleep/awake/evento)
  - [ ] Eventos del calendario: no se repiten, se ven en su día

- [ ] **Consistencia** — verificar:
  - [ ] Heatmap muestra colores correctos (verde/amarillo/rojo)
  - [ ] Botón ? muestra definiciones
  - [ ] Insights detectados coherentes con tu experiencia
  - [ ] Duración en horas (no minutos) cuando ≥ 1h

- [ ] **DNA Insights** — verificar:
  - [ ] Botón 🧬 aparece y abre
  - [ ] Secciones narrativas se cargan
  - [ ] 3D helix se renderiza (si ≥ 3 días)
  - [ ] Cuestionario semanal aparece
  - [ ] Disclaimer visible al fondo
  - [ ] Hélice 3D: rotar, zoom funciona

- [ ] **Coach** — verificar:
  - [ ] Consent prompt aparece antes de descargar
  - [ ] Info del modelo (tamaño, fuente) visible
  - [ ] Check de espacio funciona
  - [ ] Chat funciona tras descargar (o Foundation Models en iOS 26)
  - [ ] Disclaimer visible
  - [ ] Si Foundation Models disponible: coach instant sin descarga

- [ ] **Settings** — verificar:
  - [ ] Todos los toggles funcionan
  - [ ] Export CSV genera archivos
  - [ ] Links: Privacy Policy, Support, Website abren
  - [ ] Disclaimer médico visible en About
  - [ ] Consent toggles (iCloud Sync, AI Coach)
  - [ ] Background task toggles
  - [ ] Cambio de idioma aplica correctamente
  - [ ] Cambio de tema (dark/light/system)

- [ ] **Watch** — verificar:
  - [ ] Datos se sincronizan iPhone → Watch
  - [ ] Datos del Watch llegan al iPhone (anchored query)
  - [ ] Espiral se renderiza correctamente
  - [ ] Complicaciones funcionan

- [ ] **Widget** — verificar:
  - [ ] Widget muestra espiral correcta
  - [ ] Sin recuadro visible (background fix)
  - [ ] Datos completos (sin path cortado)

- [ ] **Edge cases**:
  - [ ] Abrir/cerrar app rápidamente: sin crash
  - [ ] Background → foreground: datos se actualizan
  - [ ] Sin internet: app funciona (excepto descarga coach)
  - [ ] Rotación pantalla (si aplica)
  - [ ] Low memory: sin crash (timer fix en HelixRealityView)

### Fixes urgentes si encuentras bugs
- Prioriza crashes > datos incorrectos > visual > cosmético

---

## Sábado 22 marzo — Polish & Metadata

### App Store Connect

- [ ] **Crear app en App Store Connect** (si no existe)
- [ ] **App Information:**
  - [ ] Nombre: Spiral Journey
  - [ ] Subtítulo: Sleep · Wake Cycle Tracker
  - [ ] Categoría primaria: Health & Fitness
  - [ ] Categoría secundaria: (no Medical — evita escrutinio extra)
  - [ ] Rating: 4+ (sin contenido objetable)

- [ ] **Pricing:** Free (o el modelo que elijas)

- [ ] **Privacy:**
  - [ ] Privacy Policy URL: https://xaron98.github.io/spiral-journey/privacy-policy.html
  - [ ] App Privacy questionnaire completado:
    - [ ] Health data: collected, linked to user (via iCloud)
    - [ ] Usage data: not collected
    - [ ] No tracking

- [ ] **App Review Information:**
  - [ ] Review notes: copiar de `docs/app-store-metadata.md`
  - [ ] Demo account: no necesario (app no tiene login)
  - [ ] Contact info para reviewers

### Screenshots (obligatorio)

- [ ] **iPhone 6.7"** (iPhone 15 Pro Max / 16 Pro Max) — mínimo 3, recomendado 6:
  1. Espiral principal con datos (modo 3D si se ve bien)
  2. DNA Insights — "Tu ritmo hoy"
  3. Consistencia — heatmap con colores
  4. Coach chat en acción
  5. Settings con disclaimer visible
  6. Espiral con eventos del calendario

- [ ] **iPhone 6.1"** (iPhone 15 / 16) — mismos screenshots escalados

- [ ] **iPad** (si soportas iPad) — o marca "iPhone only"

- [ ] **Apple Watch** — si publicas el Watch app:
  1. Espiral en Watch
  2. Complicación

### Textos finales

- [ ] **Descripción (4000 chars max):**
  - Copiar/adaptar de `docs/app-store-metadata.md`
  - EN + ES mínimo
  - No mencionar tabs que no existen
  - No hacer claims médicos

- [ ] **What's New:** "Initial release"

- [ ] **Keywords (100 chars):** sleep, circadian, rhythm, tracker, spiral, DNA, health, watch, analysis, coach

- [ ] **Support URL:** https://github.com/xaron98/spiral-journey/issues

---

## Domingo 23 marzo — Build & Submit

### Build final

- [ ] **Version & Build:**
  - [ ] Version: 1.0.0
  - [ ] Build: 1 (o fecha: 20260323)
  - [ ] Verificar en Info.plist / Xcode target

- [ ] **Scheme:** Release (no Debug)
  - [ ] Product → Archive
  - [ ] Validate antes de upload

- [ ] **Tests finales:**
  - [ ] `cd SpiralKit && swift test` — todo pasa
  - [ ] Build iOS Release: sin warnings
  - [ ] Build Watch Release: sin warnings

- [ ] **Archive & Upload:**
  - [ ] Product → Archive
  - [ ] Distribute App → App Store Connect
  - [ ] Esperar procesamiento (~10-30 min)

### Pre-submit review

- [ ] **Verificar en TestFlight:**
  - [ ] Instalar build desde TestFlight
  - [ ] Fresh install flow completo
  - [ ] CloudKit sync funciona en Release
  - [ ] HealthKit funciona en Release
  - [ ] No crashes

- [ ] **Última revisión:**
  - [ ] Screenshots coinciden con build final
  - [ ] Review notes son precisas
  - [ ] Privacy policy está live y actualizada
  - [ ] No hay TODOs o debug logs visibles al usuario
  - [ ] Disclaimers visibles

### Submit

- [ ] **Submit for Review** en App Store Connect
- [ ] **Expedited Review:** no necesario para v1 (solo para fixes urgentes)
- [ ] **Release:** Manual (para controlar el timing) o Automático

---

## Post-submit

- [ ] Monitorizar estado en App Store Connect
- [ ] Responder preguntas de review rápidamente
- [ ] Preparar marketing: post en redes, actualizar landing
- [ ] Planificar v1.1 con feedback de usuarios

---

## Checklist rápido de "NO hacer"

- ❌ No mencionar "diagnóstico" ni "consejo médico" en ningún texto público
- ❌ No decir "los datos nunca salen del dispositivo" (CloudKit sí sincroniza)
- ❌ No referenciar tabs que no existen (Input, Learn)
- ❌ No usar categoría "Medical" en App Store
- ❌ No subir con debug logs activos
- ❌ No subir sin haber probado en TestFlight
- ❌ No subir sin screenshots reales del build final
