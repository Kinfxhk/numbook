#!/usr/bin/env python3
"""Numbook release helper — App Store Connect API automation.

Reads ~/.hermes/secrets/numbook-asc/config.json (key id / issuer / p8 path).
Never prints key material.

Commands
  status                 latest builds + processing state
  compliance             declare no non-exempt encryption on every unhandled build
  add-to-group           attach the newest VALID build to the internal group
  full                   build → archive → upload → wait → compliance → group

  build [--skip-checks]  flutter build + xcodebuild archive (no upload)
  upload                 upload the newest archive in build/
  wait [--minutes N]     poll until the newest build leaves PROCESSING
"""
import argparse
import base64
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF_PATH = os.path.expanduser("~/.hermes/secrets/numbook-asc/config.json")
API = "https://api.appstoreconnect.apple.com/v1"


def conf():
    with open(CONF_PATH) as f:
        return json.load(f)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(c):
    now = int(time.time())
    header = {"alg": "ES256", "kid": c["key_id"], "typ": "JWT"}
    payload = {"iss": c["issuer_id"], "iat": now - 5, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode())
                     + "." + b64url(json.dumps(payload, separators=(",", ":")).encode()))
    with open(c["private_key_path"], "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return signing_input + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


def call(c, method, path, body=None, retries=3):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + token(c))
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", "numbook-release/1.0")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            last = (e.code, {"error": e.read().decode(errors="replace")[:800]})
            if e.code not in (429, 500, 502, 503, 504) or attempt == retries - 1:
                return last
        except urllib.error.URLError as e:
            last = (0, {"error": f"network: {e.reason}"[:800]})
            if attempt == retries - 1:
                return last
        time.sleep(2 ** attempt)
    return last or (0, {"error": "call failed"})


def builds(c, limit=5):
    st, d = call(c, "GET",
                 f"/builds?filter[app]={c['app_id']}&sort=-uploadedDate&limit={limit}"
                 "&fields[builds]=version,processingState,uploadedDate,usesNonExemptEncryption")
    if st != 200:
        print("builds failed", st, d)
        return []
    return d.get("data", [])


def show_builds(rows):
    for b in rows:
        a = b["attributes"]
        print(f"  build {a.get('version'):>4}  {a.get('processingState'):<12} "
              f"uploaded {a.get('uploadedDate', '')[:19]}  "
              f"enc={a.get('usesNonExemptEncryption')}")


def latest_valid(c):
    valid = [b for b in builds(c, 10)
             if b["attributes"].get("processingState") == "VALID"]
    if not valid:
        return None
    # API already sorts newest-first, but do not depend on it: pick explicitly.
    valid.sort(key=lambda b: b["attributes"].get("uploadedDate", ""), reverse=True)
    return valid[0]


def cmd_status(c):
    rows = builds(c)
    if not rows:
        print("no builds")
        return
    print(f"app {c['app_id']} — newest builds")
    show_builds(rows)


def declare_compliance(c, build):
    return call(c, "PATCH", f"/builds/{build['id']}", {
        "data": {"type": "builds", "id": build["id"],
                 "attributes": {"usesNonExemptEncryption": False}}})[0]


def cmd_compliance(c):
    rows = builds(c, 10)
    todo = [b for b in rows if b["attributes"].get("usesNonExemptEncryption") is None]
    if not todo:
        print("all builds already declared")
        return
    for b in todo:
        st = declare_compliance(c, b)
        print(f"build {b['attributes'].get('version')}: compliance -> {st}")


def group_id(c):
    st, d = call(c, "GET", f"/betaGroups?filter[app]={c['app_id']}&limit=50")
    if st != 200:
        print("betaGroups failed", st, d)
        return None
    for g in d.get("data", []):
        if g["attributes"].get("name") == c["internal_group"]:
            return g["id"]
    print("group not found:", c["internal_group"])
    return None


def attach_to_group(c, b):
    """POST build b into the internal group; returns (status, body)."""
    gid = group_id(c)
    if not gid:
        return None, None
    return call(c, "POST", f"/betaGroups/{gid}/relationships/builds", {
        "data": [{"type": "builds", "id": b["id"]}]})


def cmd_add_to_group(c):
    b = latest_valid(c)
    if not b:
        print("no VALID build yet")
        return
    st, d = attach_to_group(c, b)
    if st is not None and 200 <= st < 300:
        print(f"added build {b['attributes'].get('version')} to group: {st}")
    elif st in (409, 422):
        print(f"build {b['attributes'].get('version')} already in group ({st})")
    else:
        print(f"add-to-group failed {st}: {d}")


def pubspec_build():
    """CFBundleVersion from pubspec (the number App Store Connect shows)."""
    import re
    try:
        text = open(os.path.join(ROOT, "pubspec.yaml")).read()
    except OSError:
        return None
    m = re.search(r"^version:\s*\S+\+(\d+)", text, re.M)
    return m.group(1) if m else None


def cmd_wait(c, minutes=30, expected=None):
    """Wait until `expected` (or, if None, the newest build) leaves PROCESSING.

    A freshly uploaded build takes minutes to appear in the API; returning on
    the previous VALID build would silently skip the new one.
    """
    deadline = time.time() + minutes * 60
    seen = None
    while time.time() < deadline:
        rows = builds(c, 5)
        target = None
        for b in rows:
            if expected is None or b["attributes"].get("version") == expected:
                target = b
                break
        if target is None:
            if expected and seen != "missing":
                seen = "missing"
                print(f"build {expected} not visible yet, waiting…")
        else:
            a = target["attributes"]
            if a.get("processingState") != "PROCESSING":
                print(f"build {a.get('version')} state {a.get('processingState')}")
                return target
            if seen != a.get("version"):
                seen = a.get("version")
                print(f"build {seen} still PROCESSING…")
        time.sleep(20)
    print("timed out waiting for processing")
    return None


def run(cmd, cwd=ROOT, check=True):
    print("$", " ".join(cmd))
    p = subprocess.run(cmd, cwd=cwd)
    if check and p.returncode != 0:
        sys.exit(p.returncode)
    return p.returncode


def cmd_build(c, skip_checks=False):
    if not skip_checks:
        run(["flutter", "analyze"])
        run(["flutter", "test"])
    run(["flutter", "build", "macos", "--release"])
    archive = os.path.join("build", "Numbook-asc.xcarchive")
    if os.path.exists(os.path.join(ROOT, archive)):
        shutil.rmtree(os.path.join(ROOT, archive))
    run(["xcodebuild", "archive",
         "-workspace", "macos/Runner.xcworkspace", "-scheme", "Runner",
         "-configuration", "Release", "-archivePath", archive,
         "-allowProvisioningUpdates"])
    print("archive:", archive)
    return os.path.join(ROOT, archive)


def newest_archive():
    base = os.path.join(ROOT, "build")
    if not os.path.isdir(base):
        return None
    cands = [os.path.join(base, d) for d in os.listdir(base)
             if d.endswith(".xcarchive")]
    if not cands:
        return None
    return max(cands, key=os.path.getmtime)


def cmd_upload(c, archive=None):
    arch = archive or newest_archive()
    if not arch:
        print("no .xcarchive in build/")
        return
    print("uploading archive:", arch)
    opts = os.path.join(ROOT, "build", "exportOptions.plist")
    if not os.path.exists(opts):
        print("missing", opts)
        return
    run(["xcodebuild", "-exportArchive", "-archivePath", arch,
         "-exportOptionsPlist", opts, "-exportPath",
         os.path.join(ROOT, "build", "export"), "-allowProvisioningUpdates"])


def cmd_full(c, skip_checks=False):
    arch = cmd_build(c, skip_checks)
    cmd_upload(c, arch)
    cmd_wait(c, expected=pubspec_build())
    cmd_compliance(c)
    cmd_add_to_group(c)
    cmd_status(c)


def parse_uploaded(ts):
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def fresh_builds(rows, now, hours=26):
    """Builds uploaded within the last `hours` (uploadedDate is set at upload,
    so PROCESSING builds count too)."""
    cutoff = now - datetime.timedelta(hours=hours)
    fresh = []
    for b in rows:
        when = parse_uploaded(b["attributes"].get("uploadedDate", ""))
        if when is not None and when >= cutoff:
            fresh.append(b)
    return fresh


def cmd_watch(c):
    """Quiet daily check: only speaks when action was actually needed."""
    rows = builds(c, 5)
    if not rows:
        return
    now = datetime.datetime.now(datetime.timezone.utc)
    acted = []
    for b in fresh_builds(rows, now, hours=26):
        a = b["attributes"]
        if a.get("usesNonExemptEncryption") is None:
            st = declare_compliance(c, b)
            acted.append(f"build {a.get('version')}: compliance {st}")
    # Attach regardless of freshness: the newest VALID build belongs in the
    # group, and the POST is idempotent (duplicate -> 409/422, not reported).
    b = latest_valid(c)
    if b:
        st, _ = attach_to_group(c, b)
        if st is not None and 200 <= st < 300:
            acted.append(f"build {b['attributes'].get('version')} added to {c['internal_group']}")
    if acted:
        print("Numbook release watch")
        for line in acted:
            print(" •", line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["status", "compliance", "add-to-group",
                                        "wait", "build", "upload", "full", "watch"])
    ap.add_argument("--skip-checks", action="store_true")
    ap.add_argument("--archive", help="explicit .xcarchive path for upload")
    ap.add_argument("--minutes", type=int, default=30)
    a = ap.parse_args()
    if a.skip_checks and not os.environ.get("RELEASE_ALLOW_SKIP"):
        sys.exit("refusing --skip-checks: set RELEASE_ALLOW_SKIP=1 to override")
    c = conf()
    {
        "status": lambda: cmd_status(c),
        "compliance": lambda: cmd_compliance(c),
        "add-to-group": lambda: cmd_add_to_group(c),
        "wait": lambda: cmd_wait(c, a.minutes, expected=pubspec_build()),
        "build": lambda: cmd_build(c, a.skip_checks),
        "upload": lambda: cmd_upload(c, a.archive),
        "full": lambda: cmd_full(c, a.skip_checks),
        "watch": lambda: cmd_watch(c),
    }[a.command]()


if __name__ == "__main__":
    main()
