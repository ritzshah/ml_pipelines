#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Convert TF SavedModel to OpenVINO IR using Model Optimizer")
    parser.add_argument("--saved_model", required=True, help="Path to TF SavedModel directory")
    parser.add_argument("--out", required=True, help="Output directory for IR (.xml/.bin)")
    parser.add_argument("--model_name", default="model")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    # Requires openvino-dev installed in the environment providing 'mo' CLI
    # Example: pip install openvino-dev
    cmd = [
        "mo",
        f"--saved_model_dir={args.saved_model}",
        f"--output_dir={args.out}",
        f"--model_name={args.model_name}",
    ]
    print("Running:", " ".join(cmd))
    subprocess.check_call(cmd)

    xml = Path(args.out) / f"{args.model_name}.xml"
    binf = Path(args.out) / f"{args.model_name}.bin"
    meta = Path(args.out) / f"{args.model_name}.json"
    metadata = {
        "model_name": args.model_name,
        "xml": str(xml),
        "bin": str(binf),
    }
    with open(meta, "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"IR files: {xml}, {binf}")


if __name__ == "__main__":
    main()


