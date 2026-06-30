import unittest
import struct
import sys
import os

# Insert workspace paths so we can import windows module code directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from windows.src.telemetry_parser import F125TelemetryParser

class TestF125TelemetryParser(unittest.TestCase):
    def setUp(self):
        self.parser = F125TelemetryParser()

    def test_invalid_and_short_packets_gracefully_ignored(self):
        # Empty or short inputs must return None to prevent decoder crashes
        self.assertIsNone(self.parser.parse_packet(b""))
        self.assertIsNone(self.parser.parse_packet(b"\x00" * 10))

    def test_parse_car_telemetry_packet(self):
        # Create a mock F1 25 Car Telemetry binary packet (ID == 6, FMT >= 2024)
        header = struct.pack("<HBBBBB", 2025, 1, 1, 1, 1, 6) # Format=2025, PacketID=6
        payload_padding = b"\x00" * 22 # Header padding up to offset 29
        telemetry_data = struct.pack("<Hfff", 180, 0.85, 0.10, 0.10) # Speed=180, Throttle=0.85, Brake=0.10
        mock_packet = header + payload_padding + telemetry_data + (b"\x00" * 100) # Pad to min len

        result = self.parser.parse_packet(mock_packet)
        self.assertIsNotNone(result)
        self.assertEqual(result["type"], "telemetry")
        self.assertEqual(result["speed"], 180.0)
        self.assertAlmostEqual(result["throttle"], 0.85, places=5)
        self.assertAlmostEqual(result["brake"], 0.10, places=5)

    def test_parse_motion_extra_packet(self):
        # Create a mock F1 25 Motion Ex binary packet (ID == 13, FMT >= 2024)
        header = struct.pack("<HBBBBB", 2025, 1, 1, 1, 1, 13) # Format=2025, PacketID=13
        payload_padding = b"\x00" * 86 # Header padding up to offset 93
        motion_data = struct.pack("<ffff", -0.05, 0.15, -0.22, -0.18) # RL, RR, FL, FR slip ratios
        mock_packet = header + payload_padding + motion_data + (b"\x00" * 100)

        result = self.parser.parse_packet(mock_packet)
        self.assertIsNotNone(result)
        self.assertEqual(result["type"], "motion")
        # front_slip is min(FL, FR) -> min(-0.22, -0.18) -> -0.22
        self.assertAlmostEqual(result["front_slip"], -0.22, places=5)
        # rear_slip is max(RL, RR) -> max(-0.05, 0.15) -> 0.15
        self.assertAlmostEqual(result["rear_slip"], 0.15, places=5)

    def test_compute_haptics_lockup_active(self):
        # Trigger wheel slip brake state
        state = {
            "brake": 0.80,
            "front_slip": -0.22, # Threshold is -0.18
            "throttle": 0.0,
            "rear_slip": 0.0
        }
        cue = self.parser.compute_haptics(state)
        self.assertIsNotNone(cue)
        self.assertEqual(cue["haptic"], "lockup")
        self.assertEqual(cue["intensity"], 1.0)

    def test_compute_haptics_wheelspin_active(self):
        # Trigger wheel spin throttle state
        state = {
            "brake": 0.0,
            "front_slip": 0.0,
            "throttle": 0.90,
            "rear_slip": 0.35 # Threshold is 0.20
        }
        cue = self.parser.compute_haptics(state)
        self.assertIsNotNone(cue)
        self.assertEqual(cue["haptic"], "wheelspin")
        # Intensity = min(1.0, slip / 0.6) -> min(1.0, 0.35 / 0.6) -> 0.58
        self.assertAlmostEqual(cue["intensity"], 0.58, places=2)

    def test_compute_haptics_inactive_below_thresholds(self):
        # Test inactive thresholds
        state = {
            "brake": 0.10,
            "front_slip": -0.05,
            "throttle": 0.20,
            "rear_slip": 0.05
        }
        self.assertIsNone(self.parser.compute_haptics(state))

if __name__ == "__main__":
    unittest.main()
