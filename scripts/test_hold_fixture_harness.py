#!/usr/bin/env python3
"""Verify that the actual compiled production-pipeline driver skips unavailable local data."""
import os
from pathlib import Path
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]

class HarnessAvailabilityTests(unittest.TestCase):
    def test_missing_fixture_directory_skips_without_failure(self):
        result = subprocess.run([str(ROOT / 'build/evaluate-hold-highlights')], cwd=ROOT,
                                env={**os.environ, 'HOLD_HIGHLIGHT_FIXTURES': str(ROOT / 'build' / str(uuid.uuid4()))},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith('SKIP: no fixture directory'), result.stdout)

if __name__ == '__main__':
    unittest.main()
