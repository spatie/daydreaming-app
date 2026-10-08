import base64
from datetime import datetime, timedelta, timezone
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import feed
import prepare
import sparkle_tools


class FeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.artifact = self.root / "Daydreaming-1.2.3-4.dmg"
        self.artifact.write_bytes(b"verified-test-archive")
        self.feed = self.root / "appcast.xml"
        self.signature = base64.b64encode(bytes(range(64))).decode()
        self.valid = f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>4</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
        <enclosure url="https://getdaydreaming.com/releases/{self.artifact.name}" length="{self.artifact.stat().st_size}" sparkle:edSignature="{self.signature}"/>
        </item></channel></rss>'''
        self.feed.write_text(self.valid)

    def testValidStagedFeedAndIncreasingBuild(self):
        self.assertEqual(feed.validate(self.feed, self.artifact, "1.2.3", 4), self.signature)
        feed.require_next_build(self.feed, 5)
        for build in (0, 3, 4):
            with self.assertRaises(ValueError):
                feed.require_next_build(self.feed, build)

    def testRejectsWrongHostProtocolArchiveLengthVersionSignatureAndSystem(self):
        invalid = [self.valid.replace("https://getdaydreaming.com/releases/", "http://getdaydreaming.com/releases/"),
                   self.valid.replace("getdaydreaming.com", "attacker.example"),
                   self.valid.replace(self.artifact.name, "wrong.dmg"),
                   self.valid.replace(f'length="{self.artifact.stat().st_size}"', 'length="1"'),
                   self.valid.replace("1.2.3</", "2.0.0</"),
                   self.valid.replace("26.0</", "12.0</"),
                   self.valid.replace(self.signature, "invalid"),
                   self.valid.replace(self.signature, base64.b64encode(bytes(63)).decode()),
                   self.valid.replace("<sparkle:version>4", "<sparkle:version>3")]
        for content in invalid:
            with self.subTest(content=content):
                self.feed.write_text(content)
                with self.assertRaises(ValueError):
                    feed.validate(self.feed, self.artifact, "1.2.3", 4)

    def testRejectsDuplicateBuildAndDTD(self):
        item = "<item>" + self.valid.split("<item>")[1].split("</item>")[0] + "</item>"
        for content in (self.valid.replace("</channel>", item + "</channel>"),
                        self.valid.replace('<rss ', '<!DOCTYPE rss [<!ENTITY bad "secret">]><rss ')):
            self.feed.write_text(content)
            with self.assertRaises(ValueError):
                feed.build_numbers(self.feed)

    def testEmptyInitialFeedAcceptsFirstBuild(self):
        self.feed.write_text('<rss version="2.0"><channel/></rss>')
        feed.require_next_build(self.feed, 1)
        self.assertEqual(feed.build_numbers(self.feed), [])


class ReleaseSafetyTests(unittest.TestCase):
    @patch("prepare.subprocess.run")
    def testWeatherKitProfileMustAuthorizeExactProductionApp(self, run):
        profile = {"UUID": "test-uuid", "Name": "Daydreaming WeatherKit",
                   "TeamIdentifier": [prepare.TEAM],
                   "ExpirationDate": (datetime.now(timezone.utc) + timedelta(days=30)).replace(tzinfo=None),
                   "Entitlements": {"com.apple.application-identifier": f"{prepare.TEAM}.{prepare.BUNDLE_ID}",
                                    "com.apple.developer.weatherkit": True}}
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "Daydreaming.provisionprofile"
            path.write_bytes(b"signed fixture")
            run.return_value = subprocess.CompletedProcess([], 0, plistlib.dumps(profile))
            self.assertEqual(prepare.weatherkit_profile(path)["UUID"], "test-uuid")
            for changed in ({"com.apple.developer.weatherkit": False},
                            {"com.apple.application-identifier": "OTHER.be.spatie.daydreaming"}):
                invalid = dict(profile)
                invalid["Entitlements"] = {**profile["Entitlements"], **changed}
                run.return_value = subprocess.CompletedProcess([], 0, plistlib.dumps(invalid))
                with self.assertRaisesRegex(ValueError, "does not authorize"):
                    prepare.weatherkit_profile(path)

    @patch("prepare.run")
    def testDirtyTreeStopsBeforeAnyBuildOrNetwork(self, run):
        run.return_value = "?? unreviewed.swift"
        with self.assertRaisesRegex(ValueError, "clean committed"):
            prepare.clean_revision(Path("/test"))
        self.assertEqual(run.call_count, 1)

    @patch("prepare.run")
    def testImmutableCommitRequired(self, run):
        run.side_effect = ["", "branch-name"]
        with self.assertRaisesRegex(ValueError, "immutable"):
            prepare.clean_revision(Path("/test"))

    @patch("prepare.run")
    def testNotaryExitSuccessIsInsufficientWithoutAcceptedStatus(self, run):
        with tempfile.TemporaryDirectory() as name:
            log = Path(name) / "result.json"
            run.return_value = '{"status":"Invalid"}'
            with self.assertRaisesRegex(ValueError, "not accepted"):
                prepare.notarize(Path(name) / "app.zip", "explicit-profile", log)
            self.assertEqual(log.read_text(), '{"status":"Invalid"}\n')
            run.return_value = '{"status":"Accepted"}'
            prepare.notarize(Path(name) / "app.zip", "explicit-profile", log)

    @patch("sparkle_tools.subprocess.run")
    @patch("sparkle_tools.urllib.request.urlopen")
    def testUnverifiedToolDownloadNeverExecutesOrExtracts(self, urlopen, run):
        import io
        urlopen.return_value = io.BytesIO(b"untrusted download")
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                sparkle_tools.fetch(Path(name) / "tools")
        run.assert_not_called()

    def testReleaseToolsUseAppSpecificAccount(self):
        self.assertEqual(sparkle_tools.ACCOUNT, "be.spatie.daydreaming.sparkle")
        self.assertEqual(sparkle_tools.VERSION, "2.10.0")


if __name__ == "__main__":
    unittest.main()
