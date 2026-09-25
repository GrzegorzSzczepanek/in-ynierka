"""Functional connectivity analysis between EEG channels.

Complements the per-channel spectral/statistical features in `eegmat.features`
with inter-channel relationships: several published analyses of the EEGMAT
dataset build a Pearson correlation matrix across channel pairs (171 pairs for
19 channels) and treat the brain as a network rather than a bag of independent
electrodes, using graph-theory descriptors (clustering coefficient, degree
centrality, global/local efficiency) as classification features.
"""
from typing import Dict, List, Optional, Sequence

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import networkx as nx


def correlation_matrix(epoch: np.ndarray, ch_names: Optional[Sequence[str]] = None) -> pd.DataFrame:
    """Pearson correlation matrix between all channel pairs of one epoch.

    `epoch` has shape (n_channels, n_samples). Returns a (n_channels,
    n_channels) DataFrame indexed/labeled by `ch_names` (or Ch1, Ch2, ... if
    not given).
    """
    n_channels = epoch.shape[0]
    if ch_names is None or len(ch_names) != n_channels:
        ch_names = [f"Ch{i+1}" for i in range(n_channels)]
    corr = np.corrcoef(epoch)
    return pd.DataFrame(corr, index=list(ch_names), columns=list(ch_names))


def plot_connectivity_heatmap(corr_df: pd.DataFrame, title: str = "Macierz korelacji między kanałami"):
    """Heatmap of a channel x channel correlation matrix."""
    fig, ax = plt.subplots(figsize=(9, 7.5))
    sns.heatmap(corr_df, cmap="coolwarm", vmin=-1, vmax=1, center=0,
               square=True, linewidths=0.3, ax=ax, cbar_kws={"label": "Pearson r"})
    ax.set_title(title, fontsize=12, fontweight="bold")
    plt.tight_layout()
    return fig


def build_connectivity_graph(corr_df: pd.DataFrame, threshold: float = 0.5) -> nx.Graph:
    """Build an undirected graph from a correlation matrix, keeping edges with |r| > threshold.

    This mirrors the discrimination criterion used in several EEGMAT papers
    (e.g. resting state: correlation > 0.5 vs task: correlation < 0.5): here
    it's exposed as a reusable graph so downstream code can compute standard
    graph-theory descriptors instead of hand-rolling adjacency logic.
    """
    G = nx.Graph()
    G.add_nodes_from(corr_df.columns)
    for i, ch_i in enumerate(corr_df.columns):
        for ch_j in corr_df.columns[i + 1:]:
            r = corr_df.loc[ch_i, ch_j]
            if abs(r) > threshold:
                G.add_edge(ch_i, ch_j, weight=float(r))
    return G


def graph_theory_features(G: nx.Graph) -> Dict[str, float]:
    """Compute a small set of standard graph-theory descriptors for one connectivity graph.

    Returns global scalars (clustering coefficient, density, average degree)
    plus a warning-free small-world proxy; per-node degree/efficiency are
    available via `node_graph_features` for finer-grained analysis.
    """
    n_nodes = G.number_of_nodes()
    n_edges = G.number_of_edges()
    feats = {
        "n_edges": n_edges,
        "density": nx.density(G),
        "avg_clustering": nx.average_clustering(G) if n_nodes > 0 else 0.0,
        "avg_degree": (2 * n_edges / n_nodes) if n_nodes > 0 else 0.0,
    }
    if n_edges > 0 and nx.is_connected(G):
        feats["avg_shortest_path"] = nx.average_shortest_path_length(G)
        feats["global_efficiency"] = nx.global_efficiency(G)
    else:
        # Disconnected graphs (common at higher thresholds) have no finite
        # path length between some node pairs; global efficiency handles
        # this gracefully (0 contribution from unreachable pairs) even when
        # the graph isn't fully connected, so it's still reported.
        feats["avg_shortest_path"] = np.nan
        feats["global_efficiency"] = nx.global_efficiency(G)
    return feats


def node_graph_features(G: nx.Graph) -> pd.DataFrame:
    """Per-channel (node) graph descriptors: degree centrality and local clustering."""
    degree = dict(G.degree())
    degree_centrality = nx.degree_centrality(G)
    clustering = nx.clustering(G)
    return pd.DataFrame({
        "channel": list(G.nodes()),
        "degree": [degree[ch] for ch in G.nodes()],
        "degree_centrality": [degree_centrality[ch] for ch in G.nodes()],
        "clustering": [clustering[ch] for ch in G.nodes()],
    }).set_index("channel")


def extract_connectivity_features(
    X: np.ndarray, ch_names: Sequence[str], threshold: float = 0.5,
) -> pd.DataFrame:
    """Extract per-epoch graph-theory connectivity features for a 3D dataset.

    `X` has shape (n_epochs, n_channels, n_samples), as produced by
    `eegmat.dataset.make_dataset`. For each epoch, builds a thresholded
    Pearson-correlation graph across channels and computes global graph
    descriptors (density, clustering, efficiency). Returns one row per epoch,
    suitable for concatenation with `eegmat.features.extract_features` output
    (e.g. `pd.concat([df_features, df_connectivity], axis=1)`).
    """
    rows = []
    for i in range(X.shape[0]):
        corr_df = correlation_matrix(X[i], ch_names=ch_names)
        G = build_connectivity_graph(corr_df, threshold=threshold)
        rows.append(graph_theory_features(G))
    return pd.DataFrame(rows)


def compare_rest_task_connectivity(
    X: np.ndarray, y: np.ndarray, ch_names: Sequence[str], threshold: float = 0.5,
    n_sample_epochs: Optional[int] = 200, random_state: int = 42,
) -> pd.DataFrame:
    """Compare average connectivity graph descriptors between Rest and Task epochs.

    Optionally subsamples up to `n_sample_epochs` per class (connectivity
    extraction is more expensive than per-channel features) via
    `n_sample_epochs=None` to use all epochs. Returns a tidy DataFrame with
    one row per (epoch, state) for boxplot-style comparison.
    """
    rng = np.random.default_rng(random_state)
    rows = []
    for state, label in ((0, "Rest"), (1, "Task")):
        idx = np.where(y == state)[0]
        if n_sample_epochs is not None and len(idx) > n_sample_epochs:
            idx = rng.choice(idx, size=n_sample_epochs, replace=False)
        for i in idx:
            corr_df = correlation_matrix(X[i], ch_names=ch_names)
            G = build_connectivity_graph(corr_df, threshold=threshold)
            feats = graph_theory_features(G)
            feats["state"] = label
            rows.append(feats)
    return pd.DataFrame(rows)


def plot_connectivity_comparison(df_conn: pd.DataFrame,
                                 metrics: Sequence[str] = ("density", "avg_clustering", "global_efficiency")):
    """Boxplot comparison of graph-theory descriptors between Rest and Task, from `compare_rest_task_connectivity`."""
    fig, axes = plt.subplots(1, len(metrics), figsize=(5 * len(metrics), 5))
    if len(metrics) == 1:
        axes = [axes]
    for ax, metric in zip(axes, metrics):
        sns.boxplot(data=df_conn, x="state", y=metric, hue="state", ax=ax,
                   palette={"Rest": "#1f77b4", "Task": "#d62728"}, legend=False)
        ax.set_title(metric, fontsize=11, fontweight="bold")
        ax.set_xlabel("")
        ax.grid(True, axis="y", linestyle="--", alpha=0.4)
    plt.tight_layout()
    return fig
