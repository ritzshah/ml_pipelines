#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import datetime

import numpy as np
import pandas as pd

try:
    import tensorflow as tf
    from tensorflow import keras
except Exception as e:
    raise SystemExit("TensorFlow not available. Install with: pip install -r requirements.txt")


def make_supervised(series: np.ndarray, window: int = 20, horizon: int = 1):
    X, y = [], []
    for i in range(len(series) - window - horizon + 1):
        X.append(series[i:i + window])
        y.append(series[i + window + horizon - 1])
    return np.array(X)[..., np.newaxis], np.array(y)


def build_model(window: int) -> keras.Model:
    inputs = keras.Input(shape=(window, 1))
    x = keras.layers.LSTM(64, return_sequences=True)(inputs)
    x = keras.layers.LSTM(32)(x)
    x = keras.layers.Dense(32, activation="relu")(x)
    outputs = keras.layers.Dense(1)(x)
    model = keras.Model(inputs, outputs)
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
    return model


def train_on_symbol(csv_path: str, out_dir: str, window: int = 20, horizon: int = 1, epochs: int = 10, val_split: float = 0.2):
    df = pd.read_csv(csv_path)
    if "Adj Close" not in df.columns:
        raise ValueError("CSV must contain 'Adj Close' column")
    values = df["Adj Close"].astype(float).values

    X, y = make_supervised(values, window, horizon)
    n = len(X)
    if n < 10:
        raise ValueError("Not enough samples after windowing")
    split = int(n * (1 - val_split))
    X_train, y_train = X[:split], y[:split]
    X_val, y_val = X[split:], y[split:]

    model = build_model(window)
    history = model.fit(
        X_train,
        y_train,
        validation_data=(X_val, y_val),
        epochs=epochs,
        batch_size=32,
        verbose=2,
    )

    # Evaluate RMSE on validation
    val_pred = model.predict(X_val, verbose=0).squeeze()
    rmse = float(np.sqrt(np.mean((val_pred - y_val) ** 2)))

    # Save model (TF SavedModel)
    sym = os.path.basename(csv_path).split("_")[0]
    model_dir = os.path.join(out_dir, f"lstm_{sym}_savedmodel")
    os.makedirs(model_dir, exist_ok=True)
    model.save(model_dir)

    # Save metrics
    metrics = {
        "symbol": sym,
        "window": window,
        "horizon": horizon,
        "epochs": epochs,
        "val_rmse": rmse,
        "history": {k: [float(x) for x in v] for k, v in history.history.items()},
        "timestamp": datetime.utcnow().isoformat(),
        "model_dir": model_dir,
        "framework": "tensorflow",
        "model_type": "lstm",
    }
    metrics_path = os.path.join(out_dir, f"metrics_lstm_{sym}.json")
    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"Saved: {model_dir}\nMetrics: {metrics_path}\nRMSE: {rmse:.4f}")


def main():
    parser = argparse.ArgumentParser(description="Train LSTM on features CSV and save model+metrics to PVC")
    parser.add_argument("--features_dir", required=True, help="Directory with *_features.csv or raw CSVs with Adj Close")
    parser.add_argument("--out", required=True, help="Output directory on PVC for models/metrics")
    parser.add_argument("--window", type=int, default=20)
    parser.add_argument("--horizon", type=int, default=1)
    parser.add_argument("--epochs", type=int, default=10)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    csvs = sorted(glob.glob(os.path.join(args.features_dir, "*_features.csv")))
    if not csvs:
        csvs = sorted(glob.glob(os.path.join(args.features_dir, "*.csv")))
    if not csvs:
        raise SystemExit("No CSVs found under features_dir")

    for csv in csvs:
        try:
            train_on_symbol(csv, args.out, args.window, args.horizon, args.epochs)
        except Exception as e:
            print(f"Skipping {csv}: {e}")


if __name__ == "__main__":
    main()


