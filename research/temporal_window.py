#!/usr/bin/env python3
"""
Ventana Temporal de 5 Epochs para Sleep Staging
================================================
Concatena features de epochs vecinos para capturar contexto temporal.

Epoch actual + 2 anteriores + 2 siguientes = 5 epochs × N features

Uso:
  python3 temporal_window.py ~/Downloads/neurospiral-complete/neurospiral/results/phase_a_full/phase_a_full_features.npz
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import cohen_kappa_score, f1_score, classification_report
import sys
import time

# ═══════════════════════════════════════════════════════════════
# CARGAR DATOS
# ═══════════════════════════════════════════════════════════════

if len(sys.argv) < 2:
    print("Uso: python3 temporal_window.py <path_to_features.npz>")
    sys.exit(1)

path = sys.argv[1]
print(f"Cargando {path}...")
data = np.load(path, allow_pickle=True)

# Features
X_ind = data['individual']      # (N, 96)  — 4 señales × 3τ × 8 features
X_coup = data['coupling']       # (N, 36)  — 6 pares × 6 features
y = data['stages']              # (N,)     — 0-4
subjects = data['subjects']     # (N,)     — subject IDs

# Combinar individual + coupling
X_base = np.hstack([X_ind, X_coup])  # (N, 132)

N, n_feat = X_base.shape
n_subjects = len(np.unique(subjects))
print(f"Epochs: {N:,}")
print(f"Features base: {n_feat}")
print(f"Sujetos: {n_subjects}")
print(f"Distribución: {dict(zip(*np.unique(y, return_counts=True)))}")

# ═══════════════════════════════════════════════════════════════
# CREAR VENTANA TEMPORAL
# ═══════════════════════════════════════════════════════════════

def create_temporal_window(X, subjects, window_half=2):
    """
    Para cada epoch, concatena features de epochs vecinos.
    Solo dentro del mismo sujeto (no cruza fronteras de sujeto).
    
    window_half=2 → 5 epochs: [t-2, t-1, t, t+1, t+2]
    Resultado: N × (n_feat × (2*window_half + 1))
    """
    N, n_feat = X.shape
    window_size = 2 * window_half + 1
    X_window = np.zeros((N, n_feat * window_size))
    
    for i in range(N):
        for offset in range(-window_half, window_half + 1):
            j = i + offset
            col_start = (offset + window_half) * n_feat
            col_end = col_start + n_feat
            
            # Verificar que j está en rango Y es del mismo sujeto
            if 0 <= j < N and subjects[j] == subjects[i]:
                X_window[i, col_start:col_end] = X[j]
            else:
                # Fuera de rango o distinto sujeto: usar epoch actual (padding)
                X_window[i, col_start:col_end] = X[i]
    
    return X_window

print(f"\nCreando ventanas temporales...")
t0 = time.time()

# Baseline: sin ventana
X_no_window = X_base  # (N, 132)

# Ventana de 3 epochs (t-1, t, t+1)
X_win3 = create_temporal_window(X_base, subjects, window_half=1)

# Ventana de 5 epochs (t-2, t-1, t, t+1, t+2)
X_win5 = create_temporal_window(X_base, subjects, window_half=2)

# Ventana de 7 epochs (t-3 ... t+3) — 3.5 min de contexto
X_win7 = create_temporal_window(X_base, subjects, window_half=3)

print(f"  Sin ventana: {X_no_window.shape}")
print(f"  Ventana 3:   {X_win3.shape}")
print(f"  Ventana 5:   {X_win5.shape}")
print(f"  Ventana 7:   {X_win7.shape}")
print(f"  Tiempo: {time.time()-t0:.1f}s")

# ═══════════════════════════════════════════════════════════════
# CLASIFICACIÓN CON StratifiedGroupKFold
# ═══════════════════════════════════════════════════════════════

def evaluate(X, y, subjects, label, n_splits=5):
    """Evalúa con StratifiedGroupKFold y RandomForest."""
    sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=42)
    
    kappas = []
    f1s = []
    y_true_all = []
    y_pred_all = []
    
    for fold, (train_idx, test_idx) in enumerate(sgkf.split(X, y, groups=subjects)):
        clf = RandomForestClassifier(
            n_estimators=200,
            max_depth=20,
            min_samples_leaf=5,
            n_jobs=-1,
            random_state=42
        )
        clf.fit(X[train_idx], y[train_idx])
        y_pred = clf.predict(X[test_idx])
        
        k = cohen_kappa_score(y[test_idx], y_pred)
        f1 = f1_score(y[test_idx], y_pred, average='macro')
        kappas.append(k)
        f1s.append(f1)
        y_true_all.extend(y[test_idx])
        y_pred_all.extend(y_pred)
    
    k_mean = np.mean(kappas)
    k_std = np.std(kappas)
    f1_mean = np.mean(f1s)
    f1_std = np.std(f1s)
    
    return {
        'label': label,
        'kappa_mean': k_mean,
        'kappa_std': k_std,
        'f1_mean': f1_mean,
        'f1_std': f1_std,
        'kappas': kappas,
        'y_true': y_true_all,
        'y_pred': y_pred_all,
    }

print(f"\n{'#'*65}")
print(f"  COMPARACIÓN: BASELINE vs VENTANA TEMPORAL")
print(f"  {n_subjects} sujetos, {N:,} epochs, StratifiedGroupKFold (5-fold)")
print(f"{'#'*65}")

configs = [
    (X_no_window, "Sin ventana (132 feat)"),
    (X_win3,      "Ventana 3 epochs (396 feat)"),
    (X_win5,      "Ventana 5 epochs (660 feat)"),
    (X_win7,      "Ventana 7 epochs (924 feat)"),
]

results = []
for X_config, label in configs:
    print(f"\n  Evaluando: {label}...")
    t0 = time.time()
    r = evaluate(X_config, y, subjects, label)
    elapsed = time.time() - t0
    results.append(r)
    print(f"    κ = {r['kappa_mean']:.3f} ± {r['kappa_std']:.3f}")
    print(f"    F1 = {r['f1_mean']:.3f} ± {r['f1_std']:.3f}")
    print(f"    Folds: {['%.3f' % k for k in r['kappas']]}")
    print(f"    Tiempo: {elapsed:.0f}s")

# ═══════════════════════════════════════════════════════════════
# RESUMEN
# ═══════════════════════════════════════════════════════════════

print(f"\n{'='*65}")
print(f"  RESUMEN")
print(f"{'='*65}")
print(f"  {'Configuración':<32s}  {'κ':>12s}  {'F1':>12s}  {'Δκ':>8s}")
print(f"  {'─'*32}  {'─'*12}  {'─'*12}  {'─'*8}")

baseline_k = results[0]['kappa_mean']
for r in results:
    dk = r['kappa_mean'] - baseline_k
    dk_str = f"+{dk:.3f}" if dk > 0 else f"{dk:.3f}"
    print(f"  {r['label']:<32s}  {r['kappa_mean']:.3f}±{r['kappa_std']:.3f}"
          f"  {r['f1_mean']:.3f}±{r['f1_std']:.3f}  {dk_str}")

best = max(results, key=lambda r: r['kappa_mean'])
print(f"\n  Mejor: {best['label']}")
print(f"  Δκ vs baseline: +{best['kappa_mean'] - baseline_k:.3f}")

if best['kappa_mean'] - baseline_k > 0.02:
    print(f"\n  ★ El contexto temporal mejora significativamente la clasificación.")
    print(f"    Esto confirma que los features geométricos capturan dinámica")
    print(f"    que se explota mejor con contexto secuencial.")
elif best['kappa_mean'] - baseline_k > 0.005:
    print(f"\n  ◆ Mejora modesta. El contexto temporal ayuda pero no resuelve")
    print(f"    completamente el gap — deep learning temporal sería el siguiente paso.")
else:
    print(f"\n  ○ El contexto temporal no mejora. Los features por epoch ya capturan")
    print(f"    la información disponible en esta resolución.")

# Per-stage report del mejor
print(f"\n  Classification report ({best['label']}):")
stage_names = ['W', 'N1', 'N2', 'N3', 'REM']
print(classification_report(best['y_true'], best['y_pred'], 
                            target_names=stage_names, digits=3))
