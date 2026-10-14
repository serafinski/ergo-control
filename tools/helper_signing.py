#!/usr/bin/env python3
"""Pin the GUI's exact signature without installing or starting privileged code."""
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def app_requirement(app):
    executable = app / "Contents/MacOS/ErgoControl"
    result = subprocess.run(["codesign", "--display", "--requirements", "-", str(executable)],
                            check=True, text=True, capture_output=True)
    match = re.search(r"^designated => (.+)$", result.stdout + result.stderr, re.MULTILINE)
    if not match:
        raise SystemExit("Cannot identify the signed app executable")
    requirement = match.group(1)
    if "cdhash" in requirement or not any(term in requirement for term in ("anchor", "certificate")):
        raise SystemExit("Full-control helper requires a certificate signature, not an ad-hoc signature")
    return requirement


mode, app_path, plist_path = sys.argv[1:]
app, plist = Path(app_path), Path(plist_path)
requirement = app_requirement(app)
if mode == "prepare":
    plist.write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.local.ergocontrol.inputhelper",
        "CFBundleName": "Ergo Control Input Helper",
        "CFBundleVersion": "4",
        "ErgoAcceptedClientRequirement": requirement,
    }))
elif mode == "verify":
    if plistlib.loads(plist.read_bytes())["ErgoAcceptedClientRequirement"] != requirement:
        raise SystemExit("App signature changed after helper pinning; refusing this build")
    subprocess.run(["codesign", "--verify", "--strict", "--test-requirement", "=" + requirement, str(app)], check=True)
else:
    raise SystemExit("Use prepare or verify")
