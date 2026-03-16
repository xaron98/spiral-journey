#!/usr/bin/env python3
"""
Train a Gradient Boosting sleep-prediction model and export to Core ML.

Input:  21 features from PredictionInput (see PredictionModels.swift)
Output: predictedBedtimeHour in CONTINUOUS range (18-30, where 25 = 1 AM)
        Swift wrapper converts back to 0-24 via mod.

Uses synthetic data modelling realistic sleep distributions so the model
works from day 1.  On-device MLUpdateTask will personalise it later.

Usage:
    python3 Scripts/train_sleep_model.py

Outputs:
    spiral journey project/Resources/SleepPredictor.mlmodel
"""

import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import train_test_split
import coremltools as ct
import os

# --------------------------------------------------------------------------- #
# 1. Synthetic data generation
# --------------------------------------------------------------------------- #

np.random.seed(42)
N = 10_000  # samples


def generate_synthetic_dataset(n: int):
    """Generate realistic sleep-prediction training data.

    Each sample represents one evening's feature snapshot and the actual
    bedtime that followed.  Distributions are based on published population
    sleep statistics (NSF 2020, Roenneberg 2007).

    Target is a CONTINUOUS bedtime in range ~18-30 (avoiding midnight wrap).
    18 = 6 PM, 24 = midnight, 25 = 1 AM, 30 = 6 AM.
    """

    # --- True parameters (latent) ---
    base_bed = np.random.normal(23.0, 1.0, n)  # most people ~11 PM ± 1h
    is_weekend = np.random.binomial(1, 2 / 7, n).astype(float)
    is_tomorrow_weekend = np.random.binomial(1, 2 / 7, n).astype(float)
    weekend_shift = is_tomorrow_weekend * np.random.uniform(0.2, 1.5, n)

    # Events
    exercise = np.random.poisson(0.3, n).astype(float)
    caffeine = np.random.poisson(0.8, n).astype(float)
    melatonin = np.random.binomial(1, 0.05, n).astype(float)
    stress = np.random.poisson(0.4, n).astype(float)
    alcohol = np.random.poisson(0.15, n).astype(float)

    # Event effects (with per-sample noise to simulate individual differences)
    eff_exercise  = exercise  * np.random.normal(-0.25, 0.10, n)
    eff_caffeine  = caffeine  * np.random.normal( 0.50, 0.15, n)
    eff_melatonin = melatonin * np.random.normal(-0.33, 0.10, n)
    eff_stress    = stress    * np.random.normal( 0.25, 0.10, n)
    eff_alcohol   = alcohol   * np.random.normal(-0.17, 0.08, n)

    # Sleep pressure (0-1 scale)
    process_s = np.clip(np.random.normal(0.50, 0.15, n), 0, 1)
    pressure_effect = np.where(process_s > 0.65, -(process_s - 0.65) * 1.5, 0)

    # Sleep debt (hours, negative = undersleeping)
    sleep_debt = np.random.normal(-0.3, 0.8, n)
    debt_effect = np.clip(sleep_debt * -0.15, -0.5, 0.5)

    # Drift (minutes/day)
    drift_rate = np.random.normal(0, 8, n)
    drift_effect = (drift_rate / 60) * 0.5

    # Chronotype shift (hours from intermediate 23.5)
    chrono_shift = np.random.normal(0, 0.7, n)

    # --- Actual bedtime (continuous, no wrap) ---
    actual_bed = (
        base_bed
        + weekend_shift
        + eff_exercise + eff_caffeine + eff_melatonin + eff_stress + eff_alcohol
        + pressure_effect + debt_effect + drift_effect
        + chrono_shift * 0.3
        + np.random.normal(0, 0.3, n)  # irreducible noise
    )
    # Keep in continuous range (no mod): ~18-30
    # Some extreme early-birds might be <20, night owls >26 — that's fine
    actual_bed = np.clip(actual_bed, 18, 30)

    # --- Build feature matrix (matches PredictionInput) ---
    current_hour = np.random.uniform(16, 22, n)
    sin_hour = np.sin(2 * np.pi * current_hour / 24)
    cos_hour = np.cos(2 * np.pi * current_hour / 24)

    # Rolling stats — also in continuous space (PredictionFeatureBuilder
    # normalises late-night hours 0-6 to 24-30 in the Swift code)
    mean_bed_7d = base_bed + np.random.normal(0, 0.3, n)
    mean_wake_7d = np.clip(np.random.normal(7.5, 1.0, n), 4, 12)
    std_bed_7d = np.abs(np.random.normal(0.5, 0.3, n))

    last_sleep_dur = np.clip(np.random.normal(7.5, 1.0, n), 4, 11)

    acrophase = np.random.normal(15.0, 1.5, n)
    cosinor_r2 = np.clip(np.random.normal(0.55, 0.20, n), 0, 1)
    consistency = np.clip(np.random.normal(55, 20, n), 0, 100)
    data_count = np.random.randint(3, 30, n).astype(float)

    X = np.column_stack([
        sin_hour, cos_hour,
        is_weekend, is_tomorrow_weekend,
        mean_bed_7d, mean_wake_7d, std_bed_7d,
        sleep_debt, last_sleep_dur, process_s,
        acrophase, cosinor_r2,
        exercise, caffeine, melatonin, stress, alcohol,
        drift_rate, consistency, chrono_shift,
        data_count,
    ])

    feature_names = [
        "sinHour", "cosHour",
        "isWeekend", "isTomorrowWeekend",
        "meanBedtime7d", "meanWake7d", "stdBedtime7d",
        "sleepDebt", "lastSleepDuration", "processS",
        "acrophase", "cosinorR2",
        "exerciseToday", "caffeineToday", "melatoninToday",
        "stressToday", "alcoholToday",
        "driftRate", "consistencyScore", "chronotypeShift",
        "dataCount",
    ]

    return X, actual_bed, feature_names


# --------------------------------------------------------------------------- #
# 2. Train
# --------------------------------------------------------------------------- #

print("Generating synthetic dataset...")
X, y, feature_names = generate_synthetic_dataset(N)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

print(f"Training set: {len(X_train)}, Test set: {len(X_test)}")

model = GradientBoostingRegressor(
    n_estimators=200,
    max_depth=4,
    learning_rate=0.1,
    subsample=0.8,
    min_samples_leaf=10,
    random_state=42,
)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)

mae_hours = np.mean(np.abs(y_test - y_pred))
print(f"Test MAE: {mae_hours:.3f} hours ({mae_hours * 60:.1f} minutes)")

# Feature importance
print("\nTop 10 feature importances:")
importances = sorted(
    zip(feature_names, model.feature_importances_),
    key=lambda x: x[1], reverse=True
)
for name, imp in importances[:10]:
    print(f"  {name:20s} {imp:.4f}")


# --------------------------------------------------------------------------- #
# 3. Convert to Core ML
# --------------------------------------------------------------------------- #

print("\nConverting to Core ML...")

coreml_model = ct.converters.sklearn.convert(
    model,
    input_features=feature_names,
    output_feature_names="predictedBedtimeHour",
)

coreml_model.author = "Spiral Journey"
coreml_model.short_description = (
    "Predicts tonight's bedtime in continuous hours (18-30 range, "
    "where 24=midnight, 25=1AM). Swift wrapper converts to 0-24 via mod. "
    "Generic baseline trained on synthetic population data."
)
coreml_model.license = "Private"

# Set feature descriptions
for feat, desc in {
    "sinHour": "sin(2pi * currentHour / 24)",
    "cosHour": "cos(2pi * currentHour / 24)",
    "isWeekend": "1.0 if today is weekend",
    "isTomorrowWeekend": "1.0 if target night is weekend",
    "meanBedtime7d": "Circular mean bedtime over last 7 days (hours, continuous 18-30)",
    "meanWake7d": "Mean wake time over last 7 days (hours 4-12)",
    "stdBedtime7d": "Circular std of bedtimes (hours)",
    "sleepDebt": "Mean sleep duration - goal (hours, negative = undersleeping)",
    "lastSleepDuration": "Most recent sleep duration (hours)",
    "processS": "Homeostatic sleep pressure (0-1, Borbely model)",
    "acrophase": "Latest cosinor acrophase (hours)",
    "cosinorR2": "Cosinor fit quality (0-1)",
    "exerciseToday": "Exercise events today (count)",
    "caffeineToday": "Caffeine events today (count)",
    "melatoninToday": "Melatonin events today (count)",
    "stressToday": "Stress events today (count)",
    "alcoholToday": "Alcohol events today (count)",
    "driftRate": "Acrophase drift (minutes/day)",
    "consistencyScore": "Sleep consistency (0-100)",
    "chronotypeShift": "Chronotype offset from intermediate (hours)",
    "dataCount": "Number of records in 7-day window",
}.items():
    coreml_model.input_description[feat] = desc

coreml_model.output_description["predictedBedtimeHour"] = (
    "Predicted bedtime in continuous hours (18-30, where 24=midnight). "
    "Convert to clock hour: result % 24"
)

# Save
out_dir = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "spiral journey project", "Resources"
)
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "SleepPredictor.mlmodel")
coreml_model.save(out_path)
print(f"Saved: {out_path}")
print(f"Model size: {os.path.getsize(out_path) / 1024:.1f} KB")
print("Done!")
