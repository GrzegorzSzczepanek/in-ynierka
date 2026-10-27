import argparse
import json
from pathlib import Path

import numpy as np

d = Path(__file__).parent
ap = argparse.ArgumentParser()
ap.add_argument("--tag", default="")
tag = ap.parse_args().tag
data = np.genfromtxt(d / f"probe_dump{tag}.csv", delimiter=",", names=True)
meta = json.loads((d / f"probe_meta{tag}.json").read_text())

n_ch = meta["device"]["electrode_count"]
cid, t_mono, size, sn = (data[k] for k in ("chunk_id", "t_mono", "chunk_size", "sample_number"))
ch = np.stack([data[f"ch{i + 1}"] for i in range(n_ch)])
ct = np.stack([data[f"contact{i + 1}"] for i in range(n_ch)])

first = np.unique(cid, return_index=True)[1]
tc = t_mono[first]
sizes = size[first].astype(int)
dt = np.diff(tc)
span_wall = tc[-1] - tc[0]
dsn = np.diff(sn)

print("próbki", len(sn), "chunki", len(tc))
print("rozmiary chunków", dict(zip(*np.unique(sizes, return_counts=True))))
print(f"odstęp chunków s: mean={dt.mean():.4f} std={dt.std():.4f} max={dt.max():.4f} min={dt.min():.4f}")
print("odstępy > 0.2 s:", int((dt > 0.2).sum()))
print(f"fs z próbek/czas: {(len(sn) - sizes[-1]) / span_wall:.3f} Hz (czas {span_wall:.2f} s)")
print(f"fs z sample_number: {(sn[-1] - sn[0]) / span_wall:.3f} Hz")
print("sample_number start/koniec:", sn[0], sn[-1], "kroki:", dict(zip(*np.unique(dsn, return_counts=True))))
print("luki w sample_number:", int((dsn != 1).sum()))
print("wartości min/max/mediana odch. std per kanał:")
print(" min", np.nanmin(ch), "max", np.nanmax(ch))
print(" std per kanał", np.round(ch.std(axis=1), 1).tolist())
print(" średnia per kanał", np.round(ch.mean(axis=1), 1).tolist())
print("contact: frakcja True per kanał", np.round(ct.mean(axis=1), 2).tolist())
print("NaN:", int(np.isnan(ch).sum()), "unikalne wartości kanału 1:", len(np.unique(ch[0])))

acc_cols = [c for c in data.dtype.names if c.startswith("acc")]
for c in acc_cols:
    a = data[c]
    print(f"{c}: min={a.min():.3f} max={a.max():.3f} std={a.std():.3f} unikalne={len(np.unique(a))} zmiany/próbkę={(np.diff(a) != 0).mean():.3f}")
sat = (np.abs(ch) >= 562499).mean()
print(f"frakcja nasyconych próbek: {sat:.3f}")
