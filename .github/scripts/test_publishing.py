import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


play = load("publish_play")
ios = load("configure_ios_team")


class PublishingTests(unittest.TestCase):
    def test_production_draft_preserves_live_release(self):
        with tempfile.TemporaryDirectory() as root:
            bundle = Path(root) / "app.aab"
            notes = Path(root) / "notes.txt"
            bundle.write_bytes(b"bundle")
            notes.write_text("Release notes")
            live = {"status": "completed", "versionCodes": ["45"]}
            responses = [
                {"id": "first"},
                {"releases": [live]},
                {"versionCode": 212000001, "sha256": play.hashlib.sha256(b"bundle").hexdigest()},
                {"releases": [live, {"status": "draft", "versionCodes": ["212000001"]}]},
                {},
                {"id": "second"},
                {"releases": [live, {"status": "draft", "versionCodes": ["212000001"]}]},
                {"bundles": [{"versionCode": 212000001, "sha256": play.hashlib.sha256(b"bundle").hexdigest()}]},
                {"releases": [live, {"status": "draft", "versionCodes": ["212000001"]}]},
            ]
            calls = []

            def request(token, method, url, body=None, content_type="application/json"):
                calls.append((method, url, body))
                return responses.pop(0)

            argv = ["publish_play.py", "--aab", str(bundle), "--track", "production",
                    "--name", "2.0.5", "--version-code", "212000001",
                    "--status", "draft", "--notes-file", str(notes)]
            with patch.object(play, "request", side_effect=request), patch.object(sys, "argv", argv), \
                    patch.dict(os.environ, {"GOOGLE_OAUTH_ACCESS_TOKEN": "test"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                play.main()
            self.assertFalse(responses)
            self.assertEqual(["45"], play.json.loads(calls[3][2])["releases"][0]["versionCodes"])

    def test_ios_signing_keeps_bundle_ids(self):
        original = Path("ios/Runner.xcodeproj/project.pbxproj").read_text()
        configured = ios.configure(original, "ABC1234567")
        for profile in ("Stasis App Store CI", "Stasis Widget App Store CI"):
            self.assertIn(f'PROVISIONING_PROFILE_SPECIFIER = "{profile}";', configured)
        self.assertEqual(2, configured.count("DEVELOPMENT_TEAM = ABC1234567;"))
        self.assertEqual(original.count("PRODUCT_BUNDLE_IDENTIFIER = de.freal.unustasis;"),
                         configured.count("PRODUCT_BUNDLE_IDENTIFIER = de.freal.unustasis;"))


if __name__ == "__main__":
    unittest.main()
