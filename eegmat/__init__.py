"""Lightweight package for loading, preprocessing and analyzing the EEGMAT dataset."""
from .io import load_all, read_one, parse_fname
from .preprocess import tidy, set_montage
from .dataset import make_dataset
from .features import extract_features, extract_channel_features, select_eeg_channels

__all__ = [
    "load_all", "read_one", "parse_fname",
    "tidy", "set_montage",
    "make_dataset",
    "extract_features", "extract_channel_features", "select_eeg_channels",
]
