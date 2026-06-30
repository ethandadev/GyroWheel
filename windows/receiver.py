import sys
import os
import tkinter as tk

# Initialize dynamic DLL path resolving (handles unpacked PyInstaller locations)
from src.dll_loader import setup_dll_directory
setup_dll_directory()

from src.gui_app import GyroWheelApp

def main():
    root = tk.Tk()
    app = GyroWheelApp(root)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.stop(), root.destroy()))
    root.mainloop()

if __name__ == "__main__":
    main()
