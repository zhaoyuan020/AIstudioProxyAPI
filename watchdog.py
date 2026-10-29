#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Watchdog for AIstudioProxyAPI.

Why: the proxy has NO self-healing. Once the page / browser / queue worker dies,
every later request returns 503 until a manual restart.

What this does:
  1. polls http://127.0.0.1:2048/health every CHECK_INTERVAL seconds
  2. treats 503 / connection failure / critical flags false as a failure
  3. after FAIL_THRESHOLD consecutive failures: kill leftovers, restart the service
  4. auth is loaded from auth_profiles/saved/main.json -> no manual login needed

All output is ASCII on purpose (cmd console codepage safety).
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
HEALTH_URL = "http://127.0.0.1:2048/health"
LOG_PATH = os.path.join(BASE, "logs", "watchdog.log")

CHECK_INTERVAL = 20
STARTUP_GRACE = 150
FAIL_THRESHOLD = 3
PORTS = (2048, 3120, 9222)

# --- log beacon detection ------------------------------------------------
# /health can still look OK while the page is alive-but-broken (page.is_closed()
# is only detected inside the request path). So we also watch the service log
# for fatal-looking markers and treat them as failures.
SERVICE_LOG = os.path.join(BASE, "logs", "watchdog_service.log")
BAD_MARKERS = (
    "page lost or not ready",
    "service_unavailable",
    "Service Unavailable",
    "Application startup failed",
    "worker task",
    "Worker task",
)
_log_pos = 0
_log_hits = 0


def log_offset_reset():
    global _log_pos, _log_hits
    try:
        _log_pos = os.path.getsize(SERVICE_LOG)
    except Exception:
        _log_pos = 0
    _log_hits = 0


def scan_log_beacons():
    """Return number of new fatal markers seen since the last scan."""
    global _log_pos, _log_hits
    try:
        size = os.path.getsize(SERVICE_LOG)
    except Exception:
        return 0
    if size < _log_pos:          # log rotated / truncated
        _log_pos = 0
    if size == _log_pos:
        return 0
    try:
        with open(SERVICE_LOG, "rb") as f:
            f.seek(_log_pos)
            chunk = f.read(size - _log_pos)
        _log_pos = size
        text = chunk.decode("utf-8", "replace")
    except Exception:
        return 0
    hits = 0
    for line in text.splitlines():
        for mk in BAD_MARKERS:
            if mk in line:
                hits += 1
                log("log beacon: %s" % line.strip()[:150])
                break
    _log_hits += hits
    return hits


def reset_log_hits():
    global _log_hits
    _log_hits = 0


def log(msg):
    line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print("  " + line, flush=True)
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8", errors="replace") as f:
            f.write(line + "\n")
    except Exception:
        pass


def health_state():
    """Return (ok: bool, reason: str)."""
    try:
        req = urllib.request.Request(HEALTH_URL, headers={"Cache-Control": "no-cache"})
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req, timeout=10) as r:
            if r.status != 200:
                return False, "http_%s" % r.status
            data = json.loads(r.read().decode("utf-8", "ignore"))
    except urllib.error.HTTPError as e:
        return False, "http_%s" % e.code
    except Exception as e:
        return False, "conn_err(%s)" % type(e).__name__

    det = data.get("details") or {}
    if det.get("is_initializing"):
        return False, "initializing"
    if not det.get("is_playwright_ready"):
        return False, "playwright_down"
    if not det.get("is_page_ready"):
        return False, "page_not_ready"
    if not det.get("is_browser_connected"):
        return False, "browser_down"
    if not det.get("workerRunning"):
        return False, "worker_down"
    return True, "ok"


def pids_on_port(port):
    pids = set()
    try:
        out = subprocess.run(
            ["netstat", "-ano"], capture_output=True, text=True,
            errors="replace", timeout=25,
        ).stdout
        for line in out.splitlines():
            if ("LISTENING" in line or "LISTEN" in line) and (":%d " % port) in line:
                parts = line.split()
                if parts and parts[-1].isdigit():
                    pids.add(parts[-1])
    except Exception as e:
        log("netstat failed for port %d: %s" % (port, e))
    return pids


def kill_everything():
    for port in PORTS:
        for pid in pids_on_port(port):
            try:
                subprocess.run(["taskkill", "/F", "/T", "/PID", pid],
                               capture_output=True, timeout=25)
                log("killed pid %s on port %d" % (pid, port))
            except Exception as e:
                log("kill pid %s failed: %s" % (pid, e))
    try:
        subprocess.run(["taskkill", "/F", "/IM", "camoufox.exe"],
                       capture_output=True, timeout=25)
        log("camoufox.exe cleared")
    except Exception:
        pass


def start_service():
    py = os.path.join(BASE, ".venv", "Scripts", "python.exe")
    if not os.path.isfile(py):
        log("FATAL: venv python not found: %s" % py)
        return None
    args = [py, "launch_camoufox.py", "--debug",
            "--active-auth-json", os.path.join("auth_profiles", "saved", "main.json")]
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    env["NO_PROXY"] = "127.0.0.1,localhost"
    env["no_proxy"] = "127.0.0.1,localhost"
    out_path = os.path.join(BASE, "logs", "watchdog_service.log")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    try:
        out = open(out_path, "a", encoding="utf-8", errors="replace")
        proc = subprocess.Popen(
            args, cwd=BASE, env=env,
            stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        )
        log("service started, pid=%d, log=%s" % (proc.pid, out_path))
        return proc
    except Exception as e:
        log("FATAL: cannot start service: %s" % e)
        return None


def wait_until_ready(grace):
    deadline = time.time() + grace
    while time.time() < deadline:
        ok, reason = health_state()
        if ok:
            log("service is ready")
            return True
        time.sleep(5)
    log("service NOT ready after %ds (last: %s)" % (grace, reason))
    return False


def main():
    log("=" * 60)
    log("watchdog started | interval=%ds threshold=%d" % (CHECK_INTERVAL, FAIL_THRESHOLD))

    proc = None
    ok, reason = health_state()
    if ok:
        log("existing healthy service detected, attaching (no restart)")
    else:
        log("no healthy service (%s), starting one" % reason)
        kill_everything()
        proc = start_service()
        if proc is None:
            return 1
        wait_until_ready(STARTUP_GRACE)

    log_offset_reset()
    fails = 0
    while True:
        time.sleep(CHECK_INTERVAL)
        ok, reason = health_state()
        beacons = scan_log_beacons()

        if ok and beacons == 0:
            if fails:
                log("recovered (was %d fails)" % fails)
            fails = 0
            reset_log_hits()
            continue

        if ok and beacons:
            reason = "log_beacon_x%d" % beacons

        fails += 1
        log("FAIL %d/%d: %s" % (fails, FAIL_THRESHOLD, reason))

        if fails < FAIL_THRESHOLD:
            continue

        log("threshold reached -> restarting service")
        kill_everything()
        time.sleep(3)
        proc = start_service()
        fails = 0
        reset_log_hits()
        log_offset_reset()
        if proc is None:
            log("restart failed, retry in 60s")
            time.sleep(60)
            continue
        wait_until_ready(STARTUP_GRACE)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("watchdog stopped by user")
