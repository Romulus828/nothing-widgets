#!/usr/bin/env python3
"""System metrics collector for the Nothing desktop widgets.

Long-running: prints one JSON object per line every --interval seconds and
flushes. Every section is independent; a missing sensor never kills the
stream, it just leaves that key null so the widget can degrade.

Only the standard library is used. Reads /proc and /sys directly; the only
subprocess is nvidia-smi, and only while the dGPU is awake (see gpu()).
"""

import argparse
import glob
import json
import os
import signal
import subprocess
import sys
import time

# --------------------------------------------------------------------------- io


def read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def read_int(path, default=None):
    v = read(path)
    if v is None or v == "":
        return default
    try:
        return int(v)
    except ValueError:
        return default


def read_float(path, default=None):
    v = read(path)
    if v is None or v == "":
        return default
    try:
        return float(v)
    except ValueError:
        return default


# ------------------------------------------------------------------------ hwmon


def hwmon_devices():
    """{name: [paths]} for every hwmon device, resolved by name each call so
    index shuffles across boots or hotplug never matter."""
    out = {}
    for path in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        name = read(os.path.join(path, "name"))
        if name:
            out.setdefault(name, []).append(path)
    return out


def hwmon_channels(path, kind):
    """List of {n, label, value, high, crit, max, min} for temp*/fan* channels.
    Temperatures are converted from millidegrees to degrees."""
    chans = []
    for inp in sorted(glob.glob(os.path.join(path, f"{kind}[0-9]*_input"))):
        base = inp[: -len("_input")]
        n = int(os.path.basename(base)[len(kind):])
        raw = read_int(inp)
        if raw is None:
            continue
        scale = 1000.0 if kind == "temp" else 1.0
        chan = {
            "n": n,
            "label": read(base + "_label", "") or "",
            "value": raw / scale,
        }
        for extra in ("high", "crit", "max", "min"):
            v = read_int(base + "_" + extra)
            if v is not None:
                chan[extra] = v / scale
        chans.append(chan)
    return chans


def high_of(chan):
    """Warning threshold: drivers use either *_high (dell, nvme crit pairs) or
    *_max (coretemp, nvme); crit stays separate."""
    if chan.get("high") is not None:
        return chan["high"]
    return chan.get("max")


# -------------------------------------------------------------------------- cpu

_prev_stat = None
_cpu_model = None


def cpu_model():
    global _cpu_model
    if _cpu_model is None:
        _cpu_model = ""
        for line in (read("/proc/cpuinfo", "") or "").splitlines():
            if line.startswith("model name"):
                _cpu_model = line.split(":", 1)[1].strip()
                break
    return _cpu_model


def cpu_stat():
    """Per-cpu (idle, total) jiffies from /proc/stat; index 0 is the aggregate."""
    rows = []
    for line in (read("/proc/stat", "") or "").splitlines():
        if not line.startswith("cpu"):
            continue
        parts = line.split()
        vals = [int(x) for x in parts[1:]]
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        rows.append((idle, sum(vals)))
    return rows


def cpu(hw):
    global _prev_stat
    cur = cpu_stat()
    usage, cores = None, []
    if _prev_stat and len(_prev_stat) == len(cur):
        pct = []
        for (pi, pt), (ci, ct) in zip(_prev_stat, cur):
            dt = ct - pt
            pct.append(0.0 if dt <= 0 else max(0.0, min(100.0, 100.0 * (1 - (ci - pi) / dt))))
        usage, cores = pct[0], pct[1:]
    _prev_stat = cur

    freqs = [read_int(p) for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")]
    freqs = [f for f in freqs if f]
    freq_max = read_int("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")

    temp = high = crit = None
    core_temps = []
    for name in ("coretemp", "k10temp", "zenpower", "cpu_thermal"):
        for path in hw.get(name, []):
            chans = hwmon_channels(path, "temp")
            for c in chans:
                lab = c["label"]
                if temp is None and (lab.startswith("Package") or lab in ("Tctl", "Tdie") or (name == "cpu_thermal" and not lab)):
                    temp, high, crit = c["value"], high_of(c), c.get("crit")
                if lab.startswith("Core") or lab.startswith("Tccd"):
                    core_temps.append(c["value"])
            if temp is None and chans:
                c = chans[0]
                temp, high, crit = c["value"], high_of(c), c.get("crit")
        if temp is not None:
            break
    if temp is None:  # ACPI thermal zone fallback
        for tz in glob.glob("/sys/class/thermal/thermal_zone*"):
            if read(os.path.join(tz, "type"), "") in ("x86_pkg_temp", "TCPU", "cpu-thermal", "cpu_thermal"):
                t = read_int(os.path.join(tz, "temp"))
                if t is not None:
                    temp = t / 1000.0
                    break

    return {
        "model": cpu_model(),
        "threads": max(0, len(cur) - 1),
        "usage": usage,
        "cores": cores,
        "freq_mhz": (sum(freqs) / len(freqs) / 1000.0) if freqs else None,
        "freq_max_mhz": (freq_max / 1000.0) if freq_max else None,
        "temp": temp,
        "temp_high": high,
        "temp_crit": crit,
        "core_temps": core_temps,
    }


# ------------------------------------------------------------------------ memory


def mem():
    info = {}
    for line in (read("/proc/meminfo", "") or "").splitlines():
        k, _, v = line.partition(":")
        info[k] = int(v.split()[0]) * 1024  # kB -> bytes
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", info.get("MemFree", 0))
    used = max(0, total - avail)
    stotal = info.get("SwapTotal", 0)
    sused = max(0, stotal - info.get("SwapFree", 0))
    return {
        "total": total,
        "used": used,
        "available": avail,
        "percent": (100.0 * used / total) if total else None,
        "swap_total": stotal,
        "swap_used": sused,
        "swap_percent": (100.0 * sused / stotal) if stotal else None,
    }


# --------------------------------------------------------------------------- gpu

_nvidia = None          # {"pci": path, "name": str}
_nvidia_checked = False
_gpu_idle_polls = 0     # consecutive polls with no real work on an awake dGPU
_gpu_next_poll = 0.0    # monotonic time before which we skip nvidia-smi
_gpu_last = None        # last successful sample, re-emitted while backing off


def find_nvidia():
    global _nvidia, _nvidia_checked
    if _nvidia_checked:
        return _nvidia
    _nvidia_checked = True
    for dev in glob.glob("/sys/bus/pci/devices/*"):
        if read(os.path.join(dev, "vendor"), "") != "0x10de":
            continue
        if not (read(os.path.join(dev, "class"), "") or "").startswith("0x03"):
            continue
        _nvidia = {"pci": dev, "name": ""}
        break
    return _nvidia


def nvidia_smi(fields, timeout=3.0):
    try:
        out = subprocess.run(
            ["nvidia-smi", f"--query-gpu={','.join(fields)}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return [p.strip() for p in out.stdout.strip().splitlines()[0].split(",")]


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def gpu(interval):
    """Discrete NVIDIA via nvidia-smi, guarded so polling never keeps a sleeping
    dGPU awake: skip entirely while runtime-suspended, and back off (up to 60 s)
    while the GPU is awake but idle so the autosuspend timer can expire."""
    global _gpu_idle_polls, _gpu_next_poll, _gpu_last
    dev = find_nvidia()
    if dev is None:
        return amd_gpu()
    status = read(os.path.join(dev["pci"], "power", "runtime_status"), "unknown")
    base = {"vendor": "nvidia", "name": dev["name"], "state": status}
    if status == "suspended":
        _gpu_idle_polls = 0
        _gpu_next_poll = 0.0
        _gpu_last = None
        return dict(base, state="suspended")

    now = time.monotonic()
    if now < _gpu_next_poll and _gpu_last is not None:
        return dict(_gpu_last, state="idle", stale=True)

    row = nvidia_smi(["name", "utilization.gpu", "temperature.gpu", "memory.used",
                      "memory.total", "power.draw", "clocks.sm", "pstate"])
    if row is None or len(row) < 8:
        return dict(base, state="unavailable")
    dev["name"] = row[0]
    sample = {
        "vendor": "nvidia",
        "name": row[0],
        "state": "active",
        "util": num(row[1]),
        "temp": num(row[2]),
        "mem_used": num(row[3]),      # MiB
        "mem_total": num(row[4]),     # MiB
        "power_w": num(row[5]),
        "clock_mhz": num(row[6]),
        "pstate": row[7],
    }
    busy = (sample["util"] or 0) > 0 or (sample["mem_used"] or 0) > 256
    if busy:
        _gpu_idle_polls = 0
        _gpu_next_poll = 0.0
    else:
        _gpu_idle_polls += 1
        # 2 idle polls at the base cadence, then 10s, 20s, 40s, 60s...
        if _gpu_idle_polls >= 2:
            backoff = min(60.0, 10.0 * (2 ** (_gpu_idle_polls - 2)))
            _gpu_next_poll = now + max(backoff, interval)
        sample["state"] = "idle"
    _gpu_last = sample
    return sample


def amd_gpu():
    for dev in glob.glob("/sys/class/drm/card[0-9]/device"):
        if read(os.path.join(dev, "vendor"), "") != "0x1002":
            continue
        busy = read_int(os.path.join(dev, "gpu_busy_percent"))
        if busy is None:
            continue
        temp = None
        for hw in glob.glob(os.path.join(dev, "hwmon", "hwmon*")):
            for c in hwmon_channels(hw, "temp"):
                if c["label"] in ("edge", "junction") or temp is None:
                    temp = c["value"]
                    if c["label"] == "junction":
                        break
        used = read_int(os.path.join(dev, "mem_info_vram_used"))
        total = read_int(os.path.join(dev, "mem_info_vram_total"))
        return {
            "vendor": "amd", "name": "AMD GPU", "state": "active",
            "util": float(busy), "temp": temp,
            "mem_used": (used / 2**20) if used else None,
            "mem_total": (total / 2**20) if total else None,
            "power_w": None, "clock_mhz": None, "pstate": "",
        }
    return {"vendor": "", "name": "", "state": "unavailable"}


# -------------------------------------------------------------------------- disk

_prev_disk = None  # (t, read_sectors, write_sectors)


def physical_disks():
    return [os.path.basename(d) for d in glob.glob("/sys/block/*") if os.path.exists(os.path.join(d, "device"))]


def disk(mount):
    global _prev_disk
    out = {"mount": mount}
    try:
        st = os.statvfs(mount)
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - st.f_bfree * st.f_frsize
        out.update(total=total, used=used, free=free, percent=(100.0 * used / total) if total else None)
    except OSError:
        out.update(total=None, used=None, free=None, percent=None)

    disks = set(physical_disks())
    rd = wr = 0
    for line in (read("/proc/diskstats", "") or "").splitlines():
        p = line.split()
        if len(p) < 10 or p[2] not in disks:
            continue
        rd += int(p[5])
        wr += int(p[9])
    now = time.monotonic()
    if _prev_disk:
        dt = now - _prev_disk[0]
        if dt > 0:
            out["read_bps"] = max(0.0, (rd - _prev_disk[1]) * 512 / dt)
            out["write_bps"] = max(0.0, (wr - _prev_disk[2]) * 512 / dt)
    _prev_disk = (now, rd, wr)
    out["devices"] = sorted(disks)
    return out


# --------------------------------------------------------------------------- net

_prev_net = None  # (t, rx, tx)


def default_iface():
    for line in (read("/proc/net/route", "") or "").splitlines()[1:]:
        p = line.split()
        if len(p) > 1 and p[1] == "00000000":
            return p[0]
    return ""


def net():
    global _prev_net
    rx = tx = 0
    up = []
    for d in glob.glob("/sys/class/net/*"):
        name = os.path.basename(d)
        if name == "lo":
            continue
        if read(os.path.join(d, "operstate"), "") not in ("up", "unknown"):
            continue
        r = read_int(os.path.join(d, "statistics", "rx_bytes"), 0)
        t = read_int(os.path.join(d, "statistics", "tx_bytes"), 0)
        if r or t:
            up.append(name)
        rx += r or 0
        tx += t or 0
    now = time.monotonic()
    out = {"iface": default_iface(), "up": bool(up), "ifaces": sorted(up)}
    if _prev_net:
        dt = now - _prev_net[0]
        if dt > 0:
            out["rx_bps"] = max(0.0, (rx - _prev_net[1]) / dt)
            out["tx_bps"] = max(0.0, (tx - _prev_net[2]) / dt)
    _prev_net = (now, rx, tx)
    return out


# ----------------------------------------------------------------------- battery


def battery():
    for d in sorted(glob.glob("/sys/class/power_supply/BAT*")):
        cap = read_int(os.path.join(d, "capacity"))
        if cap is None:
            continue
        power = read_int(os.path.join(d, "power_now"))
        if power:
            power_w = power / 1e6
        else:
            v = read_int(os.path.join(d, "voltage_now"))
            i = read_int(os.path.join(d, "current_now"))
            power_w = (v * i / 1e12) if (v and i) else None
        return {
            "present": True,
            "capacity": cap,
            "status": read(os.path.join(d, "status"), "Unknown"),
            "power_w": power_w,
        }
    return {"present": False}


# ------------------------------------------------------------ temps and fans


def temps_and_fans(hw, cpu_info, gpu_info):
    """Curated sensor list in display order. Values are None when absent so the
    widget can hide the row. Labels are short and uppercase on purpose."""
    temps = []

    def add(id_, label, value, high=None, crit=None):
        temps.append({"id": id_, "label": label, "value": value, "high": high, "crit": crit})

    add("cpu", "CPU", cpu_info.get("temp"), cpu_info.get("temp_high"), cpu_info.get("temp_crit"))

    gtemp = gpu_info.get("temp") if gpu_info.get("state") in ("active", "idle") else None
    add("gpu", "GPU", gtemp, 83, 93)

    # NVMe composite
    nvme = None
    hi = cr = None
    for path in hw.get("nvme", []):
        for c in hwmon_channels(path, "temp"):
            if c["label"] == "Composite" or nvme is None:
                nvme, hi, cr = c["value"], high_of(c), c.get("crit")
                if c["label"] == "Composite":
                    break
        if nvme is not None:
            break
    add("nvme", "NVME", nvme, hi, cr)

    # Dell platform sensors (memory, ambient, video) via dell_ddv labels
    mem_t = amb = video = None
    ambients = []
    for path in hw.get("dell_ddv", []):
        for c in hwmon_channels(path, "temp"):
            lab = c["label"]
            if lab == "Memory":
                mem_t = c["value"]
            elif lab == "Ambient":
                ambients.append(c["value"])
            elif lab == "Video":
                video = c["value"]
    if ambients:
        amb = min(ambients)
    add("mem", "MEMORY", mem_t, 70, 85)
    if gtemp is None and video is not None:
        # dGPU asleep: Dell still reports the video sensor; surface it as GPU
        temps[1]["value"] = video
        temps[1]["source"] = "dell"

    wifi = None
    for path in hw.get("iwlwifi_1", []) + hw.get("iwlwifi", []):
        for c in hwmon_channels(path, "temp"):
            wifi = c["value"]
            break
    add("wifi", "WI-FI", wifi, 80, 95)
    add("ambient", "AMBIENT", amb, 45, 55)

    bat = None
    for path in hw.get("BAT0", []) + hw.get("BAT1", []):
        for c in hwmon_channels(path, "temp"):
            bat = c["value"]
            break
    add("battery", "BATTERY", bat, 45, 60)

    fans = []
    seen_max = {}
    for path in hw.get("dell_smm", []):
        for c in hwmon_channels(path, "fan"):
            if "max" in c:
                seen_max[c["n"]] = c["max"]
    fan_sources = hw.get("dell_ddv", []) or hw.get("dell_smm", []) or hw.get("thinkpad", []) or hw.get("asus", []) or hw.get("nct6775", [])
    for path in fan_sources:
        for c in hwmon_channels(path, "fan"):
            label = (c["label"] or f"FAN {c['n']}").upper()
            fans.append({
                "id": f"fan{c['n']}",
                "label": label,
                "rpm": c["value"],
                "max": c.get("max") or seen_max.get(c["n"]),
            })
        if fans:
            break
    return temps, fans


# -------------------------------------------------------------------------- main


def sample(interval, mount):
    hw = hwmon_devices()
    out = {"t": time.time(), "interval": interval, "errors": []}

    def section(name, fn, *args):
        try:
            out[name] = fn(*args)
        except Exception as e:  # noqa: BLE001 - one bad sensor must not kill the stream
            out[name] = None
            out["errors"].append(f"{name}: {e.__class__.__name__}: {e}")

    section("cpu", cpu, hw)
    section("mem", mem)
    section("gpu", gpu, interval)
    section("disk", disk, mount)
    section("net", net)
    section("battery", battery)
    try:
        temps, fans = temps_and_fans(hw, out.get("cpu") or {}, out.get("gpu") or {})
        out["temps"], out["fans"] = temps, fans
    except Exception as e:  # noqa: BLE001
        out["temps"], out["fans"] = [], []
        out["errors"].append(f"temps: {e.__class__.__name__}: {e}")
    try:
        out["uptime"] = float((read("/proc/uptime", "0 0") or "0 0").split()[0])
        out["load"] = [float(x) for x in (read("/proc/loadavg", "0 0 0") or "0 0 0").split()[:3]]
    except (ValueError, IndexError):
        out["uptime"], out["load"] = None, None
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--mount", default="/")
    ap.add_argument("--once", action="store_true", help="emit two samples (so rates are valid) and exit")
    args = ap.parse_args()
    interval = max(0.5, args.interval)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    # Prime the delta counters so the first visible sample already has rates.
    sample(interval, args.mount)
    time.sleep(min(1.0, interval))
    emitted = 0
    while True:
        started = time.monotonic()
        s = sample(interval, args.mount)
        try:
            sys.stdout.write(json.dumps(s, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            return
        emitted += 1
        if args.once and emitted >= 2:
            return
        time.sleep(max(0.1, interval - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
