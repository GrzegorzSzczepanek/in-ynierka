"""Time-frequency and band-power analysis helpers: Rest vs Task comparisons.

Functions here operate on raw MNE objects (already tidied/montaged) or on
paths to EDF files, and return a matplotlib Figure (or a results DataFrame
for population-level analyses).
"""
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import mne
from scipy import signal, stats
from scipy.integrate import trapezoid

from .io import read_one
from .preprocess import tidy, set_montage

# Standard EEG frequency bands (Hz), shared with eegmat.features
BANDS = {
    "Delta (1-4 Hz)": (1, 4),
    "Theta (4-8 Hz)": (4, 8),
    "Alpha (8-13 Hz)": (8, 13),
    "Beta (13-30 Hz)": (13, 30),
    "Gamma (30-45 Hz)": (30, 45),
}


def _band_mean_power(psd_vals: np.ndarray, f_arr: np.ndarray, fmin: float, fmax: float) -> np.ndarray:
    mask = (f_arr >= fmin) & (f_arr <= fmax)
    return psd_vals[:, mask].mean(axis=-1)


def load_rest_task_pair(data_dir: Path, subject_id: str) -> Tuple[mne.io.BaseRaw, mne.io.BaseRaw]:
    """Load and preprocess the Rest (`_1.edf`) and Task (`_2.edf`) recordings for one subject."""
    raw_rest = set_montage(tidy(read_one(Path(data_dir) / f"{subject_id}_1.edf", preload=True)))
    raw_task = set_montage(tidy(read_one(Path(data_dir) / f"{subject_id}_2.edf", preload=True)))
    return raw_rest, raw_task


def rest_vs_task_dashboard(data_dir: Path, subject_id: str = "Subject00", channel: str = "O1"):
    """Build a multi-panel dashboard comparing Rest vs Task for one subject.

    Panels: raw time-domain snippet, PSD overlay, and per-band mean power bars.
    Returns the matplotlib Figure.
    """
    raw_rest, raw_task = load_rest_task_pair(data_dir, subject_id)
    raw_rest_eeg = raw_rest.copy().pick("eeg")
    raw_task_eeg = raw_task.copy().pick("eeg")

    psd_rest = raw_rest_eeg.compute_psd(fmin=1, fmax=45)
    psd_task = raw_task_eeg.compute_psd(fmin=1, fmax=45)
    freqs = psd_rest.freqs
    data_rest = psd_rest.get_data()
    data_task = psd_task.get_data()

    fig = plt.figure(figsize=(16, 11), constrained_layout=True)
    gs = fig.add_gridspec(2, 3)

    # Panel 1: time-domain snippet (5s window) on `channel`
    ax_time = fig.add_subplot(gs[0, :2])
    sfreq = raw_rest.info["sfreq"]
    n = int(5.0 * sfreq)
    if channel in raw_rest.ch_names:
        sig_rest = raw_rest.get_data(picks=channel)[0, :n] * 1e6
        sig_task = raw_task.get_data(picks=channel)[0, :n] * 1e6
        t = np.arange(n) / sfreq
        ax_time.plot(t, sig_rest, label="Rest", color="#1f77b4", alpha=0.8)
        ax_time.plot(t, sig_task, label="Task", color="#d62728", alpha=0.8)
        ax_time.set_title(f"Signal snippet ({channel})")
        ax_time.set_xlabel("Time [s]")
        ax_time.set_ylabel("Amplitude [µV]")
        ax_time.legend()
        ax_time.grid(True, linestyle="--", alpha=0.4)

    # Panel 2: PSD overlay (averaged across EEG channels)
    ax_psd = fig.add_subplot(gs[0, 2])
    ax_psd.plot(freqs, data_rest.mean(axis=0), label="Rest", color="#1f77b4")
    ax_psd.plot(freqs, data_task.mean(axis=0), label="Task", color="#d62728")
    ax_psd.set_title("Mean PSD (all EEG channels)")
    ax_psd.set_xlabel("Frequency [Hz]")
    ax_psd.set_ylabel("Power")
    ax_psd.legend()
    ax_psd.grid(True, linestyle="--", alpha=0.4)

    # Panel 3: per-band mean power comparison
    ax_bands = fig.add_subplot(gs[1, :])
    band_names = list(BANDS.keys())
    rest_vals = [_band_mean_power(data_rest, freqs, *BANDS[b]).mean() for b in band_names]
    task_vals = [_band_mean_power(data_task, freqs, *BANDS[b]).mean() for b in band_names]
    x = np.arange(len(band_names))
    width = 0.35
    ax_bands.bar(x - width / 2, rest_vals, width, label="Rest", color="#1f77b4")
    ax_bands.bar(x + width / 2, task_vals, width, label="Task", color="#d62728")
    ax_bands.set_xticks(x)
    ax_bands.set_xticklabels(band_names, rotation=15)
    ax_bands.set_ylabel("Mean band power")
    ax_bands.set_title("Rest vs Task: per-band mean power (all EEG channels)")
    ax_bands.legend()
    ax_bands.grid(True, axis="y", linestyle="--", alpha=0.4)

    plt.suptitle(f"Rest vs Task dashboard — {subject_id}", fontsize=13, fontweight="bold")
    return fig


def plot_spectrogram_pair(data_dir: Path, subject_id: str, channel: str = "O1",
                          duration: float = 30.0, fmax: float = 32.0):
    """Plot side-by-side STFT spectrograms (Rest vs Task) for one channel of one subject."""
    raw_rest, raw_task = load_rest_task_pair(data_dir, subject_id)
    sfreq = raw_rest.info["sfreq"]
    sig_r = raw_rest.get_data(picks=channel)[0, : int(duration * sfreq)] * 1e6
    sig_t = raw_task.get_data(picks=channel)[0, : int(duration * sfreq)] * 1e6

    nperseg = int(sfreq * 2)
    noverlap = int(sfreq * 1.75)
    f_r, t_r, Sxx_r = signal.spectrogram(sig_r, fs=sfreq, nperseg=nperseg, noverlap=noverlap)
    f_t, t_t, Sxx_t = signal.spectrogram(sig_t, fs=sfreq, nperseg=nperseg, noverlap=noverlap)

    mask_r = (f_r >= 1) & (f_r <= fmax)
    mask_t = (f_t >= 1) & (f_t <= fmax)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5), constrained_layout=True)
    for ax, f, t, Sxx, mask, title in (
        (axes[0], f_r, t_r, Sxx_r, mask_r, "Rest"),
        (axes[1], f_t, t_t, Sxx_t, mask_t, "Task"),
    ):
        Sxx_db = 10 * np.log10(Sxx[mask, :] + 1e-20)
        pcm = ax.pcolormesh(t, f[mask], Sxx_db, shading="gouraud", cmap="viridis")
        ax.axhspan(8, 13, facecolor="white", alpha=0.18, edgecolor="white", label="Alpha (8-13 Hz)")
        ax.set_title(f"{title} — {subject_id} ({channel})")
        ax.set_xlabel("Time [s]")
        ax.set_ylabel("Frequency [Hz]")
        ax.legend(loc="upper right")
        fig.colorbar(pcm, ax=ax, label="Power [dB]")
    return fig


def plot_spectrogram_grid(data_dir: Path, pairs: Sequence[Tuple[str, int]], channel: str = "O1",
                          duration: float = 25.0, fmax: float = 32.0):
    """Plot a 2x2 grid of blinded spectrograms for a list of (subject_id, state) pairs.

    `state` is 1 (Rest) or 2 (Task). Titles are neutral ("Sample #n") so the grid
    can be used for a blinded visual inspection exercise; the mapping of sample
    index -> (subject, state label) is returned alongside the figure.
    """
    fig, axes = plt.subplots(2, 2, figsize=(15, 9), constrained_layout=True)
    axes = axes.flatten()
    answers: Dict[str, str] = {}

    for idx, (subj, state) in enumerate(pairs[:4]):
        raw = set_montage(tidy(read_one(Path(data_dir) / f"{subj}_{state}.edf", preload=True)))
        sf = raw.info["sfreq"]
        sig = raw.get_data(picks=channel)[0, : int(duration * sf)] * 1e6
        f, t, Sxx = signal.spectrogram(sig, fs=sf, nperseg=int(sf * 2), noverlap=int(sf * 1.75))
        mask = (f >= 1) & (f <= fmax)
        Sxx_db = 10 * np.log10(Sxx[mask, :] + 1e-20)

        ax = axes[idx]
        ax.pcolormesh(t, f[mask], Sxx_db, shading="gouraud", cmap="viridis")
        ax.axhspan(8, 13, facecolor="white", alpha=0.18, linestyle="--", edgecolor="white",
                   label="Alpha band (8-13 Hz)")
        ax.set_title(f"Sample #{idx + 1}", fontsize=12, fontweight="bold")
        ax.set_ylabel("Frequency [Hz]")
        ax.set_xlabel("Time [s]")
        ax.set_ylim(1, fmax)
        ax.legend(loc="upper right")

        state_str = "REST" if state == 1 else "TASK"
        answers[f"Sample #{idx + 1}"] = f"{subj} ({state_str})"

    return fig, answers


def population_alpha_erd(data_dir: Path, subjects: Sequence[str], channel: str = "O1",
                         duration: float = 60.0) -> pd.DataFrame:
    """Compute per-subject Alpha Event-Related Desynchronization (ERD) for `channel`.

    ERD = (alpha_task - alpha_rest) / alpha_rest * 100. Negative values indicate
    alpha power suppression during the task, as expected under cognitive load.
    Returns a DataFrame with one row per subject.
    """
    ch_name = channel if channel.upper().startswith("EEG") else f"EEG {channel}"
    records = []

    for subj in subjects:
        raw_r = mne.io.read_raw_edf(Path(data_dir) / f"{subj}_1.edf", include=[ch_name],
                                    preload=True, verbose=False)
        raw_t = mne.io.read_raw_edf(Path(data_dir) / f"{subj}_2.edf", include=[ch_name],
                                    preload=True, verbose=False)
        sf = raw_r.info["sfreq"]
        n = int(duration * sf)
        sig_r = raw_r.get_data()[0, :n] * 1e6
        sig_t = raw_t.get_data()[0, :n] * 1e6

        f_r, p_r = signal.welch(sig_r, fs=sf, nperseg=int(sf * 2))
        f_t, p_t = signal.welch(sig_t, fs=sf, nperseg=int(sf * 2))

        def _band(f, p, fmin, fmax):
            m = (f >= fmin) & (f <= fmax)
            return trapezoid(p[m], f[m])

        alpha_r = _band(f_r, p_r, 8, 13)
        alpha_t = _band(f_t, p_t, 8, 13)
        erd = ((alpha_t - alpha_r) / alpha_r) * 100 if alpha_r else np.nan

        records.append({
            "subject": subj,
            "alpha_rest": alpha_r,
            "alpha_task": alpha_t,
            "alpha_erd_pct": erd,
        })

    return pd.DataFrame(records)


def alpha_erd_vs_performance(df_features: pd.DataFrame, info_df: pd.DataFrame,
                             alpha_col: str = "O1_alpha_rel",
                             performance_col: str = "Number of subtractions",
                             target_col: str = "target", group_col: str = "subject"):
    """Correlate per-subject Alpha ERD (from epoch-level features) with task performance.

    `df_features` is the epoch-level feature table (target: 0=rest, 1=task);
    `info_df` is the `subject-info.csv` metadata with a `Subject` column like
    "Subject07". Returns (figure, pearson_r, p_value).
    """
    rest_alpha = df_features[df_features[target_col] == 0].groupby(group_col)[alpha_col].mean()
    task_alpha = df_features[df_features[target_col] == 1].groupby(group_col)[alpha_col].mean()

    comp_df = pd.DataFrame({"rest_alpha": rest_alpha, "task_alpha": task_alpha}).dropna()
    comp_df["alpha_erd_%"] = ((comp_df["task_alpha"] - comp_df["rest_alpha"]) / comp_df["rest_alpha"]) * 100

    info = info_df.copy()
    info["sub_int"] = info["Subject"].str.extract(r"(\d+)").astype(int)
    merged = comp_df.merge(info, left_index=True, right_on="sub_int")

    r_val, p_val = stats.pearsonr(merged[performance_col], merged["alpha_erd_%"])

    fig = plt.figure(figsize=(9, 5.5))
    sns.regplot(data=merged, x=performance_col, y="alpha_erd_%",
               scatter_kws={"s": 55, "alpha": 0.8, "color": "#2c3e50"},
               line_kws={"color": "#e74c3c", "linewidth": 2})
    plt.axhline(0, color="gray", linestyle="--", alpha=0.6)
    plt.title(f"Korelacja: {performance_col} vs Tłumienie Alfy (ERD)\nr = {r_val:.2f} (p = {p_val:.3f})",
             fontsize=12, fontweight="bold")
    plt.xlabel(performance_col, fontsize=11)
    plt.ylabel("Tłumienie mocy Alfy (Alpha ERD) [%]\n(Wartości bardziej ujemne = silniejsza reakcja mózgu)",
              fontsize=10)
    plt.grid(True, linestyle="--", alpha=0.5)
    plt.tight_layout()
    return fig, r_val, p_val
