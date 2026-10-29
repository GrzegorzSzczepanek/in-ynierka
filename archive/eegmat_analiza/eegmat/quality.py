"""Signal-quality / artifact-verification helpers.

Sanity checks run after feature extraction and ICA cleaning, to confirm the
epoched data doesn't contain gross artifacts before it's used for modeling.
"""
from typing import Tuple

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def peak_to_peak_report(df_features: pd.DataFrame, threshold_uv: float = 150.0):
    """Plot the distribution of max peak-to-peak amplitude per epoch and flag outliers.

    Expects `df_features` to contain per-channel `*_ptp` columns (in Volts, as
    produced by `eegmat.features.extract_features`). Returns (figure, n_outliers,
    pct_outliers).
    """
    ptp_cols = [c for c in df_features.columns if c.endswith("_ptp")]
    max_ptp_uv = df_features[ptp_cols].max(axis=1) * 1e6
    n_outliers = int((max_ptp_uv > threshold_uv).sum())
    pct_outliers = n_outliers / len(df_features) * 100

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    sns.histplot(max_ptp_uv, bins=45, kde=True, color="#34495e", ax=axes[0])
    axes[0].axvline(threshold_uv, color="#e74c3c", linestyle="--", lw=2,
                    label=f"Próg artefaktu ({threshold_uv:g} µV)")
    axes[0].set_title("A. Rozkład maksymalnej amplitudy międzyszczytowej (Peak-to-Peak)",
                      fontsize=11, fontweight="bold")
    axes[0].set_xlabel("Maksymalna amplituda epoki [µV]")
    axes[0].set_ylabel("Liczba epok")
    axes[0].legend(frameon=True)
    axes[0].grid(True, linestyle="--", alpha=0.5)

    sns.boxplot(x=max_ptp_uv, color="#5dade2", ax=axes[1], width=0.4)
    axes[1].axvline(threshold_uv, color="#e74c3c", linestyle="--", lw=2)
    axes[1].set_title(
        f"B. Statystyka jakości sygnału\nMediana: {max_ptp_uv.median():.1f} µV | "
        f"Podejrzane epoki (>{threshold_uv:g} µV): {pct_outliers:.1f}% ({n_outliers} z {len(df_features)})",
        fontsize=11, fontweight="bold")
    axes[1].set_xlabel("Amplituda [µV]")
    axes[1].grid(True, linestyle="--", alpha=0.5)

    plt.suptitle("Analiza Jakości Sygnału i Weryfikacja Oczyszczenia ICA", fontsize=13, fontweight="bold", y=1.02)
    plt.tight_layout()
    return fig, n_outliers, pct_outliers


def class_balance_report(df_features: pd.DataFrame, target_col: str = "target",
                         group_col: str = "subject"):
    """Plot overall class balance and per-subject epoch counts.

    Highlights the expected ~3:1 rest:task imbalance (rest recordings are
    longer than the arithmetic task), motivating balanced-accuracy/F1 metrics
    and `class_weight='balanced'` in `eegmat.models`.
    """
    counts = df_features[target_col].value_counts()
    n_rest = int(counts.get(0, 0))
    n_task = int(counts.get(1, 0))
    total = len(df_features)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    bars = axes[0].bar(["Spoczynek (0)", "Zadanie (1)"], [n_rest, n_task],
                       color=["#1f77b4", "#d62728"], width=0.45, edgecolor="black", alpha=0.85)
    for bar, n in zip(bars, [n_rest, n_task]):
        axes[0].text(bar.get_x() + bar.get_width() / 2, bar.get_height() / 2,
                    f"{n} epok\n({n/total*100:.1f}%)", ha="center", va="center",
                    color="white", fontweight="bold", fontsize=12)
    axes[0].set_title(f"A. Balans epok w zbiorze (Łącznie: {total} epok)", fontsize=11, fontweight="bold")
    axes[0].set_ylabel("Liczba epok")
    axes[0].grid(True, axis="y", linestyle="--", alpha=0.5)

    crosstab_sub = pd.crosstab(df_features[group_col], df_features[target_col])
    axes[1].bar(crosstab_sub.index, crosstab_sub.get(0, 0), label="Spoczynek", color="#1f77b4", alpha=0.8)
    axes[1].bar(crosstab_sub.index, crosstab_sub.get(1, 0), bottom=crosstab_sub.get(0, 0),
               label="Zadanie", color="#d62728", alpha=0.8)
    axes[1].set_title("B. Liczba epok przypadająca na każdego badanego", fontsize=11, fontweight="bold")
    axes[1].set_xlabel("Identyfikator badanego")
    axes[1].set_ylabel("Liczba epok")
    axes[1].legend(loc="upper right", frameon=True)
    axes[1].grid(True, axis="y", linestyle="--", alpha=0.5)
    axes[1].tick_params(axis="x", rotation=90)

    plt.suptitle("Analiza Niezbalansowania Epok w Zbiorze EEGMAT", fontsize=13, fontweight="bold", y=1.02)
    plt.tight_layout()
    return fig, n_rest, n_task
