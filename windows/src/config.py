import sys

# High-frequency UDP packet loop parameters
CONFIG = {
    "host": "0.0.0.0",
    "port": 5005,
    "timeout": 0.5,
    "telemetry_port": 20777,
}

# 1:1 Parity with iOS/Android button layouts
BUTTON_MAP = {
    "btn1": 0x1000,   # XUSB_GAMEPAD_A (A)
    "btn2": 0x2000,   # XUSB_GAMEPAD_B (B)
    "btn3": 0x4000,   # XUSB_GAMEPAD_X (X)
    "btn4": 0x8000,   # XUSB_GAMEPAD_Y (Y)
    "btn5": 0x0100,   # XUSB_GAMEPAD_LEFT_SHOULDER (LB)
    "btn6": 0x0200,   # XUSB_GAMEPAD_RIGHT_SHOULDER (RB)
    "btn7": 0x0040,   # XUSB_GAMEPAD_LEFT_THUMB (L3)
    "btn8": 0x0080,   # XUSB_GAMEPAD_RIGHT_THUMB (R3)
    "btn9": 0x0020,   # XUSB_GAMEPAD_BACK (Back / Select)
    "btn10": 0x0010,  # XUSB_GAMEPAD_START (Start)
    "btn11": 0x0001,  # XUSB_GAMEPAD_DPAD_UP (Up)
    "btn12": 0x0002,  # XUSB_GAMEPAD_DPAD_DOWN (Down)
    "btn13": 0x0004,  # XUSB_GAMEPAD_DPAD_LEFT (Left)
    "btn14": 0x0008,  # XUSB_GAMEPAD_DPAD_RIGHT (Right)
    # Mapping for extra macro buttons (btn15 - btn30) to preserve client parity
    **{f"btn{i}": None for i in range(15, 31)}
}
