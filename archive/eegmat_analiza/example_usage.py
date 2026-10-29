"""Simple example showing how to use the eegmat package to load data and build dataset.

Run with: .venv/bin/python scripts/example_usage.py
"""
from pathlib import Path
from eegmat.io import load_all
from eegmat.dataset import make_dataset


def find_data_dir():
    candidates = [
        Path("datasets/physionet.org/files/eegmat/1.0.0"),
        Path("physionet.org/files/eegmat/1.0.0"),
    ]
    for p in candidates:
        if p.exists():
            return p
    raise FileNotFoundError(f"No data dir found. Checked: {candidates}")


def main():
    DATA_DIR = find_data_dir()
    records = load_all(DATA_DIR, preload=False)
    print("loaded records:", len(records))
    X, y, groups = make_dataset(records, epoch_len=4.0)
    print("X shape:", X.shape)
    import numpy as np
    if y.size:
        print("y counts:", dict(zip(*np.unique(y, return_counts=True))))
    else:
        print("y counts: empty")


if __name__ == "__main__":
    main()
