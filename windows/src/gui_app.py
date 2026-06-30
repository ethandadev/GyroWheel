import socket
import sys
import tkinter as tk
from tkinter import ttk, messagebox
import threading

from .config import CONFIG
from .dll_loader import preflight_vigembus_check
from .receiver_core import ReceiverEngine

try:
    from zeroconf import ServiceInfo, Zeroconf
    has_zeroconf = True
except ImportError:
    has_zeroconf = False

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
        self.root.geometry("460x420")
        self.root.resizable(False, False)

        self.ip_addr = local_ip()
        self.zc = None
        self.engine = None
        
        self.running = False
        self.current_hz = 0
        self.speed_kmh = 0.0
        self.telemetry_live = False

        self.setup_ui()
        self._preflight_driver_check()
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

        ttk.Label(conn_frame, text=self.ip_addr, style="IP.TLabel").pack(anchor=tk.W)
        
        port_frame = ttk.Frame(conn_frame)
        port_frame.pack(fill=tk.X, pady=(5, 0))
        ttk.Label(port_frame, text="Port:").pack(side=tk.LEFT)
        self.port_var = tk.StringVar(value=str(CONFIG["port"]))
        self.port_entry = ttk.Entry(port_frame, textvariable=self.port_var, width=10)
        self.port_entry.pack(side=tk.LEFT, padx=(5, 0))

        # Telemetry Box
        tel_frame = ttk.LabelFrame(main_frame, text="F1 Telemetry Status", padding="10")
        tel_frame.pack(fill=tk.X, pady=(0, 15))
        self.tel_var = tk.StringVar(value="Waiting — configure F1 25 UDP to 127.0.0.1:20777")
        ttk.Label(tel_frame, textvariable=self.tel_var).pack(anchor=tk.W)

        # Controls Button Layout
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.start_btn = ttk.Button(btn_frame, text="Start", command=self.toggle_start)
        self.start_btn.pack(side=tk.LEFT)
        
        ttk.Button(btn_frame, text="Setup help", command=self.show_help).pack(side=tk.LEFT, padx=(10, 0))

    def _preflight_driver_check(self):
        """Issues warnings to UI if registry missing ViGEmBus kernel driver."""
        if not preflight_vigembus_check():
            msg = (
                "ViGEmBus Driver Not Detected!\n\n"
                "GyroWheel requires the ViGEmBus controller driver to create virtual Xbox pads.\n"
                "Please download and install it here:\n"
                "https://github.com/ViGEm/ViGEmBus/releases"
            )
            messagebox.showwarning("Driver Missing", msg)

    def show_help(self):
        msg = (
            "1. Put this PC and your phone on the same Wi-Fi.\n"
            "2. Press Start. This requires ViGEmBus to create a virtual Xbox 360 controller.\n"
            "3. On your phone, open GyroWheel, tap Settings, and enter the IP and port shown.\n"
            "4. In F1 25, enable UDP Telemetry and point it to 127.0.0.1 port 20777."
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

        # Initialize the core loop network engine
        self.engine = ReceiverEngine(
            port=port,
            on_error=self.on_engine_error,
            on_speed_update=self.on_speed_update
        )

        try:
            self.engine.start()
        except OSError as exc:
            messagebox.showerror("Error", f"Could not bind UDP port {port}: {exc}")
            return

        if has_zeroconf:
            try:
                hostname = socket.gethostname()
                ip_bytes = socket.inet_aton(self.ip_addr)
                info = ServiceInfo(
                    "_gyrowheel._udp.local.",
                    f"GyroWheel — {hostname}._gyrowheel._udp.local.",
                    addresses=[ip_bytes],
                    port=port,
                    properties={},
                    server=f"{hostname}.local.",
                )
                self.zc = Zeroconf()
                self.zc.register_service(info)
            except Exception as e:
                print(f"Bonjour/Zeroconf registration failed: {e}")

        self.running = True
        self.start_btn.config(text="Stop")
        self.status_var.set("Virtual gamepad active · listening")
        self.port_entry.config(state="disabled")

    def stop(self):
        self.running = False
        
        if self.zc is not None:
            self.zc.unregister_all_services()
            self.zc.close()
            self.zc = None
            
        if self.engine:
            self.engine.stop()
            self.engine = None
            
        self.start_btn.config(text="Start")
        self.status_var.set("Idle — press Start")
        self.hz_var.set("")
        self.tel_var.set("Waiting — configure F1 25 UDP to 127.0.0.1:20777")
        self.port_entry.config(state="normal")
        self.current_hz = 0
        self.telemetry_live = False

    def on_engine_error(self, message):
        """Thread-safe error reporting callback from receiver core."""
        self.root.after(0, lambda: messagebox.showerror("Engine Error", message))
        self.root.after(0, self.stop)

    def on_speed_update(self, speed, live):
        self.speed_kmh = speed
        self.telemetry_live = live

    def update_ui_loop(self):
        if self.running and self.engine:
            hz = self.engine.stats.take()
            self.hz_var.set(f"{hz} Hz")
            
            if self.telemetry_live:
                self.tel_var.set(f"F1 25 Telemetry: Active · {int(self.speed_kmh)} km/h · Speed-steering + Haptics active")
            else:
                self.tel_var.set("F1 25 Telemetry: Waiting — configure UDP to 127.0.0.1:20777")
                
        self.root.after(1000, self.update_ui_loop)
