# Auditoría técnica y de publicación — Spiral Journey (2026-03)

## Hallazgos clave

1. **Inconsistencia de privacidad/documentación**: la app declara “nada sale del dispositivo”, pero el código inicializa sync con CloudKit y descarga de modelo desde Hugging Face para el coach IA.
2. **Rendimiento/batería**: hay polling de HealthKit cada 5 segundos en foreground.
3. **Arquitectura de persistencia**: estado completo serializado a `UserDefaults` en muchos `didSet`; esto escala peor al crecer historial.
4. **Calidad de código**: se eliminó una variable no usada en `CoachEngine` para evitar warnings.

## Recomendaciones

- Convertir “sync always-on” a toggle explícito de usuario con copy legal claro.
- Migrar persistencia pesada a SQLite/SwiftData y mantener `UserDefaults` solo para preferencias.
- Sustituir polling fijo por eventos + backoff adaptativo (15s/30s/60s) según actividad.
- Añadir disclaimer visible “no es consejo médico/diagnóstico” en onboarding y ficha de App Store.
