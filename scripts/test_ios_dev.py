"""Audit boot isolation must retain existing devices/data and leave normal runs alone."""
import json
import unittest
from unittest.mock import patch
import ios_dev


class SimulatorBootTests(unittest.TestCase):
    def calls_for(self, fresh_boot, state="Booted"):
        device_type = ios_dev.DEVICE_TYPES["se"][1]
        runtimes = {"runtimes": [
            {"identifier": "ios27", "name": "iOS 27", "version": "27.0", "isAvailable": True,
             "supportedDeviceTypes": [{"identifier": device_type}]},
            {"identifier": "duo27", "name": "iOS 27.1", "version": "27.1", "isAvailable": True,
             "supportedDeviceTypes": [{"identifier": "duo-only"}]},
        ]}
        devices = {"devices": {"ios27": [{"name": ios_dev.DEVICE_TYPES["se"][0], "udid": "existing-se", "state": state}]}}

        def response(*args, **kwargs):
            if args == ("xcrun", "simctl", "list", "runtimes", "--json"):
                return json.dumps(runtimes)
            if args == ("xcrun", "simctl", "list", "devices", "available", "--json"):
                return json.dumps(devices)
            return ""

        with patch.object(ios_dev, "run", side_effect=response) as run:
            self.assertEqual(ios_dev.simulator("se", fresh_boot=fresh_boot), "existing-se")
            return [entry.args for entry in run.call_args_list]

    def test_audit_reboots_existing_compatible_device_without_erasing(self):
        calls = self.calls_for(True)
        shutdown = ("xcrun", "simctl", "shutdown", "existing-se")
        boot = ("xcrun", "simctl", "boot", "existing-se")
        self.assertLess(calls.index(shutdown), calls.index(boot))
        self.assertFalse(any("erase" in args or "create" in args for args in calls))

    def test_normal_run_keeps_booted_device(self):
        calls = self.calls_for(False)
        self.assertFalse(any("shutdown" in args or "boot" in args for args in calls))

    def test_audit_boots_shutdown_device_without_extra_shutdown(self):
        calls = self.calls_for(True, state="Shutdown")
        self.assertIn(("xcrun", "simctl", "boot", "existing-se"), calls)
        self.assertFalse(any("shutdown" in args for args in calls))


if __name__ == "__main__":
    unittest.main()
