import argparse
import ctypes as C
import csv
import json
import queue
import struct
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LIB = ROOT / "vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib"

CH_SAMPLE_NUMBER = 0
CH_MEASUREMENT = 1
CH_CONTACT = 1025
CH_ACCEL = 2561
N_ACC = 3
CH_STREAMING = 2625


class BleDevice(C.Structure):
    _fields_ = [("name", C.c_char_p), ("mac_address", C.c_char_p)]


class Version(C.Structure):
    _fields_ = [("major", C.c_uint8), ("minor", C.c_uint8), ("patch", C.c_uint8)]


class DeviceInfo(C.Structure):
    _fields_ = [
        ("id", C.c_uint8),
        ("hardware_version", Version),
        ("firmware_version", Version),
        ("serial_number", C.c_size_t),
        ("sample_per_packet", C.c_size_t),
    ]


class Config(C.Structure):
    _fields_ = [
        ("log_buffer_size", C.c_size_t),
        ("log_path", C.c_char * 200),
        ("log_level", C.c_uint8),
        ("append_logs", C.c_bool),
        ("timestamps_enabled", C.c_bool),
        ("autoflush", C.c_bool),
        ("thread_ids_enabled", C.c_bool),
        ("chunk_size", C.c_size_t),
        ("enable_logs", C.c_bool),
        ("update_path", C.c_char * 200),
        ("adapter_index", C.c_uint8),
    ]


CHUNK_CB = C.CFUNCTYPE(None, C.POINTER(C.c_void_p), C.c_size_t, C.c_void_p)
VOID_CB = C.CFUNCTYPE(None, C.c_void_p)
DISCONNECT_CB = C.CFUNCTYPE(None, C.c_void_p)


def load(path):
    lib = C.CDLL(str(path))
    p = C.c_void_p
    sig = {
        "ba_core_init": (C.c_uint8, []),
        "ba_core_close": (C.c_uint8, []),
        "ba_core_scan": (C.c_uint8, [C.POINTER(C.POINTER(BleDevice)), C.POINTER(C.c_size_t)]),
        "ba_core_get_version": (C.POINTER(Version), []),
        "ba_core_get_config": (C.c_uint8, [C.POINTER(Config)]),
        "ba_core_set_config": (C.c_uint8, [C.POINTER(Config)]),
        "ba_eeg_manager_new": (p, []),
        "ba_eeg_manager_free": (None, [p]),
        "ba_eeg_manager_connect": (C.c_uint8, [p, C.c_char_p, p, p]),
        "ba_eeg_manager_disconnect": (None, [p]),
        "ba_eeg_manager_is_connected": (C.c_bool, [p]),
        "ba_eeg_manager_start_stream": (C.c_uint8, [p, p, p]),
        "ba_eeg_manager_stop_stream": (C.c_uint8, [p, p, p]),
        "ba_eeg_manager_load_config": (C.c_uint8, [p, p, p]),
        "ba_eeg_manager_set_channel_enabled": (None, [p, C.c_uint16, C.c_bool]),
        "ba_eeg_manager_set_data_stream_rate": (C.c_uint8, [p, C.c_uint8]),
        "ba_eeg_manager_read_sample_frequency": (C.c_uint8, [p, C.POINTER(C.c_uint8)]),
        "ba_eeg_manager_get_channel_index": (C.c_size_t, [p, C.c_uint16]),
        "ba_eeg_manager_get_device_info": (C.POINTER(DeviceInfo), [p]),
        "ba_eeg_manager_set_callback_chunk": (None, [p, CHUNK_CB, p]),
        "ba_eeg_manager_set_callback_disconnect": (None, [p, DISCONNECT_CB, p]),
        "ba_eeg_manager_get_stream_channel_data_types": (
            None,
            [p, C.POINTER(C.POINTER(C.c_uint8)), C.POINTER(C.c_size_t)],
        ),
        "ba_core_device_features_get": (p, [C.POINTER(DeviceInfo)]),
        "ba_core_device_features_has_accel": (C.c_bool, [p]),
        "ba_core_device_features_has_gyro": (C.c_bool, [p]),
        "ba_core_device_features_is_bipolar": (C.c_bool, [p]),
        "ba_core_device_features_electrode_count": (C.c_uint8, [p]),
    }
    for name, (res, args) in sig.items():
        fn = getattr(lib, name)
        fn.restype = res
        fn.argtypes = args
    return lib


def ver(v):
    return f"{v.major}.{v.minor}.{v.patch}"


def scan(lib):
    devs = C.POINTER(BleDevice)()
    n = C.c_size_t()
    err = lib.ba_core_scan(C.byref(devs), C.byref(n))
    return err, [(devs[i].name.decode(), devs[i].mac_address.decode()) for i in range(n.value)]


def writer(q, out_path, stop, n_ch, n_acc):
    cols = (
        ["chunk_id", "t_mono", "t_wall", "chunk_size", "pos", "sample_number"]
        + [f"ch{i + 1}" for i in range(n_ch)]
        + [f"contact{i + 1}" for i in range(n_ch)]
        + [f"acc{i + 1}" for i in range(n_acc)]
    )
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        while not (stop.is_set() and q.empty()):
            try:
                chunk_id, t_mono, t_wall, size, sn, meas, contact, acc = q.get(timeout=0.2)
            except queue.Empty:
                continue
            sns = struct.unpack(f"<{size}Q", sn)
            vals = [struct.unpack(f"<{size}d", m) for m in meas]
            cts = [struct.unpack(f"<{size}?", c) for c in contact]
            accs = [struct.unpack(f"<{size}f", c) for c in acc]
            for pos in range(size):
                w.writerow(
                    [chunk_id, f"{t_mono:.6f}", f"{t_wall:.6f}", size, pos, sns[pos]]
                    + [repr(v[pos]) for v in vals]
                    + [int(c[pos]) for c in cts]
                    + [repr(v[pos]) for v in accs]
                )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=str(DEFAULT_LIB))
    ap.add_argument("--device")
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--scan-only", action="store_true")
    ap.add_argument("--accel", action="store_true")
    ap.add_argument("--tag", default="")
    ap.add_argument("--out", default=str(Path(__file__).parent))
    a = ap.parse_args()
    out = Path(a.out)

    lib = load(a.lib)
    meta = {"lib_version": None}
    print("init", lib.ba_core_init())
    meta["lib_version"] = ver(lib.ba_core_get_version().contents)

    err, devices = scan(lib)
    print("scan", err, devices)
    if a.scan_only:
        lib.ba_core_close()
        return
    name = a.device or (devices[0][0] if len(devices) == 1 else None)
    if not name:
        raise SystemExit("podaj --device")

    mgr = lib.ba_eeg_manager_new()
    disconnects = []
    dcb = DISCONNECT_CB(lambda _: disconnects.append((time.monotonic(), time.time())))
    lib.ba_eeg_manager_set_callback_disconnect(mgr, dcb, None)

    err = lib.ba_eeg_manager_connect(mgr, name.encode(), None, None)
    print("connect", err)
    if err:
        lib.ba_eeg_manager_free(mgr)
        lib.ba_core_close()
        raise SystemExit(1)

    info = lib.ba_eeg_manager_get_device_info(mgr).contents
    feat = lib.ba_core_device_features_get(C.byref(info))
    meta["device"] = {
        "name": name,
        "model_id": info.id,
        "hw": ver(info.hardware_version),
        "fw": ver(info.firmware_version),
        "serial": info.serial_number,
        "sample_per_packet": info.sample_per_packet,
        "electrode_count": lib.ba_core_device_features_electrode_count(feat),
        "has_accel": lib.ba_core_device_features_has_accel(feat),
        "has_gyro": lib.ba_core_device_features_has_gyro(feat),
        "bipolar": lib.ba_core_device_features_is_bipolar(feat),
    }

    n_ch = meta["device"]["electrode_count"]
    print("rate", lib.ba_eeg_manager_set_data_stream_rate(mgr, 6))
    lib.ba_eeg_manager_set_channel_enabled(mgr, CH_SAMPLE_NUMBER, True)
    for i in range(n_ch):
        lib.ba_eeg_manager_set_channel_enabled(mgr, CH_MEASUREMENT + i, True)
        lib.ba_eeg_manager_set_channel_enabled(mgr, CH_CONTACT + i, True)
    n_acc = N_ACC if a.accel else 0
    for i in range(n_acc):
        lib.ba_eeg_manager_set_channel_enabled(mgr, CH_ACCEL + i, True)
    print("load_config", lib.ba_eeg_manager_load_config(mgr, None, None))

    rate = C.c_uint8()
    lib.ba_eeg_manager_read_sample_frequency(mgr, C.byref(rate))
    cfg = Config()
    lib.ba_core_get_config(C.byref(cfg))
    idx_sn = lib.ba_eeg_manager_get_channel_index(mgr, CH_SAMPLE_NUMBER)
    idx_m = [lib.ba_eeg_manager_get_channel_index(mgr, CH_MEASUREMENT + i) for i in range(n_ch)]
    idx_c = [lib.ba_eeg_manager_get_channel_index(mgr, CH_CONTACT + i) for i in range(n_ch)]
    idx_a = [lib.ba_eeg_manager_get_channel_index(mgr, CH_ACCEL + i) for i in range(n_acc)]
    types = C.POINTER(C.c_uint8)()
    n_types = C.c_size_t()
    lib.ba_eeg_manager_get_stream_channel_data_types(mgr, C.byref(types), C.byref(n_types))
    meta.update(
        rate_code=rate.value,
        chunk_size_config=cfg.chunk_size,
        idx_sample_number=idx_sn,
        idx_measurement=idx_m,
        idx_contact=idx_c,
        idx_accel=idx_a,
        stream_channel_data_types=[types[i] for i in range(n_types.value)],
    )

    q = queue.Queue()
    stop = threading.Event()
    counter = [0]

    def on_chunk(data, size, _):
        t_mono, t_wall = time.monotonic(), time.time()
        counter[0] += 1
        q.put(
            (
                counter[0],
                t_mono,
                t_wall,
                size,
                C.string_at(data[idx_sn], size * 8),
                [C.string_at(data[i], size * 8) for i in idx_m],
                [C.string_at(data[i], size) for i in idx_c],
                [C.string_at(data[i], size * 4) for i in idx_a],
            )
        )

    cb = CHUNK_CB(on_chunk)
    lib.ba_eeg_manager_set_callback_chunk(mgr, cb, None)
    wt = threading.Thread(target=writer, args=(q, out / f"probe_dump{a.tag}.csv", stop, n_ch, n_acc))
    wt.start()

    t0 = time.monotonic()
    print("start_stream", lib.ba_eeg_manager_start_stream(mgr, None, None))
    time.sleep(a.seconds)
    meta["stop_stream"] = lib.ba_eeg_manager_stop_stream(mgr, None, None)
    meta["duration_s"] = time.monotonic() - t0
    lib.ba_eeg_manager_set_callback_chunk(mgr, CHUNK_CB(), None)
    stop.set()
    wt.join()
    meta["chunks"] = counter[0]
    meta["disconnect_events"] = disconnects

    lib.ba_eeg_manager_disconnect(mgr)
    lib.ba_eeg_manager_free(mgr)
    lib.ba_core_close()
    (out / f"probe_meta{a.tag}.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
