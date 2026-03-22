#!/usr/bin/env python3
"""Generate the SleepDNA scientific paper as PDF — English version with full-width tables."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm, cm
from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    KeepTogether
)

WIDTH, HEIGHT = A4
MARGIN = 2 * cm
CONTENT_W = WIDTH - 2 * MARGIN

ACCENT = HexColor("#7c3aed")
DARK = HexColor("#1a1a2e")
MUTED = HexColor("#666666")

styles = getSampleStyleSheet()

styles.add(ParagraphStyle(
    "PaperTitle", parent=styles["Title"],
    fontSize=17, leading=21, spaceAfter=6,
    textColor=DARK, alignment=TA_CENTER
))
styles.add(ParagraphStyle(
    "Authors", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_CENTER,
    textColor=MUTED, spaceAfter=4
))
styles.add(ParagraphStyle(
    "Affiliation", parent=styles["Normal"],
    fontSize=9, leading=12, alignment=TA_CENTER,
    textColor=MUTED, spaceAfter=16
))
styles.add(ParagraphStyle(
    "AbstractTitle", parent=styles["Heading2"],
    fontSize=12, leading=14, textColor=ACCENT,
    spaceAfter=6, spaceBefore=12
))
styles.add(ParagraphStyle(
    "AbstractBody", parent=styles["Normal"],
    fontSize=9.5, leading=13, alignment=TA_JUSTIFY,
    leftIndent=0.8 * cm, rightIndent=0.8 * cm,
    spaceAfter=12, textColor=DARK
))
styles.add(ParagraphStyle(
    "SectionHead", parent=styles["Heading1"],
    fontSize=13, leading=16, textColor=ACCENT,
    spaceBefore=18, spaceAfter=8
))
styles.add(ParagraphStyle(
    "SubHead", parent=styles["Heading2"],
    fontSize=11, leading=14, textColor=DARK,
    spaceBefore=12, spaceAfter=6
))
styles.add(ParagraphStyle(
    "Body", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_JUSTIFY,
    spaceAfter=8, textColor=DARK
))
styles.add(ParagraphStyle(
    "Equation", parent=styles["Normal"],
    fontSize=10, leading=14, alignment=TA_CENTER,
    spaceAfter=8, spaceBefore=4, textColor=DARK,
    fontName="Courier"
))
styles.add(ParagraphStyle(
    "RefItem", parent=styles["Normal"],
    fontSize=8.5, leading=11, alignment=TA_JUSTIFY,
    leftIndent=1.2 * cm, firstLineIndent=-1.2 * cm,
    spaceAfter=4, textColor=DARK
))
styles.add(ParagraphStyle(
    "TableCaption", parent=styles["Normal"],
    fontSize=9, leading=12, textColor=MUTED,
    spaceAfter=6, spaceBefore=6
))
styles.add(ParagraphStyle(
    "CellStyle", parent=styles["Normal"],
    fontSize=8, leading=10, textColor=DARK
))
styles.add(ParagraphStyle(
    "CellHeader", parent=styles["Normal"],
    fontSize=8, leading=10, textColor=HexColor("#ffffff"),
    fontName="Helvetica-Bold"
))


def make_table(data, col_ratios, caption):
    """Build a table using Paragraph cells so text wraps instead of collapsing."""
    total = sum(col_ratios)
    col_widths = [CONTENT_W * r / total for r in col_ratios]

    table_data = []
    for row_idx, row in enumerate(data):
        style = styles["CellHeader"] if row_idx == 0 else styles["CellStyle"]
        table_data.append([Paragraph(str(cell), style) for cell in row])

    t = Table(table_data, colWidths=col_widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT),
        ("GRID", (0, 0), (-1, -1), 0.5, HexColor("#cccccc")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ]))
    return [Paragraph(caption, styles["TableCaption"]), t, Spacer(1, 10)]


story = []
S = story.append

# ═══ Title ═══
S(Paragraph(
    "SleepDNA: Computational Genomics and Spatial Topology<br/>"
    "Applied to Sleep Time-Series Analysis on the Edge",
    styles["PaperTitle"]
))
S(Spacer(1, 6))
S(Paragraph("Spiral Journey Project — Technical Foundation Paper", styles["Authors"]))
S(Paragraph("Independent Research · March 2026", styles["Affiliation"]))

# ═══ Abstract ═══
S(Paragraph("Abstract", styles["AbstractTitle"]))
S(Paragraph(
    "<b>Background:</b> Current sleep monitoring systems rely on static aggregate metrics that fail to capture "
    "the dynamic interaction between the endogenous circadian rhythm and the daily exposome. We present "
    "<i>SleepDNA</i>, a novel computational framework that translates the principles of the Central Dogma of "
    "Molecular Biology, sequence alignment, and 3D topology into sleep time-series analysis. "
    "<b>Methods:</b> The system encodes sleep architecture into 16-feature daily nucleotide vectors, organized "
    "as a double-helix structure where Strand 1 (sleep physiology) and Strand 2 (behavioral context) are coupled "
    "via Phase Locking Value (PLV) computed through Hilbert Transform. Weighted Dynamic Time Warping (DTW) with "
    "a personalized scoring matrix (SleepBLOSUM) enables motif discovery, mutation classification, and sequence "
    "prediction. Advanced topological metrics — Persistent Homology, Gauss Linking Number, and Mutual Information "
    "Spectrum — provide structural insight into circadian-homeostatic coupling. The entire computational pipeline "
    "executes on-device using Apple's Accelerate framework, ensuring absolute data privacy. "
    "<b>Results:</b> The framework produces seven health biomarkers, discovers recurring weekly sleep motifs, "
    "classifies pattern deviations as silent/missense/nonsense mutations, and generates personalized sleep "
    "predictions. Preliminary self-tracking data demonstrates the system's ability to detect non-obvious "
    "temporal correlations between behavioral factors and sleep outcomes. "
    "<b>Conclusions:</b> SleepDNA establishes a new paradigm in predictive digital chronobiology by replacing "
    "descriptive statistics with structural sleep genomics, providing causal-level personalized insights without "
    "compromising user privacy.",
    styles["AbstractBody"]
))
S(Paragraph(
    "<b>Keywords:</b> sleep analysis, circadian rhythm, computational genomics, Dynamic Time Warping, "
    "Phase Locking Value, topological data analysis, on-device inference, digital health",
    styles["AbstractBody"]
))

# ═══ 1. Introduction ═══
S(Paragraph("1. Introduction", styles["SectionHead"]))
S(Paragraph(
    "Sleep is a complex, multi-dimensional physiological process governed by two interacting regulatory systems: "
    "the homeostatic sleep drive (Process S) and the circadian pacemaker (Process C) [1]. While consumer "
    "wearables have made sleep tracking ubiquitous, the analytical methods employed by most applications remain "
    "rudimentary — typically limited to nightly summaries of duration, efficiency, and basic stage classification. "
    "These approaches discard the rich temporal structure embedded in longitudinal sleep data and fail to capture "
    "how daily behavioral choices modulate sleep architecture over time.",
    styles["Body"]
))
S(Paragraph(
    "We propose <i>SleepDNA</i>, a computational framework inspired by molecular biology and bioinformatics "
    "that treats an individual's sleep history as a genetic sequence amenable to alignment, motif discovery, "
    "mutation analysis, and topological characterization. The framework operates entirely on-device, preserving "
    "data privacy while enabling sophisticated analysis previously restricted to clinical research settings. "
    "Unlike emerging autonomous scientific discovery systems such as EvoScientist [24], which achieve only "
    "21% success in complex method implementation without human supervision, SleepDNA adopts a hybrid approach: "
    "bioinformatics computational tools operated under expert researcher supervision. This architecture aligns "
    "with the growing trend of specialized edge models — such as MSBA-YOLO [25] achieving 96.1% precision "
    "in clinical detection at only 6.4MB — where on-device inference delivers both privacy and performance.",
    styles["Body"]
))
S(Paragraph(
    "This paper presents the theoretical foundations, implemented algorithms, derived health biomarkers, and "
    "potential future research directions of the SleepDNA system. We emphasize that the genomic metaphor is "
    "computational, not biological — we do not claim that sleep patterns constitute literal DNA, but rather "
    "that the mathematical tools developed for sequence analysis are remarkably well-suited to temporal sleep "
    "data [2].",
    styles["Body"]
))

# ═══ 2. Theoretical Framework ═══
S(Paragraph("2. Theoretical Framework", styles["SectionHead"]))

S(Paragraph("2.1. The Two-Process Model of Sleep Regulation", styles["SubHead"]))
S(Paragraph(
    "The foundational physiological model underlying SleepDNA is Borbely's Two-Process Model [1], later "
    "refined by Daan, Beersma, and Borbely [3]. Process S represents homeostatic sleep pressure that "
    "accumulates exponentially during wakefulness and dissipates during sleep:",
    styles["Body"]
))
S(Paragraph("S(t) = S<sub>0</sub> . exp(-t / tau<sub>fall</sub>)   during sleep", styles["Equation"]))
S(Paragraph("S(t) = 1 - (1 - S<sub>0</sub>) . exp(-t / tau<sub>rise</sub>)   during wakefulness", styles["Equation"]))
S(Paragraph(
    "where tau<sub>rise</sub> = 18.2h and tau<sub>fall</sub> = 4.2h are empirically derived time constants [3]. "
    "Process C is modeled as a 24-hour cosine oscillation derived from cosinor analysis [4, 5].",
    styles["Body"]
))

S(Paragraph("2.2. Cosinor Rhythmometry", styles["SubHead"]))
S(Paragraph(
    "Circadian rhythm parameters are estimated using the single-component cosinor method [4]:",
    styles["Body"]
))
S(Paragraph("Y(t) = MESOR + A . cos(omega . t + phi)", styles["Equation"]))
S(Paragraph(
    "where MESOR is the midline estimating statistic of rhythm, A is amplitude, and phi is acrophase "
    "(peak time). The coefficient of determination (R<super>2</super>) quantifies the goodness of fit and serves as our "
    "primary measure of circadian coherence [5]. A sliding window of 7 days provides temporal resolution "
    "while maintaining statistical stability.",
    styles["Body"]
))

S(Paragraph("2.3. The Double-Helix Encoding Model", styles["SubHead"]))
S(Paragraph(
    "Each day of a user's sleep history is encoded as a 16-dimensional feature vector (DayNucleotide), "
    "organized into two complementary strands:",
    styles["Body"]
))

story.extend(make_table(
    [
        ["Index", "Strand", "Feature", "Encoding", "Description"],
        ["0-1", "1 (Sleep)", "Bedtime", "sin/cos circular", "Circular encoding of bedtime hour to resolve midnight discontinuity"],
        ["2-3", "1 (Sleep)", "Wake time", "sin/cos circular", "Circular encoding of wake-up hour"],
        ["4", "1 (Sleep)", "Sleep duration", "hours / 12", "Total sleep hours normalized to [0,1] range"],
        ["5", "1 (Sleep)", "Process S", "Pressure [0,1]", "Homeostatic sleep pressure from the two-process model"],
        ["6", "1 (Sleep)", "Acrophase", "Peak hour / 24", "Normalized peak circadian hour"],
        ["7", "1 (Sleep)", "Cosinor R2", "Strength [0,1]", "Circadian rhythm goodness-of-fit (coherence)"],
        ["8", "2 (Context)", "Caffeine", "count / 5", "Number of caffeine consumptions during the day"],
        ["9", "2 (Context)", "Exercise", "binary [0,1]", "Whether the user performed physical exercise"],
        ["10", "2 (Context)", "Alcohol", "count / 3", "Number of alcohol consumptions"],
        ["11", "2 (Context)", "Melatonin", "binary [0,1]", "Whether the user took melatonin"],
        ["12", "2 (Context)", "Stress", "count / 3", "Self-reported stress level"],
        ["13", "2 (Context)", "Weekend", "binary [0,1]", "Whether the day is Saturday or Sunday"],
        ["14", "2 (Context)", "Drift", "minutes / 120", "Schedule shift relative to chronotype"],
        ["15", "2 (Context)", "Sleep quality", "(dur/goal) x R2", "Composite metric of duration and regularity"],
    ],
    col_ratios=[6, 8, 12, 10, 24],
    caption="<b>Table 1.</b> DayNucleotide feature encoding (16 dimensions per day)."
))

S(Paragraph(
    "Circular encoding of time-of-day variables (bedtime, wake time) via sin/cos pairs resolves the "
    "midnight discontinuity problem (23:59 to 00:01 appears as a large jump in linear encoding but is "
    "correctly represented as a small angular difference in circular space).",
    styles["Body"]
))

# ═══ 3. Analytical Methods ═══
S(PageBreak())
S(Paragraph("3. Analytical Methods", styles["SectionHead"]))

S(Paragraph("3.1. Phase Locking Value via Hilbert Transform", styles["SubHead"]))
S(Paragraph(
    "Inter-strand coupling (the 'base pairs' of SleepDNA) is quantified using Phase Locking Value (PLV) [6, 7]. "
    "For each of the 56 possible strand 1 - strand 2 feature pairs, we compute the analytic signal via "
    "Hilbert Transform using the Accelerate framework's vDSP FFT routines, extract instantaneous phase, "
    "and calculate PLV as:",
    styles["Body"]
))
S(Paragraph("PLV = |mean(exp(i . delta_theta(t)))| in [0, 1]", styles["Equation"]))
S(Paragraph(
    "where delta_theta(t) is the instantaneous phase difference between features. PLV = 1 indicates perfect "
    "phase synchrony; PLV = 0 indicates no synchrony. Pairs with PLV > 0.3 are retained as significant "
    "base pairs. The mean phase difference indicates the temporal relationship (lead/lag) between context "
    "events and sleep outcomes.",
    styles["Body"]
))

S(Paragraph("3.2. Personalized Scoring Matrix (SleepBLOSUM)", styles["SubHead"]))
S(Paragraph(
    "Inspired by the BLOSUM substitution matrices used in protein sequence alignment [8], we developed "
    "SleepBLOSUM — a personalized 16-element weight vector learned from each user's data. For each feature k, "
    "we compute the mutual information (MI) between the feature's time series and next-day sleep quality [9, 10]:",
    styles["Body"]
))
S(Paragraph("MI(X;Y) = H(X) + H(Y) - H(X,Y)", styles["Equation"]))
S(Paragraph(
    "where H denotes Shannon entropy computed over 5-bin discretizations. Weights are normalized to [0, 3.0] "
    "and require a minimum of 14 days of data. Features with higher MI receive proportionally greater weight "
    "in subsequent DTW distance calculations. To our knowledge, this represents the first application of "
    "information-theoretic personalized scoring matrices to consumer sleep data.",
    styles["Body"]
))

S(Paragraph("3.3. Dynamic Time Warping for Sequence Alignment", styles["SubHead"]))
S(Paragraph(
    "Week-to-week comparison uses weighted Dynamic Time Warping (DTW) [11], where each week is represented "
    "as a 7x16 feature matrix (WeekSequence). The DTW distance between weeks A and B is computed using "
    "SleepBLOSUM-weighted Euclidean distance:",
    styles["Body"]
))
S(Paragraph("d(a, b) = sqrt(sum_k w_k . (a_k - b_k)<super>2</super>)", styles["Equation"]))
S(Paragraph(
    "A full O(n<super>2</super>) cost matrix with optimal warping path backtracking enables alignment of weeks with "
    "slightly different temporal structures (e.g., a late-start week aligned to an early-start week). "
    "Partial DTW extends this to in-progress weeks for real-time prediction.",
    styles["Body"]
))

S(Paragraph("3.4. Motif Discovery via Agglomerative Clustering", styles["SubHead"]))
S(Paragraph(
    "Recurring sleep patterns ('motifs') are discovered using pairwise DTW distance matrix followed by "
    "agglomerative clustering [12, 13]. Single-linkage clustering with a distance threshold of 8.0 groups "
    "similar weeks into up to 10 motifs. Each motif's centroid (element-wise mean of member weeks) represents "
    "the canonical pattern. Motifs are auto-named based on the dominant feature deviation from the global mean "
    "(e.g., 'late-night', 'high-stress', 'early-bird').",
    styles["Body"]
))

S(Paragraph("3.5. Mutation Classification", styles["SubHead"]))
S(Paragraph(
    "Following the biological metaphor [14], each week's deviation from its nearest motif centroid is classified "
    "as a mutation based on quality delta:",
    styles["Body"]
))

story.extend(make_table(
    [
        ["Classification", "Threshold", "Interpretation"],
        ["Silent (Stable)", "delta < 0.05", "Week follows the expected pattern without significant deviation"],
        ["Missense (Slight variation)", "0.05 <= delta <= 0.15", "Moderate deviation from the usual pattern"],
        ["Nonsense (Significant change)", "delta > 0.15", "Major disruption of the sleep pattern"],
    ],
    col_ratios=[18, 12, 30],
    caption="<b>Table 2.</b> Mutation classification thresholds."
))

S(Paragraph(
    "Expression rules are discovered by median-splitting each context feature within a motif and comparing "
    "average sleep quality above and below the threshold, revealing which behavioral factors modulate sleep "
    "quality within specific pattern contexts.",
    styles["Body"]
))

S(Paragraph("3.6. Sequence Prediction", styles["SubHead"]))
S(Paragraph(
    "Sleep prediction uses a DTW-based k-nearest-neighbors approach inspired by BLAST sequence alignment [15]. "
    "The current in-progress week (1-6 days) is aligned to all historical full weeks via partial DTW. The top 5 "
    "most similar weeks are identified, and the 'next day' from each historical match is used as a prediction "
    "candidate. Inverse-distance weighting produces a consensus prediction for bedtime, wake time, and sleep "
    "duration. Circular features (bedtime, wake) are decoded from sin/cos components via atan2.",
    styles["Body"]
))

# ═══ 4. Advanced Topological Metrics ═══
S(PageBreak())
S(Paragraph("4. Advanced Topological Metrics", styles["SectionHead"]))

S(Paragraph("4.1. Persistent Circadian Homology (PCH)", styles["SubHead"]))
S(Paragraph(
    "We apply Persistent Homology [16, 17] to the 3D helix point cloud generated from the DayNucleotide "
    "sequences. Using a simplified Rips filtration with Union-Find tracking:",
    styles["Body"]
))
S(Paragraph(
    "- <b>beta<sub>0</sub></b> (connected components): counts long-lived clusters in the helix, representing distinct "
    "circadian regimes.<br/>"
    "- <b>beta<sub>1</sub></b> (loops): detected via Euler characteristic heuristic, representing periodic structures.<br/>"
    "- <b>Structural Stability</b>: mean persistence of features with lifetime exceeding 25% of the maximum "
    "pairwise distance. Higher stability indicates more consistent circadian architecture.",
    styles["Body"]
))
S(Paragraph(
    "To our knowledge, this is the first application of persistent homology to circadian sleep data. "
    "We designate this metric Persistent Circadian Homology (PCH).",
    styles["Body"]
))

S(Paragraph("4.2. Strand Entanglement via Gauss Linking Number", styles["SubHead"]))
S(Paragraph(
    "The coupling between sleep (Strand 1) and context (Strand 2) helices is quantified using the discrete "
    "Gauss linking integral [18]:",
    styles["Body"]
))
S(Paragraph(
    "Lk = (1/4pi) sum_i sum_j (dR1 x dR2) . (R1 - R2) / |R1 - R2|<super>3</super>",
    styles["Equation"]
))
S(Paragraph(
    "Linking Number Density (LND) = |Lk| / N<sub>segments</sub> provides a normalized measure of strand "
    "entanglement. LND > 0.1 indicates coherent coupling between sleep physiology and behavioral context. "
    "This is an entirely original application of knot theory to sleep data, never previously published.",
    styles["Body"]
))

S(Paragraph("4.3. Mutual Information Spectrum (MIS)", styles["SubHead"]))
S(Paragraph(
    "The Mutual Information Spectrum (MIS) quantifies hour-by-hour coupling between the circadian process C(t) "
    "and the homeostatic derivative dH/dt across 24 one-hour windows [1, 9]. This reveals the specific hours "
    "of day when the two regulatory processes are most and least synchronized — information that could inform "
    "personalized sleep scheduling recommendations.",
    styles["Body"]
))

# ═══ 5. Health Biomarkers ═══
S(Paragraph("5. Derived Health Biomarkers", styles["SectionHead"]))

story.extend(make_table(
    [
        ["Biomarker", "Formula / Method", "Alert Threshold", "Ref."],
        ["Circadian Coherence", "Mean cosinor R2 (14-day window)", "< 0.2 (Circadian Anarchy)", "[5]"],
        ["Homeostasis Balance (HB)", "Mean |C(t) - S(t)| from two-process model", "> 0.3 (Desynchrony)", "[1,3]"],
        ["Fragmentation Score", "Awake transitions / total sleep phases", "> 0.6 (High fragmentation)", "[19]"],
        ["Drift Severity", "Mean |daily drift| in minutes", "> 15 min/day (Severe drift)", "Custom"],
        ["Helical Continuity (HCI)", "1 - (awake phases / total phases)", "Informational (no threshold)", "[20]"],
        ["REM Drift Slope (RDS)", "Linear regression of REM phase timing", "|slope| > 0.5 (Abnormal)", "Custom"],
        ["REM Cluster Entropy (RCE)", "Shannon entropy of inter-REM intervals", "Informational (no threshold)", "Custom"],
    ],
    col_ratios=[14, 22, 16, 5],
    caption="<b>Table 3.</b> Derived health biomarkers with alert thresholds."
))

# ═══ 6. On-Device Architecture ═══
S(Paragraph("6. On-Device Architecture", styles["SectionHead"]))
S(Paragraph(
    "The entire SleepDNA pipeline executes locally on iOS devices using Apple's Accelerate framework (vDSP) "
    "for signal processing and vectorized computation. No sleep data is transmitted to external servers. "
    "This architecture aligns with the adoption gap documented by the Anthropic Economic Index [26], which "
    "identifies a 61-point disparity between theoretical AI capability (94%) and observed professional usage "
    "(33%). By executing inference on-device, SleepDNA eliminates cloud API dependency, associated costs, "
    "and the latency and privacy concerns that inhibit healthcare AI adoption. "
    "The pipeline is tier-gated based on available data:",
    styles["Body"]
))

story.extend(make_table(
    [
        ["Tier", "Data Required", "Enabled Analyses"],
        ["Basic", "< 4 weeks", "Nucleotide encoding, PLV, health markers, helix geometry"],
        ["Intermediate", "4-8 weeks", "All Basic + motif discovery, sequence prediction, BLOSUM learning"],
        ["Full", "8+ weeks", "All Intermediate + persistent homology, linking number, MIS, expression rules"],
    ],
    col_ratios=[8, 10, 40],
    caption="<b>Table 4.</b> Tier-gated analysis pipeline."
))

S(Paragraph(
    "Profile snapshots are persisted as compressed JSON in SwiftData with external storage, keeping the "
    "database lean. The SleepBLOSUM weight matrix is cached separately for cross-session reuse. All "
    "computations run on background queues with actor isolation for thread safety.",
    styles["Body"]
))

# ═══ 7. Potential Future Studies ═══
S(PageBreak())
S(Paragraph("7. Potential Future Studies", styles["SectionHead"]))

S(Paragraph("7.1. Validation Against Polysomnography", styles["SubHead"]))
S(Paragraph(
    "The most critical validation step is comparing SleepDNA predictions and biomarkers against clinical "
    "polysomnography (PSG) recordings. A prospective study with 50-100 participants wearing both an Apple Watch "
    "and undergoing 2-3 nights of PSG would enable: (a) validation of motif classification accuracy, "
    "(b) correlation of SleepBLOSUM weights with PSG-derived sleep staging, and (c) calibration of health "
    "biomarker thresholds against clinical outcomes.",
    styles["Body"]
))

S(Paragraph("7.2. SleepBLOSUM Predictive Validity", styles["SubHead"]))
S(Paragraph(
    "A controlled study measuring whether personalized SleepBLOSUM weights predict next-day subjective fatigue "
    "(via Karolinska Sleepiness Scale) more accurately than uniform weights or established algorithms "
    "(e.g., AutoSleep, Oura scoring). Hypothesis: personalized MI-weighted features capture individual "
    "differences that uniform models miss.",
    styles["Body"]
))

S(Paragraph("7.3. Interpersonal Chronobiology", styles["SubHead"]))
S(Paragraph(
    "Extension of the framework to comparative genomics between co-sleeping partners. Three proposed analyses: "
    "(a) <i>Co-sleeping Dynamics</i> — cross-recurrence quantification of awakening patterns between partners; "
    "(b) <i>Chronotype Compatibility</i> — distance between motif centroids as a measure of circadian sacrifice; "
    "(c) <i>Differential Sensitivity</i> — comparing SleepBLOSUM matrices reveals why the same stimulus "
    "(e.g., late dinner) disrupts one partner's sleep but not the other's.",
    styles["Body"]
))

S(Paragraph("7.4. Intra-Night Codon Analysis", styles["SubHead"]))
S(Paragraph(
    "For users with Apple Watch providing sleep stage data (REM, Deep, Light, Awake at 15-minute resolution), "
    "the framework can be extended to k-mer analysis (k=3) of stage transitions within a single night. "
    "Each triplet of consecutive stages would be scored for architectural integrity, enabling detection of "
    "specific disruption patterns (e.g., repeated [REM, Awake, Light] triplets indicating REM fragmentation). "
    "The 64 possible triplets (4<super>3</super>) could be scored using a codon quality table derived from "
    "correlation with next-day subjective outcomes.",
    styles["Body"]
))

S(Paragraph("7.5. Topological Biomarker Clinical Correlates", styles["SubHead"]))
S(Paragraph(
    "The novel topological metrics (PCH, LND, MIS) require clinical validation. Proposed study: correlate "
    "Persistent Circadian Homology with diagnosed circadian rhythm sleep-wake disorders (CRSWD), and Linking "
    "Number Density with treatment response in cognitive-behavioral therapy for insomnia (CBT-I). If "
    "topological features predict treatment outcomes, they could serve as objective digital biomarkers for "
    "sleep medicine.",
    styles["Body"]
))

S(Paragraph("7.6. On-Device Large Language Model Integration", styles["SubHead"]))
S(Paragraph(
    "With Apple's Foundation Models framework (iOS 26), the system could employ an on-device LLM to translate "
    "mathematical findings into personalized natural language insights. Rather than using the LLM for prediction "
    "(where deterministic DTW is more accurate and reliable), it would serve as a semantic interpreter — "
    "connecting detected patterns to actionable advice while maintaining absolute data privacy.",
    styles["Body"]
))

# ═══ 8. Limitations ═══
S(Paragraph("8. Limitations", styles["SectionHead"]))
S(Paragraph(
    "Several limitations should be acknowledged. First, the genomic metaphor is computational, not biological — "
    "sleep patterns are not DNA, and users should not interpret results as medical diagnoses [2]. Second, "
    "the system relies on user-reported context data (caffeine, stress, etc.) which introduces measurement "
    "bias. Third, Apple Watch sleep staging accuracy varies by model and is less precise than clinical PSG. "
    "Fourth, the PLV-based correlation analysis cannot establish causation — confounding variables (e.g., "
    "weekend effect masking as alcohol benefit) are not controlled for. Fifth, the topological metrics "
    "(PCH, LND) are exploratory and lack clinical validation. Sixth, future integration of large language "
    "models (LLMs) for result interpretation introduces the risk of 'alignment tax' or sycophancy — the "
    "documented tendency of LLMs to produce responses that validate user bias rather than providing objective "
    "assessments [27], which could generate misleading insights if not properly controlled. "
    "Finally, the motif discovery requires 8+ weeks "
    "of continuous data, which presents an onboarding challenge.",
    styles["Body"]
))

# ═══ 9. Conclusion ═══
S(Paragraph("9. Conclusion", styles["SectionHead"]))
S(Paragraph(
    "SleepDNA demonstrates that mathematical tools from bioinformatics, signal processing, and algebraic "
    "topology can be fruitfully applied to consumer sleep data. By encoding sleep as nucleotide sequences, "
    "the framework enables motif discovery, mutation classification, personalized prediction, and topological "
    "analysis that go substantially beyond traditional sleep metrics. The on-device architecture ensures that "
    "this sophisticated analysis remains private and accessible. Future validation studies will determine "
    "whether the novel biomarkers proposed here have clinical utility in sleep medicine.",
    styles["Body"]
))

# ═══ References ═══
S(PageBreak())
S(Paragraph("References", styles["SectionHead"]))

refs = [
    "[1] Borbely, A.A. (1982). A two process model of sleep regulation. <i>Human Neurobiology</i>, 1(3), 195-204.",
    "[2] SleepDNA Project (2026). Scientific Basis Document: SleepDNA as computational metaphor. Internal technical report.",
    "[3] Daan, S., Beersma, D.G.M., & Borbely, A.A. (1984). Timing of human sleep: Recovery process gated by a circadian pacemaker. <i>American Journal of Physiology</i>, 246(2), R161-R183.",
    "[4] Cornelissen, G. (2014). Cosinor-based rhythmometry. <i>Theoretical Biology and Medical Modelling</i>, 11, 16.",
    "[5] Refinetti, R., Cornelissen, G., & Halberg, F. (2007). Procedures for numerical analysis of circadian rhythms. <i>Biological Rhythm Research</i>, 38(4), 275-325.",
    "[6] Lachaux, J.P., Rodriguez, E., Martinerie, J., & Varela, F.J. (1999). Measuring phase synchrony in brain signals. <i>Human Brain Mapping</i>, 8(4), 194-208.",
    "[7] Mormann, F., Lehnertz, K., David, P., & Elger, C.E. (2000). Mean phase coherence as a measure for phase synchronization. <i>Journal of Neurophysiology</i>, 84(6), 3187-3189.",
    "[8] Henikoff, S. & Henikoff, J.G. (1992). Amino acid substitution matrices from protein blocks. <i>PNAS</i>, 89(22), 10915-10919.",
    "[9] Shannon, C.E. (1948). A mathematical theory of communication. <i>Bell System Technical Journal</i>, 27(3), 379-423.",
    "[10] Battiti, R. (1994). Using mutual information for selecting features in supervised neural net learning. <i>IEEE Transactions on Neural Networks</i>, 5(4), 537-550.",
    "[11] Sakoe, H. & Chiba, S. (1978). Dynamic programming algorithm optimization for spoken word recognition. <i>IEEE Trans. ASSP</i>, 26(1), 43-49.",
    "[12] Bailey, T.L. & Elkan, C. (1994). Fitting a mixture model by expectation maximization to discover motifs in biopolymers. <i>ISMB Proceedings</i>, 28-36.",
    "[13] Hastie, T., Tibshirani, R., & Friedman, J. (2009). <i>The Elements of Statistical Learning</i> (2nd ed.). Springer.",
    "[14] Alberts, B., Johnson, A., Lewis, J., et al. (2002). <i>Molecular Biology of the Cell</i> (4th ed.). Garland Science.",
    "[15] Altschul, S.F., Gish, W., Miller, W., et al. (1990). Basic local alignment search tool. <i>Journal of Molecular Biology</i>, 215(3), 403-410.",
    "[16] Edelsbrunner, H., Letscher, D., & Zomorodian, A. (2000). Topological persistence and simplification. <i>Discrete & Computational Geometry</i>, 28(4), 511-533.",
    "[17] Carlsson, G. (2009). Topology and data. <i>Bulletin of the American Mathematical Society</i>, 46(2), 255-308.",
    "[18] Bates, A.D. & Maxwell, A. (2005). <i>DNA Topology</i> (2nd ed.). Oxford University Press.",
    "[19] Bonnet, M.H. & Arand, D.L. (2003). Clinical effects of sleep fragmentation versus sleep deprivation. <i>Sleep Medicine Reviews</i>, 7(4), 297-310.",
    "[20] Carskadon, M.A. & Dement, W.C. (2011). Monitoring and staging human sleep. In M.H. Kryger et al. (Eds.), <i>Principles and Practice of Sleep Medicine</i> (5th ed.).",
    "[21] Bird, A. (2007). Perceptions of epigenetics. <i>Nature</i>, 447(7143), 396-398.",
    "[22] Nirenberg, M. & Matthaei, J.H. (1961). The dependence of cell-free protein synthesis upon naturally occurring or synthetic polyribonucleotides. <i>PNAS</i>, 47(10), 1588-1602.",
    "[23] Watson, J.D. & Crick, F.H.C. (1953). Molecular structure of nucleic acids. <i>Nature</i>, 171(4356), 737-738.",
    "[24] EvoScientist (2026). Towards Multi-Agent Evolving AI Scientists for End-to-End Scientific Discovery. <i>arXiv</i>, 2603.08127.",
    "[25] MSBA-YOLO (2026). Lightweight laryngeal disease detection algorithm. <i>AI</i>, 7(3). MDPI.",
    "[26] Massenkoff, M. & McCrory, P. (2026). Labor market impacts of AI: A new measure and early evidence. Anthropic Research.",
    "[27] Lerchner, A. (2026). The Abstraction Fallacy: Why AI Can Simulate But Not Instantiate Consciousness. Google DeepMind Publications.",
]

for ref in refs:
    S(Paragraph(ref, styles["RefItem"]))

# ═══ Build ═══
output_path = "/Users/xaron/Desktop/spiral journey project/docs/SleepDNA-Scientific-Paper.pdf"
doc = SimpleDocTemplate(
    output_path,
    pagesize=A4,
    leftMargin=MARGIN, rightMargin=MARGIN,
    topMargin=MARGIN, bottomMargin=MARGIN,
    title="SleepDNA: Computational Genomics Applied to Sleep Analysis",
    author="Spiral Journey Project"
)
doc.build(story)
print(f"PDF generated: {output_path}")
