#!/usr/bin/env python3
import argparse
import glob
import json
import os


def main():
    parser = argparse.ArgumentParser(description="Select best model by RMSE across metrics JSONs")
    parser.add_argument("--metrics_dir", required=True, help="Directory containing metrics_*.json files")
    parser.add_argument("--out", required=True, help="Output file path for selection result JSON")
    args = parser.parse_args()

    metric_files = sorted(glob.glob(os.path.join(args.metrics_dir, "metrics_*.json")))
    if not metric_files:
        raise SystemExit("No metrics_*.json files found")

    best = None
    for mf in metric_files:
        with open(mf, "r") as f:
            m = json.load(f)
        rmse = float(m.get("val_rmse", 1e18))
        if best is None or rmse < best["val_rmse"]:
            best = m
            best["metrics_file"] = mf

    if best is None:
        raise SystemExit("Could not determine best model")

    with open(args.out, "w") as f:
        json.dump(best, f, indent=2)
    print(f"Best model: {best.get('model_type')} {best.get('symbol')} RMSE={best['val_rmse']:.4f}")
    print(f"Selection written to: {args.out}")


if __name__ == "__main__":
    main()


