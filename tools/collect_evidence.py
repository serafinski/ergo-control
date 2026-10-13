#!/usr/bin/env python3
"""Collect scoped device evidence; never open input devices or load vendor code."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "analysis/local"
HANDOFF = ROOT / "razer-ergo-codex-handoff"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HANDOFF / "MANIFEST.json").read_text())
    errors = [name for name, info in manifest.items()
              if not (HANDOFF / name).is_file()
              or (HANDOFF / name).stat().st_size != info["size_bytes"]
              or sha256(HANDOFF / name) != info["sha256"]]
    if errors:
        raise SystemExit(f"Evidence verification failed: {errors}")
    package = ROOT / "RazerSynapseInstaller.pkg"
    report = {"verifiedEvidenceFiles": len(manifest), "installerSha256": sha256(package),
              "macOS": command("sw_vers"), "architecture": command("uname", "-m"),
              "systemExtensions": command("systemextensionsctl", "list")}
    processes = command("ps", "-axo", "pid,comm").splitlines()
    report["relatedProcesses"] = [p for p in processes if re.search("razer|overdrive|karabiner", p, re.I)]
    engine = Path.home() / "Library/Razer/RazerAppEngine/Razer.app/Contents"
    report["installedEngineVersion"] = plistlib.loads((engine / "Info.plist").read_bytes()).get("CFBundleShortVersionString")
    report["installedHashes"] = {name: sha256(engine / name) for name in [
        "Resources/app.asar", "CommonDylib/libmapping_engine.dylib",
        "CommonDylib/libSysUtilsNative.dylib", "CommonDylib/libsimple_service.dylib"]}
    devices = plistlib.loads(subprocess.check_output(["ioreg", "-r", "-c", "IOHIDDevice", "-a"]))
    report["hid"] = []
    for device in devices:
        if device.get("VendorID") != 1678 or device.get("ProductID") != 707:
            continue
        selected = {key: device.get(key) for key in ["Product", "VendorID", "ProductID", "Transport",
            "PrimaryUsagePage", "PrimaryUsage", "MaxInputReportSize", "MaxOutputReportSize", "MaxFeatureReportSize"]}
        selected["ReportDescriptor"] = device.get("ReportDescriptor", b"").hex()
        report["hid"].append(selected)
    # Extract selected protocol facts, not the user's complete logs, serial numbers, or profiles.
    logs = Path.home() / "Library/Application Support/Razer/RazerAppEngine/User Data/Logs"
    findings = []
    for path in sorted(logs.glob("products_708_mw*.log")):
        for line_number, line in enumerate(path.read_text().splitlines(), 1):
            match = re.search(r"connectDevice\(\) result\(0\): (\{.*\})$", line)
            if match and not any(f["fact"] == "connection" for f in findings):
                findings.append({"source": path.name, "line": line_number, "fact": "connection", "value": json.loads(match[1])})
            match = re.search(r"setDeviceMode - set device to driver mode with result (\{.*\})$", line)
            if match and not any(f["fact"] == "driver_mode" for f in findings):
                data = json.loads(match[1])
                findings.append({"source": path.name, "line": line_number, "fact": "driver_mode",
                    "value": {k: data[k] for k in ["status", "jsonData", "command", "dataSend"]}})
    report["historicalProtocolFacts"] = findings
    (OUT / "environment.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Verified {len(manifest)} evidence files. Saved scoped environment and protocol facts to {OUT / 'environment.json'}")


if __name__ == "__main__":
    main()
