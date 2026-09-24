"""Dataset helpers: epoching and dataset construction used by the notebook."""
from typing import Dict, Tuple
import numpy as np
import mne
from .preprocess import tidy, set_montage


def make_dataset(records: Dict[Tuple[int, int], mne.io.BaseRaw], epoch_len: float = 4.0):
    """Convert loaded raws into (X, y, groups).

    X: (n_epochs, n_channels, n_samples)
    y: binary labels (0=rest, 1=task)
    groups: subject id per epoch
    """
    X, y, groups = [], [], []
    for (subj, state), raw in records.items():
        r = set_montage(tidy(raw.copy().load_data()))
        ep = mne.make_fixed_length_epochs(r, duration=epoch_len, preload=True, verbose=False)
        data = ep.get_data(picks="eeg")
        X.append(data)
        y.append(np.full(len(data), 0 if state == 1 else 1))
        groups.append(np.full(len(data), subj))
    if not X:
        return np.empty((0, 0, 0)), np.array([]), np.array([])
    return np.concatenate(X), np.concatenate(y), np.concatenate(groups)
