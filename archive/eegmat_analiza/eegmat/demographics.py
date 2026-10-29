"""Demographic summary plots for the `subject-info.csv` metadata.

Complements `eegmat.plots` (which focuses on the subtractions/count-quality
distribution) with participant-level breakdowns: gender, count-quality split,
and a combined gender x performance view.
"""
from typing import Dict, Optional

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def _make_autopct(values):
    def fmt(pct):
        total = sum(values)
        val = int(round(pct * total / 100.0))
        return f"{pct:.1f}%\n({val} osób)"
    return fmt


def _donut(ax, counts: pd.Series, colors, title: str, total_label: str = "badanych"):
    labels = counts.index
    values = counts.values
    explode = [0.04] * len(values)

    wedges, texts, autotexts = ax.pie(
        values, labels=labels, autopct=_make_autopct(values), startangle=140,
        colors=colors, explode=explode, pctdistance=0.72,
        wedgeprops={"width": 0.55, "edgecolor": "white", "linewidth": 2.5},
        textprops={"fontsize": 11, "fontweight": "medium"},
    )
    for autotext in autotexts:
        autotext.set_color("white")
        autotext.set_fontweight("bold")
        autotext.set_fontsize(11)
    ax.text(0, 0, f"Łącznie\n{sum(values)} {total_label}", ha="center", va="center",
            fontsize=13, fontweight="bold", color="#333333")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=25)
    return ax


def count_quality_pie(info_df: pd.DataFrame, quality_col: str = "Count quality"):
    """Donut chart of Count quality groups (G = good performers, B = bad)."""
    counts = info_df[quality_col].value_counts().rename({
        1: "Grupa G (Wysoka wydajność / Good)",
        0: "Grupa B (Niska wydajność / Bad)",
    })
    fig, ax = plt.subplots(figsize=(7, 7))
    _donut(ax, counts, colors=["#2ecc71", "#e74c3c"], title="Rozkład badanych wg jakości liczenia")
    plt.tight_layout()
    return fig


def gender_pie(info_df: pd.DataFrame, gender_col: str = "Gender"):
    """Donut chart of participant gender distribution."""
    counts = info_df[gender_col].value_counts().rename({
        "F": "Kobiety (F)",
        "M": "Mężczyźni (M)",
    })
    fig, ax = plt.subplots(figsize=(7, 7))
    _donut(ax, counts, colors=["#e84393", "#0984e3"], title="Dystrybucja badanych wg płci (Gender)")
    plt.tight_layout()
    return fig


def gender_quality_combo(info_df: pd.DataFrame, gender_col: str = "Gender",
                         quality_col: str = "Count quality",
                         value_col: str = "Number of subtractions"):
    """Two-panel view: subtractions by gender (box+strip) and quality split by gender (stacked %)."""
    df_plot = info_df.copy()
    n_f = (df_plot[gender_col] == "F").sum()
    n_m = (df_plot[gender_col] == "M").sum()
    df_plot["Płeć"] = df_plot[gender_col].map({
        "F": f"Kobiety (F, n={n_f})",
        "M": f"Mężczyźni (M, n={n_m})",
    })
    df_plot["Jakość liczenia"] = df_plot[quality_col].map({1: "Grupa G (Dobra)", 0: "Grupa B (Niska)"})

    palette_gender = {f"Kobiety (F, n={n_f})": "#e84393", f"Mężczyźni (M, n={n_m})": "#0984e3"}
    colors_quality = {"Grupa B (Niska)": "#e74c3c", "Grupa G (Dobra)": "#2ecc71"}

    fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))

    sns.boxplot(
        ax=axes[0], data=df_plot, x="Płeć", y=value_col,
        hue="Płeć", palette=palette_gender, legend=False,
        width=0.45, boxprops=dict(alpha=0.6), showmeans=True,
        meanprops={"marker": "o", "markerfacecolor": "white", "markeredgecolor": "black", "markersize": 8},
    )
    sns.stripplot(ax=axes[0], data=df_plot, x="Płeć", y=value_col,
                  color="black", size=6, jitter=0.18, alpha=0.7)
    axes[0].set_title("A. Liczba odejmowań wg płci\n(Biała kropka = średnia)", fontsize=12, fontweight="bold")
    axes[0].set_xlabel("")
    axes[0].set_ylabel(value_col, fontsize=11)
    axes[0].grid(True, linestyle="--", alpha=0.5, axis="y")

    crosstab_pct = pd.crosstab(df_plot["Płeć"], df_plot["Jakość liczenia"], normalize="index") * 100
    crosstab_pct = crosstab_pct[[c for c in colors_quality if c in crosstab_pct.columns]]
    crosstab_pct.plot(kind="bar", stacked=True, ax=axes[1],
                      color=[colors_quality[c] for c in crosstab_pct.columns],
                      edgecolor="black", alpha=0.85, width=0.5, legend=True)
    axes[1].set_title("B. Jakość liczenia wg płci (udział %)", fontsize=12, fontweight="bold")
    axes[1].set_xlabel("")
    axes[1].set_ylabel("Udział [%]")
    axes[1].tick_params(axis="x", rotation=0)
    axes[1].grid(True, axis="y", linestyle="--", alpha=0.5)

    plt.tight_layout()
    return fig
