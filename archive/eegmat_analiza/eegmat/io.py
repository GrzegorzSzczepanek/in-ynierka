from pathlib import Path
import re
from typing import Dict, Tuple
import mne


def parse_fname(p: Path) -> Tuple[int, int]:
    """Parse filenames like 'Subject00_1.edf' -> (subject, state)."""
    m = re.match(r"Subject(\d+)_(\d)\.edf", p.name)
    if not m:
        raise ValueError(f"Unexpected filename: {p.name}")
    return int(m.group(1)), int(m.group(2))


def load_all(data_dir: Path, preload: bool = False) -> Dict[Tuple[int, int], mne.io.BaseRaw]:
    """Load all Subject*.edf files from `data_dir` into a dict keyed by (subject, state)."""
    records = {}
    for p in sorted(Path(data_dir).glob("Subject*.edf")):
        subj, state = parse_fname(p)
        records[(subj, state)] = mne.io.read_raw_edf(p, preload=preload)
    return records


def read_one(path: Path, preload: bool = True) -> mne.io.BaseRaw:
    """Convenience wrapper around mne.io.read_raw_edf."""
    return mne.io.read_raw_edf(Path(path), preload=preload)
