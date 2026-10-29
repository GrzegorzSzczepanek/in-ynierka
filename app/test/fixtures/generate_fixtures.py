import json
from pathlib import Path

import numpy as np
from scipy import signal

fs = 250
rng = np.random.default_rng(7)
t = np.arange(2000) / fs
x = (20 * np.sin(2 * np.pi * 10 * t) + 30 * np.sin(2 * np.pi * 50 * t)
     + 50 * np.sin(2 * np.pi * 0.3 * t) + rng.normal(0, 5, t.size))

sos = np.vstack([
    signal.butter(4, 1, "high", fs=fs, output="sos"),
    signal.butter(4, 40, "low", fs=fs, output="sos"),
    signal.tf2sos(*signal.iirnotch(50, 30, fs=fs)),
])
y = signal.sosfilt(sos, x)

seg = y[-500:]
f, p = signal.welch(seg, fs=fs, window="hann", nperseg=250, noverlap=125,
                    nfft=512, detrend="constant", scaling="density")
df = fs / 512
band = lambda lo, hi: float(p[(f >= lo) & (f <= hi)].sum() * df)

out = {
    "fs": fs,
    "x": x.tolist(),
    "filtered": y.tolist(),
    "psd": p.tolist(),
    "alpha_power": band(8, 12),
    "hf_power": band(30, 40),
    "total_power": band(1, 40),
}
Path(__file__).with_name("dsp_reference.json").write_text(json.dumps(out))
