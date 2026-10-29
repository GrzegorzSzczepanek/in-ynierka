"""Subject-level splitting utilities and visualization.

Functions
- split_subjects: split list of subject identifiers into named splits (fractions or counts),
  supports optional stratification by label.
- plot_subject_allocation: visualize allocation per subject and counts per split.

Designed to be called from notebook cells; returns simple Python objects.
"""
from typing import Iterable, List, Dict, Any, Optional, Tuple
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

try:
    from sklearn.model_selection import StratifiedShuffleSplit
except Exception:
    StratifiedShuffleSplit = None


def _to_fraction_map(spec: Dict[str, Any], n: int) -> Dict[str, float]:
    """Convert spec values (fractions or integer counts) to fractions summing to <=1.
    Remaining subjects (if any) will be left unassigned or can be included in last split.
    """
    # First, detect which are ints (counts) vs floats
    total_count = 0
    frac_map: Dict[str, float] = {}
    count_map: Dict[str, int] = {}
    for k, v in spec.items():
        if isinstance(v, int):
            count_map[k] = v
            total_count += v
        else:
            frac_map[k] = float(v)
    # If counts provided, convert to fractions
    if count_map:
        # convert counts to fractions
        for k, c in count_map.items():
            frac_map[k] = c / n
    # Normalize if sum > 1
    s = sum(frac_map.values())
    if s > 1.0 + 1e-8:
        # normalize
        for k in list(frac_map.keys()):
            frac_map[k] = frac_map[k] / s
    return frac_map


def _to_count_map(spec: Dict[str, Any], n: int, min_size: Optional[int] = 1) -> Dict[str, int]:
    """Convert spec (fractions or absolute counts) into integer counts summing to n.

    Uses the largest-remainder method for fair rounding. Ensures each split has at
    least `min_size` if possible; if sum(min_size) > n, min_size is reduced evenly.
    """
    # First, separate ints and fractions
    raw_counts: Dict[str, float] = {}
    specified_counts = {}
    for k, v in spec.items():
        if isinstance(v, int):
            specified_counts[k] = v
        else:
            raw_counts[k] = float(v) * n

    # Start with specified absolute counts
    count_map: Dict[str, int] = {k: int(v) for k, v in specified_counts.items()}
    remaining_n = n - sum(count_map.values())

    # If no fractional specs provided, remaining splits are those missing from count_map
    frac_keys = [k for k in spec.keys() if k not in specified_counts]
    if remaining_n < 0:
        # too many absolute counts requested; scale them down proportionally
        scale = n / max(1, sum(specified_counts.values()))
        for k in specified_counts:
            count_map[k] = int(round(specified_counts[k] * scale))
        remaining_n = n - sum(count_map.values())
        frac_keys = [k for k in spec.keys() if k not in count_map]

    # If there are fractional parts to assign, compute raw counts and apply largest remainder
    if frac_keys and remaining_n > 0:
        raws = {k: float(spec[k]) * remaining_n for k in frac_keys}
        floors = {k: int(np.floor(v)) for k, v in raws.items()}
        remainders = {k: raws[k] - floors[k] for k in frac_keys}
        for k in frac_keys:
            count_map[k] = floors[k]
        assigned = sum(floors.values())
        leftover = remaining_n - assigned
        # distribute leftover by largest remainders
        for k in sorted(remainders.keys(), key=lambda x: remainders[x], reverse=True)[:leftover]:
            count_map[k] += 1
    else:
        # no fractional keys, if leftover>0 add to last split in spec order
        if remaining_n > 0:
            last = list(spec.keys())[-1]
            count_map[last] = count_map.get(last, 0) + remaining_n

    # Ensure min_size
    if min_size is None:
        min_size = 0
    min_total = min_size * len(spec)
    if min_total > n:
        # reduce min_size evenly
        min_size = max(0, n // len(spec))

    # enforce by moving from largest splits to small ones
    # compute current counts
    for k in spec.keys():
        count_map.setdefault(k, 0)

    # Loop until all >= min_size or no movers
    changed = True
    while changed:
        changed = False
        for k, cnt in list(count_map.items()):
            if cnt < min_size:
                # find donor with > min_size+1
                donor = max(((dk, dv) for dk, dv in count_map.items()), key=lambda x: x[1])
                if donor[1] > min_size:
                    count_map[k] += 1
                    count_map[donor[0]] -= 1
                    changed = True
        # break if no possible moves
    return count_map


def split_subjects(subjects: Iterable[Any],
                   spec: Dict[str, Any] = None,
                   random_state: Optional[int] = None,
                   stratify: Optional[Dict[Any, Any]] = None,
                   ensure_nonempty: bool = True,
                   min_size: Optional[int] = 1) -> Dict[str, List[Any]]:
    """Split subjects into named splits.

    Parameters
    - subjects: iterable of subject identifiers (hashable)
    - spec: dict mapping split_name -> fraction (0..1) or absolute count (int). If None, defaults
      to {'train':0.6,'val':0.2,'dev':0.1,'holdout':0.1}
    - random_state: seed for shuffling
    - stratify: optional mapping subject->label for stratified splitting
    - ensure_nonempty: if True, tries to avoid empty splits by moving subjects to tiny splits

    Returns: dict split_name -> list(subjects)
    """
    subjects = list(subjects)
    n = len(subjects)
    if spec is None:
        spec = {'train': 0.6, 'val': 0.2, 'dev': 0.1, 'holdout': 0.1}
    frac_map = _to_fraction_map(spec, n)
    # compute integer counts per split using helper
    count_map = _to_count_map(spec, n, min_size=min_size)
    rng = np.random.RandomState(random_state)
    # Prepare order
    if stratify is None or StratifiedShuffleSplit is None:
        order = subjects.copy()
        rng.shuffle(order)
        # assign slices sequentially according to integer counts
        assignments: Dict[str, List[Any]] = {k: [] for k in count_map.keys()}
        start = 0
        splits = list(count_map.keys())
        for i, k in enumerate(splits):
            take = int(count_map.get(k, 0))
            # for last split, take remaining to avoid rounding drift
            if i == len(splits) - 1:
                take = n - start
            assignments[k] = order[start:start+take]
            start += take
        # if ensure_nonempty, move one subject to empty splits
        if ensure_nonempty:
            for k, lst in list(assignments.items()):
                if len(lst) == 0:
                    # find a split with > min_size
                    donor = None
                    for dk, dl in assignments.items():
                        if len(dl) > (min_size or 1):
                            donor = dk
                            break
                    if donor is not None:
                        assignments[k].append(assignments[donor].pop())
        return assignments

    # Stratified sequential splitting: iteratively take fractions using StratifiedShuffleSplit
    labels = [stratify.get(s, 0) for s in subjects]
    remaining_idx = np.arange(n)
    assignments: Dict[str, List[Any]] = {k: [] for k in count_map.keys()}
    remaining_subjects = np.array(subjects)
    remaining_labels = np.array(labels)
    splits = list(count_map.keys())
    for i, k in enumerate(splits):
        take = int(count_map.get(k, 0))
        if i == len(splits) - 1:
            sel_idx = np.arange(len(remaining_subjects))
        else:
            if take <= 0:
                sel_idx = np.array([], dtype=int)
            else:
                if StratifiedShuffleSplit is None:
                    perm = rng.permutation(len(remaining_subjects))
                    sel_idx = perm[:take]
                else:
                    n_targets = len(remaining_subjects)
                    # if take > n_targets, clip
                    take = min(take, n_targets)
                    if take == 0:
                        sel_idx = np.array([], dtype=int)
                    else:
                        sss = StratifiedShuffleSplit(n_splits=1, train_size=take, random_state=rng)
                        try:
                            train_idx, _ = next(sss.split(np.zeros(n_targets), remaining_labels))
                        except Exception:
                            perm = rng.permutation(n_targets)
                            train_idx = perm[:take]
                        sel_idx = np.array(train_idx, dtype=int)
        # assign selected
        assignments[k] = list(remaining_subjects[sel_idx])
        # remove selected from remaining
        if len(sel_idx) > 0:
            mask = np.ones(len(remaining_subjects), dtype=bool)
            mask[sel_idx] = False
            remaining_subjects = remaining_subjects[mask]
            remaining_labels = remaining_labels[mask]

    # If ensure_nonempty, fix
    if ensure_nonempty:
        for k, lst in list(assignments.items()):
            if len(lst) == 0:
                # find donor
                donor = None
                for dk, dl in assignments.items():
                    if len(dl) > 1:
                        donor = dk
                        break
                if donor is not None:
                    assignments[k].append(assignments[donor].pop())

    return assignments


def plot_subject_allocation(assignments: Dict[str, List[Any]],
                            sort_key: Optional[Any] = None,
                            figsize: Tuple[int, int] = (10, 6),
                            palette: Optional[Dict[str, str]] = None):
    """Visualize subject allocation.

    Produces two plots: top - bar counts per split; bottom - heatmap-like subject allocation
    (subjects on x-axis, rows=1, color = split) to show contiguous or random assignment.
    """
    # Flatten into dataframe
    rows = []
    for split, subs in assignments.items():
        for s in subs:
            rows.append({'subject': s, 'split': split})
    if not rows:
        raise ValueError('No assignments to plot')
    df = pd.DataFrame(rows)
    # sort subjects
    def _subid(x):
        try:
            return int(str(x).lstrip('Subject').lstrip('0') or 0)
        except Exception:
            try:
                return int(''.join(filter(str.isdigit, str(x))) or 0)
            except Exception:
                return 0
    if sort_key is None:
        df['subid'] = df['subject'].apply(_subid)
        df = df.sort_values('subid')
    elif callable(sort_key):
        df = df.sort_values(by='subject', key=lambda s: s.map(sort_key))
    else:
        df = df.sort_values(by=sort_key)

    # counts
    counts = df['split'].value_counts().reindex(list(assignments.keys()), fill_value=0)

    # palette and discrete colormap consistent for bars, heatmap and legend
    splits = list(assignments.keys())
    if palette is None:
        colors = sns.color_palette('tab10', n_colors=len(splits))
        palette = {s: colors[i] for i, s in enumerate(splits)}
    # list of colors in the same order as splits
    colors_list = [palette[s] for s in splits]

    fig = plt.figure(figsize=figsize)
    gs = fig.add_gridspec(2, 1, height_ratios=[1, 3], hspace=0.25)

    ax0 = fig.add_subplot(gs[0])
    counts.plot(kind='bar', color=[palette[s] for s in counts.index], ax=ax0)
    ax0.set_ylabel('Number of subjects')
    ax0.set_title('Subjects per split')

    ax1 = fig.add_subplot(gs[1])
    # create matrix 1 x n_subjects with numeric codes
    subj_list = df['subject'].tolist()
    split_to_idx = {s: i for i, s in enumerate(splits)}
    arr = np.array([split_to_idx[s] for s in df['split']])[None, :]

    # create a ListedColormap and discrete norm so values map correctly to colors_list
    from matplotlib.colors import ListedColormap, BoundaryNorm
    cmap = ListedColormap(colors_list)
    norm = BoundaryNorm(boundaries=np.arange(len(splits)+1)-0.5, ncolors=len(splits))

    im = ax1.imshow(arr, aspect='auto', cmap=cmap, norm=norm)
    ax1.set_yticks([])
    # reduce number of xticks if too many subjects
    n_subj = len(subj_list)
    if n_subj > 40:
        step = max(1, n_subj // 40)
        xticks = np.arange(0, n_subj, step)
    else:
        xticks = np.arange(n_subj)
    ax1.set_xticks(xticks)
    ax1.set_xticklabels([str(subj_list[i]) for i in xticks], rotation=90, fontsize=8)
    ax1.set_title('Subject allocation (left->right)')
    # legend mapping using exact palette colors
    handles = [plt.Line2D([0], [0], marker='s', color=palette[s], linestyle='') for s in splits]
    ax1.legend(handles, splits, bbox_to_anchor=(1.02, 1), loc='upper left')

    plt.tight_layout()
    return fig
