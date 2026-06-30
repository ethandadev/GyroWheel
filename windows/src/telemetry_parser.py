import struct
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional

class TelemetryParser(ABC):
    @abstractmethod
    def parse_packet(self, data: bytes) -> Optional[Dict[str, Any]]:
        """Parses incoming telemetry buffer packets."""
        pass

    @abstractmethod
    def compute_haptics(self, state: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Computes vibration triggers based on dynamic threshold evaluations."""
        pass

class GenericTelemetryParser(TelemetryParser):
    def parse_packet(self, data: bytes) -> Optional[Dict[str, Any]]:
        return None

    def compute_haptics(self, state: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        return None

class F125TelemetryParser(TelemetryParser):
    """
    Decodes the standard Codemasters UDP binary buffer structure for F1 25.
    Provides speed-sensitive steering coefficients and dynamic lockup/wheelspin haptics.
    """
    def __init__(self):
        self.last_lockup = 0.0
        self.last_wheelspin = 0.0

    def parse_packet(self, data: bytes) -> Optional[Dict[str, Any]]:
        if len(data) < 24:
            return None
        
        # Format code (u16), packet ID (u8)
        fmt, _, _, _, _, packet_id = struct.unpack("<HBBBBB", data[:7])
        if fmt < 2024:
            return None

        # Car Telemetry Packet ID == 6
        if packet_id == 6:
            # Simple offset parsing to extract speed, throttle, and brake values
            # for the main player vehicle (usually index 0)
            if len(data) < 100:
                return None
            speed = struct.unpack("<H", data[29:31])[0]
            throttle = struct.unpack("<f", data[31:35])[0]
            brake = struct.unpack("<f", data[39:43])[0]
            return {
                "type": "telemetry",
                "speed": float(speed),
                "throttle": float(throttle),
                "brake": float(brake),
                "front_slip": 0.0,
                "rear_slip": 0.0
            }
        
        # Motion Extra Packet ID == 13 (contains tire slip ratios)
        elif packet_id == 13:
            if len(data) < 150:
                return None
            # Extract tire slip ratios
            rl, rr, fl, fr = struct.unpack("<ffff", data[93:109])
            return {
                "type": "motion",
                "front_slip": min(float(fl), float(fr)),
                "rear_slip": max(float(rl), float(rr))
            }
        
        return None

    def compute_haptics(self, state: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        import time
        now = time.time()
        
        # Wheel lockup / understeer check during braking
        if state.get("brake", 0.0) > 0.25 and state.get("front_slip", 0.0) < -0.18:
            if now - self.last_lockup > 0.12:
                self.last_lockup = now
                return {"haptic": "lockup", "intensity": 1.0}
                
        # Wheelspin check during throttle application
        if state.get("throttle", 0.0) > 0.35 and state.get("rear_slip", 0.0) > 0.20:
            if now - self.last_wheelspin > 0.15:
                self.last_wheelspin = now
                intensity = min(1.0, state.get("rear_slip", 0.0) / 0.6)
                return {"haptic": "wheelspin", "intensity": round(intensity, 2)}
                
        return None
