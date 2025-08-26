#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import datetime

import numpy as np
import pandas as pd

try:
    from statsmodels.tsa.arima.model import ARIMA
except Exception:
    raise SystemExit("statsmodels not available. Install with: pip install -r requirements.txt")


def train_arima_on_symbol(csv_path: str, out_dir: str, order=(5, 1, 0)):
    df = pd.read_csv(csv_path)
    if "Adj Close" not in df.columns:
        raise ValueError("CSV must contain 'Adj Close' column")
    y = df["Adj Close"].astype(float).values

    # Simple train/val split
    n = len(y)
    split = int(n * 0.8)
    train, val = y[:split], y[split:]

    model = ARIMA(train, order=order)
    fit = model.fit()
    forecast = fit.forecast(steps=len(val))
    rmse = float(np.sqrt(np.mean((forecast - val) ** 2)))

    sym = os.path.basename(csv_path).split("_")[0]
    model_dir = os.path.join(out_dir, f"arima_{sym}")
    os.makedirs(model_dir, exist_ok=True)

    # Save a simple JSON with params and coefficients (statsmodels save can be large)
    model_info = {
        "symbol": sym,
        "order": order,
        "params": {str(k): float(v) for k, v in fit.params.items()},
    }
    with open(os.path.join(model_dir, "model.json"), "w") as f:
        json.dump(model_info, f, indent=2)

    metrics = {
        "symbol": sym,
        "val_rmse": rmse,
        "timestamp": datetime.utcnow().isoformat(),
        "model_dir": model_dir,
        "framework": "statsmodels",
        "model_type": "arima",
    }
    metrics_path = os.path.join(out_dir, f"metrics_arima_{sym}.json")
    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"Saved: {model_dir}\nMetrics: {metrics_path}\nRMSE: {rmse:.4f}")


def main():
    parser = argparse.ArgumentParser(description="Train ARIMA and save model+metrics to PVC")
    parser.add_argument("--features_dir", required=True, help="Directory with *_features.csv or raw CSVs with Adj Close")
    parser.add_argument("--out", required=True, help="Output directory on PVC for models/metrics")
    parser.add_argument("--order", default="5,1,0", help="ARIMA order p,d,q")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    order = tuple(int(x) for x in args.order.split(","))

    csvs = sorted(glob.glob(os.path.join(args.features_dir, "*_features.csv")))
    if not csvs:
        csvs = sorted(glob.glob(os.path.join(args.features_dir, "*.csv")))
    if not csvs:
        raise SystemExit("No CSVs found under features_dir")

    for csv in csvs:
        try:
            train_arima_on_symbol(csv, args.out, order)
        except Exception as e:
            print(f"Skipping {csv}: {e}")


if __name__ == "__main__":
    main()


