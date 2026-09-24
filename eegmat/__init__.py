"""Lightweight package for loading and preprocessing EEGMAT dataset used in the notebook."""
from .io import load_all, parse_fname
from .preprocess import tidy, set_montage
from .dataset import make_dataset

__all__ = ["load_all", "parse_fname", "tidy", "set_montage", "make_dataset"]
