import os
import sys
import json
import socket
import time
import threading
from typing import Dict, Any, Tuple

from .config import CONFIG, BUTTON_MAP
from .telemetry_parser import F125TelemetryParser

# Lazy import of vgamepad handles loading errors gracefully inside run loop
vgamepad = None

class SharedState:
    def __init__(self):
        self.lock = threading.Lock()
        self.steer = 0.0
        self.throttle = 0.0
        self.brake = 0.0
        self.buttons = {f"btn{i}": False for i in range(1, 31)}
        self.last_packet = 0.0

    def update(self, data: Dict[str, Any]):
        with self.lock:
            self.steer = max(-1.0, min(1.0, float(data.get("steer", 0.0))))
            self.throttle = max(0.0, min(1.0, float(data.get("throttle", 0.0))))
            self.brake = max(0.0, min(1.0, float(data.get("brake", 0.0))))
            incoming = data.get("buttons", {})
            if isinstance(incoming, dict):
                for name in self.buttons:
                    self.buttons[name] = bool(incoming.get(name, False))
            self.last_packet = time.time()

    def snapshot(self) -> Tuple[float, float, float, Dict[str, bool], float]:
        with self.lock:
            return (self.steer, self.throttle, self.brake, dict(self.buttons), self.last_packet)

class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.count = 0

    def tick(self):
        with self.lock:
            self.count += 1

    def take(self) -> int:
        with self.lock:
            n, self.count = self.count, 0
            return n

class ReceiverEngine:
    def __init__(self, port: int, on_error=None, on_speed_update=None):
        self.port = port
        self.on_error = on_error
        self.on_speed_update = on_speed_update
        self.state = SharedState()
        self.stats = Stats()
        
        self.running = False
        self.stop_event = threading.Event()
        self.sock = None
        self.tel_sock = None
        self.threads = []
        
        self.client_address = None
        self.telemetry = F125TelemetryParser()
        self.speed_kmh = 0.0
        self.telemetry_live = False
        self.last_telemetry_packet = 0.0

    def start(self):
        global vgamepad
        if vgamepad is None:
            import vgamepad as vg
            vgamepad = vg

        # Set up primary UDP Socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((CONFIG["host"], self.port))
        self.sock.settimeout(0.4)

        # Set up telemetry UDP Socket
        self.tel_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.tel_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.tel_sock.bind((CONFIG["host"], CONFIG["telemetry_port"]))
        except Exception as e:
            print(f"[warning] Could not bind telemetry port {CONFIG['telemetry_port']}: {e}")
        self.tel_sock.settimeout(0.4)

        self.stop_event.clear()
        self.running = True

        self.threads = [
            threading.Thread(target=self._recv_loop, daemon=True),
            threading.Thread(target=self._telemetry_loop, daemon=True),
            threading.Thread(target=self._input_loop, daemon=True),
            threading.Thread(target=self._heartbeat_loop, daemon=True)
        ]

        for t in self.threads:
            t.start()

    def stop(self):
        self.running = False
        self.stop_event.set()

        if self.sock:
            try:
                self.sock.close()
            except:
                pass
            self.sock = None

        if self.tel_sock:
            try:
                self.tel_sock.close()
            except:
                pass
            self.tel_sock = None

        for t in self.threads:
            t.join(timeout=1.0)
        self.threads = []

    def _recv_loop(self):
        while not self.stop_event.is_set():
            try:
                data, addr = self.sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                msg = json.loads(data.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            if "steer" in msg:
                self.client_address = addr
                self.state.update(msg)
                self.stats.tick()

    def _telemetry_loop(self):
        """Processes binary packets from racing games to compute haptics/grip scales."""
        telemetry_state = {"speed": 0.0, "throttle": 0.0, "brake": 0.0, "front_slip": 0.0, "rear_slip": 0.0}
        
        while not self.stop_event.is_set():
            try:
                data, _ = self.tel_sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            
            parsed = self.telemetry.parse_packet(data)
            if parsed:
                self.last_telemetry_packet = time.time()
                self.telemetry_live = True
                
                # Update rolling game telemetry state
                for k, v in parsed.items():
                    if k != "type":
                        telemetry_state[k] = v

                if parsed.get("type") == "telemetry":
                    self.speed_kmh = parsed.get("speed", 0.0)
                    if self.on_speed_update:
                        self.on_speed_update(self.speed_kmh, True)

                # Process tire dynamics to resolve wheel lockups or spins
                haptic_cue = self.telemetry.compute_haptics(telemetry_state)
                if haptic_cue and self.client_address and self.sock:
                    try:
                        self.sock.sendto(json.dumps(haptic_cue).encode("utf-8"), self.client_address)
                    except Exception as e:
                        print(f"[warning] Failed to send haptics back to client: {e}")

    def _input_loop(self):
        try:
            gamepad = vgamepad.VX360Gamepad()
        except Exception as e:
            if self.on_error:
                self.on_error(f"Failed to initialize Virtual Gamepad: {e}\nEnsure ViGEmBus is installed correctly.")
            return

        tick = 0.005
        while not self.stop_event.is_set():
            now = time.time()
            steer, throttle, brake, buttons, last = self.state.snapshot()

            if last == 0.0 or (now - last) > CONFIG["timeout"]:
                gamepad.reset()
                gamepad.update()
                time.sleep(tick)
                continue

            # Speed-sensitive steering calculation (adjust scale based on telemetry speed)
            speed_scale = 1.0
            if self.telemetry_live and self.speed_kmh > 5.0:
                speed_scale = 1.0 - (min(self.speed_kmh, 320.0) / 320.0) * 0.85
                speed_scale = max(0.12, min(speed_scale, 1.0))

            steer_val = int(steer * speed_scale * 32767)
            steer_val = max(-32768, min(32767, steer_val))
            gamepad.left_joystick(x_value=steer_val, y_value=0)

            gamepad.right_trigger(value=int(throttle * 255))
            gamepad.left_trigger(value=int(brake * 255))

            for name, is_pressed in buttons.items():
                mapped_btn = BUTTON_MAP.get(name)
                if mapped_btn:
                    if is_pressed:
                        gamepad.press_button(button=mapped_btn)
                    else:
                        gamepad.release_button(button=mapped_btn)

            gamepad.update()
            time.sleep(tick)

    def _heartbeat_loop(self):
        """10Hz monitor loop feeding current speed and status indicators back to phone."""
        while not self.stop_event.is_set():
            time.sleep(0.1)
            now = time.time()
            live = (now - self.last_telemetry_packet) < 2.0
            if not live:
                self.telemetry_live = False
                self.speed_kmh = 0.0
                if self.on_speed_update:
                    self.on_speed_update(0.0, False)

            if self.client_address and self.sock:
                # Calculate speed steering scale for the phone UI indicator
                speed_scale = 1.0
                if self.telemetry_live and self.speed_kmh > 5.0:
                    speed_scale = 1.0 - (min(self.speed_kmh, 320.0) / 320.0) * 0.85
                    speed_scale = max(0.12, min(speed_scale, 1.0))
                
                heartbeat_data = {
                    "haptic": "none",
                    "limit": round(speed_scale, 2)
                }
                try:
                    self.sock.sendto(json.dumps(heartbeat_data).encode("utf-8"), self.client_address)
                except:
                    pass
