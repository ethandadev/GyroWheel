import json
import socket
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

try:
    import vgamepad as vg
except ImportError:
    print("Missing dependency 'vgamepad'. Install with: pip install vgamepad")
    sys.exit(1)

try:
    from zeroconf import ServiceInfo, Zeroconf
    has_zeroconf = True
except ImportError:
    has_zeroconf = False

CONFIG = {
    "host": "0.0.0.0",
    "port": 5005,
    "timeout": 0.5,
}

BUTTON_MAP = {
    "btn1": vg.XUSB_BUTTON.XUSB_GAMEPAD_A,
    "btn2": vg.XUSB_BUTTON.XUSB_GAMEPAD_B,
    "btn3": vg.XUSB_BUTTON.XUSB_GAMEPAD_X,
    "btn4": vg.XUSB_BUTTON.XUSB_GAMEPAD_Y,
    "btn5": vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER,
    "btn6": vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER,
    "btn7": vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_THUMB,
    "btn8": vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_THUMB,
    "btn9": vg.XUSB_BUTTON.XUSB_GAMEPAD_BACK,
    "btn10": vg.XUSB_BUTTON.XUSB_GAMEPAD_START,
}

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
            self.steer = max(-1.0, min(1.0, float(data.get("steer", 0.0))))
            self.throttle = max(0.0, min(1.0, float(data.get("throttle", 0.0))))
            self.brake = max(0.0, min(1.0, float(data.get("brake", 0.0))))
            incoming = data.get("buttons", {})
            if isinstance(incoming, dict):
                for name in self.buttons:
                    self.buttons[name] = bool(incoming.get(name, False))
            self.last_packet = time.time()

    def snapshot(self):
        with self.lock:
            return (self.steer, self.throttle, self.brake, dict(self.buttons), self.last_packet)

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

def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


class GyroWheelApp:
    def __init__(self, root):
        self.root = root
        self.root.title("GyroWheel Receiver")
        self.root.geometry("450x400")
        self.root.resizable(False, False)

        self.running = False
        self.sock = None
        self.state = SharedState()
        self.stats = Stats()
        self.stop_event = threading.Event()
        self.threads = []
        self.zc = None
        
        self.current_hz = 0

        self.setup_ui()
        self.update_ui_loop()

    def setup_ui(self):
        style = ttk.Style()
        style.configure("TLabel", font=("Segoe UI", 10))
        style.configure("Title.TLabel", font=("Segoe UI", 16, "bold"))
        style.configure("IP.TLabel", font=("Consolas", 20, "bold"))

        main_frame = ttk.Frame(self.root, padding="20 20 20 20")
        main_frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(main_frame, text="GyroWheel Receiver", style="Title.TLabel").pack(anchor=tk.W, pady=(0, 15))

        # Status Box
        status_frame = ttk.LabelFrame(main_frame, text="Status", padding="10")
        status_frame.pack(fill=tk.X, pady=(0, 15))
        
        self.status_var = tk.StringVar(value="Idle — press Start")
        self.hz_var = tk.StringVar(value="")
        
        status_inner = ttk.Frame(status_frame)
        status_inner.pack(fill=tk.X)
        
        self.status_lbl = ttk.Label(status_inner, textvariable=self.status_var)
        self.status_lbl.pack(side=tk.LEFT)
        ttk.Label(status_inner, textvariable=self.hz_var, foreground="gray").pack(side=tk.RIGHT)

        # Connection Box
        conn_frame = ttk.LabelFrame(main_frame, text="On your phone, enter", padding="10")
        conn_frame.pack(fill=tk.X, pady=(0, 15))

        self.ip_addr = local_ip()
        ttk.Label(conn_frame, text=self.ip_addr, style="IP.TLabel").pack(anchor=tk.W)
        
        port_frame = ttk.Frame(conn_frame)
        port_frame.pack(fill=tk.X, pady=(5, 0))
        ttk.Label(port_frame, text="Port:").pack(side=tk.LEFT)
        self.port_var = tk.StringVar(value=str(CONFIG["port"]))
        self.port_entry = ttk.Entry(port_frame, textvariable=self.port_var, width=10)
        self.port_entry.pack(side=tk.LEFT, padx=(5, 0))

        # Start/Stop Button
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.start_btn = ttk.Button(btn_frame, text="Start", command=self.toggle_start)
        self.start_btn.pack(side=tk.LEFT)
        
        ttk.Button(btn_frame, text="Setup help", command=self.show_help).pack(side=tk.LEFT, padx=(10, 0))

    def show_help(self):
        msg = (
            "1. Put this PC and your phone on the same Wi-Fi.\n"
            "2. Press Start. This requires ViGEmBus to create a virtual Xbox 360 controller.\n"
            "3. On your phone, open GyroWheel, tap Settings, and enter the IP and port shown.\n"
            "4. Start your game. It will detect an Xbox 360 controller."
        )
        messagebox.showinfo("Setup Help", msg)

    def toggle_start(self):
        if self.running:
            self.stop()
        else:
            self.start()

    def start(self):
        try:
            port = int(self.port_var.get())
            CONFIG["port"] = port
        except ValueError:
            messagebox.showerror("Error", "Invalid port number.")
            return

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.sock.bind((CONFIG["host"], CONFIG["port"]))
        except OSError as exc:
            messagebox.showerror("Error", f"Could not bind UDP port {CONFIG['port']}: {exc}")
            return
        self.sock.settimeout(0.4)

        self.stop_event.clear()
        
        if has_zeroconf:
            try:
                hostname = socket.gethostname()
                ip_bytes = socket.inet_aton(self.ip_addr)
                info = ServiceInfo(
                    "_gyrowheel._udp.local.",
                    f"GyroWheel — {hostname}._gyrowheel._udp.local.",
                    addresses=[ip_bytes],
                    port=CONFIG["port"],
                    properties={},
                    server=f"{hostname}.local.",
                )
                self.zc = Zeroconf()
                self.zc.register_service(info)
            except Exception as e:
                print(f"Bonjour/Zeroconf registration failed: {e}")

        self.threads = [
            threading.Thread(target=self.recv_loop, daemon=True),
            threading.Thread(target=self.input_loop, daemon=True),
            threading.Thread(target=self.report_loop, daemon=True),
        ]
        
        for t in self.threads:
            t.start()
            
        self.running = True
        self.start_btn.config(text="Stop")
        self.status_var.set("Virtual gamepad active · listening")
        self.port_entry.config(state="disabled")

    def stop(self):
        self.running = False
        self.stop_event.set()
        
        if self.zc is not None:
            self.zc.unregister_all_services()
            self.zc.close()
            self.zc = None
            
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
            self.sock = None
            
        for t in self.threads:
            t.join(timeout=1.0)
            
        self.start_btn.config(text="Start")
        self.status_var.set("Idle — press Start")
        self.hz_var.set("")
        self.port_entry.config(state="normal")
        self.current_hz = 0

    def recv_loop(self):
        while not self.stop_event.is_set():
            try:
                data, _addr = self.sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                msg = json.loads(data.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            if "steer" in msg:
                self.state.update(msg)
                self.stats.tick()

    def input_loop(self):
        try:
            gamepad = vg.VX360Gamepad()
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Error", f"Failed to init vgamepad: {e}\nEnsure ViGEmBus is installed."))
            self.root.after(0, self.stop)
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

            steer_val = int(steer * 32767)
            if steer_val < -32768: steer_val = -32768
            if steer_val > 32767: steer_val = 32767
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

    def report_loop(self):
        while not self.stop_event.wait(1.0):
            hz = self.stats.take()
            self.current_hz = hz

    def update_ui_loop(self):
        if self.running:
            self.hz_var.set(f"{self.current_hz} Hz")
        self.root.after(1000, self.update_ui_loop)

def main():
    root = tk.Tk()
    app = GyroWheelApp(root)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.stop(), root.destroy()))
    root.mainloop()

if __name__ == "__main__":
    main()
