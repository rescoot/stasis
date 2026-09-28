import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.error
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
                {"releases": [{"status": "draft", "versionCodes": ["212000001"]}, live]},
                {},
                {"id": "second"},
                {"releases": [{"status": "draft", "versionCodes": ["212000001"]}, live]},
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

    def test_production_order_does_not_affect_safety_check(self):
        live = {"name": "live", "status": "completed", "versionCodes": ["45"]}
        draft = {"name": "next", "status": "draft", "versionCodes": ["46"]}
        self.assertTrue(play.same_releases({"releases": [live, draft]},
                                           {"releases": [draft, live]}))
        self.assertFalse(play.same_releases({"releases": [live, draft]},
                                            {"releases": [live]}))

    def test_transient_play_read_is_retried(self):
        unavailable = urllib.error.HTTPError(
            "https://example.test", 503, "Unavailable", {}, io.BytesIO(b"temporarily unavailable")
        )
        with patch.object(play.urllib.request, "urlopen", side_effect=[
            unavailable, io.BytesIO(json.dumps({"track": "internal"}).encode())
        ]) as open_url, patch.object(play.time, "sleep") as sleep:
            result = play.request("test-token", "GET", "https://example.test")
        self.assertEqual({"track": "internal"}, result)
        self.assertEqual(2, open_url.call_count)
        sleep.assert_called_once_with(1)

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
