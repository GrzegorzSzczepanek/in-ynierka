import argparse
import ctypes as C
import json
import time
from pathlib import Path

from probe import (CH_CONTACT, CH_MEASUREMENT, CH_SAMPLE_NUMBER, CHUNK_CB, DEFAULT_LIB,
                   DISCONNECT_CB, load)

N_CH = 32


def start(lib, mgr, name, state):
    err = lib.ba_eeg_manager_connect(mgr, name.encode(), None, None)
    res = {"connect": err}
    if err:
        return res
    lib.ba_eeg_manager_set_data_stream_rate(mgr, 6)
    lib.ba_eeg_manager_set_channel_enabled(mgr, CH_SAMPLE_NUMBER, True)
    for i in range(N_CH):
        lib.ba_eeg_manager_set_channel_enabled(mgr, CH_MEASUREMENT + i, True)
        lib.ba_eeg_manager_set_channel_enabled(mgr, CH_CONTACT + i, True)
    res["load_config"] = lib.ba_eeg_manager_load_config(mgr, None, None)
    idx_sn = lib.ba_eeg_manager_get_channel_index(mgr, CH_SAMPLE_NUMBER)

    def on_chunk(data, size, _):
        sn = C.cast(data[idx_sn], C.POINTER(C.c_size_t))[0]
        state["chunks"].append((time.monotonic(), size, sn))

    state["cb"] = CHUNK_CB(on_chunk)
    lib.ba_eeg_manager_set_callback_chunk(mgr, state["cb"], None)
    res["start_stream"] = lib.ba_eeg_manager_start_stream(mgr, None, None)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", required=True)
    ap.add_argument("--lib", default=str(DEFAULT_LIB))
    ap.add_argument("--wait", type=float, default=90)
    a = ap.parse_args()

    lib = load(a.lib)
    lib.ba_core_init()
    mgr = lib.ba_eeg_manager_new()
    state = {"chunks": []}
    events = []
    dcb = DISCONNECT_CB(lambda _: events.append(("disconnect_callback", time.monotonic())))
    lib.ba_eeg_manager_set_callback_disconnect(mgr, dcb, None)

    out = {"first_run": start(lib, mgr, a.device, state)}
    print(out)
    if out["first_run"].get("start_stream") != 0:
        raise SystemExit("start nieudany")

    t_start = time.monotonic()
    print("\nSTRUMIEŃ DZIAŁA. Wyłącz teraz czepek (lub odejdź poza zasięg BLE).\n", flush=True)
    seen_chunks = 0
    disc_conn = None
    while time.monotonic() - t_start < a.wait:
        time.sleep(0.1)
        if disc_conn is None and not lib.ba_eeg_manager_is_connected(mgr):
            disc_conn = time.monotonic()
        if events and disc_conn is not None:
            break
    last_chunk = state["chunks"][-1][0] if state["chunks"] else None
    cb_t = events[0][1] if events else None
    out["detect"] = {
        "chunks_before": len(state["chunks"]),
        "last_chunk_after_start_s": last_chunk and last_chunk - t_start,
        "disconnect_callback_after_last_chunk_s": cb_t and last_chunk and cb_t - last_chunk,
        "is_connected_false_after_last_chunk_s": disc_conn and last_chunk and disc_conn - last_chunk,
        "silence_at_end_s": last_chunk and time.monotonic() - last_chunk,
        "disconnect_callback_fired": bool(events),
        "is_connected_at_end": bool(lib.ba_eeg_manager_is_connected(mgr)),
    }
    out["detect"]["stop_stream_err_after_loss"] = lib.ba_eeg_manager_stop_stream(mgr, None, None)
    print(json.dumps(out["detect"], indent=2))

    input("\nWłącz czepek z powrotem, poczekaj aż zacznie świecić i naciśnij Enter... ")

    state["chunks"].clear()
    events.clear()
    out["reconnect_same_manager"] = start(lib, mgr, a.device, state)
    time.sleep(10)
    out["reconnect_same_manager"]["chunks_10s"] = len(state["chunks"])
    out["reconnect_same_manager"]["first_sample_number"] = state["chunks"][0][2] if state["chunks"] else None
    print(json.dumps(out["reconnect_same_manager"], indent=2))

    if not state["chunks"]:
        lib.ba_eeg_manager_free(mgr)
        mgr = lib.ba_eeg_manager_new()
        lib.ba_eeg_manager_set_callback_disconnect(mgr, dcb, None)
        out["reconnect_new_manager"] = start(lib, mgr, a.device, state)
        time.sleep(10)
        out["reconnect_new_manager"]["chunks_10s"] = len(state["chunks"])
        print(json.dumps(out["reconnect_new_manager"], indent=2))

    lib.ba_eeg_manager_stop_stream(mgr, None, None)
    lib.ba_eeg_manager_disconnect(mgr)
    lib.ba_eeg_manager_free(mgr)
    lib.ba_core_close()
    Path(__file__).with_name("disconnect_test.json").write_text(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
