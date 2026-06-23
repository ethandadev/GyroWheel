#!/usr/bin/env python3
"""
GyroWheel — macOS receiver (keyboard / mouse emulation)
=======================================================

The "works today" path: no DriverKit, no entitlements — just Accessibility
permission. Receives the iOS app's 60 Hz InputPacket over UDP and drives the
game with synthesized keyboard / mouse input via pynput (Quartz/CoreGraphics
under the hood).

Steering options (CONFIG["steer_mode"]):
  "keyboard" — proportional A/D via ~20 Hz software PWM (duty cycle == |steer|)
  "mouse"    — relative mouse movement (for mouse-steered games)

Run:   python3 receiver.py
Stop:  Ctrl+C   (all held keys released cleanly)

macOS permission: System Settings → Privacy & Security → Accessibility →
enable your terminal app (or Python). Otherwise key presses are silently dropped.

Packet (from the phone):
  {"steer": -1..1, "throttle": 0..1, "brake": 0..1,
   "buttons": {"btn1": bool, "btn2": bool, "btn3": bool, "btn4": bool}}
"""

import json
import socket
import subprocess
import sys
import threading
import time

try:
    from pynput.keyboard import Controller as KeyboardController, Key
    from pynput.mouse import Controller as MouseController
except ImportError:
    print("Missing dependency 'pynput'.  Install with:  pip3 install -r requirements.txt")
    sys.exit(1)


# --------------------------------------------------------------------------- #
#  Configuration — edit to taste
# --------------------------------------------------------------------------- #
CONFIG = {
    "host": "0.0.0.0",
    "port": 5005,

    "steer_mode": "keyboard",      # "keyboard" or "mouse"
    "steer_left_key": "a",
    "steer_right_key": "d",
    "throttle_key": "w",
    "brake_key": "s",

    # btnN -> key (first 8 mapped; btn9..btn30 unmapped by default — set as needed).
    # The keyboard path can't meaningfully use 30 distinct keys, so extras are "".
    "buttons": {
        **{"btn1": "space", "btn2": "shift", "btn3": "e", "btn4": "q",
           "btn5": "f", "btn6": "r", "btn7": "c", "btn8": "v"},
        **{f"btn{i}": "" for i in range(9, 31)},
    },

    "deadzone": 0.05,              # ignore |steer| below this
    "throttle_threshold": 0.10,
    "brake_threshold": 0.10,

    # Analog pedals: PWM the throttle/brake keys by value (feathering).
    # False = simple threshold hold.
    "analog_pedals": False,

    "pwm_period": 0.05,            # s; ~20 Hz proportional-steering window
    "loop_tick": 0.003,           # s; input worker resolution (~330 Hz)
    "mouse_sensitivity": 1500.0,  # px/sec at full lock (mouse mode)

    "timeout": 0.5,               # s; release everything if packets stop
}


# --------------------------------------------------------------------------- #
#  Key-name resolution
# --------------------------------------------------------------------------- #
SPECIAL_KEYS = {
    "space": Key.space, "shift": Key.shift, "shift_r": Key.shift_r,
    "ctrl": Key.ctrl, "control": Key.ctrl, "alt": Key.alt, "option": Key.alt,
    "cmd": Key.cmd, "command": Key.cmd, "enter": Key.enter, "return": Key.enter,
    "tab": Key.tab, "esc": Key.esc, "escape": Key.esc,
    "backspace": Key.backspace, "delete": Key.delete,
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
    "f1": Key.f1, "f2": Key.f2, "f3": Key.f3, "f4": Key.f4, "f5": Key.f5, "f6": Key.f6,
}


def resolve_key(name):
    if not name:
        return None
    n = name.strip().lower()
    if n in SPECIAL_KEYS:
        return SPECIAL_KEYS[n]
    if len(n) == 1:
        return n
    return None


def clampf(value, lo, hi):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return lo
    return max(lo, min(hi, value))


# --------------------------------------------------------------------------- #
#  Key manager — idempotent press/release reconciliation
# --------------------------------------------------------------------------- #
class KeyManager:
    """Holds exactly the requested key set each tick (no double-press / leaks)."""

    def __init__(self):
        self.kb = KeyboardController()
        self.mouse = MouseController()
        self._held = set()

    def reconcile(self, desired):
        for name in list(self._held - desired):
            self._release(name)
        for name in (desired - self._held):
            self._press(name)

    def _press(self, name):
        key = resolve_key(name)
        if key is None:
            return
        try:
            self.kb.press(key)
            self._held.add(name)
        except Exception as exc:
            print(f"[warn] press '{name}': {exc}")

    def _release(self, name):
        self._held.discard(name)
        key = resolve_key(name)
        if key is None:
            return
        try:
            self.kb.release(key)
        except Exception as exc:
            print(f"[warn] release '{name}': {exc}")

    def release_all(self):
        for name in list(self._held):
            self._release(name)


# --------------------------------------------------------------------------- #
#  Shared state
# --------------------------------------------------------------------------- #
class SharedState:
    def __init__(self):
        self.lock = threading.Lock()
        self.steer = 0.0
        self.throttle = 0.0
        self.brake = 0.0
        self.buttons = {f"btn{i}": False for i in range(1, 31)}
        self.last_packet = 0.0

    def update(self, data):
        with self.lock:
            self.steer = clampf(data.get("steer", 0.0), -1.0, 1.0)
            self.throttle = clampf(data.get("throttle", 0.0), 0.0, 1.0)
            self.brake = clampf(data.get("brake", 0.0), 0.0, 1.0)
            incoming = data.get("buttons", {})
            if isinstance(incoming, dict):
                for name in self.buttons:
                    self.buttons[name] = bool(incoming.get(name, False))
            self.last_packet = time.time()

    def snapshot(self):
        with self.lock:
            return (self.steer, self.throttle, self.brake,
                    dict(self.buttons), self.last_packet)


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.count = 0

    def tick(self):
        with self.lock:
            self.count += 1

    def take(self):
        with self.lock:
            n, self.count = self.count, 0
            return n


# --------------------------------------------------------------------------- #
#  Threads
# --------------------------------------------------------------------------- #
def recv_loop(sock, state, stats, stop):
    while not stop.is_set():
        try:
            data, _addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            msg = json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            continue
        if "steer" in msg:
            state.update(msg)
            stats.tick()


def input_loop(state, keys, stop):
    period = CONFIG["pwm_period"]
    tick = CONFIG["loop_tick"]
    deadzone = CONFIG["deadzone"]
    mouse_accum = 0.0

    while not stop.is_set():
        now = time.time()
        steer, throttle, brake, buttons, last = state.snapshot()

        # Failsafe: stale data -> release everything.
        if last == 0.0 or (now - last) > CONFIG["timeout"]:
            keys.reconcile(set())
            mouse_accum = 0.0
            time.sleep(tick)
            continue

        desired = set()

        # ---- Steering ----
        if CONFIG["steer_mode"] == "mouse":
            if abs(steer) > deadzone:
                mouse_accum += steer * CONFIG["mouse_sensitivity"] * tick
                step = int(mouse_accum)
                if step != 0:
                    keys.mouse.move(step, 0)
                    mouse_accum -= step
            else:
                mouse_accum = 0.0
        else:
            magnitude = abs(steer)
            if magnitude > deadzone:
                phase = (now % period) / period
                if phase < magnitude:
                    desired.add(CONFIG["steer_right_key"] if steer > 0
                                else CONFIG["steer_left_key"])

        # ---- Throttle / Brake ----
        if CONFIG["analog_pedals"]:
            phase = (now % period) / period
            if throttle > CONFIG["throttle_threshold"] and phase < throttle:
                desired.add(CONFIG["throttle_key"])
            if brake > CONFIG["brake_threshold"] and phase < brake:
                desired.add(CONFIG["brake_key"])
        else:
            if throttle > CONFIG["throttle_threshold"]:
                desired.add(CONFIG["throttle_key"])
            if brake > CONFIG["brake_threshold"]:
                desired.add(CONFIG["brake_key"])

        # ---- Buttons ----
        for name, pressed in buttons.items():
            if pressed:
                key = CONFIG["buttons"].get(name)
                if key:
                    desired.add(key)

        keys.reconcile(desired)
        time.sleep(tick)


def report_loop(state, stats, stop):
    while not stop.wait(1.0):
        hz = stats.take()
        steer, throttle, brake, buttons, last = state.snapshot()
        live = bool(last) and (time.time() - last) < CONFIG["timeout"]
        flag = "LIVE" if live else "----"
        pressed = [name for name, value in buttons.items() if value]
        print(f"[{flag}] {hz:3d} Hz | steer {steer:+.2f} | "
              f"thr {throttle:.2f} | brk {brake:.2f} | btns {pressed}")


# --------------------------------------------------------------------------- #
#  Main
# --------------------------------------------------------------------------- #
def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind((CONFIG["host"], CONFIG["port"]))
    except OSError as exc:
        print(f"Could not bind UDP port {CONFIG['port']}: {exc}")
        sys.exit(1)
    sock.settimeout(0.4)

    state = SharedState()
    keys = KeyManager()
    stats = Stats()
    stop = threading.Event()

    # Advertise over Bonjour so the phone can auto-discover this Mac.
    bonjour = None
    try:
        svc_name = f"GyroWheel — {socket.gethostname().split('.')[0]}"
        bonjour = subprocess.Popen(
            ["dns-sd", "-R", svc_name, "_gyrowheel._udp", ".", str(CONFIG["port"])],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, ValueError):
        bonjour = None

    threads = [
        threading.Thread(target=recv_loop, args=(sock, state, stats, stop), daemon=True),
        threading.Thread(target=input_loop, args=(state, keys, stop), daemon=True),
        threading.Thread(target=report_loop, args=(state, stats, stop), daemon=True),
    ]

    print("=" * 60)
    print(" GyroWheel receiver (keyboard / mouse)")
    print(f"  Listening on UDP port {CONFIG['port']}")
    print(f"  Enter this IP on the phone:  {local_ip()}")
    print(f"  Steering mode: {CONFIG['steer_mode']}")
    print("  Ctrl+C to quit (keys auto-released).")
    print("=" * 60)

    for t in threads:
        t.start()

    try:
        while not stop.is_set():
            time.sleep(0.3)
    except KeyboardInterrupt:
        print("\nShutting down…")
    finally:
        stop.set()
        keys.release_all()
        if bonjour is not None:
            bonjour.terminate()
        try:
            sock.close()
        except OSError:
            pass
        for t in threads:
            t.join(timeout=1.0)
        print("Done.")


if __name__ == "__main__":
    main()
