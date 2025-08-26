#!/usr/bin/env python3
import argparse
import os
import glob
import pandas as pd
import numpy as np


def compute_features(df: pd.DataFrame, windows=(5, 10, 20)) -> pd.DataFrame:
    df = df.copy()
    # Assumes columns: Date, Open, High, Low, Close, Adj Close, Volume
    df["Return"] = df["Adj Close"].pct_change()
    for w in windows:
        df[f"MA_{w}"] = df["Adj Close"].rolling(w).mean()
        df[f"STD_{w}"] = df["Adj Close"].rolling(w).std()
        df[f"RSI_{w}"] = rsi(df["Adj Close"], w)
    df.dropna(inplace=True)
    return df


def rsi(series: pd.Series, period: int = 14) -> pd.Series:
    delta = series.diff()
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)
    roll_up = pd.Series(gain).rolling(period).mean()
    roll_down = pd.Series(loss).rolling(period).mean()
    rs = roll_up / (roll_down + 1e-9)
    return 100.0 - (100.0 / (1.0 + rs))


def main():
    parser = argparse.ArgumentParser(description="Generate technical features from downloaded CSVs")
    parser.add_argument("--input_root", required=True, help="Root folder containing download_* folders")
    parser.add_argument("--output", required=True, help="Output folder under PVC, e.g. /mnt/pvc/nyse-features")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    # Find latest download batch
    candidates = sorted(glob.glob(os.path.join(args.input_root, "download_*")))
    if not candidates:
        raise SystemExit("No download_* folder found under input_root")
    latest = candidates[-1]
    csvs = sorted(glob.glob(os.path.join(latest, "*.csv")))
    if not csvs:
        raise SystemExit("No CSVs found in latest download folder")

    outputs = []
    for csv_path in csvs:
        sym = os.path.basename(csv_path).split("_")[0]
        df = pd.read_csv(csv_path)
        feat = compute_features(df)
        out_csv = os.path.join(args.output, f"{sym}_features.csv")
        feat.to_csv(out_csv, index=False)
        outputs.append(out_csv)
        print(f"Saved features: {out_csv}")

    print(f"Generated {len(outputs)} feature files to {args.output}")


if __name__ == "__main__":
    main()


