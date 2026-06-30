import os
import sys

def preflight_vigembus_check() -> bool:
    """
    Registry pre-flight check to verify if the required ViGEmBus
    virtual game controller bus driver is installed on Windows.
    """
    if sys.platform != "win32":
        return True
    try:
        import winreg
        key_path = r"SYSTEM\CurrentControlSet\Services\ViGEmBus"
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_path, 0, winreg.KEY_READ):
            return True
    except FileNotFoundError:
        return False
    except Exception as e:
        print(f"[warning] Registry pre-flight check exception: {e}")
        return True # Fallback to True, try starting anyway

def setup_dll_directory():
    """
    Resolves and configures dynamic DLL loading directories. Prevents common
    PyInstaller temporary unpacking path issues for ViGEmClient.dll.
    """
    if sys.platform != "win32":
        return

    mei_dir = getattr(sys, '_MEIPASS', None)
    search_paths = []
    
    if mei_dir:
        search_paths.append(mei_dir)
        search_paths.append(os.path.join(mei_dir, "vgamepad", "win", "x64"))
    
    # Executable running directory
    exe_dir = os.path.dirname(sys.executable)
    search_paths.append(exe_dir)
    search_paths.append(os.path.dirname(os.path.abspath(__file__)))

    for path in search_paths:
        if path and os.path.exists(path):
            try:
                # Python 3.8+ Windows DLL directory loading API
                os.add_dll_directory(path)
            except AttributeError:
                # Fallback for older python or environment overrides
                os.environ["PATH"] = path + os.pathsep + os.environ["PATH"]
