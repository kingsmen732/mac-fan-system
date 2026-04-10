import json
import os
import unittest
from pathlib import Path

import main


class MainModuleTests(unittest.TestCase):
    def test_parse_pmset_keys_normalizes_keys(self) -> None:
        text = """
        Battery Power:
         highpowermode         1
         lowpowermode          0
        """

        self.assertEqual(
            main.parse_pmset_keys(text),
            {"highpowermode": "1", "lowpowermode": "0"},
        )

    def test_build_payload_keeps_fan_fields(self) -> None:
        fans = [
            main.FanRPM(index=0, rpm=2400, target_rpm=2300, min_rpm=2200, max_rpm=7000, mode="auto")
        ]

        payload = main.build_payload(fans, None)

        self.assertIn("timestamp", payload)
        self.assertEqual(payload["error"], None)
        self.assertEqual(payload["fans"][0]["rpm"], 2400)
        self.assertEqual(payload["fans"][0]["mode"], "auto")

    def test_native_lib_env_var_reports_missing_file(self) -> None:
        original = os.environ.get(main.NATIVE_LIB_ENV_VAR)
        os.environ[main.NATIVE_LIB_ENV_VAR] = str(Path("/tmp/does-not-exist-libfanbridge.dylib"))
        try:
            with self.assertRaises(main.NativeFanError) as context:
                main.ensure_native_bridge()
        finally:
            if original is None:
                os.environ.pop(main.NATIVE_LIB_ENV_VAR, None)
            else:
                os.environ[main.NATIVE_LIB_ENV_VAR] = original

        self.assertIn("missing native bridge", str(context.exception))


if __name__ == "__main__":
    unittest.main()
