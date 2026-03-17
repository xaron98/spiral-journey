#!/usr/bin/env python3
"""
Train an updatable Neural Network for sleep prediction and export to Core ML.

Builds a 3-layer MLP (21 → 64 → 32 → 1) with the output layer marked as
updatable.  On-device MLUpdateTask fine-tunes it with real user data.

StandardScaler normalisation is folded into the first layer weights so the
Core ML model accepts raw PredictionInput features directly.

Usage:
    python3 Scripts/train_updatable_model.py

Outputs:
    spiral journey project/Resources/SleepPredictorUpdatable.mlmodel
"""

import numpy as np
from sklearn.neural_network import MLPRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import coremltools as ct
from coremltools.models import datatypes, MLModel
from coremltools.models.neural_network import NeuralNetworkBuilder, SgdParams
import os

# --------------------------------------------------------------------------- #
# 1. Synthetic data generation (duplicated from train_sleep_model.py)
# --------------------------------------------------------------------------- #

np.random.seed(42)
N = 10_000


def generate_synthetic_dataset(n: int):
    """Generate realistic sleep-prediction training data.

    Target is a CONTINUOUS bedtime in range ~18-30 (avoiding midnight wrap).
    18 = 6 PM, 24 = midnight, 25 = 1 AM, 30 = 6 AM.
    """
    # Chronotype subpopulations (mixture model)
    #   30% night owls:   mean 25.5 (1:30 AM), std 1.0h
    #   50% intermediate: mean 23.5 (11:30 PM), std 0.7h
    #   20% early birds:  mean 22.0 (10:00 PM), std 0.5h
    chrono_type = np.random.choice(3, size=n, p=[0.30, 0.50, 0.20])
    chrono_means = np.array([25.5, 23.5, 22.0])
    chrono_stds  = np.array([1.0, 0.7, 0.5])
    base_bed = np.array([
        np.random.normal(chrono_means[c], chrono_stds[c]) for c in chrono_type
    ])

    is_weekend = np.random.binomial(1, 2 / 7, n).astype(float)
    is_tomorrow_weekend = np.random.binomial(1, 2 / 7, n).astype(float)
    weekend_shift = is_tomorrow_weekend * np.random.uniform(0.2, 1.5, n)

    exercise = np.random.poisson(0.3, n).astype(float)
    caffeine = np.random.poisson(0.8, n).astype(float)
    melatonin = np.random.binomial(1, 0.05, n).astype(float)
    stress = np.random.poisson(0.4, n).astype(float)
    alcohol = np.random.poisson(0.15, n).astype(float)

    # Correlated event effects on target bedtime
    eff_caffeine  = caffeine  * np.random.uniform(20, 40, n) / 60.0
    eff_exercise  = exercise  * np.random.uniform(-20, -10, n) / 60.0
    eff_alcohol   = alcohol   * np.random.uniform(15, 30, n) / 60.0
    eff_melatonin = melatonin * np.random.uniform(-30, -15, n) / 60.0
    eff_stress    = stress    * np.random.normal(0.25, 0.10, n)

    process_s = np.clip(np.random.normal(0.50, 0.15, n), 0, 1)
    pressure_effect = np.where(process_s > 0.65, -22.5 / 60.0, 0.0)

    sleep_debt = np.random.normal(-0.3, 0.8, n)
    debt_effect = np.clip(sleep_debt * -0.15, -0.5, 0.5)

    drift_rate = np.random.normal(0, 8, n)
    drift_effect = (drift_rate / 60) * 0.5

    chrono_shift = np.array([
        (chrono_means[c] - 23.5) for c in chrono_type
    ]) + np.random.normal(0, 0.2, n)

    actual_bed = (
        base_bed
        + weekend_shift
        + eff_exercise + eff_caffeine + eff_melatonin + eff_stress + eff_alcohol
        + pressure_effect + debt_effect + drift_effect
        + np.random.normal(0, 0.3, n)
    )
    actual_bed = np.clip(actual_bed, 18, 30)

    current_hour = np.random.uniform(16, 22, n)
    sin_hour = np.sin(2 * np.pi * current_hour / 24)
    cos_hour = np.cos(2 * np.pi * current_hour / 24)

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
# 2. Train sklearn MLP
# --------------------------------------------------------------------------- #

print("Generating synthetic dataset …")
X, y, feature_names = generate_synthetic_dataset(N)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)
print(f"Train: {len(X_train)}, Test: {len(X_test)}")

scaler = StandardScaler()
X_train_s = scaler.fit_transform(X_train)
X_test_s = scaler.transform(X_test)

print("Training MLP (21 → 64 → 32 → 1) …")

# Use SGD with warm restarts — more numerically stable than lbfgs on this data
import warnings
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    mlp = MLPRegressor(
        hidden_layer_sizes=(64, 32),
        activation="relu",
        solver="adam",
        learning_rate_init=0.001,
        alpha=0.01,               # L2 regularisation
        batch_size=256,
        max_iter=500,
        random_state=42,
        early_stopping=True,
        validation_fraction=0.1,
        n_iter_no_change=20,
        tol=1e-5,
    )
    mlp.fit(X_train_s, y_train)

y_pred = mlp.predict(X_test_s)
mae = np.mean(np.abs(y_test - y_pred))
print(f"MLP Test MAE: {mae:.3f} hours ({mae * 60:.1f} minutes)")

# --------------------------------------------------------------------------- #
# 3. Fold StandardScaler into first layer weights
# --------------------------------------------------------------------------- #

W1, b1 = mlp.coefs_[0].copy(), mlp.intercepts_[0].copy()   # (21, 64), (64,)
W2, b2 = mlp.coefs_[1].copy(), mlp.intercepts_[1].copy()   # (64, 32), (32,)
W3, b3 = mlp.coefs_[2].copy(), mlp.intercepts_[2].copy()   # (32, 1),  (1,)

# Clip extreme weights to prevent numerical issues after scaler folding
MAX_W = 100.0
for W in [W1, W2, W3]:
    np.clip(W, -MAX_W, MAX_W, out=W)
for b in [b1, b2, b3]:
    np.clip(b, -MAX_W, MAX_W, out=b)

print(f"Weight ranges: W1=[{W1.min():.3f}, {W1.max():.3f}], "
      f"W2=[{W2.min():.3f}, {W2.max():.3f}], "
      f"W3=[{W3.min():.3f}, {W3.max():.3f}]")

# layer1 = ((X - μ)/σ) @ W1 + b1  =  X @ (W1/σ[:,None]) + (b1 - (μ/σ) @ W1)
mean = scaler.mean_    # (21,)
std  = scaler.scale_   # (21,)

# Guard against zero/tiny std
std_safe = np.where(std < 1e-10, 1.0, std)

W1_folded = W1 / std_safe[:, None]
b1_folded = b1 - (mean / std_safe) @ W1

# Verify no NaN/inf in folded weights
assert np.all(np.isfinite(W1_folded)), "W1_folded has non-finite values!"
assert np.all(np.isfinite(b1_folded)), "b1_folded has non-finite values!"

print("Scaler folded into first dense layer ✓")

# --------------------------------------------------------------------------- #
# 4. Build Core ML Neural Network (updatable)
# --------------------------------------------------------------------------- #

print("Building Core ML neural network …")

input_features  = [("features", datatypes.Array(21))]
output_features = [("predictedBedtimeHour", datatypes.Array(1))]

builder = NeuralNetworkBuilder(
    input_features, output_features, disable_rank5_shape_mapping=True
)

# Dense 1: 21 → 64 (scaler folded)
builder.add_inner_product(
    name="dense1",
    W=W1_folded.T.flatten().astype(np.float32),
    b=b1_folded.astype(np.float32),
    input_channels=21, output_channels=64, has_bias=True,
    input_name="features", output_name="dense1_out",
)
builder.add_activation(
    name="relu1", non_linearity="RELU",
    input_name="dense1_out", output_name="relu1_out",
)

# Dense 2: 64 → 32
builder.add_inner_product(
    name="dense2",
    W=W2.T.flatten().astype(np.float32),
    b=b2.astype(np.float32),
    input_channels=64, output_channels=32, has_bias=True,
    input_name="relu1_out", output_name="dense2_out",
)
builder.add_activation(
    name="relu2", non_linearity="RELU",
    input_name="dense2_out", output_name="relu2_out",
)

# Output layer: 32 → 1  (UPDATABLE)
builder.add_inner_product(
    name="output_layer",
    W=W3.T.flatten().astype(np.float32),
    b=b3.astype(np.float32),
    input_channels=32, output_channels=1, has_bias=True,
    input_name="relu2_out", output_name="predictedBedtimeHour",
)

# Mark output layer as updatable
builder.make_updatable(["output_layer"])

# Loss: MSE between prediction and target "predictedBedtimeHour_true"
builder.set_mean_squared_error_loss(
    name="mse_loss",
    input_feature=("predictedBedtimeHour", datatypes.Array(1)),
)

# Optimizer
builder.set_sgd_optimizer(SgdParams(lr=0.01, batch=16, momentum=0.0))
builder.set_epochs(50)

# --------------------------------------------------------------------------- #
# 5. Save
# --------------------------------------------------------------------------- #

spec = builder.spec
model = MLModel(spec)

model.author = "Spiral Journey"
model.short_description = (
    "Updatable sleep prediction NN (21→64→32→1). "
    "Output: predictedBedtimeHour (continuous 18-30). "
    "Last layer fine-tunable via MLUpdateTask."
)
model.license = "Private"

out_dir = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "spiral journey project", "Resources",
)
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "SleepPredictorUpdatable.mlmodel")
model.save(out_path)

size_kb = os.path.getsize(out_path) / 1024
print(f"\nSaved: {out_path}")
print(f"Model size: {size_kb:.1f} KB")
print("Done! ✓")
