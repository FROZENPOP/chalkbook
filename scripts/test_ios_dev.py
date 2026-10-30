"""Audit boot isolation must retain existing devices/data and leave normal runs alone."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
# Support both direct execution and `python3 -m unittest scripts.test_ios_dev`.
if __package__:
    from . import ios_dev
else:
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

    def test_cli_preserves_test_and_build_and_isolates_only_audit(self):
        for action in ("test", "build", "audit"):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as folder:
                with patch.object(sys, "argv", ["ios_dev.py", action]), \
                     patch.object(ios_dev, "ROOT", Path(folder)), \
                     patch.object(ios_dev, "run"), \
                     patch.object(ios_dev, "simulator", return_value="existing-phone") as simulator, \
                     patch.object(ios_dev.subprocess, "run", return_value=types.SimpleNamespace(returncode=0)) as process, \
                     contextlib.redirect_stdout(io.StringIO()):
                    ios_dev.main()
                simulator.assert_called_once_with("iphone16", fresh_boot=action == "audit")
                command = process.call_args.args[0]
                self.assertEqual(command[-1], "build" if action == "build" else "test")
                self.assertEqual("-only-testing:ClimbingAppUITests/AccessibilityAuditUITests" in command, action == "audit")

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
