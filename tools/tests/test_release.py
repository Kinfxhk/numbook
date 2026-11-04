"""Pure-logic tests for tools/release.py.

Run:  python3 -m unittest discover -s tools/tests -v
Only pure functions are tested: no network, no real key material.
"""
import base64
import datetime
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

import release


def b64d(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


class B64UrlTest(unittest.TestCase):
    def test_padding_stripped(self):
        self.assertEqual(release.b64url(b"\xff\xff\xff"), "____")


class TokenTest(unittest.TestCase):
    def setUp(self):
        key = ec.generate_private_key(ec.SECP256R1())
        self.pub = key.public_key()
        pem = key.private_bytes(serialization.Encoding.PEM,
                                serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption())
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "key.p8")
        with open(self.path, "wb") as f:
            f.write(pem)
        self.conf = {"key_id": "KID123", "issuer_id": "iss-abc",
                     "private_key_path": self.path}

    def tearDown(self):
        self.tmp.cleanup()

    def test_jwt_shape_and_signature(self):
        j = release.token(self.conf)
        h, p, s = j.split(".")
        self.assertEqual(json.loads(b64d(h)),
                         {"alg": "ES256", "kid": "KID123", "typ": "JWT"})
        payload = json.loads(b64d(p))
        self.assertEqual(payload["iss"], "iss-abc")
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["exp"] - payload["iat"], 1205)
        sig = b64d(s)
        self.assertEqual(len(sig), 64)
        # JWT carries raw r||s; cryptography verifies DER, so re-encode.
        der = encode_dss_signature(int.from_bytes(sig[:32], "big"),
                                   int.from_bytes(sig[32:], "big"))
        self.pub.verify(der, f"{h}.{p}".encode(), ec.ECDSA(hashes.SHA256()))


class FreshBuildsTest(unittest.TestCase):
    NOW = datetime.datetime(2026, 11, 4, 9, 0, tzinfo=datetime.timezone.utc)

    def test_window_boundary_and_garbage(self):
        rows = [
            {"attributes": {"version": "1", "uploadedDate": "2026-11-03T08:00:00.000Z"}},
            {"attributes": {"version": "2", "uploadedDate": "2026-11-03T07:00:00.000Z"}},
            {"attributes": {"version": "3", "uploadedDate": "2026-11-03T06:59:59.000Z"}},
            {"attributes": {"version": "4", "uploadedDate": "not-a-date"}},
            {"attributes": {"version": "5"}},
        ]
        fresh = release.fresh_builds(rows, self.NOW, hours=26)
        self.assertEqual([b["attributes"]["version"] for b in fresh], ["1", "2"])

    def test_processing_counts_as_fresh(self):
        rows = [{"attributes": {"version": "9",
                                "uploadedDate": "2026-11-04T08:00:00.000Z",
                                "processingState": "PROCESSING"}}]
        self.assertEqual(len(release.fresh_builds(rows, self.NOW, hours=26)), 1)


class LatestValidTest(unittest.TestCase):
    def test_prefers_newest_valid(self):
        rows = [
            {"id": "1", "attributes": {"version": "1", "processingState": "VALID",
                                       "uploadedDate": "2026-11-01T00:00:00Z"}},
            {"id": "2", "attributes": {"version": "2", "processingState": "PROCESSING",
                                       "uploadedDate": "2026-11-03T00:00:00Z"}},
            {"id": "3", "attributes": {"version": "3", "processingState": "VALID",
                                       "uploadedDate": "2026-11-02T00:00:00Z"}},
        ]
        orig = release.builds
        release.builds = lambda c, limit=5: rows[:limit]
        try:
            self.assertEqual(release.latest_valid({})["id"], "3")
        finally:
            release.builds = orig


if __name__ == "__main__":
    unittest.main()
