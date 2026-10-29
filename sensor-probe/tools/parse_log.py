#!/usr/bin/env python3
"""Turn a Sensor Probe log (GARMIN/APPS/LOGS/<APP>.TXT or simulator console
output) into a capability / sampling-rate report.

    python3 tools/parse_log.py SENSORPROBE.TXT            # markdown to stdout
    python3 tools/parse_log.py SENSORPROBE.TXT --csv out  # also out_rates.csv etc.

Only lines starting with "SP," are read; anything else is ignored. If the log
holds several runs, the last one (from the last META line) is reported unless
--run N is given.
"""
import argparse
import csv
import sys

RATE_COLS = [
    "phase", "channel", "requested_hz", "error",
    "callbacks", "empty_callbacks", "samples", "first_batch",
    "observed_hz_cb", "observed_hz_ts", "dropped_est",
    "cb_interval_mean_ms", "cb_interval_std_ms", "cb_interval_min_ms", "cb_interval_max_ms",
    "batch_min", "batch_max",
    "ts_count", "ts_interval_mean_ms", "ts_interval_std_ms", "ts_interval_min_ms", "ts_interval_max_ms",
    "ts_gaps", "ts_missing", "ts_backwards",
    "value_min", "value_max", "value_mean",
]
HIST_COLS = ["store", "count", "nulls", "oldest", "newest", "spacing_s", "min", "max", "mean"]


def split_runs(lines):
    runs, cur = [], None
    for line in lines:
        line = line.strip()
        if not line.startswith("SP,"):
            continue
        parts = line.split(",")
        if len(parts) < 4:
            continue
        rec = {"seq": parts[1], "t": parts[2], "kind": parts[3], "f": parts[4:]}
        if rec["kind"] == "META" or cur is None:
            cur = []
            runs.append(cur)
        cur.append(rec)
    return runs


def num(s):
    if s in ("", None):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def fmt(v, nd=1):
    if v is None:
        return "–"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def build(run):
    out = {"meta": None, "inv": [], "api": [], "snap": [], "hist": [], "rates": [],
           "hf_err": {}, "info_rate": None, "info_fields": [], "pos_rate": None,
           "batt": {}, "end": None, "aborted": False, "hf_start": {}}
    for r in run:
        k, f = r["kind"], r["f"]
        if k == "META":
            out["meta"] = f
        elif k == "INV":
            out["inv"].append((f[0], ",".join(f[1:])))
        elif k == "API":
            out["api"].append((f[0], f[1]))
        elif k == "SNAP":
            out["snap"].append((f[0], ",".join(f[1:])))
        elif k == "HIST":
            out["hist"].append(dict(zip(HIST_COLS, f)))
        elif k == "HF_START":
            out["hf_start"][f[0]] = f
        elif k == "HF_ERR":
            out["hf_err"][f[0]] = f[1]
        elif k == "RATE":
            out["rates"].append(dict(zip(RATE_COLS, f)))
        elif k == "INFO_RATE":
            out["info_rate"] = f
        elif k == "INFO_FIELD":
            out["info_fields"].append(f)
        elif k == "POS_RATE":
            out["pos_rate"] = f
        elif k == "BATT":
            out["batt"].setdefault(f[0], {})[f[1]] = num(f[2])
        elif k == "END":
            out["end"] = f
        elif k == "ABORT":
            out["aborted"] = True
    return out


def verdict(row):
    """One-word summary per rate row."""
    if row.get("error"):
        return "error"
    if (num(row["samples"]) or 0) == 0:
        return "no data"
    req = num(row["requested_hz"]) or 0
    if req <= 0:
        return "ok"
    hz = num(row["observed_hz_ts"]) or num(row["observed_hz_cb"])
    if hz is None:
        return "too short"
    ratio = hz / req
    if ratio > 1.05:
        return "faster than asked"
    if ratio >= 0.95:
        return "met"
    if ratio >= 0.5:
        return "partial"
    return "clamped/low"


def markdown(r):
    o = []
    o.append("# Sensor Probe report\n")
    if r["meta"]:
        o.append(f"App {r['meta'][1]}, watch clock at start {r['meta'][2]}, "
                 f"HF phase {r['meta'][3]} s, listener period {r['meta'][7]} s.\n")
    if r["aborted"]:
        o.append("**Run was aborted before the plan finished.**\n")

    o.append("## Device\n")
    o.append("| Key | Value |\n|---|---|")
    for k, v in r["inv"]:
        o.append(f"| {k} | {v} |")
    o.append("")

    o.append("## API presence on this firmware\n")
    o.append("Present means the symbol exists; it does not mean the sensor returns data.\n")
    o.append("| API | Present |\n|---|---|")
    for k, v in r["api"]:
        o.append(f"| {k} | {'yes' if v == 'true' else 'no'} |")
    o.append("")

    o.append("## High-rate listener (registerSensorDataListener)\n")
    o.append("Observed Hz uses per-sample timestamps when the firmware provides them "
             "(API 5.1.1+), otherwise callback arrival times. Dropped is the shortfall "
             "against the requested rate over the callback window; gaps count "
             "timestamp steps over 1.5x the nominal interval.\n")
    o.append("| Phase | Ch | Req Hz | Obs Hz (ts) | Obs Hz (cb) | Verdict | Samples | Dropped est | "
             "Gaps / missing | Callback interval ms (mean ± sd, max) | Sample interval ms (mean ± sd) | "
             "Batch size | Value range | Battery Δ% |")
    o.append("|" + "---|" * 14)
    for row in r["rates"]:
        b = r["batt"].get(row["phase"], {})
        bd = (b.get("start") - b.get("end")) if b.get("start") is not None and b.get("end") is not None else None
        o.append("| {p} | {c} | {req} | {hts} | {hcb} | {v} | {n} | {d} | {g} | {cbm} ± {cbs}, {cbx} | "
                 "{tsm} ± {tss} | {bmin}–{bmax} | {vmin} … {vmax} | {bd} |".format(
                     p=row["phase"], c=row["channel"], req=row["requested_hz"],
                     hts=fmt(num(row["observed_hz_ts"]), 2), hcb=fmt(num(row["observed_hz_cb"]), 2),
                     v=verdict(row), n=row["samples"], d=row["dropped_est"] or "–",
                     g=(f"{row['ts_gaps']} / {row['ts_missing']}" if num(row["ts_count"]) else "no ts"),
                     cbm=fmt(num(row["cb_interval_mean_ms"])), cbs=fmt(num(row["cb_interval_std_ms"])),
                     cbx=fmt(num(row["cb_interval_max_ms"]), 0),
                     tsm=fmt(num(row["ts_interval_mean_ms"]), 2), tss=fmt(num(row["ts_interval_std_ms"]), 2),
                     bmin=row["batch_min"] or "–", bmax=row["batch_max"] or "–",
                     vmin=fmt(num(row["value_min"]), 1), vmax=fmt(num(row["value_max"]), 1),
                     bd=fmt(bd, 0)))
        if row.get("error"):
            o.append(f"|  | error: {row['error']} |" + " |" * 12)
    o.append("")

    o.append("## 1 Hz Sensor.Info events (enableSensorEvents)\n")
    if r["info_rate"]:
        f = r["info_rate"]
        o.append(f"{f[0]} events, interval mean {fmt(num(f[1]))} ms, sd {fmt(num(f[2]))}, "
                 f"min {fmt(num(f[3]), 0)}, max {fmt(num(f[4]), 0)}." + (f" Error: {f[5]}" if len(f) > 5 and f[5] else "") + "\n")
        o.append("| Field | Exists | Non-null events |\n|---|---|---|")
        for name, present, nn, total in r["info_fields"]:
            o.append(f"| {name} | {'yes' if present == 'true' else 'no'} | {nn}/{total} |")
    else:
        o.append("Not run.")
    o.append("")

    o.append("## Position (GNSS) events\n")
    if r["pos_rate"]:
        f = r["pos_rate"]
        q = f[5].split(";") if len(f) > 5 else []
        o.append(f"{f[0]} events, interval mean {fmt(num(f[1]))} ms, sd {fmt(num(f[2]))}. "
                 f"Quality counts [none, last-known, poor, usable, good]: {q}." +
                 (f" Error: {f[6]}" if len(f) > 6 and f[6] else "") + "\n")
    else:
        o.append("Not run.\n")

    o.append("## Stored history (SensorHistory / ActivityMonitor)\n")
    o.append("Spacing is the average time between stored samples, i.e. the background logging rate.\n")
    o.append("| Store | Samples | Nulls/invalid | Spacing s | Min | Max | Mean |\n|---|---|---|---|---|---|---|")
    for h in r["hist"]:
        o.append(f"| {h.get('store')} | {h.get('count')} | {h.get('nulls', '–')} | "
                 f"{fmt(num(h.get('spacing_s')), 0)} | {fmt(num(h.get('min')))} | "
                 f"{fmt(num(h.get('max')))} | {fmt(num(h.get('mean')))} |")
    o.append("")

    o.append("## Snapshot values at start\n")
    o.append("NA = field does not exist on this firmware; empty = exists but null.\n")
    o.append("| Field | Value |\n|---|---|")
    for k, v in r["snap"]:
        o.append(f"| {k} | {v} |")
    o.append("")
    if r["end"]:
        o.append(f"Battery at end: {r['end'][0]}%.\n")
    return "\n".join(o)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--run", type=int, default=-1, help="run index (default: last)")
    ap.add_argument("--csv", help="prefix for CSV outputs")
    a = ap.parse_args()
    with open(a.log, encoding="utf-8", errors="replace") as fh:
        runs = split_runs(fh)
    if not runs:
        sys.exit("no SP, lines found")
    r = build(runs[a.run])
    print(markdown(r))
    if a.csv:
        with open(a.csv + "_rates.csv", "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=RATE_COLS + ["verdict"])
            w.writeheader()
            for row in r["rates"]:
                w.writerow({**row, "verdict": verdict(row)})
        with open(a.csv + "_history.csv", "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=HIST_COLS)
            w.writeheader()
            for h in r["hist"]:
                w.writerow(h)


if __name__ == "__main__":
    main()
