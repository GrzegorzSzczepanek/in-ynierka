"""Preprocessing utilities: tidy channel names and set montage."""
from typing import Dict
import mne


OLD2NEW = {"T3": "T7", "T4": "T8", "T5": "P7", "T6": "P8"}


def tidy(raw: mne.io.BaseRaw) -> mne.io.BaseRaw:
    """Remove common prefixes and set non-scalp channel types.

    - removes leading 'EEG ' if present
    - marks ECG channels as 'ecg'
    - marks A1/A2 as 'misc'
    """
    raw.rename_channels({ch: ch.replace("EEG ", "").strip() for ch in raw.ch_names})
    remap: Dict[str, str] = {}
    for ch in raw.ch_names:
        u = ch.upper()
        if "ECG" in u:
            remap[ch] = "ecg"
        elif "A1" in u or "A2" in u:
            remap[ch] = "misc"
    if remap:
        raw.set_channel_types(remap)
    return raw


def set_montage(raw: mne.io.BaseRaw) -> mne.io.BaseRaw:
    """Remap a few legacy channel names and set standard_1020 montage."""
    raw.rename_channels({ch: OLD2NEW[ch] for ch in raw.ch_names if ch in OLD2NEW})
    raw.set_montage("standard_1020", match_case=False, on_missing="warn")
    return raw
