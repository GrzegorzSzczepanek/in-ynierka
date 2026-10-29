"""Model validation and benchmarking utilities.

Centralizes the GroupKFold-based evaluation used across the ML notebook:
comparing classifiers, comparing channel subsets (medical 19-channel montage
vs a consumer-grade 4-electrode headset), feature importance, and PCA
visualization of the feature space.
"""
from typing import Dict, List, Optional, Sequence

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from sklearn.decomposition import PCA
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold, StratifiedKFold, cross_validate
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

DEFAULT_MODELS = {
    "Logistic Regression": lambda: make_pipeline(
        StandardScaler(), LogisticRegression(max_iter=1000, random_state=42, class_weight="balanced")
    ),
    "SVM (RBF Kernel)": lambda: make_pipeline(
        StandardScaler(), SVC(kernel="rbf", C=1.0, random_state=42, class_weight="balanced")
    ),
    "Random Forest": lambda: RandomForestClassifier(
        n_estimators=100, max_depth=10, random_state=42, n_jobs=-1, class_weight="balanced"
    ),
}


def check_group_leakage(X: pd.DataFrame, groups: pd.Series, n_splits: int = 5) -> pd.DataFrame:
    """Run GroupKFold and report train/test subject counts per fold plus any leakage.

    Leakage should always be 0 if `groups` correctly identifies subjects; this
    is a sanity check to run before trusting any cross-validated score.
    """
    gkf = GroupKFold(n_splits=n_splits)
    rows = []
    for fold, (train_idx, test_idx) in enumerate(gkf.split(X, groups=groups)):
        train_subs = set(np.asarray(groups)[train_idx])
        test_subs = set(np.asarray(groups)[test_idx])
        rows.append({
            "fold": fold + 1,
            "n_train_subjects": len(train_subs),
            "n_test_subjects": len(test_subs),
            "leakage": len(train_subs & test_subs),
        })
    return pd.DataFrame(rows)


def compare_models_groupkfold(X: pd.DataFrame, y: pd.Series, groups: pd.Series,
                              models: Optional[Dict] = None, n_splits: int = 5,
                              scoring: Sequence[str] = ("accuracy", "balanced_accuracy", "f1")) -> pd.DataFrame:
    """Cross-validate a set of classifiers with GroupKFold (split by subject).

    Returns a long-format DataFrame with one row per (model, fold), suitable
    for boxplot/barplot comparison. Uses `class_weight='balanced'` by default
    to account for the rest/task class imbalance.
    """
    if models is None:
        models = {name: factory() for name, factory in DEFAULT_MODELS.items()}

    gkf = GroupKFold(n_splits=n_splits)
    results = []
    for name, model in models.items():
        cv_res = cross_validate(model, X, y, groups=groups, cv=gkf, scoring=list(scoring), n_jobs=-1)
        n_folds = len(cv_res[f"test_{scoring[0]}"])
        for i in range(n_folds):
            row = {"Model": name, "fold": i + 1}
            for metric in scoring:
                row[metric] = cv_res[f"test_{metric}"][i]
            results.append(row)
    return pd.DataFrame(results)


def plot_model_comparison(df_results: pd.DataFrame, metrics: Sequence[str] = ("accuracy", "f1")):
    """Bar/box plot comparing models across the metrics produced by `compare_models_groupkfold`."""
    fig, axes = plt.subplots(1, len(metrics), figsize=(7 * len(metrics), 5))
    if len(metrics) == 1:
        axes = [axes]
    for ax, metric in zip(axes, metrics):
        sns.barplot(data=df_results, x="Model", y=metric, hue="Model", ax=ax,
                   palette="Blues_d", legend=False, capsize=0.1)
        ax.set_title(f"Mean {metric} (GroupKFold)", fontsize=12, fontweight="bold")
        ax.set_ylim(0, 1.0)
        ax.grid(True, axis="y", linestyle="--", alpha=0.5)
        ax.tick_params(axis="x", rotation=15)
    plt.tight_layout()
    return fig


def compare_channel_setups(df_features: pd.DataFrame, setups: Dict[str, Sequence[str]],
                           target_col: str = "target", group_col: str = "subject",
                           model_factory=None, n_splits: int = 5,
                           scoring: Sequence[str] = ("accuracy", "balanced_accuracy", "f1")) -> pd.DataFrame:
    """Compare classification performance across different channel subsets.

    `setups` maps a setup name (e.g. "19 medical channels", "4 consumer channels")
    to a list of channel prefixes (e.g. ["Fp1", "Fp2", "T7", "T8"]); feature
    columns are matched by `col.startswith(f"{ch}_")`. Uses GroupKFold on
    `group_col` (subject) with `class_weight='balanced'` by default, and
    returns a tidy results table: one row per (setup, fold, metric-columns).
    """
    if model_factory is None:
        model_factory = DEFAULT_MODELS["Random Forest"]

    y = df_features[target_col]
    groups = df_features[group_col]
    gkf = GroupKFold(n_splits=n_splits)

    rows = []
    for setup_name, channels in setups.items():
        cols = [c for c in df_features.columns
               if any(c.startswith(f"{ch}_") for ch in channels)]
        if not cols:
            raise ValueError(f"No feature columns found for setup '{setup_name}' with channels {channels}")
        X = df_features[cols]
        model = model_factory()
        cv_res = cross_validate(model, X, y, groups=groups, cv=gkf, scoring=list(scoring), n_jobs=-1)
        n_folds = len(cv_res[f"test_{scoring[0]}"])
        for i in range(n_folds):
            row = {"setup": setup_name, "n_channels": len(channels), "n_features": len(cols), "fold": i + 1}
            for metric in scoring:
                row[metric] = cv_res[f"test_{metric}"][i]
            rows.append(row)

    return pd.DataFrame(rows)


def summarize_channel_comparison(df_results: pd.DataFrame,
                                 metrics: Sequence[str] = ("accuracy", "balanced_accuracy", "f1")) -> pd.DataFrame:
    """Aggregate `compare_channel_setups` output into a mean +/- std summary table per setup."""
    agg = df_results.groupby("setup")[list(metrics)].agg(["mean", "std"])
    agg.columns = [f"{metric}_{stat}" for metric, stat in agg.columns]
    return agg.reset_index()


def feature_importance_plot(X: pd.DataFrame, y: pd.Series, top_n: int = 15,
                            random_state: int = 42):
    """Fit a RandomForest on the full feature set and plot the top-N feature importances."""
    clf = RandomForestClassifier(n_estimators=100, random_state=random_state, n_jobs=-1)
    clf.fit(X, y)
    importances = pd.Series(clf.feature_importances_, index=X.columns).sort_values(ascending=False).head(top_n)

    fig = plt.figure(figsize=(10, 0.4 * top_n + 2))
    importances.plot(kind="barh", color="#3498db", edgecolor="black")
    plt.gca().invert_yaxis()
    plt.title(f"Top {top_n} najważniejszych cech (Random Forest Feature Importance)", fontsize=12, fontweight="bold")
    plt.xlabel("Waga cechy (MDI / Gini Importance)")
    plt.grid(True, axis="x", linestyle="--", alpha=0.5)
    plt.tight_layout()
    return fig, importances


def build_subject_level_table(df_features: pd.DataFrame, info_df: pd.DataFrame,
                              feature_group_col: str = "subject",
                              quality_col: str = "Count quality",
                              rest_only: bool = True, target_col: str = "target") -> pd.DataFrame:
    """Aggregate epoch-level features into one row per subject, labeled with Count quality.

    `Count quality` (good/bad performer) is a subject-level trait, not an
    epoch-level one, so classifying it requires collapsing the epoch x feature
    table down to one row per subject (mean over epochs) before fitting a
    model — otherwise epochs from the same subject would leak between train
    and test through ordinary row-level CV.

    `rest_only=True` averages only the resting-state epochs (`target_col == 0`),
    which asks "can baseline EEG alone predict who will be a good counter?" — a
    stronger and more interesting claim than using task epochs, since it needs
    no data from the arithmetic task itself. Returns a DataFrame indexed by
    subject with one row per subject and a `count_quality` label column.
    """
    df = df_features.copy()
    if rest_only:
        df = df[df[target_col] == 0]

    feature_cols = [c for c in df.columns if c not in (target_col, feature_group_col)]
    subject_means = df.groupby(feature_group_col)[feature_cols].mean()

    info = info_df.copy()
    info["sub_int"] = info["Subject"].str.extract(r"(\d+)").astype(int)
    labels = info.set_index("sub_int")[quality_col].rename("count_quality")

    table = subject_means.join(labels, how="inner")
    return table


def classify_count_quality(subject_table: pd.DataFrame, label_col: str = "count_quality",
                           models: Optional[Dict] = None, n_splits: int = 5,
                           scoring: Sequence[str] = ("accuracy", "balanced_accuracy", "f1"),
                           random_state: int = 42) -> pd.DataFrame:
    """Cross-validate classifiers predicting Count quality (good/bad counter) per subject.

    Expects one row per subject (see `build_subject_level_table`). Uses
    StratifiedKFold rather than GroupKFold since each row is already a
    distinct subject — there is no group to split by, only a class balance
    to preserve across folds. With ~36 subjects, keep `n_splits` modest
    (default 5) to leave enough test subjects per fold.
    """
    if models is None:
        models = {name: factory() for name, factory in DEFAULT_MODELS.items()}

    X = subject_table.drop(columns=[label_col])
    y = subject_table[label_col]

    skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=random_state)
    results = []
    for name, model in models.items():
        cv_res = cross_validate(model, X, y, cv=skf, scoring=list(scoring), n_jobs=-1)
        n_folds = len(cv_res[f"test_{scoring[0]}"])
        for i in range(n_folds):
            row = {"Model": name, "fold": i + 1}
            for metric in scoring:
                row[metric] = cv_res[f"test_{metric}"][i]
            results.append(row)
    return pd.DataFrame(results)


def pca_feature_space(df_features: pd.DataFrame, target_col: str = "target",
                      group_col: str = "subject", n_sample_subjects: int = 8,
                      random_state: int = 42):
    """2D PCA of the feature space, colored by task state and by subject identity.

    The subject panel highlights the biometric-clustering phenomenon (features
    cluster more by who the person is than by what state they're in), which is
    the key motivation for subject-level (GroupKFold) validation.
    """
    X = df_features.drop(columns=[target_col, group_col], errors="ignore")
    y = df_features[target_col]
    subjects = df_features[group_col]

    X_scaled = StandardScaler().fit_transform(X)
    pca = PCA(n_components=2, random_state=random_state)
    coords = pca.fit_transform(X_scaled)

    pca_df = pd.DataFrame({
        "PC1": coords[:, 0],
        "PC2": coords[:, 1],
        "Stan": y.map({0: "Spoczynek (Rest)", 1: "Zadanie (Task)"}),
        "Subject": subjects.astype(str),
    })

    fig, axes = plt.subplots(1, 2, figsize=(16, 6))

    sns.scatterplot(data=pca_df, x="PC1", y="PC2", hue="Stan",
                    palette={"Spoczynek (Rest)": "#1f77b4", "Zadanie (Task)": "#d62728"},
                    alpha=0.6, s=30, ax=axes[0])
    axes[0].set_title(
        f"A. Przestrzeń cech 2D wg STANU\n(Wyjaśniona wariancja: {pca.explained_variance_ratio_.sum()*100:.1f}%)",
        fontsize=11, fontweight="bold")
    axes[0].grid(True, linestyle="--", alpha=0.4)

    sample_subs = [str(s) for s in sorted(subjects.unique())[:n_sample_subjects]]
    sub_filtered = pca_df[pca_df["Subject"].isin(sample_subs)]
    sns.scatterplot(data=sub_filtered, x="PC1", y="PC2", hue="Subject", palette="tab10",
                    alpha=0.8, s=40, ax=axes[1])
    axes[1].set_title(
        f"B. Przestrzeń cech 2D wg TOŻSAMOŚCI BADANEGO ({n_sample_subjects} przykładowych osób)\n"
        "Widoczne silne klastrowanie wokół cech osobniczych!",
        fontsize=11, fontweight="bold")
    axes[1].grid(True, linestyle="--", alpha=0.4)

    plt.suptitle("Analiza PCA (2D): Stan poznawczy vs Indywidualny profil biometryczny EEG",
                fontsize=13, fontweight="bold")
    plt.tight_layout()
    return fig, pca
