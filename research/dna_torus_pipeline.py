#!/usr/bin/env python3
"""
Pipeline Toroidal para Secuencias de ADN
========================================
Aplica el pipeline de sleep staging (Takens → Toro de Clifford → 8 features)
de forma independiente a cada base {A, T, C, G}, y evalúa si la matriz de
distancias entre features recupera la involución Watson-Crick (A↔T, C↔G).

Arquitectura (idéntica al pipeline de sueño):
  d_A[n] → Takens ℝ⁴ → S³ → Toro de Clifford → 8 features
  d_T[n] → Takens ℝ⁴ → S³ → Toro de Clifford → 8 features
  d_C[n] → Takens ℝ⁴ → S³ → Toro de Clifford → 8 features
  d_G[n] → Takens ℝ⁴ → S³ → Toro de Clifford → 8 features

Uso:
  python3 dna_torus_pipeline.py ecoli_k12.fasta
  python3 dna_torus_pipeline.py ecoli_synthetic.fasta  # control negativo
"""

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial.distance import pdist, squareform
from collections import Counter
import sys
import time

BASES = ['A', 'T', 'C', 'G']
FEATURE_NAMES = [
    'omega1',              # winding number dominante
    'torus_curvature',     # curvatura media de la trayectoria
    'angular_acceleration',# derivada segunda del ángulo
    'geodesic_distance',   # distancia total recorrida en el toro
    'angular_entropy',     # entropía de la distribución angular
    'phase_diff_std',      # desviación estándar de diferencias de fase
    'phase_coherence',     # coherencia de fase (1 - circ_var)
    'transition_rate',     # tasa de transiciones entre celdas
]


# ═══════════════════════════════════════════════════════════════
# FASE 1: Codificación de ADN como señales de densidad
# ═══════════════════════════════════════════════════════════════

def load_fasta(filepath):
    """Carga secuencia FASTA. Retorna string de bases en mayúscula."""
    seq_parts = []
    with open(filepath) as f:
        for line in f:
            if not line.startswith('>'):
                seq_parts.append(line.strip().upper())
    seq = ''.join(seq_parts)
    # Filtrar solo ATCG (ignorar N, etc.)
    seq = ''.join(b for b in seq if b in 'ATCG')
    return seq


def seq_to_density(seq_str, sigma):
    """
    Convierte secuencia de ADN en 4 señales de densidad suavizadas.
    
    Args:
        seq_str: String de bases (ATCG)
        sigma: Desviación estándar del kernel gaussiano (en bp)
    
    Returns:
        dict con 4 arrays de densidad local, uno por base
    """
    seq_array = np.frombuffer(seq_str.encode(), dtype='S1')
    signals = {}
    for base in BASES:
        indicator = (seq_array == base.encode()).astype(np.float64)
        signals[base] = gaussian_filter1d(indicator, sigma=sigma)
    return signals


# ═══════════════════════════════════════════════════════════════
# FASE 2: Embedding de Takens → ℝ⁴
# ═══════════════════════════════════════════════════════════════

def takens_embedding(signal, tau, m=4):
    """
    Embedding de Takens para una señal 1D.
    
    Args:
        signal: array 1D de densidad
        tau: delay temporal (en muestras/bp)
        m: dimensión del embedding (4 para proyectar a S³)
    
    Returns:
        array de shape (N - (m-1)*tau, m)
    """
    N = len(signal)
    n_vectors = N - (m - 1) * tau
    if n_vectors <= 0:
        raise ValueError(f"Señal demasiado corta para tau={tau}, m={m}")
    
    embedding = np.zeros((n_vectors, m))
    for i in range(m):
        embedding[:, i] = signal[i * tau : i * tau + n_vectors]
    return embedding


def optimal_tau(signal, max_tau=500):
    """
    Estima tau óptimo como primer mínimo de la autocorrelación.
    (Aproximación rápida; el primer mínimo de mutual information es más robusto
    pero computacionalmente costoso para señales largas.)
    """
    signal_centered = signal - np.mean(signal)
    var = np.var(signal_centered)
    if var < 1e-15:
        return 1
    
    for tau in range(1, min(max_tau, len(signal) // 4)):
        corr = np.mean(signal_centered[tau:] * signal_centered[:-tau]) / var
        if corr < 1 / np.e:  # Primer cruce del umbral 1/e
            return tau
    return max_tau


# ═══════════════════════════════════════════════════════════════
# FASE 3: Proyección a S³ → Toro de Clifford → Ángulos
# ═══════════════════════════════════════════════════════════════

def project_to_torus(embedding):
    """
    Proyecta embedding ℝ⁴ → S³ → ángulos toroidales (θ₁, θ₂).
    
    El toro de Clifford en S³ se parametriza como:
    (cos θ₁, sin θ₁, cos θ₂, sin θ₂) / √2
    
    Args:
        embedding: array (N, 4)
    
    Returns:
        theta1, theta2: arrays de ángulos toroidales
    """
    # Normalizar a S³
    norms = np.linalg.norm(embedding, axis=1, keepdims=True)
    norms[norms < 1e-15] = 1.0
    V = embedding / norms
    
    # Ángulos toroidales
    theta1 = np.arctan2(V[:, 1], V[:, 0])  # ángulo en plano (x₁, x₂)
    theta2 = np.arctan2(V[:, 3], V[:, 2])  # ángulo en plano (x₃, x₄)
    
    return theta1, theta2


# ═══════════════════════════════════════════════════════════════
# FASE 4: Extracción de 8 Features del Toro
# ═══════════════════════════════════════════════════════════════

def extract_torus_features(theta1, theta2, n_cells=8):
    """
    Extrae los 8 features toroidales de una trayectoria (θ₁, θ₂).
    
    Replica exactamente los 8 features del pipeline de sueño:
    ω₁, torus_curvature, angular_acceleration, geodesic_distance,
    angular_entropy, phase_diff_std, phase_coherence, transition_rate
    """
    N = len(theta1)
    if N < 10:
        return np.zeros(8)
    
    # --- Diferencias angulares (unwrapped) ---
    dtheta1 = np.diff(np.unwrap(theta1))
    dtheta2 = np.diff(np.unwrap(theta2))
    
    # 1. ω₁ — Winding number dominante
    omega1 = np.sum(dtheta1) / (2 * np.pi)
    
    # 2. Torus curvature — Curvatura media de la trayectoria
    #    κ = |dθ''| / (1 + |dθ'|²)^(3/2) promediado
    ddtheta1 = np.diff(dtheta1)
    ddtheta2 = np.diff(dtheta2)
    speed = np.sqrt(dtheta1[:-1]**2 + dtheta2[:-1]**2)
    accel = np.sqrt(ddtheta1**2 + ddtheta2**2)
    denom = (1 + speed**2)**(1.5)
    denom[denom < 1e-15] = 1e-15
    curvature = np.mean(accel / denom)
    
    # 3. Angular acceleration — Aceleración angular media
    angular_accel = np.mean(np.sqrt(ddtheta1**2 + ddtheta2**2))
    
    # 4. Geodesic distance — Distancia total en el toro
    geodesic = np.sum(np.sqrt(dtheta1**2 + dtheta2**2))
    # Normalizar por longitud de la trayectoria
    geodesic_norm = geodesic / N
    
    # 5. Angular entropy — Entropía de distribución en celdas
    cell1 = ((theta1 + np.pi) / (2 * np.pi) * n_cells).astype(int) % n_cells
    cell2 = ((theta2 + np.pi) / (2 * np.pi) * n_cells).astype(int) % n_cells
    cell_ids = cell1 * n_cells + cell2
    counts = np.bincount(cell_ids, minlength=n_cells**2).astype(float)
    counts = counts[counts > 0]
    probs = counts / counts.sum()
    entropy = -np.sum(probs * np.log2(probs))
    max_entropy = np.log2(n_cells**2)
    angular_entropy = entropy / max_entropy if max_entropy > 0 else 0
    
    # 6. Phase diff std — Variabilidad de la diferencia de fase θ₁-θ₂
    phase_diff = np.unwrap(theta1 - theta2)
    phase_diff_std = np.std(np.diff(phase_diff))
    
    # 7. Phase coherence — Estabilidad de fase (1 - circular variance)
    phase_complex = np.exp(1j * (theta1 - theta2))
    phase_coherence = np.abs(np.mean(phase_complex))
    
    # 8. Transition rate — Tasa de transiciones entre celdas
    transitions = np.sum(np.diff(cell_ids) != 0) / (N - 1)
    
    return np.array([
        omega1,
        curvature,
        angular_accel,
        geodesic_norm,
        angular_entropy,
        phase_diff_std,
        phase_coherence,
        transitions,
    ])


# ═══════════════════════════════════════════════════════════════
# FASE 5: Pipeline completo para una ventana
# ═══════════════════════════════════════════════════════════════

def process_window(signals_window, tau_dict):
    """
    Ejecuta el pipeline para una ventana de las 4 señales de densidad.
    
    Args:
        signals_window: dict {base: array de densidad en la ventana}
        tau_dict: dict {base: tau óptimo}
    
    Returns:
        dict {base: array de 8 features}
    """
    features = {}
    for base in BASES:
        signal = signals_window[base]
        tau = tau_dict[base]
        
        try:
            emb = takens_embedding(signal, tau, m=4)
            theta1, theta2 = project_to_torus(emb)
            feats = extract_torus_features(theta1, theta2)
        except (ValueError, IndexError):
            feats = np.full(8, np.nan)
        
        features[base] = feats
    
    return features


# ═══════════════════════════════════════════════════════════════
# FASE 6: Test de Involución
# ═══════════════════════════════════════════════════════════════

def test_involution(features_dict, metric='euclidean'):
    """
    Evalúa si la matriz de distancias entre los 4 vectores de features
    recupera la involución Watson-Crick.
    
    La predicción es:
      d(A,T) < d(A,C), d(A,G)  y  d(C,G) < d(C,A), d(C,T)
    
    Returns:
        dict con métricas de involución
    """
    F = np.array([features_dict[b] for b in BASES])  # (4, 8)
    
    if np.any(np.isnan(F)):
        return {'valid': False}
    
    # Normalizar features (z-score por columna)
    mu = F.mean(axis=0, keepdims=True)
    std = F.std(axis=0, keepdims=True)
    std[std < 1e-15] = 1.0
    F_norm = (F - mu) / std
    
    # Matriz de distancias 4×4
    D = squareform(pdist(F_norm, metric=metric))
    
    # Indices: A=0, T=1, C=2, G=3
    d_AT = D[0, 1]  # Watson-Crick par 1
    d_CG = D[2, 3]  # Watson-Crick par 2
    d_AG = D[0, 3]  # Purina-Purina
    d_AC = D[0, 2]
    d_TG = D[1, 3]
    d_TC = D[1, 2]
    
    # ¿Se cumple la involución Watson-Crick?
    wc_pair1 = d_AT < min(d_AC, d_AG)      # A más cerca de T
    wc_pair2 = d_CG < min(d_AC, d_TG)      # C más cerca de G (corregido)
    wc_involution = wc_pair1 and wc_pair2
    
    # ¿Se cumple la involución Purina/Pirimidina?
    ry_pair1 = d_AG < min(d_AT, d_AC)       # A más cerca de G (purinas)
    ry_pair2 = d_TC < min(d_TG, d_AT)       # T más cerca de C (pirimidinas)  
    ry_involution = ry_pair1 and ry_pair2
    
    # ¿Se cumple la involución Keto/Amino?
    km_pair1 = d_AC < min(d_AT, d_AG)       # A más cerca de C (amino)
    km_pair2 = d_TG < min(d_TC, d_AT)       # T más cerca de G (keto)
    km_involution = km_pair1 and km_pair2
    
    # Ratio de separabilidad: d_inter / d_intra para Watson-Crick
    d_intra_wc = (d_AT + d_CG) / 2
    d_inter_wc = (d_AC + d_AG + d_TC + d_TG) / 4
    separation_ratio = d_inter_wc / d_intra_wc if d_intra_wc > 1e-15 else 0
    
    return {
        'valid': True,
        'distance_matrix': D,
        'wc_involution': wc_involution,
        'ry_involution': ry_involution,
        'km_involution': km_involution,
        'separation_ratio': separation_ratio,
        'distances': {
            'AT': d_AT, 'CG': d_CG,
            'AG': d_AG, 'AC': d_AC,
            'TG': d_TG, 'TC': d_TC,
        },
    }


# ═══════════════════════════════════════════════════════════════
# FASE 7: Ejecución Multi-escala
# ═══════════════════════════════════════════════════════════════

def run_pipeline(seq_str, sigma, window_size, stride=None):
    """
    Pipeline completo multi-ventana.
    
    Args:
        seq_str: secuencia de ADN
        sigma: escala de suavizado (bp)
        window_size: tamaño de ventana (bp)
        stride: paso entre ventanas (default: window_size // 2)
    
    Returns:
        lista de resultados por ventana + resumen
    """
    if stride is None:
        stride = window_size // 2
    
    # Paso 1: Señales de densidad
    signals = seq_to_density(seq_str, sigma)
    N = len(seq_str)
    
    # Paso 2: Tau óptimo por base (calculado sobre toda la señal)
    tau_dict = {}
    for base in BASES:
        tau_dict[base] = optimal_tau(signals[base], max_tau=min(500, window_size // 8))
    
    # Paso 3: Procesar ventanas
    window_results = []
    all_features = {b: [] for b in BASES}
    
    n_windows = (N - window_size) // stride + 1
    
    for i in range(n_windows):
        start = i * stride
        end = start + window_size
        
        # Extraer ventana de cada señal
        win_signals = {b: signals[b][start:end] for b in BASES}
        
        # Pipeline: Takens → Toro → 8 features (por base)
        features = process_window(win_signals, tau_dict)
        
        # Test de involución
        inv_result = test_involution(features)
        
        if inv_result['valid']:
            window_results.append(inv_result)
            for b in BASES:
                all_features[b].append(features[b])
    
    if not window_results:
        return {'error': 'No valid windows'}
    
    # Resumen global
    n_valid = len(window_results)
    wc_count = sum(r['wc_involution'] for r in window_results)
    ry_count = sum(r['ry_involution'] for r in window_results)
    km_count = sum(r['km_involution'] for r in window_results)
    sep_ratios = [r['separation_ratio'] for r in window_results]
    
    # Features promedio por base (para distancia global)
    mean_features = {b: np.mean(all_features[b], axis=0) for b in BASES}
    global_inv = test_involution(mean_features)
    
    return {
        'sigma': sigma,
        'window_size': window_size,
        'n_windows': n_valid,
        'tau': tau_dict,
        # Fracción de ventanas donde cada involución se detecta
        'wc_rate': wc_count / n_valid,
        'ry_rate': ry_count / n_valid,
        'km_rate': km_count / n_valid,
        # Ratio de separabilidad
        'separation_ratio_mean': np.mean(sep_ratios),
        'separation_ratio_std': np.std(sep_ratios),
        # Test global (features promediados)
        'global_involution': global_inv,
        # Features medios por base (para inspección)
        'mean_features': mean_features,
    }


def print_results(result, label=""):
    """Imprime resultados de forma legible."""
    if 'error' in result:
        print(f"  ERROR: {result['error']}")
        return
    
    print(f"\n{'='*65}")
    if label:
        print(f"  {label}")
    print(f"  σ={result['sigma']} bp | ventana={result['window_size']} bp | "
          f"n={result['n_windows']} ventanas")
    print(f"  τ por base: { {b: result['tau'][b] for b in BASES} }")
    print(f"{'='*65}")
    
    print(f"\n  Tasa de detección de involución por ventana:")
    print(f"    Watson-Crick (A↔T, C↔G): {result['wc_rate']:.1%}")
    print(f"    Purina/Pirim (A↔G, T↔C): {result['ry_rate']:.1%}")
    print(f"    Keto/Amino   (A↔C, T↔G): {result['km_rate']:.1%}")
    
    print(f"\n  Ratio de separabilidad WC (inter/intra):")
    print(f"    {result['separation_ratio_mean']:.3f} ± {result['separation_ratio_std']:.3f}")
    print(f"    (>1 = pares WC más compactos que no-pares)")
    
    gi = result['global_involution']
    if gi['valid']:
        print(f"\n  Test global (features promediados):")
        print(f"    Involución WC detectada: {'✓ SÍ' if gi['wc_involution'] else '✗ NO'}")
        print(f"    Involución RY detectada: {'✓ SÍ' if gi['ry_involution'] else '✗ NO'}")
        print(f"    Involución KM detectada: {'✓ SÍ' if gi['km_involution'] else '✗ NO'}")
        
        print(f"\n  Matriz de distancias (features normalizados):")
        D = gi['distance_matrix']
        print(f"         A       T       C       G")
        for i, b in enumerate(BASES):
            row = '    '.join(f"{D[i,j]:.3f}" for j in range(4))
            print(f"    {b}  {row}")
        
        print(f"\n  Distancias clave:")
        d = gi['distances']
        print(f"    d(A,T) = {d['AT']:.3f}  ← par WC")
        print(f"    d(C,G) = {d['CG']:.3f}  ← par WC")
        print(f"    d(A,G) = {d['AG']:.3f}  ← purinas")
        print(f"    d(T,C) = {d['TC']:.3f}  ← pirimidinas")
        print(f"    d(A,C) = {d['AC']:.3f}")
        print(f"    d(T,G) = {d['TG']:.3f}")
    
    # Features por base
    print(f"\n  Features medios por base:")
    print(f"    {'Feature':<24s}  {'A':>8s}  {'T':>8s}  {'C':>8s}  {'G':>8s}")
    print(f"    {'─'*24}  {'─'*8}  {'─'*8}  {'─'*8}  {'─'*8}")
    mf = result['mean_features']
    for j, fname in enumerate(FEATURE_NAMES):
        vals = [f"{mf[b][j]:8.4f}" for b in BASES]
        print(f"    {fname:<24s}  {'  '.join(vals)}")


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Uso: python3 dna_torus_pipeline.py <archivo.fasta>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    print(f"Cargando {filepath}...")
    seq = load_fasta(filepath)
    
    counts = Counter(seq)
    total = len(seq)
    print(f"Secuencia: {total:,} bp")
    for b in BASES:
        print(f"  {b}: {counts.get(b,0):,} ({100*counts.get(b,0)/total:.1f}%)")
    
    # ─── Barrido multi-escala ───
    configs = [
        # (sigma, window_size) — de escala fina a gruesa
        (30,    5_000),    # Resolución de motivos/codones
        (100,   10_000),   # Elementos regulatorios
        (500,   50_000),   # Genes
        (2000,  100_000),  # Dominios cromosómicos
    ]
    
    print(f"\n{'#'*65}")
    print(f"  PIPELINE TOROIDAL — BARRIDO MULTI-ESCALA")
    print(f"  Buscando involuciones en {filepath}")
    print(f"{'#'*65}")
    
    for sigma, window_size in configs:
        if window_size > total:
            print(f"\n  [SKIP] σ={sigma}, ventana={window_size} > longitud de secuencia")
            continue
        
        t0 = time.time()
        result = run_pipeline(seq, sigma=sigma, window_size=window_size)
        elapsed = time.time() - t0
        
        label = f"Escala σ={sigma} bp, ventana={window_size} bp  [{elapsed:.1f}s]"
        print_results(result, label)
    
    print(f"\n{'#'*65}")
    print(f"  INTERPRETACIÓN:")
    print(f"  - Si WC_rate >> 33%: la involución Watson-Crick domina")
    print(f"  - Si RY_rate >> 33%: la dicotomía purina/pirimidina domina")
    print(f"  - Si todas ≈ 33%: no hay involución preferida (aleatorio)")
    print(f"  - separation_ratio > 1: los pares WC son más compactos")
    print(f"{'#'*65}")
