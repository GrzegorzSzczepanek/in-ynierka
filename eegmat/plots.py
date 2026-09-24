"""Plotting helpers for EEGMAT notebook: boxplots and "snake" plots for subtractions.

Functions are designed to be called from notebook cells. They accept a pandas
DataFrame (subject-info) and return the current matplotlib Figure.
"""
from typing import Optional, Any
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


def boxplot_subtractions(info_df: pd.DataFrame,
                         group_col: str = 'Count quality',
                         value_col: str = 'Number of subtractions',
                         order: Optional[list] = None,
                         invert: bool = False,
                         figsize=(8, 6),
                         palette: Optional[str] = 'Set2'):
    """Draw a boxplot + swarm overlay for number of subtractions grouped by `group_col`.

    Returns the matplotlib Figure object.
    """
    df = info_df.copy()
    if group_col not in df.columns:
        df['_all_group'] = 'All'
        group_col = '_all_group'

    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    sns.boxplot(x=group_col, y=value_col, data=df, order=order, palette=palette)
    sns.swarmplot(x=group_col, y=value_col, data=df, color='k', alpha=0.6)
    plt.title(f'{value_col} by {group_col}')
    plt.xlabel(group_col)
    plt.ylabel(value_col)
    plt.tight_layout()
    if invert:
        plt.gca().invert_yaxis()
    return plt.gcf()


def snake_plot_subtractions(info_df: pd.DataFrame,
                            subject_col: str = 'Subject',
                            value_col: str = 'Number of subtractions',
                            group_col: Optional[str] = 'Count quality',
                            sort_by: Optional[str] = None,
                            figsize=(12, 5),
                            palette: Optional[str] = 'tab10'):
    """Create a snake-style line plot of subtractions per subject.

    Note: retained for backwards-compatibility. Consider using `swarm_plot_subtractions`
    or `raincloud_subtractions` for more informative visuals.
    """
    df = info_df.copy()
    df[value_col] = pd.to_numeric(df[value_col], errors='coerce')
    try:
        df['_subid'] = df[subject_col].astype(str).str.extract(r'(\d+)', expand=False).astype(float)
    except Exception:
        df['_subid'] = np.arange(len(df))

    if sort_by and sort_by in df.columns:
        df = df.sort_values(by=sort_by)
    else:
        df = df.sort_values(by='_subid')

    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    if group_col and group_col in df.columns:
        for i, (g, sub) in enumerate(df.groupby(group_col)):
            plt.plot(sub['_subid'], sub[value_col], marker='o', label=str(g), color=sns.color_palette(palette)[i % 10])
    else:
        plt.plot(df['_subid'], df[value_col], marker='o', linestyle='-')

    plt.xlabel('Subject (id)')
    plt.ylabel(value_col)
    if group_col and group_col in df.columns:
        plt.legend(title=group_col)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    return plt.gcf()


def violin_subtractions(info_df: pd.DataFrame,
                        group_col: str = 'Count quality',
                        value_col: str = 'Number of subtractions',
                        figsize=(8, 6),
                        palette: Optional[str] = 'Pastel1',
                        order: Optional[list] = None,
                        show_box: bool = True,
                        title: Optional[str] = None):
    """Violin plot alternative to boxplot with nicer defaults.
    - `palette`: seaborn palette name
    - `show_box`: overlay a thin boxplot inside violin
    Returns the matplotlib Figure.
    """
    df = info_df.copy()
    if group_col not in df.columns:
        df['_all_group'] = 'All'
        group_col = '_all_group'

    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    sns.violinplot(x=group_col, y=value_col, data=df, palette=palette, order=order, inner=None, cut=0)
    if show_box:
        sns.boxplot(x=group_col, y=value_col, data=df, width=0.1, showcaps=True, boxprops={'zorder':2,'facecolor':'none'}, showfliers=False, whiskerprops={'linewidth':1.0}, order=order)
    sns.stripplot(x=group_col, y=value_col, data=df, color='k', alpha=0.6, jitter=True, order=order)
    plt.title(title or f'{value_col} by {group_col} (violin)')
    plt.xlabel(group_col)
    plt.ylabel(value_col)
    plt.tight_layout()
    return plt.gcf()


def swarm_plot_subtractions(info_df: pd.DataFrame,
                            group_col: str = 'Count quality',
                            value_col: str = 'Number of subtractions',
                            figsize=(10,6),
                            palette: Optional[str] = 'Set2'):
    """Swarm plot (beeswarm) showing all points per group with jitter.
    Useful alternative to snake/line plots.
    """
    df = info_df.copy()
    if group_col not in df.columns:
        df['_all_group'] = 'All'
        group_col = '_all_group'
    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    sns.swarmplot(x=group_col, y=value_col, data=df, palette=palette)
    plt.title(f'{value_col} by {group_col} (swarm)')
    plt.xlabel(group_col)
    plt.ylabel(value_col)
    plt.tight_layout()
    return plt.gcf()


def raincloud_subtractions(info_df: pd.DataFrame,
                           group_col: str = 'Count quality',
                           value_col: str = 'Number of subtractions',
                           figsize=(10,6),
                           palette: Optional[str] = 'Pastel1',
                           order: Optional[list] = None):
    """Approximate a raincloud plot: half violin + box + scatter.
    """
    df = info_df.copy()
    if group_col not in df.columns:
        df['_all_group'] = 'All'
        group_col = '_all_group'

    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    # violin
    sns.violinplot(x=group_col, y=value_col, data=df, palette=palette, order=order, inner=None, cut=0)
    # box inside
    sns.boxplot(x=group_col, y=value_col, data=df, width=0.08, showcaps=True, boxprops={'facecolor':'white','zorder':2}, order=order)
    # scatter / swarm
    sns.stripplot(x=group_col, y=value_col, data=df, color='k', alpha=0.6, jitter=True, order=order)
    plt.title(f'{value_col} by {group_col} (raincloud)')
    plt.xlabel(group_col)
    plt.ylabel(value_col)
    plt.tight_layout()
    return plt.gcf()


def distribution_plot(info_df: pd.DataFrame,
                      value_col: str,
                      group_col: Optional[str] = None,
                      kind: str = 'kde',
                      figsize=(8, 5),
                      palette: Optional[str] = 'Set2',
                      bins: int = 30,
                      fill: bool = True,
                      show_stats: bool = True):
    """Plot distribution of `value_col`. If `group_col` provided, plot each group's
    distribution on the same axes. Supported `kind`: 'kde','hist','ecdf','violin','box'.

    Returns matplotlib Figure.
    """
    df = info_df.copy()
    if value_col not in df.columns:
        raise ValueError(f'value_col "{value_col}" not in DataFrame')

    plt.figure(figsize=figsize)
    sns.set_style('whitegrid')
    if group_col and group_col in df.columns:
        groups = sorted(df[group_col].dropna().unique())
        colors = sns.color_palette(palette, n_colors=len(groups))
        if kind in ('violin', 'box'):
            # categorical plots handle groups more cleanly
            if kind == 'violin':
                sns.violinplot(x=group_col, y=value_col, data=df, palette=palette, inner='quartile')
            else:
                sns.boxplot(x=group_col, y=value_col, data=df, palette=palette)
            if show_stats:
                for i, g in enumerate(groups):
                    cnt = len(df[df[group_col] == g])
                    plt.text(i, plt.ylim()[0], f'n={cnt}', ha='center', va='bottom', fontsize=8)
        else:
            for i, g in enumerate(groups):
                sub = df[df[group_col] == g]
                label = f"{g} (n={len(sub)})" if show_stats else str(g)
                if kind == 'kde':
                    sns.kdeplot(sub[value_col].dropna(), label=label, color=colors[i], fill=fill)
                elif kind == 'ecdf':
                    sns.ecdfplot(sub[value_col].dropna(), label=label, color=colors[i])
                else:
                    sns.histplot(sub[value_col].dropna(), label=label, color=colors[i], bins=bins, stat='density', alpha=0.4)
            plt.legend(title=group_col)
    else:
        if kind == 'kde':
            sns.kdeplot(df[value_col].dropna(), fill=fill)
            if show_stats:
                med = df[value_col].median()
                plt.axvline(med, color='k', linestyle='--', label=f'median={med:.2f}')
                plt.legend()
        elif kind == 'ecdf':
            sns.ecdfplot(df[value_col].dropna())
            if show_stats:
                med = df[value_col].median()
                plt.axvline(med, color='k', linestyle='--')
        elif kind == 'violin':
            sns.violinplot(y=value_col, data=df, palette=palette, inner='quartile')
            if show_stats:
                cnt = len(df)
                plt.text(0, plt.ylim()[0], f'n={cnt}', ha='center', va='bottom', fontsize=8)
        elif kind == 'box':
            sns.boxplot(y=value_col, data=df)
            if show_stats:
                cnt = len(df)
                plt.text(0, plt.ylim()[0], f'n={cnt}', ha='center', va='bottom', fontsize=8)
        else:
            sns.histplot(df[value_col].dropna(), bins=bins)

    plt.xlabel(value_col)
    plt.ylabel('Density')
    plt.title(f'Distribution of {value_col}' + (f' by {group_col}' if group_col else ''))
    plt.tight_layout()
    return plt.gcf()


def distribution_by_assignments(info_df: pd.DataFrame,
                                assignments: Any,
                                subject_col: str,
                                value_col: str,
                                kind: str = 'box',
                                figsize=(10, 6),
                                palette: Optional[str] = 'Set2',
                                bins: int = 30,
                                show_stats: bool = True):
    """Map `assignments` (split->list(subjects)) onto `info_df` via `subject_col`,
    then call `distribution_plot` with `group_col='split'` to show distributions per split.
    """
    # Build DataFrame mapping subject->split
    rows = []
    # accept dict, mapping, or iterable of pairs; accept sets/lists as values
    if isinstance(assignments, dict):
        items = assignments.items()
    else:
        try:
            items = list(assignments)
        except Exception:
            raise ValueError('assignments must be a mapping split->iterable(subjects)')
    for split, subs in items:
        for s in subs:
            rows.append({'subject': s, 'split': split})
    if not rows:
        raise ValueError('Empty assignments')
    assign_df = pd.DataFrame(rows)
    # merge on subject column
    merged = info_df.merge(assign_df, left_on=subject_col, right_on='subject', how='inner')
    if merged.empty:
        raise ValueError('No subjects from assignments found in info_df')

    # If user requested a categorical box/violin plot, draw directly to ensure correct type
    if kind in ('box', 'violin'):
        plt.figure(figsize=figsize)
        sns.set_style('whitegrid')
        if kind == 'box':
            sns.boxplot(x='split', y=value_col, data=merged, palette=palette)
        else:
            sns.violinplot(x='split', y=value_col, data=merged, palette=palette, inner='quartile')
        if show_stats:
            groups = sorted(merged['split'].dropna().unique())
            for i, g in enumerate(groups):
                sub = merged[merged['split'] == g]
                cnt = len(sub)
                med = sub[value_col].median() if cnt > 0 else np.nan
                plt.text(i, plt.ylim()[0], f'n={cnt}', ha='center', va='bottom', fontsize=8)
                plt.text(i, plt.ylim()[1], f'med={med:.1f}' if not np.isnan(med) else 'med=NA', ha='center', va='top', fontsize=8)
        plt.xlabel('split')
        plt.ylabel(value_col)
        plt.title(f'Distribution of {value_col} by split')
        plt.tight_layout()
        return plt.gcf()

    # otherwise, delegate to distribution_plot for kde/hist/ecdf
    return distribution_plot(merged, value_col=value_col, group_col='split', kind=kind, figsize=figsize, palette=palette, bins=bins, show_stats=show_stats)


def quantity_quality_plot(info_df: pd.DataFrame,
                          subject_col: str = 'Subject',
                          quantity_col: str = 'Number of subtractions',
                          quality_col: str = 'Count quality',
                          figsize=(14, 6),
                          palette: Optional[str] = 'Set2',
                          sort_by_quantity: bool = True,
                          rotate_xticks: bool = True):
    """Combined plot showing both quantity and quality per subject.

    Top: bar plot of `quantity_col` per subject, colored by `quality_col`.
    Bottom: boxplot (with swarm) of `quantity_col` per quality category.
    Returns matplotlib Figure.
    """
    df = info_df.copy()
    if subject_col not in df.columns:
        raise ValueError(f'subject_col "{subject_col}" not found')
    if quantity_col not in df.columns:
        raise ValueError(f'quantity_col "{quantity_col}" not found')

    df[quantity_col] = pd.to_numeric(df[quantity_col], errors='coerce')
    df[quality_col] = df.get(quality_col, 'All')

    # choose order of subjects
    if sort_by_quantity:
        order = df.sort_values(by=quantity_col, ascending=False)[subject_col].astype(str).tolist()
    else:
        order = df[subject_col].astype(str).tolist()

    # palette mapping
    qualities = list(pd.Categorical(df[quality_col]).categories)
    colors = sns.color_palette(palette, n_colors=max(2, len(qualities)))
    qual_to_color = {q: colors[i % len(colors)] for i, q in enumerate(qualities)}

    # build figure with two rows
    fig = plt.figure(figsize=figsize)
    gs = fig.add_gridspec(2, 1, height_ratios=[2, 1], hspace=0.25)

    ax0 = fig.add_subplot(gs[0])
    # prepare bar values in order
    vals = df.set_index(subject_col).reindex(order)[quantity_col].fillna(0).values
    bar_colors = [qual_to_color.get(df.loc[df[subject_col].astype(str) == s, quality_col].iat[0], (0.6,0.6,0.6)) if not df.loc[df[subject_col].astype(str) == s].empty else (0.7,0.7,0.7) for s in order]
    ax0.bar(range(len(order)), vals, color=bar_colors)
    ax0.set_ylabel(quantity_col)
    ax0.set_title(f'{quantity_col} per subject (colored by {quality_col})')
    if rotate_xticks:
        ax0.set_xticks(range(len(order)))
        ax0.set_xticklabels(order, rotation=90, fontsize=8)
    else:
        ax0.set_xticks([])
    # annotate counts on top of bars (small)
    for i, v in enumerate(vals):
        if not np.isnan(v) and v > 0:
            ax0.text(i, v + max(0.01, max(vals) * 0.01), str(int(v)), ha='center', va='bottom', fontsize=7)

    # legend for qualities
    handles = [plt.Line2D([0], [0], marker='s', color=qual_to_color[q], linestyle='') for q in qualities]
    ax0.legend(handles, qualities, title=quality_col, bbox_to_anchor=(1.02, 1), loc='upper left')

    ax1 = fig.add_subplot(gs[1])
    sns.boxplot(x=quality_col, y=quantity_col, data=df, palette=palette, ax=ax1)
    sns.swarmplot(x=quality_col, y=quantity_col, data=df, color='k', alpha=0.6, ax=ax1)
    ax1.set_xlabel(quality_col)
    ax1.set_ylabel(quantity_col)
    ax1.set_title(f'Distribution of {quantity_col} by {quality_col}')

    plt.tight_layout()
    return fig


def correct_incorrect_ratio_plot(info_df: pd.DataFrame,
                                 subject_col: str = 'Subject',
                                 correct_col: Optional[str] = None,
                                 incorrect_col: Optional[str] = None,
                                 subtractions_df: Optional[pd.DataFrame] = None,
                                 correct_flag_col: str = 'correct',
                                 normalize: bool = True,
                                 kind: str = 'stacked',
                                 figsize=(12, 4),
                                 palette: Optional[dict] = None,
                                 annotate: bool = True):
    """Plot per-subject correct vs incorrect subtraction counts or fractions.

    Two input modes:
    - Aggregated mode: `info_df` contains columns with absolute counts
      (provide `correct_col` and `incorrect_col`).
    - Long mode: provide `subtractions_df` with one row per subtraction and a
      boolean column `correct_flag_col` indicating correctness; it will be
      grouped by `subject_col`.

    `kind` can be 'stacked' (stacked bars) or 'ratio' (single bar = fraction correct).
    If `normalize=True` the stacked bars are shown as fractions (0..1).
    Returns matplotlib Figure.
    """
    # Determine counts per subject
    # allow info_df to be None if subtractions_df is provided
    if info_df is None:
        info_df = pd.DataFrame()

    # If user supplied explicit column names, try to use them; if exact names
    # are missing, try case-insensitive substring matching to be forgiving.
    if correct_col and incorrect_col and (not info_df.empty):
        cols = list(info_df.columns)
        if correct_col in cols and incorrect_col in cols:
            use_corr, use_incorr = correct_col, incorrect_col
        else:
            # attempt case-insensitive substring match
            lc_cols = {c.lower(): c for c in cols}
            use_corr = None
            use_incorr = None
            for c in cols:
                cl = c.lower()
                if use_corr is None and correct_col.lower() in cl:
                    use_corr = c
                if use_incorr is None and incorrect_col.lower() in cl:
                    use_incorr = c
            # also try prefix matching for common patterns
            if use_corr is None:
                for c in cols:
                    if c.lower().startswith(correct_col.lower()):
                        use_corr = c
                        break
            if use_incorr is None:
                for c in cols:
                    if c.lower().startswith(incorrect_col.lower()):
                        use_incorr = c
                        break
            if use_corr is None or use_incorr is None:
                # fall through to other modes
                use_corr = use_corr
                use_incorr = use_incorr

        if use_corr and use_incorr and use_corr in info_df.columns and use_incorr in info_df.columns:
            df_counts = info_df[[subject_col, use_corr, use_incorr]].copy()
            df_counts = df_counts.rename(columns={use_corr: 'correct', use_incorr: 'incorrect'})
        else:
            # will continue to try other inference methods below
            df_counts = None
    elif subtractions_df is not None:
        s = subtractions_df.copy()
        if subject_col not in s.columns or correct_flag_col not in s.columns:
            raise ValueError('subtractions_df must contain subject_col and correct_flag_col')
        grp = s.groupby(subject_col)[correct_flag_col].agg(['sum', 'count']).reset_index()
        grp = grp.rename(columns={'sum': 'correct', 'count': 'total'})
        grp['incorrect'] = grp['total'] - grp['correct']
        df_counts = grp[[subject_col, 'correct', 'incorrect']]
    else:
        # try to auto-detect columns named like 'correct'/'incorrect' or 'n_correct' etc.
        lower = {c: c.lower() for c in info_df.columns}
        corr = None
        incorr = None
        for c, lc in lower.items():
            if 'correct' in lc and corr is None:
                corr = c
            if ('incorrect' in lc or 'wrong' in lc or 'false' in lc) and incorr is None:
                incorr = c
            if ('n_correct' in lc or 'num_correct' in lc) and corr is None:
                corr = c
        if corr and incorr:
            df_counts = info_df[[subject_col, corr, incorr]].rename(columns={corr: 'correct', incorr: 'incorrect'})
        else:
            raise ValueError('Could not infer correct/incorrect columns; provide correct_col/incorrect_col or subtractions_df')

    # ensure types
    df_counts['correct'] = pd.to_numeric(df_counts['correct'], errors='coerce').fillna(0).astype(int)
    df_counts['incorrect'] = pd.to_numeric(df_counts['incorrect'], errors='coerce').fillna(0).astype(int)
    df_counts['total'] = df_counts['correct'] + df_counts['incorrect']
    df_counts['frac_correct'] = df_counts['correct'] / df_counts['total'].replace({0: 1})

    # order by total descending
    df_counts = df_counts.sort_values('total', ascending=False).reset_index(drop=True)

    subjects = df_counts[subject_col].astype(str).tolist()
    corrects = df_counts['correct'].values
    incorrects = df_counts['incorrect'].values

    # palette
    if palette is None:
        palette = {'correct': (0.2, 0.6, 0.2), 'incorrect': (0.8, 0.2, 0.2)}

    fig, ax = plt.subplots(figsize=figsize)
    x = np.arange(len(subjects))
    if kind == 'stacked':
        if normalize:
            totals = corrects + incorrects
            # avoid division by zero
            frac_corr = np.divide(corrects, totals, out=np.zeros_like(corrects, dtype=float), where=totals != 0)
            frac_inc = 1 - frac_corr
            ax.bar(x, frac_corr, color=palette.get('correct'), label='correct')
            ax.bar(x, frac_inc, bottom=frac_corr, color=palette.get('incorrect'), label='incorrect')
            ax.set_ylabel('Fraction')
            ax.set_ylim(0, 1)
        else:
            ax.bar(x, corrects, color=palette.get('correct'), label='correct')
            ax.bar(x, incorrects, bottom=corrects, color=palette.get('incorrect'), label='incorrect')
            ax.set_ylabel('Count')
        if annotate:
            for i, (c, ic, tot) in enumerate(zip(corrects, incorrects, df_counts['total'].values)):
                if normalize:
                    ax.text(i, 0.5, f'n={tot}', ha='center', va='center', fontsize=7, color='white')
                else:
                    ax.text(i, c + ic + max(1, int(0.01 * max(df_counts['total'].max(), 1))), str(int(tot)), ha='center', va='bottom', fontsize=7)
    elif kind == 'ratio':
        ax.bar(x, df_counts['frac_correct'].values, color=palette.get('correct'))
        ax.set_ylim(0, 1)
        ax.set_ylabel('Fraction correct')
        if annotate:
            for i, (f, tot) in enumerate(zip(df_counts['frac_correct'].values, df_counts['total'].values)):
                ax.text(i, f + 0.02, f'{f:.2f}\nn={tot}', ha='center', va='bottom', fontsize=7)
    else:
        raise ValueError('kind must be "stacked" or "ratio"')

    ax.set_xticks(x)
    ax.set_xticklabels(subjects, rotation=90, fontsize=8)
    ax.set_xlabel('Subject')
    ax.set_title('Correct vs Incorrect subtractions per subject')
    ax.legend()
    plt.tight_layout()
    return fig
