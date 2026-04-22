"""
Comparación justa: Espectrales vs Geométricos vs Combinados
============================================================
Todos con las mismas mejoras (Delta + LightGBM) para comparación limpia.

Uso: python3 comparacion_justa.py
"""

import subprocess
subprocess.run(['pip3', 'install', 'lightgbm', '-q'])

import numpy as np
import lightgbm as lgb
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import cohen_kappa_score, f1_score, classification_report
import time

path = '/Users/xaron/Downloads/neurospiral-complete/neurospiral/results/hmc_features_multiscale.npz'
print(f"Cargando {path}...")
data = np.load(path, allow_pickle=True)

X_spec = data['features_spectral']    # (115378, 8)
X_geom = data['features_geometric']   # (115378, 57)
X_comb = np.hstack([X_spec, X_geom])  # (115378, 65)
y = data['stages'].astype(int)
subjects = data['subjects']

N = len(y)
n_subjects = len(np.unique(subjects))
stage_names = ['W', 'N1', 'N2', 'N3', 'REM']

print(f"Epochs: {N:,} | Sujetos: {n_subjects}")
print(f"Spectral: {X_spec.shape[1]} feat | Geometric: {X_geom.shape[1]} feat | Combined: {X_comb.shape[1]} feat")
print(f"Spectral names: {list(data['feature_names_spectral'])}")
unique, counts = np.unique(y, return_counts=True)
for s, c in zip(unique, counts):
    print(f"  {stage_names[s]}: {c:,} ({100*c/N:.1f}%)")

# ═══════════════════════════════════════════════════════════════
# DELTA FEATURES
# ═══════════════════════════════════════════════════════════════

def add_delta(X, subjects):
    deltas = np.zeros_like(X)
    for i in range(1, len(X)):
        if subjects[i] == subjects[i - 1]:
            deltas[i] = X[i] - X[i - 1]
    return np.hstack([X, deltas])

print("\nCreando delta features...")
X_spec_d = add_delta(X_spec, subjects)   # 16 feat
X_geom_d = add_delta(X_geom, subjects)   # 114 feat
X_comb_d = add_delta(X_comb, subjects)   # 130 feat
print(f"  Spectral+delta: {X_spec_d.shape}")
print(f"  Geometric+delta: {X_geom_d.shape}")
print(f"  Combined+delta: {X_comb_d.shape}")

# ═══════════════════════════════════════════════════════════════
# EVALUACION
# ═══════════════════════════════════════════════════════════════

def evaluate(X, y, subjects, label, n_splits=5):
    sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=42)
    kappas, f1s = [], []
    y_true_all, y_pred_all = [], []

    for fold, (train_idx, test_idx) in enumerate(sgkf.split(X, y, groups=subjects)):
        clf = lgb.LGBMClassifier(
            n_estimators=300, max_depth=15, learning_rate=0.05,
            num_leaves=63, min_child_samples=20,
            subsample=0.8, colsample_bytree=0.8,
            n_jobs=-1, random_state=42, verbose=-1)
        clf.fit(X[train_idx], y[train_idx])
        y_pred = clf.predict(X[test_idx])

        k = cohen_kappa_score(y[test_idx], y_pred)
        f1 = f1_score(y[test_idx], y_pred, average='macro')
        kappas.append(k)
        f1s.append(f1)
        y_true_all.extend(y[test_idx])
        y_pred_all.extend(y_pred)
        print(f"    Fold {fold+1}: k={k:.3f}")

    return {
        'label': label,
        'kappa_mean': np.mean(kappas), 'kappa_std': np.std(kappas),
        'f1_mean': np.mean(f1s), 'f1_std': np.std(f1s),
        'y_true': y_true_all, 'y_pred': y_pred_all,
    }

# ═══════════════════════════════════════════════════════════════
# CORRER
# ═══════════════════════════════════════════════════════════════

print(f"\n{'#'*65}")
print(f"  COMPARACION JUSTA: SPECTRAL vs GEOMETRIC vs COMBINED")
print(f"  Todas con Delta + LightGBM")
print(f"  {n_subjects} sujetos, {N:,} epochs, StratifiedGroupKFold")
print(f"{'#'*65}")

configs = [
    # Sin deltas (baseline de cada tipo)
    (X_spec,   "1. Spectral (8 feat)"),
    (X_geom,   "2. Geometric (57 feat)"),
    (X_comb,   "3. Combined (65 feat)"),
    # Con deltas (la mejora que funciona)
    (X_spec_d, "4. Spectral + delta (16 feat)"),
    (X_geom_d, "5. Geometric + delta (114 feat)"),
    (X_comb_d, "6. Combined + delta (130 feat)"),
]

results = []
for X_cfg, label in configs:
    print(f"\n  {label}...")
    t0 = time.time()
    r = evaluate(X_cfg, y, subjects, label)
    elapsed = time.time() - t0
    results.append(r)
    print(f"  -> k = {r['kappa_mean']:.3f} +/- {r['kappa_std']:.3f} | "
          f"F1 = {r['f1_mean']:.3f} | {elapsed:.0f}s")

# ═══════════════════════════════════════════════════════════════
# RESUMEN
# ═══════════════════════════════════════════════════════════════

print(f"\n{'='*70}")
print(f"  RESUMEN — COMPARACION JUSTA")
print(f"{'='*70}")
print(f"  {'Config':<36s}  {'n_feat':>6s}  {'kappa':>12s}  {'F1':>10s}")
print(f"  {'_'*36}  {'_'*6}  {'_'*12}  {'_'*10}")

for r in results:
    n = r['label'].split('(')[1].split(')')[0] if '(' in r['label'] else '?'
    print(f"  {r['label']:<36s}  {n:>6s}  {r['kappa_mean']:.3f}+/-{r['kappa_std']:.3f}"
          f"  {r['f1_mean']:.3f}+/-{r['f1_std']:.3f}")

# Comparaciones clave
print(f"\n  PREGUNTAS CLAVE:")
spec = results[0]['kappa_mean']
geom = results[1]['kappa_mean']
comb = results[2]['kappa_mean']
spec_d = results[3]['kappa_mean']
geom_d = results[4]['kappa_mean']
comb_d = results[5]['kappa_mean']

print(f"\n  1. Geometric vs Spectral (sin delta):")
if geom > spec:
    print(f"     Geometric GANA: {geom:.3f} vs {spec:.3f} (delta_k = +{geom-spec:.3f})")
else:
    print(f"     Spectral GANA: {spec:.3f} vs {geom:.3f} (delta_k = +{spec-geom:.3f})")

print(f"\n  2. Geometric vs Spectral (con delta):")
if geom_d > spec_d:
    print(f"     Geometric GANA: {geom_d:.3f} vs {spec_d:.3f} (delta_k = +{geom_d-spec_d:.3f})")
else:
    print(f"     Spectral GANA: {spec_d:.3f} vs {geom_d:.3f} (delta_k = +{spec_d-geom_d:.3f})")

print(f"\n  3. Combined vs mejor individual:")
best_ind = max(spec_d, geom_d)
best_name = "Spectral+d" if spec_d > geom_d else "Geometric+d"
if comb_d > best_ind:
    print(f"     Combined GANA: {comb_d:.3f} vs {best_name} {best_ind:.3f} (delta_k = +{comb_d-best_ind:.3f})")
    print(f"     -> Los features son COMPLEMENTARIOS")
else:
    print(f"     {best_name} GANA: {best_ind:.3f} vs Combined {comb_d:.3f}")
    print(f"     -> Combinar no aporta (posible redundancia o ruido)")

print(f"\n  4. Aporte de los deltas:")
print(f"     Spectral: {spec:.3f} -> {spec_d:.3f} (delta_k = +{spec_d-spec:.3f})")
print(f"     Geometric: {geom:.3f} -> {geom_d:.3f} (delta_k = +{geom_d-geom:.3f})")
print(f"     Combined: {comb:.3f} -> {comb_d:.3f} (delta_k = +{comb_d-comb:.3f})")

# Classification report del mejor
best = max(results, key=lambda r: r['kappa_mean'])
print(f"\n  Classification report ({best['label']}):")
print(classification_report(best['y_true'], best['y_pred'],
                            target_names=stage_names, digits=3))
