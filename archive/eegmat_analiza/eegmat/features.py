"""Feature extraction utilities for EEG signals and epochs.

Calculates:
- Band powers (Delta, Theta, Alpha, Beta, Gamma) in absolute (µV²) and relative (%) terms.
- Cognitive workload and engagement indices (Theta/Alpha, Theta/Beta, Engagement).
- Spectral Entropy (distribution regularity of power spectrum).
- Hjorth parameters (Activity, Mobility, Complexity).
- Statistical moments (std, peak-to-peak amplitude, skewness, kurtosis).
"""
from typing import Dict, List, Optional, Sequence
import numpy as np
import pandas as pd
from scipy import signal, stats
from scipy.integrate import trapezoid
from joblib import Parallel, delayed

# Standard EEG frequency bands (Hz)
BANDS = {
    "delta": (1.0, 4.0),
    "theta": (4.0, 8.0),
    "alpha": (8.0, 13.0),
    "beta": (13.0, 30.0),
    "gamma": (30.0, 45.0),
}


def extract_channel_features(sig: np.ndarray, sfreq: float = 500.0) -> Dict[str, float]:
    """Extract full suite of spectral, non-linear, and statistical features from 1D EEG signal.

    Parameters
    ----------
    sig : np.ndarray
        1D time series (samples,).
    sfreq : float
        Sampling frequency in Hz (default: 500.0).

    Returns
    -------
    Dict[str, float]
        Dictionary of extracted feature values.
    """
    n_samples = len(sig)
    feats: Dict[str, float] = {}

    # ----------------------------------------------------
    # 1. Spectral Analysis (Welch PSD)
    # ----------------------------------------------------
    nperseg = min(int(sfreq * 2), n_samples)
    f, psd = signal.welch(sig, fs=sfreq, nperseg=nperseg)

    mask_tot = (f >= 1.0) & (f <= 45.0)
    tot_power = trapezoid(psd[mask_tot], f[mask_tot]) if np.any(mask_tot) else 1e-12
    tot_power = max(tot_power, 1e-12)

    feats["total_power"] = float(tot_power)

    band_powers: Dict[str, float] = {}
    for b_name, (fmin, fmax) in BANDS.items():
        m = (f >= fmin) & (f <= fmax)
        bp = float(trapezoid(psd[m], f[m])) if np.any(m) else 0.0
        band_powers[b_name] = bp
        feats[f"{b_name}_abs"] = bp
        feats[f"{b_name}_rel"] = bp / tot_power

    # Cognitive Ratios
    alpha = max(band_powers["alpha"], 1e-12)
    theta = max(band_powers["theta"], 1e-12)
    beta = max(band_powers["beta"], 1e-12)

    feats["tar"] = theta / alpha
    feats["tbr"] = theta / beta
    feats["engagement"] = beta / (theta + alpha)

    # Spectral Entropy (normalized Shannon entropy of PSD)
    psd_sub = psd[mask_tot]
    sum_psd = np.sum(psd_sub)
    if sum_psd > 0 and len(psd_sub) > 1:
        p_norm = psd_sub / sum_psd
        p_norm = p_norm[p_norm > 0]
        feats["spec_entropy"] = float(-np.sum(p_norm * np.log2(p_norm)) / np.log2(len(p_norm)))
    else:
        feats["spec_entropy"] = 0.0

    # ----------------------------------------------------
    # 2. Hjorth Parameters (Activity, Mobility, Complexity)
    # ----------------------------------------------------
    d1 = np.diff(sig)
    d2 = np.diff(d1)
    v0 = float(np.var(sig))
    v1 = float(np.var(d1))
    v2 = float(np.var(d2))

    activity = v0
    mobility = np.sqrt(v1 / max(v0, 1e-12))
    complexity = (np.sqrt(v2 / max(v1, 1e-12)) / max(mobility, 1e-12))

    feats["hjorth_activity"] = activity
    feats["hjorth_mobility"] = float(mobility)
    feats["hjorth_complexity"] = float(complexity)

    # ----------------------------------------------------
    # 3. Time-Domain Statistical Moments
    # ----------------------------------------------------
    feats["std"] = float(np.std(sig))
    feats["ptp"] = float(np.ptp(sig))
    feats["skewness"] = float(stats.skew(sig))
    feats["kurtosis"] = float(stats.kurtosis(sig))

    return feats


def extract_epoch_features(
    epoch: np.ndarray, sfreq: float = 500.0, ch_names: Optional[List[str]] = None
) -> Dict[str, float]:
    """Extract features for a single 2D epoch (n_channels, n_samples)."""
    n_channels = epoch.shape[0]
    if ch_names is None or len(ch_names) != n_channels:
        ch_names = [f"Ch{i+1}" for i in range(n_channels)]

    epoch_feats: Dict[str, float] = {}
    for i, ch in enumerate(ch_names):
        ch_dict = extract_channel_features(epoch[i], sfreq=sfreq)
        for feat_name, val in ch_dict.items():
            epoch_feats[f"{ch}_{feat_name}"] = val
    return epoch_feats


def extract_features(
    X: np.ndarray,
    sfreq: float = 500.0,
    ch_names: Optional[List[str]] = None,
    n_jobs: int = -1,
    verbose: int = 0,
) -> pd.DataFrame:
    """Parallelized feature extraction for a 3D dataset of epochs.

    Parameters
    ----------
    X : np.ndarray
        Shape (n_epochs, n_channels, n_samples).
    sfreq : float
        Sampling frequency in Hz (default: 500.0).
    ch_names : Optional[List[str]]
        List of channel names matching the 2nd axis of X.
    n_jobs : int
        Number of parallel jobs (-1 uses all CPU cores).
    verbose : int
        Verbosity level for joblib Parallel.

    Returns
    -------
    pd.DataFrame
        DataFrame with rows = epochs, columns = named features (e.g. 'O1_alpha_rel').
    """
    n_epochs, n_channels, _ = X.shape

    if ch_names is None or len(ch_names) != n_channels:
        ch_names = [f"Ch{i+1}" for i in range(n_channels)]

    results = Parallel(n_jobs=n_jobs, verbose=verbose)(
        delayed(extract_epoch_features)(X[i], sfreq=sfreq, ch_names=ch_names)
        for i in range(n_epochs)
    )

    return pd.DataFrame(results)


def select_eeg_channels(df_features: pd.DataFrame, channels: Sequence[str],
                        keep_cols: Sequence[str] = ("target", "subject")) -> pd.DataFrame:
    """Restrict a wide feature DataFrame (from `extract_features`) to a channel subset.

    Feature columns are named `"{channel}_{feature}"` (e.g. `"O1_alpha_rel"`);
    this keeps only columns whose channel prefix is in `channels`, plus any
    metadata columns listed in `keep_cols` that are present in the DataFrame.

    Useful to simulate a reduced-electrode consumer headset (e.g. 4 channels)
    versus the full medical montage, for `eegmat.models.compare_channel_setups`.
    """
    feature_cols = [c for c in df_features.columns
                    if any(c.startswith(f"{ch}_") for ch in channels)]
    meta_cols = [c for c in keep_cols if c in df_features.columns]
    return df_features[meta_cols + feature_cols]
