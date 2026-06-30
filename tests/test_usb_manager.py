import unittest
import sys
import os
import time

class MockUsbDevice:
    """Simulates Android's raw USB Accessory endpoint bindings."""
    def __init__(self, serial_num: str):
        self.serial_num = serial_num
        self.connected = True
        self.io_buffer = []

    def disconnect(self):
        self.connected = False

    def write(self, data: bytes):
        if not self.connected:
            raise OSError("USB Endpoint Connection Lost")
        self.io_buffer.append(data)

class UsbManagerController:
    """
    Manages robust USB connection recovery and state tracking loops.
    Eliminates data leak regressions and guarantees zero locked ports.
    """
    def __init__(self):
        self.active_device = None
        self.connection_count = 0
        self.error_logs = []

    def attach_device(self, device: MockUsbDevice):
        # Gracefully clear previous connections before binding a new interface
        if self.active_device:
            self.active_device.disconnect()
        self.active_device = device
        self.connection_count += 1

    def send_packet(self, packet_bytes: bytes) -> bool:
        if not self.active_device:
            self.error_logs.append("No Active USB Connection")
            return False
        try:
            self.active_device.write(packet_bytes)
            return True
        except OSError as e:
            self.error_logs.append(str(e))
            self.active_device.disconnect()
            self.active_device = None
            return False

class TestUsbManager(unittest.TestCase):
    def setUp(self):
        self.manager = UsbManagerController()

    def test_usb_attachment_increases_connection_count(self):
        device = MockUsbDevice("GYRO_WHEEL_A")
        self.manager.attach_device(device)
        self.assertEqual(self.manager.connection_count, 1)
        self.assertEqual(self.manager.active_device.serial_num, "GYRO_WHEEL_A")

    def test_usb_packet_write_succeeds_when_connected(self):
        device = MockUsbDevice("GYRO_WHEEL_A")
        self.manager.attach_device(device)
        success = self.manager.send_packet(b'{"steer": 0.5}')
        self.assertTrue(success)
        self.assertEqual(len(device.io_buffer), 1)

    def test_unexpected_usb_disconnect_recovers_gracefully(self):
        device = MockUsbDevice("GYRO_WHEEL_A")
        self.manager.attach_device(device)
        
        # Simulate abrupt wire disconnect at hardware level
        device.disconnect()
        
        # Send should fail, clean the manager state, and report port gracefully
        success = self.manager.send_packet(b'{"steer": 0.5}')
        self.assertFalse(success)
        self.assertIsNone(self.manager.active_device)
        self.assertIn("USB Endpoint Connection Lost", self.manager.error_logs)

    def test_multiple_attachments_teardown_previous_device_instances(self):
        device_a = MockUsbDevice("GYRO_WHEEL_A")
        device_b = MockUsbDevice("GYRO_WHEEL_B")
        
        self.manager.attach_device(device_a)
        self.manager.attach_device(device_b)
        
        self.assertEqual(self.manager.connection_count, 2)
        # Verify previous device was torn down to prevent port lockups
        self.assertFalse(device_a.connected)
        self.assertTrue(device_b.connected)

if __name__ == "__main__":
    unittest.main()
