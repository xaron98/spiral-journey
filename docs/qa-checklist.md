# QA Checklist — Pre-Submission

Repeatable checklist for every build candidate before App Store submission.

## Functional Tests

- [ ] Fresh install without HealthKit — onboarding completes, manual entry works
- [ ] Fresh install with HealthKit — permissions requested, data imported
- [ ] Onboarding complete flow — all steps, skip paths, back navigation
- [ ] Chronotype questionnaire — all questions, result screen, saved to profile
- [ ] Spiral navigation (all 4 modes: arch 2D/3D, log 2D/3D)
- [ ] Analysis tab — consistency score, trends chart, weekly summary
- [ ] Coach — download / cancel / retry / delete / chat
  - [ ] Download prompt shows model name, size, source, Wi-Fi note
  - [ ] Low storage warning appears when < 3 GB free
  - [ ] Download progress displays correctly
  - [ ] Cancel mid-download works cleanly
  - [ ] Delete model in Settings frees space
  - [ ] Chat streaming and stop button work
- [ ] Settings — all toggles, language switch, export CSV
- [ ] DNA Insights — button, sections, questionnaire
- [ ] CloudKit sync (2 devices)
  - [ ] Episode created on device A appears on device B
  - [ ] Event created on device A appears on device B
  - [ ] Episode deleted on device A is deleted on device B (not events)
  - [ ] Event deleted on device A is deleted on device B (not episodes)
- [ ] Watch sync (iPhone to Watch, Watch to iPhone)
- [ ] Calendar permission deny/allow
- [ ] Background resume / foreground refresh
- [ ] Export data (CSV)
- [ ] Dark mode / Light mode / System
- [ ] All 8 languages (EN, ES, CA, DE, FR, ZH, JA, AR)

## App Review Package

- [ ] Review notes final (`docs/app-store-metadata.md`)
- [ ] Privacy URL live and accessible
- [ ] Support URL live and accessible
- [ ] Screenshots match current build
- [ ] Metadata matches actual features
- [ ] Disclaimers visible (Settings, DNA, Coach)
- [ ] HealthKit permissions described accurately
- [ ] No references to non-existent tabs/features

## Technical

- [ ] All tests pass (440+)
- [ ] iOS build succeeds
- [ ] Watch build succeeds
- [ ] No compiler warnings
- [ ] Entitlements Debug/Release aligned
- [ ] No `@unchecked Sendable` remaining
- [ ] `PrivacyInfo.xcprivacy` consistent
