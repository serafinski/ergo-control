#!/usr/bin/env python3
"""Explicit, interactive export of this repo's isolated local signing identity.

Run this yourself to prepare GitHub secrets. Never called by a build or workflow.
"""
import getpass
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
keychain = root / "build/local-signing/ErgoDevelopment.keychain-db"
output = root / "build/release-signing.p12"
if not keychain.exists():
    raise SystemExit("Build the app locally first to create its persistent signing identity.")
if output.exists():
    raise SystemExit("build/release-signing.p12 already exists; preserve or remove it before exporting again.")
print("Exports the private signing identity to ignored build/release-signing.p12.")
print("This file grants permission to sign Ergo Control updates. Keep it private.")
password = getpass.getpass("Choose a password for the exported P12: ")
if not password or password != getpass.getpass("Repeat password: "):
    raise SystemExit("Passwords must match and cannot be empty.")
old_mask = os.umask(0o077)
try:
    result = subprocess.run(["security", "export", "-k", str(keychain), "-t", "identities", "-f", "pkcs12",
                             "-P", password, "-o", str(output)], capture_output=True)
    if result.returncode:
        output.unlink(missing_ok=True)
        raise SystemExit("Keychain export failed. Unlock the local signing keychain by building the app, then retry.")
finally:
    os.umask(old_mask)
print("Export complete. Follow docs/RELEASING.md to add the two repository secrets.")
