# Research

Public research artifacts that informed the scientific foundation of Spiral
Journey. This material was submitted to CIBM and rejected for lack of novelty;
it is kept here for transparency and to let others reproduce the analyses that
drove product decisions.

These scripts and data files are not part of the iOS application target.
Nothing in this folder is built or shipped with the app.

## Files

### Analysis scripts
- `comparacion_justa.py` — Fair comparison between the Spiral Journey sleep
  model and the baseline AASM classifier on the same epochs.
- `dna_torus_pipeline.py` — End-to-end pipeline that turns overnight sleep
  records into a SleepDNA torus embedding.
- `mejoras_local.py` — Local-search refinements tested during the validation
  study.
- `permutation_test.py` — Permutation significance test used to compute the
  p-values reported in the unpublished manuscript.
- `temporal_window.py` — Sliding-window aggregator used for temporal pattern
  detection.

### Data / results
- `ecoli_k12.fasta` — Reference genome (E. coli K-12). Used as a control for
  the DNA-metaphor baseline comparison.
- `permutation_results_sigma30.json` — Permutation test results, σ=30.
- `permutation_results_sigma2000.json` — Permutation test results, σ=2000.

### Supporting package
- `neurospiral-integration/` — Self-contained Swift Package scratchpad used
  during early iteration of the NeuroSpiral torus. Production code lives in
  the top-level `SpiralGeometry/` SPM package; this copy is kept for
  reproducibility of the numbers in the research scripts.

## Running the scripts

Python 3.11 + numpy + pandas are expected. Create a local virtualenv inside
this folder (git-ignored):

```bash
python3 -m venv research/.venv
source research/.venv/bin/activate
pip install numpy pandas
python research/permutation_test.py
```
