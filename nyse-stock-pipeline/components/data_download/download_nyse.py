#!/usr/bin/env python3
import argparse
import os
import sys
import time
from datetime import datetime

try:
    import yfinance as yf
except ImportError:
    print("Missing yfinance. Install with: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(1)


def ensure_dir(path: str) -> None:
    if not os.path.exists(path):
        os.makedirs(path, exist_ok=True)


def download_symbol(symbol: str, start: str, end: str, out_dir: str) -> str:
    df = yf.download(symbol, start=start, end=end, progress=False, auto_adjust=False)
    if df is None or df.empty:
        return ""
    df.reset_index(inplace=True)
    csv_path = os.path.join(out_dir, f"{symbol.upper()}_{start}_{end}.csv")
    df.to_csv(csv_path, index=False)
    return csv_path


def main():
    parser = argparse.ArgumentParser(description="Download NYSE stock data to a PVC path")
    parser.add_argument("--symbols", required=True, help="Comma-separated tickers, e.g. AAPL,MSFT,GOOG")
    parser.add_argument("--start", required=True, help="Start date YYYY-MM-DD")
    parser.add_argument("--end", required=True, help="End date YYYY-MM-DD")
    parser.add_argument("--out", required=True, help="Output directory, e.g. /mnt/pvc/nyse-data")
    args = parser.parse_args()

    symbols = [s.strip().upper() for s in args.symbols.split(",") if s.strip()]
    start = args.start
    end = args.end
    out_root = os.path.abspath(args.out)

    ensure_dir(out_root)
    stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    out_dir = os.path.join(out_root, f"download_{stamp}")
    ensure_dir(out_dir)

    print(f"Writing CSVs under: {out_dir}")
    saved = []
    for sym in symbols:
        try:
            print(f"Downloading {sym}...")
            p = download_symbol(sym, start, end, out_dir)
            if p:
                size = os.path.getsize(p)
                print(f"  ✓ {sym}: {p} ({size} bytes)")
                saved.append(p)
            else:
                print(f"  ✗ {sym}: no data returned")
        except Exception as e:
            print(f"  ✗ {sym}: {e}")
        time.sleep(0.2)

    if not saved:
        print("No files saved.")
        sys.exit(2)

    manifest = os.path.join(out_dir, "manifest.txt")
    with open(manifest, "w") as f:
        f.write("\n".join(saved))
    print(f"Saved {len(saved)} files. Manifest: {manifest}")


if __name__ == "__main__":
    main()


