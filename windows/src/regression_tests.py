import os
import sys
import unittest

# Ensure the module can be run directly as a standard standalone file
if __name__ == "__main__" and __package__ is None:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
    __package__ = "windows.src"

from .dll_loader import preflight_vigembus_check, setup_dll_directory
from .telemetry_parser import F125TelemetryParser

class TestReceiverInfrastructure(unittest.TestCase):
    def test_preflight_checks(self):
        """Verifies driver diagnostic checks are reliable across host operating systems."""
        result = preflight_vigembus_check()
        # Should return a valid boolean response
        self.assertIn(result, [True, False])

    def test_setup_dll_directories(self):
        """Validates that DLL loading directories are injected without faults."""
        try:
            setup_dll_directory()
            success = True
        except Exception as e:
            success = False
            print(f"setup_dll_directory failure: {e}")
        self.assertTrue(success)

    def test_telemetry_parser_empty(self):
        """Ensures the parsing sequence fails gracefully with empty buffers."""
        parser = F125TelemetryParser()
        self.assertIsNone(parser.parse_packet(b""))
        self.assertIsNone(parser.compute_haptics({}))

if __name__ == "__main__":
    unittest.main()
