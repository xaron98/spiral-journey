# [Experimental] SleepDNA — Scientific Basis & Positioning

**Status:** Experimental — computational metaphor, not biological claim

---

## What SleepDNA Is

SleepDNA is a **computational model** that borrows concepts from genomics to analyze sleep patterns:

- **Nucleotides** = daily feature vectors (16 normalized values per day)
- **Sequences** = weekly sliding windows of nucleotides
- **Motifs** = recurring patterns discovered via DTW clustering ("sleep genes")
- **Mutations** = deviations from expected patterns (silent/missense/nonsense)
- **SleepBLOSUM** = personalized scoring matrix (inspired by BLOSUM62 in bioinformatics)
- **Base Pairs** = phase synchrony between sleep data and life context (Hilbert PLV)
- **Double Helix** = two interleaved data strands visualized in 3D

These are **metaphors for pattern analysis**, not claims about actual DNA or genetics.

---

## What SleepDNA Is NOT

SleepDNA does **not** claim that:

- Sleep patterns are encoded in biological DNA
- Dreams can be inherited between generations
- The app performs genetic analysis
- The "mutations" are actual DNA mutations
- The "genes" are actual genes

---

## Scientific Foundations

### What the evidence supports

| Claim | Evidence Level | Key References |
|---|---|---|
| Sleep architecture has heritable components | Strong | Twin studies on nightmare frequency, REM traits |
| Environmental factors modulate sleep via systemic signals | Strong | Stress → cortisol → HPA axis → sleep disruption |
| Paternal sleep deprivation affects offspring metabolism | Moderate | Mouse study: metabolic alterations in male offspring |
| Sperm RNAs (tsRNAs) can transmit stress/metabolic states | Moderate-Strong | Causal evidence via microinjection in mice |
| Sleep predispositions (not content) can be inherited | Moderate | Genetic associations with nightmare frequency, chronotype |
| DTW is valid for time series comparison | Strong | Established in signal processing, validated for biosignals |
| Personalized scoring improves pattern matching | Strong | Mutual information for feature selection is standard ML |

### What the evidence does NOT support

| Claim | Evidence Level |
|---|---|
| Dream content can be encoded in DNA | None |
| Specific sleep experiences are inherited | None |
| Epigenetic marks survive reprogramming to transmit complex information | Very limited in mammals |
| "Sleep genes" (in the literal sense) exist for specific patterns | None |

### The biological analogy holds because

1. **Both systems have "sequence" structure** — DNA has ATCG, sleep has daily feature vectors
2. **Both have recurring motifs** — genes repeat, sleep patterns repeat
3. **Both have "expression" modulated by environment** — gene expression depends on context, sleep patterns depend on lifestyle
4. **Both can be aligned and compared** — BLAST aligns DNA sequences, DTW aligns sleep sequences
5. **Both benefit from personalized scoring** — BLOSUM matrices are substitution-specific, SleepBLOSUM is user-specific

### Key literature

**Heritable sleep traits:**
- Barclay et al. — genetic contribution to nightmare frequency (twin studies)
- Lane et al. — GWAS linking sleep traits with psychiatric phenotypes

**Epigenetic inheritance (context):**
- Chen et al. — tsRNAs in sperm transmit metabolic state (Nature, 2016)
- Gapp et al. — RNA injection reproduces behavioral phenotypes (Nature Neuroscience, 2014)
- Dias & Bhatt — olfactory conditioning and transgenerational inheritance (Nature Neuroscience, 2014)

**Sleep and memory:**
- Stickgold & Walker — sleep-dependent memory consolidation
- Rasch & Born — about sleep's role in memory (Physiological Reviews, 2013)

**Two-Process Model:**
- Borbély (1982) — foundational model for sleep homeostasis (Process S + Process C)

**DTW for biosignals:**
- Sakoe & Chiba (1978) — Dynamic Time Warping for pattern matching

---

## Recommended Positioning

### For App Store / Marketing

> "Spiral Journey models your sleep patterns as a biological structure — like a DNA helix — to reveal invisible patterns and predict your sleep using techniques from genomics and signal processing. All analysis is computational, not genetic."

### For Scientific Publication

> "We present SleepDNA, a computational framework that encodes daily sleep data as feature vectors (nucleotides), groups them into weekly sequences, and applies Dynamic Time Warping with an adaptive personalized scoring matrix (SleepBLOSUM) to discover recurring motifs, classify pattern deviations, and predict sleep by sequence alignment."

### For Users

> "Your SleepDNA is your unique sleep fingerprint — the patterns that make your sleep yours. The app learns what affects YOUR sleep specifically, and uses your history to spot patterns and predict what's coming."

---

## Future Research Directions

### Validated (ready to study)
- SleepBLOSUM lift: does personalization improve prediction accuracy?
- Motif stability: are discovered patterns consistent over time?
- Health marker correlations: do HB, HCI, RDS, RCE correlate with subjective sleep quality?

### Speculative (requires collaboration)
- Do SleepBLOSUM weights correlate with chronotype genetics?
- Can motif disruption predict onset of sleep disorders?
- Does REM Cluster Entropy correlate with mental health outcomes?

### Out of scope (no scientific basis)
- Hereditary transmission of dream content
- Genetic encoding of sleep experiences
- Transgenerational memory via sleep
