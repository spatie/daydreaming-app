import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci
import notes
import publish
import sparkle_tools


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "test@example.invalid")
        self.commit("Initial picture picker")
        self.git("tag", "v0.1.0")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True)

    def commit(self, message):
        self.git("commit", "--allow-empty", "-qm", message)

    def testMaintainedVersionNotesWinWithoutInventingChanges(self):
        release = self.repo / "docs/releases/0.2.0.md"
        release.parent.mkdir(parents=True)
        release.write_text("# Daydreaming 0.2.0\n\n- Pan your original when cropping.\n")
        self.assertEqual(notes.generate(self.repo, "0.2.0", "v0.1.0"), release.read_text())

    def testActualRangeDedupesAndDoesNotExposePrivateLinks(self):
        self.commit("fix: Keep the crop unchanged (#21)")
        self.commit("fix: Keep the crop unchanged (#22)")
        self.commit("feat: Add picture history https://github.com/private/repo/pull/3")
        result = notes.generate(self.repo, "0.2.0", "v0.1.0")
        self.assertEqual(result.count("Keep the crop unchanged"), 1)
        self.assertIn("Add picture history", result)
        self.assertNotIn("Initial picture picker", result)
        self.assertNotIn("https://", result)
        self.assertNotIn("#21", result)

    def testNoChangesAndInvalidInputsFail(self):
        with self.assertRaisesRegex(ValueError, "No maintained"):
            notes.generate(self.repo, "0.2.0", "v0.1.0")
        for version in ("../../secret", "1.0.0\nmalicious", "beta"):
            with self.assertRaises(ValueError):
                notes.generate(self.repo, version, None)
        with self.assertRaises(ValueError):
            notes.generate(self.repo, "0.2.0", "--all")

    def testHTMLCannotExecuteCommitText(self):
        rendered = notes.render('# Safe\n\n- <img src=x onerror="run()">\n\n<script>alert(1)</script>')
        self.assertIn("&lt;img", rendered)
        self.assertNotIn("<script>", rendered)


class ReleaseBoundaryTests(unittest.TestCase):
    @patch("publish.verify_dmg")
    @patch("publish.validate_app")
    @patch("publish.signing_arguments", return_value=[])
    @patch("publish.subprocess.run")
    @patch("publish.fetch")
    def testPublisherValidatesThePreparedWeatherKitProfile(self, fetch, run, signing, validate, verify_dmg):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "release"
            work = Path(folder) / "work"
            directory.mkdir()
            work.mkdir()
            fetch.return_value = work / "Sparkle"
            run.return_value = subprocess.CompletedProcess([], 0, "", "TeamIdentifier=97KRXCRMAY")
            manifest = {"version": "0.9.0", "build": 53, "gitRevision": "a" * 40,
                        "weatherKitProfileUUID": "f7307d68-c04f-49cc-b2b2-37730b63ed25",
                        "archiveSignatures": {"Daydreaming-0.9.0-53.dmg": "dmg", "Daydreaming-0.9.0-53.zip": "zip"}}

            publish.verify_signatures(directory, manifest, work, None)

            validate.assert_called_once_with(work / "Daydreaming.app", "0.9.0", 53, "a" * 40,
                                             "f7307d68-c04f-49cc-b2b2-37730b63ed25")

    def testPublicKeyDerivationAgainstRFC8032WithoutExportingOwnerKey(self):
        import base64
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / "fixture.key"
            key.write_text(base64.b64encode(bytes.fromhex(
                "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")).decode())
            key.chmod(0o600)
            expected = base64.b64encode(bytes.fromhex(
                "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).decode()
            self.assertEqual(sparkle_tools.public_key(key), expected)
            key.chmod(0o644)
            with self.assertRaisesRegex(ValueError, "owner-only"):
                sparkle_tools.public_key(key)

    def testMissingCredentialsOnlyListNames(self):
        with self.assertRaisesRegex(ValueError, "APPLE_CERTIFICATE_P12") as error:
            ci.preflight({"DAYDREAMING_RELEASE_TOKEN": "sensitive-test-token"})
        self.assertNotIn("sensitive-test-token", str(error.exception))

    @patch.dict("os.environ", {}, clear=True)
    def testCredentialSetupRefusesOwnerMachine(self):
        with self.assertRaisesRegex(ValueError, "only run in GitHub Actions"):
            ci.setup()

    def testAPIWillNotRedirectBearerCredentials(self):
        with self.assertRaisesRegex(ValueError, "Refusing to forward"):
            publish.NoRedirect().redirect_request(None, None, 302, "Found", {}, "https://attacker.invalid")

    @patch("publish.subprocess.run")
    @patch("publish.remote_digest")
    def testExistingObjectsAreVerifiedAndNeverOverwritten(self, remote, run):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "Daydreaming-0.1.0-15.dmg"
            archive.write_bytes(b"archive")
            env = {"DAYDREAMING_S3_PREFIX": "daydreaming", "DAYDREAMING_OBJECT_BASE_URL": "https://objects.example/daydreaming",
                   "DAYDREAMING_S3_ENDPOINT": "https://objects.example", "DAYDREAMING_S3_REGION": "eu", "DAYDREAMING_S3_BUCKET": "releases"}
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            run.return_value = subprocess.CompletedProcess([], 0, "{}", "")
            remote.return_value = (digest, 7)
            self.assertEqual(publish.upload(archive, digest, env), "https://objects.example/daydreaming/" + archive.name)
            self.assertEqual(run.call_count, 1)
            remote.return_value = ("wrong-hash", 7)
            with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
                publish.upload(archive, digest, env)
            self.assertEqual(run.call_count, 2)

    @patch("publish.subprocess.run")
    def testStoragePermissionErrorsNeverBecomeMissingObjects(self, run):
        env = {"DAYDREAMING_S3_PREFIX": "daydreaming", "DAYDREAMING_OBJECT_BASE_URL": "https://objects.example/daydreaming",
               "DAYDREAMING_S3_ENDPOINT": "https://objects.example", "DAYDREAMING_S3_REGION": "eu", "DAYDREAMING_S3_BUCKET": "releases"}
        run.return_value = subprocess.CompletedProcess([], 1, "", "An error occurred (403): Forbidden")
        with self.assertRaisesRegex(ValueError, "Not treating access errors"):
            publish.upload(Path("Daydreaming-0.1.0-15.dmg"), "hash", env)
        self.assertEqual(run.call_count, 1)

    @patch("publish.verify_signatures")
    @patch("publish.remote_digest")
    @patch("publish.api")
    def testIncompleteReleaseNeverMakesNetworkCalls(self, api, remote, verify):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "RELEASE_INCOMPLETE").write_text("failed notarization")
            with self.assertRaisesRegex(ValueError, "Incomplete release"):
                publish.publish(Path(folder))
        api.assert_not_called()
        remote.assert_not_called()
        verify.assert_not_called()


if __name__ == "__main__":
    unittest.main()
