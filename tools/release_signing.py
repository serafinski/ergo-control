#!/usr/bin/env python3
"""Import a persistent release identity into an ephemeral GitHub runner keychain."""
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode:
        # Arguments and tool diagnostics may contain credentials. Never log them.
        raise SystemExit(f"Release signing failed in {Path(arguments[0]).name} (exit {result.returncode}).")
    return result.stdout


def main():
    root = os.environ.get("RUNNER_TEMP")
    if not root:
        raise SystemExit("This script requires a GitHub runner's RUNNER_TEMP.")
    folder = Path(root) / "ergo-release-signing"
    keychain = folder / "release.keychain-db"
    saved_search = folder / "search-list.json"
    if sys.argv[1:] == ["cleanup"]:
        if saved_search.exists():
            run(["security", "list-keychains", "-d", "user", "-s", *json.loads(saved_search.read_text())])
        if keychain.exists():
            run(["security", "delete-keychain", str(keychain)])
        for name in ["identity.p12", "search-list.json"]:
            (folder / name).unlink(missing_ok=True)
        return
    if sys.argv[1:] != ["install"]:
        raise SystemExit("Use install or cleanup.")
    certificate = os.environ.get("SIGNING_CERTIFICATE_P12_B64", "")
    password = os.environ.get("SIGNING_CERTIFICATE_PASSWORD", "")
    if not certificate or not password:
        raise SystemExit("Set SIGNING_CERTIFICATE_P12_B64 and SIGNING_CERTIFICATE_PASSWORD repository secrets first. See docs/RELEASING.md.")
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    original = shlex.split(run(["security", "list-keychains", "-d", "user"]))
    saved_search.write_text(json.dumps(original))
    package = folder / "identity.p12"
    package.touch(mode=0o600)
    try:
        package.write_bytes(base64.b64decode("".join(certificate.split()), validate=True))
        temporary_password = secrets.token_urlsafe(32)
        run(["security", "create-keychain", "-p", temporary_password, str(keychain)])
        run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
        run(["security", "unlock-keychain", "-p", temporary_password, str(keychain)])
        run(["security", "import", str(package), "-k", str(keychain), "-P", password, "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", temporary_password, str(keychain)])
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original])
        identities = list(dict.fromkeys(re.findall(r'^\s*\d+\) ([0-9A-Fa-f]{40}) "', run(["security", "find-identity", "-p", "codesigning", str(keychain)]), re.MULTILINE)))
        if len(identities) != 1:
            raise SystemExit("The P12 must contain exactly one code-signing identity.")
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write(f"ERGO_CODESIGN_IDENTITY={identities[0]}\nERGO_CODESIGN_KEYCHAIN={keychain}\n")
        print("Persistent signing identity imported; private material was not logged.")
    finally:
        package.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
