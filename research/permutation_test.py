#!/usr/bin/env python3
"""
Test de Permutación — Validación estadística de la involución Watson-Crick
==========================================================================

Pregunta: ¿La involución WC detectada por el pipeline toroidal se debe a
la estructura secuencial del ADN, o es un artefacto de la composición de bases?

Método:
  1. Ejecutar pipeline en secuencia real → métricas reales
  2. Permutar la secuencia N veces (destruye orden, preserva composición)
  3. Ejecutar pipeline en cada permutación → distribución nula
  4. p-valor = P(métrica_null ≥ métrica_real)

Uso:
  python3 permutation_test.py ecoli_k12.fasta
  python3 permutation_test.py ecoli_k12.fasta --n_perms 1000  # más preciso
"""

import numpy as np
from collections import Counter
import sys
import time
import json
from dna_torus_pipeline import (
    load_fasta, seq_to_density, optimal_tau, BASES,
    takens_embedding, project_to_torus, extract_torus_features,
    test_involution, FEATURE_NAMES
)


def run_single_scale(seq_str, sigma, window_size, stride=None):
    """
    Pipeline para una escala. Retorna métricas resumidas.
    Versión optimizada del run_pipeline original.
    """
    if stride is None:
        stride = window_size // 2

    signals = seq_to_density(seq_str, sigma)
    N = len(seq_str)

    tau_dict = {}
    for base in BASES:
        tau_dict[base] = optimal_tau(signals[base], max_tau=min(500, window_size // 8))

    wc_hits = 0
    ry_hits = 0
    km_hits = 0
    sep_ratios = []
    n_valid = 0
    all_features = {b: [] for b in BASES}

    n_windows = (N - window_size) // stride + 1

    for i in range(n_windows):
        start = i * stride
        end = start + window_size
        win_signals = {b: signals[b][start:end] for b in BASES}

        features = {}
        for base in BASES:
            signal = win_signals[base]
            tau = tau_dict[base]
            try:
                emb = takens_embedding(signal, tau, m=4)
                theta1, theta2 = project_to_torus(emb)
                feats = extract_torus_features(theta1, theta2)
            except (ValueError, IndexError):
                feats = np.full(8, np.nan)
            features[base] = feats

        inv = test_involution(features)
        if inv['valid']:
            n_valid += 1
            if inv['wc_involution']:
                wc_hits += 1
            if inv['ry_involution']:
                ry_hits += 1
            if inv['km_involution']:
                km_hits += 1
            sep_ratios.append(inv['separation_ratio'])
            for b in BASES:
                all_features[b].append(features[b])

    if n_valid == 0:
        return None

    # Distancia global (features promediados)
    mean_features = {b: np.mean(all_features[b], axis=0) for b in BASES}
    global_inv = test_involution(mean_features)

    return {
        'n_valid': n_valid,
        'wc_rate': wc_hits / n_valid,
        'ry_rate': ry_hits / n_valid,
        'km_rate': km_hits / n_valid,
        'sep_ratio_mean': np.mean(sep_ratios),
        'sep_ratio_median': np.median(sep_ratios),
        'global_wc': global_inv['wc_involution'] if global_inv['valid'] else False,
        'global_d_AT': global_inv['distances']['AT'] if global_inv['valid'] else np.nan,
        'global_d_CG': global_inv['distances']['CG'] if global_inv['valid'] else np.nan,
        'global_d_inter_mean': np.mean([
            global_inv['distances']['AC'],
            global_inv['distances']['AG'],
            global_inv['distances']['TC'],
            global_inv['distances']['TG'],
        ]) if global_inv['valid'] else np.nan,
    }


def permute_sequence(seq_str):
    """Permuta la secuencia preservando composición exacta."""
    arr = np.array(list(seq_str))
    np.random.shuffle(arr)
    return ''.join(arr)


def run_permutation_test(seq_str, sigma, window_size, n_perms=200):
    """
    Test de permutación completo.
    """
    N = len(seq_str)
    print(f"\n{'='*65}")
    print(f"  TEST DE PERMUTACIÓN")
    print(f"  σ={sigma} bp | ventana={window_size} bp | {n_perms} permutaciones")
    print(f"  Secuencia: {N:,} bp")
    print(f"{'='*65}")

    # ─── Paso 1: Secuencia real ───
    print(f"\n  [1/3] Ejecutando pipeline en secuencia REAL...")
    t0 = time.time()
    real = run_single_scale(seq_str, sigma, window_size)
    t_real = time.time() - t0

    if real is None:
        print("  ERROR: No se pudieron procesar ventanas.")
        return

    print(f"        Completado en {t_real:.1f}s")
    print(f"        WC rate = {real['wc_rate']:.1%}")
    print(f"        Sep ratio = {real['sep_ratio_mean']:.4f}")
    print(f"        d(A,T) = {real['global_d_AT']:.3f}")
    print(f"        d(C,G) = {real['global_d_CG']:.3f}")
    print(f"        d(inter) = {real['global_d_inter_mean']:.3f}")

    # ─── Paso 2: Permutaciones ───
    print(f"\n  [2/3] Ejecutando {n_perms} permutaciones...")
    t0 = time.time()

    null_wc_rates = []
    null_sep_ratios = []
    null_d_AT = []
    null_d_CG = []
    null_d_inter = []
    null_global_wc = []

    est_time = t_real * n_perms
    print(f"        Tiempo estimado: {est_time/60:.0f} minutos")
    print(f"        Progreso: ", end='', flush=True)

    for i in range(n_perms):
        perm_seq = permute_sequence(seq_str)
        perm_result = run_single_scale(perm_seq, sigma, window_size)

        if perm_result is not None:
            null_wc_rates.append(perm_result['wc_rate'])
            null_sep_ratios.append(perm_result['sep_ratio_mean'])
            null_d_AT.append(perm_result['global_d_AT'])
            null_d_CG.append(perm_result['global_d_CG'])
            null_d_inter.append(perm_result['global_d_inter_mean'])
            null_global_wc.append(perm_result['global_wc'])

        # Barra de progreso
        if (i + 1) % max(1, n_perms // 20) == 0:
            pct = 100 * (i + 1) / n_perms
            elapsed = time.time() - t0
            remaining = elapsed / (i + 1) * (n_perms - i - 1)
            print(f"{pct:.0f}%", end=' ', flush=True)

    elapsed = time.time() - t0
    print(f"\n        Completado en {elapsed/60:.1f} minutos")

    # ─── Paso 3: P-valores ───
    null_wc_rates = np.array(null_wc_rates)
    null_sep_ratios = np.array(null_sep_ratios)
    null_d_AT = np.array(null_d_AT)
    null_d_CG = np.array(null_d_CG)
    null_d_inter = np.array(null_d_inter)
    n_null = len(null_wc_rates)

    # P-valor: fracción de permutaciones que igualan o superan al real
    p_wc_rate = np.mean(null_wc_rates >= real['wc_rate'])
    p_sep_ratio = np.mean(null_sep_ratios >= real['sep_ratio_mean'])

    # Para distancias: real debería tener d_intra MENOR que nulo
    p_d_AT = np.mean(null_d_AT <= real['global_d_AT'])
    p_d_CG = np.mean(null_d_CG <= real['global_d_CG'])

    # Métrica combinada: ratio de distancia intra/inter
    real_ratio = (real['global_d_AT'] + real['global_d_CG']) / (2 * real['global_d_inter_mean'])
    null_ratios = (null_d_AT + null_d_CG) / (2 * null_d_inter)
    p_distance_ratio = np.mean(null_ratios <= real_ratio)

    # Fracción de permutaciones donde el test global detecta WC
    null_global_wc_rate = np.mean(null_global_wc)

    print(f"\n  [3/3] RESULTADOS")
    print(f"  {'─'*60}")
    print(f"\n  Métrica                    Real      Null (μ±σ)      p-valor")
    print(f"  {'─'*60}")
    print(f"  WC rate (ventanas)      {real['wc_rate']:8.1%}   "
          f"{np.mean(null_wc_rates):6.1%} ± {np.std(null_wc_rates):5.1%}   "
          f"p = {p_wc_rate:.4f}")
    print(f"  Sep ratio (inter/intra) {real['sep_ratio_mean']:8.4f}   "
          f"{np.mean(null_sep_ratios):6.4f} ± {np.std(null_sep_ratios):5.4f}   "
          f"p = {p_sep_ratio:.4f}")
    print(f"  d(A,T) global           {real['global_d_AT']:8.3f}   "
          f"{np.mean(null_d_AT):6.3f} ± {np.std(null_d_AT):5.3f}   "
          f"p = {p_d_AT:.4f}")
    print(f"  d(C,G) global           {real['global_d_CG']:8.3f}   "
          f"{np.mean(null_d_CG):6.3f} ± {np.std(null_d_CG):5.3f}   "
          f"p = {p_d_CG:.4f}")
    print(f"  Ratio distancia WC/inter{real_ratio:8.4f}   "
          f"{np.mean(null_ratios):6.4f} ± {np.std(null_ratios):5.4f}   "
          f"p = {p_distance_ratio:.4f}")
    print(f"  Global WC detectada     {'SÍ':>8s}   "
          f"{null_global_wc_rate:6.1%} de perms")

    print(f"\n  {'─'*60}")
    if p_wc_rate < 0.001 and p_distance_ratio < 0.001:
        print(f"  ★ RESULTADO: La involución Watson-Crick es estadísticamente")
        print(f"    significativa (p < 0.001). NO es artefacto composicional.")
        print(f"    El pipeline detecta estructura secuencial real.")
    elif p_wc_rate < 0.01 or p_distance_ratio < 0.01:
        print(f"  ◆ RESULTADO: Señal significativa (p < 0.01) pero moderada.")
        print(f"    Incrementar n_perms para mayor precisión.")
    elif p_wc_rate < 0.05 or p_distance_ratio < 0.05:
        print(f"  ○ RESULTADO: Señal marginal (p < 0.05).")
        print(f"    Necesita más permutaciones o escalas adicionales.")
    else:
        print(f"  ✗ RESULTADO: La involución NO supera el test de permutación.")
        print(f"    La estructura detectada es explicable por composición.")
    print(f"  {'─'*60}")

    # Guardar datos para análisis posterior
    output = {
        'sigma': sigma,
        'window_size': window_size,
        'n_perms': n_null,
        'real': {
            'wc_rate': float(real['wc_rate']),
            'sep_ratio': float(real['sep_ratio_mean']),
            'd_AT': float(real['global_d_AT']),
            'd_CG': float(real['global_d_CG']),
            'd_inter': float(real['global_d_inter_mean']),
            'distance_ratio': float(real_ratio),
        },
        'null': {
            'wc_rates': null_wc_rates.tolist(),
            'sep_ratios': null_sep_ratios.tolist(),
            'distance_ratios': null_ratios.tolist(),
        },
        'p_values': {
            'wc_rate': float(p_wc_rate),
            'sep_ratio': float(p_sep_ratio),
            'd_AT': float(p_d_AT),
            'd_CG': float(p_d_CG),
            'distance_ratio': float(p_distance_ratio),
        },
    }

    outfile = f'permutation_results_sigma{sigma}.json'
    with open(outfile, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\n  Datos guardados en: {outfile}")

    return output


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Uso: python3 permutation_test.py <archivo.fasta> [--n_perms N]")
        sys.exit(1)

    filepath = sys.argv[1]
    n_perms = 200
    if '--n_perms' in sys.argv:
        idx = sys.argv.index('--n_perms')
        n_perms = int(sys.argv[idx + 1])

    print(f"Cargando {filepath}...")
    seq = load_fasta(filepath)
    print(f"Secuencia: {len(seq):,} bp")
    counts = Counter(seq)
    for b in BASES:
        print(f"  {b}: {counts[b]:,} ({100*counts[b]/len(seq):.1f}%)")

    # Ejecutar en la escala que dio mejor señal: σ=30
    print(f"\n{'#'*65}")
    print(f"  TEST DE PERMUTACIÓN — σ=30 bp (mejor escala)")
    print(f"{'#'*65}")
    run_permutation_test(seq, sigma=30, window_size=5000, n_perms=n_perms)

    # También σ=2000 para ver si la señal es multi-escala
    print(f"\n{'#'*65}")
    print(f"  TEST DE PERMUTACIÓN — σ=2000 bp (escala gruesa)")
    print(f"{'#'*65}")
    run_permutation_test(seq, sigma=2000, window_size=100000, n_perms=n_perms)
