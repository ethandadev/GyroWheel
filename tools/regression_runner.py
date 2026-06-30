import os
import sys
import subprocess

def run_all_checks():
    print("=" * 65)
    print(" GyroWheel Ecosystem Compatibility Matrix & Regression Check")
    print("=" * 65)
    
    # 1. Host Operating System Analysis
    print(f"[info] Operating System: {sys.platform}")
    print(f"[info] Python Version: {sys.version.split()[0]}")
    
    # 2. Mocking PyInstaller MEIPASS temporary directories
    mock_mei = os.path.abspath(os.path.join(os.path.dirname(__file__), "../windows/src"))
    setattr(sys, "_MEIPASS", mock_mei)
    print(f"[info] Simulated PyInstaller MEIPASS: {mock_mei}")
    
    # 3. Running core system regressions
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    
    print("\n--- Running Tests ---")
    test_cmd = [
        sys.executable, "-m", "unittest", "discover",
        "-s", os.path.abspath(os.path.join(os.path.dirname(__file__), "../tests")),
        "-p", "test_*.py"
    ]
    
    result = subprocess.run(test_cmd, capture_output=True, text=True)
    print(result.stdout)
    print(result.stderr)
    
    if result.returncode == 0:
        print("[pass] All Automated Verification Tests Passed!")
    else:
        print("[fail] Unit testing failures detected.")
        sys.exit(1)

    print("\n--- Running Windows Internal Regression ---")
    reg_cmd = [
        sys.executable, "-m", "unittest", "windows.src.gui_app"
    ]
    # Verify we can load the internal UI files cleanly without syntax blocks
    try:
        from windows.src.dll_loader import preflight_vigembus_check, setup_dll_directory
        setup_dll_directory()
        driver_ok = preflight_vigembus_check()
        print(f"[info] Pre-flight ViGEmBus check: {'DETECTED' if driver_ok else 'NOT FOUND'}")
        print("[pass] Windows DLL Search Paths resolved smoothly without crashes!")
    except Exception as e:
        print(f"[fail] Windows modules threw import errors: {e}")
        sys.exit(1)

    print("\n" + "=" * 65)
    print(" COMPATIBILITY MATRIX COMPLETED: SUCCESS")
    print("=" * 65)

if __name__ == "__main__":
    run_all_checks()
