"""
4 Mejoras sobre el Pipeline de Sueño — Versión Local Mac
=========================================================
1. Delta features (velocidad de cambio entre epochs)
2. Pesos de clase (atención extra a N1)
3. LightGBM (aprende de sus errores)
4. HMM post-smoothing (corrige secuencias imposibles)

Uso: python3 mejoras_local.py
"""

import subprocess
subprocess.run(['pip3', 'install', 'lightgbm', '-q'])

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import cohen_kappa_score, f1_score, classification_report, recall_score
import lightgbm as lgb
import time

path = '/Users/xaron/Downloads/neurospiral-complete/neurospiral/results/phase_a_full/phase_a_full_features.npz'

print(f"Cargando {path}...")
data = np.load(path, allow_pickle=True)

X_ind = data['individual']
X_coup = data['coupling']
y = data['stages'].astype(int)
subjects = data['subjects']

X_base = np.hstack([X_ind, X_coup])
N, n_feat = X_base.shape
n_subjects = len(np.unique(subjects))
print(f"Epochs: {N:,} | Features: {n_feat} | Sujetos: {n_subjects}")

stage_names = ['W', 'N1', 'N2', 'N3', 'REM']
unique, counts = np.unique(y, return_counts=True)
for s, c in zip(unique, counts):
    print(f"  {stage_names[s]}: {c:,} ({100*c/N:.1f}%)")

def add_delta_features(X, subjects):
    N, nf = X.shape
    deltas = np.zeros_like(X)
    for i in range(1, N):
        if subjects[i] == subjects[i - 1]:
            deltas[i] = X[i] - X[i - 1]
    return np.hstack([X, deltas])

print("\nCreando delta features...")
X_delta = add_delta_features(X_base, subjects)
print(f"  Base: {X_base.shape} -> Con deltas: {X_delta.shape}")

def build_transition_matrix(y, subjects, n_classes=5):
    trans = np.zeros((n_classes, n_classes))
    for i in range(1, len(y)):
        if subjects[i] == subjects[i - 1]:
            trans[y[i - 1], y[i]] += 1
    row_sums = trans.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1
    trans = trans / row_sums
    trans = (trans + 1e-4)
    trans = trans / trans.sum(axis=1, keepdims=True)
    return trans

def hmm_smooth(y_pred, y_proba, subjects, transition_matrix):
    n_classes = transition_matrix.shape[0]
    y_smoothed = y_pred.copy()
    log_trans = np.log(transition_matrix + 1e-10)
    unique_subjects = np.unique(subjects)
    for subj in unique_subjects:
        mask = subjects == subj
        idx = np.where(mask)[0]
        if len(idx) < 2:
            continue
        proba = y_proba[idx]
        T = len(idx)
        log_proba = np.log(proba + 1e-10)
        V = np.zeros((T, n_classes))
        B = np.zeros((T, n_classes), dtype=int)
        V[0] = log_proba[0]
        for t in range(1, T):
            for j in range(n_classes):
                scores = V[t - 1] + log_trans[:, j] + log_proba[t, j]
                B[t, j] = np.argmax(scores)
                V[t, j] = scores[B[t, j]]
        path = np.zeros(T, dtype=int)
        path[-1] = np.argmax(V[-1])
        for t in range(T - 2, -1, -1):
            path[t] = B[t + 1, path[t + 1]]
        y_smoothed[idx] = path
    return y_smoothed

print("\nCalculando matriz de transicion del sueno...")
trans_matrix = build_transition_matrix(y, subjects)
print("  Matriz de transicion (filas=desde, columnas=hacia):")
print(f"  {'':>6s}  {'W':>6s}  {'N1':>6s}  {'N2':>6s}  {'N3':>6s}  {'REM':>6s}")
for i, name in enumerate(stage_names):
    row = '  '.join(f"{trans_matrix[i, j]:6.3f}" for j in range(5))
    print(f"  {name:>6s}  {row}")

def evaluate(X, y, subjects, label, classifier='rf', use_weights=False,
             use_hmm=False, trans_matrix=None, n_splits=5):
    sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=42)
    kappas, f1s = [], []
    kappas_pre_hmm = []
    y_true_all, y_pred_all = [], []
    for fold, (train_idx, test_idx) in enumerate(sgkf.split(X, y, groups=subjects)):
        X_train, X_test = X[train_idx], X[test_idx]
        y_train, y_test = y[train_idx], y[test_idx]
        subj_test = subjects[test_idx]
        if classifier == 'rf':
            clf = RandomForestClassifier(
                n_estimators=200, max_depth=20, min_samples_leaf=5,
                class_weight='balanced' if use_weights else None,
                n_jobs=-1, random_state=42)
            clf.fit(X_train, y_train)
            y_pred = clf.predict(X_test)
            y_proba = clf.predict_proba(X_test)
        elif classifier == 'lgbm':
            if use_weights:
                class_counts = np.bincount(y_train, minlength=5)
                total = len(y_train)
                weights = total / (5 * class_counts + 1e-10)
                sample_weights = weights[y_train]
            else:
                sample_weights = None
            clf = lgb.LGBMClassifier(
                n_estimators=300, max_depth=15, learning_rate=0.05,
                num_leaves=63, min_child_samples=20,
                subsample=0.8, colsample_bytree=0.8,
                class_weight='balanced' if use_weights else None,
                n_jobs=-1, random_state=42, verbose=-1)
            clf.fit(X_train, y_train, sample_weight=sample_weights)
            y_pred = clf.predict(X_test)
            y_proba = clf.predict_proba(X_test)
        k_pre = cohen_kappa_score(y_test, y_pred)
        kappas_pre_hmm.append(k_pre)
        if use_hmm and trans_matrix is not None:
            y_pred = hmm_smooth(y_pred, y_proba, subj_test, trans_matrix)
        k = cohen_kappa_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred, average='macro')
        kappas.append(k)
        f1s.append(f1)
        y_true_all.extend(y_test)
        y_pred_all.extend(y_pred)
        hmm_str = f" -> {k:.3f} (HMM)" if use_hmm else ""
        print(f"    Fold {fold+1}: k={k_pre:.3f}{hmm_str}")
    return {
        'label': label,
        'kappa_mean': np.mean(kappas), 'kappa_std': np.std(kappas),
        'f1_mean': np.mean(f1s), 'f1_std': np.std(f1s),
        'kappa_pre_hmm': np.mean(kappas_pre_hmm),
        'y_true': y_true_all, 'y_pred': y_pred_all,
    }

print(f"\n{'#'*65}")
print(f"  COMPARACION: 4 MEJORAS INDIVIDUALES + COMBINADAS")
print(f"  {n_subjects} sujetos, {N:,} epochs")
print(f"{'#'*65}")

configs = [
    (X_base,  "A. Baseline RF",                    'rf',   False, False),
    (X_delta, "B. + Delta features",               'rf',   False, False),
    (X_base,  "C. + Class weights",                'rf',   True,  False),
    (X_base,  "D. LightGBM",                       'lgbm', False, False),
    (X_base,  "E. + HMM smoothing",                'rf',   False, True),
    (X_delta, "F. Delta + weights",                 'rf',   True,  False),
    (X_delta, "G. Delta + LightGBM",               'lgbm', False, False),
    (X_delta, "H. Delta + LightGBM + weights",     'lgbm', True,  False),
    (X_delta, "I. Delta + LightGBM + w + HMM",     'lgbm', True,  True),
    (X_base,  "J. LightGBM + weights + HMM",       'lgbm', True,  True),
]

results = []
for X_cfg, label, clf_type, weights, hmm in configs:
    print(f"\n  {label}...")
    t0 = time.time()
    r = evaluate(X_cfg, y, subjects, label,
                 classifier=clf_type, use_weights=weights,
                 use_hmm=hmm, trans_matrix=trans_matrix)
    elapsed = time.time() - t0
    results.append(r)
    print(f"  -> k = {r['kappa_mean']:.3f} +/- {r['kappa_std']:.3f} | "
          f"F1 = {r['f1_mean']:.3f} | {elapsed:.0f}s")

print(f"\n{'='*70}")
print(f"  RESUMEN FINAL")
print(f"{'='*70}")
print(f"  {'Config':<38s}  {'kappa':>12s}  {'F1':>10s}  {'delta_k':>8s}")
print(f"  {'_'*38}  {'_'*12}  {'_'*10}  {'_'*8}")

bk = results[0]['kappa_mean']
for r in results:
    dk = r['kappa_mean'] - bk
    s = f"+{dk:.3f}" if dk >= 0 else f"{dk:.3f}"
    print(f"  {r['label']:<38s}  {r['kappa_mean']:.3f}+/-{r['kappa_std']:.3f}"
          f"  {r['f1_mean']:.3f}+/-{r['f1_std']:.3f}  {s}")

best = max(results, key=lambda r: r['kappa_mean'])
dk_best = best['kappa_mean'] - bk
print(f"\n  Mejor: {best['label']}")
print(f"  delta_k vs baseline: +{dk_best:.3f}")
print(f"  Mejora relativa: +{100*dk_best/bk:.1f}%")

print(f"\n  Classification report ({best['label']}):")
print(classification_report(best['y_true'], best['y_pred'],
                            target_names=stage_names, digits=3))

print(f"\n  Comparacion N1 (la clase mas dificil):")
for r in [results[0], best]:
    n1_recall = recall_score(r['y_true'], r['y_pred'], labels=[1], average=None)[0]
    print(f"    {r['label']:<38s}  N1 recall = {n1_recall:.1%}")
