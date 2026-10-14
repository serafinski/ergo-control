#!/usr/bin/env python3
"""Collect scoped local metadata without opening input devices or loading vendor code."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LIBRARIES = ["Resources/app.asar", "CommonDylib/libmapping_engine.dylib",
             "CommonDylib/libSysUtilsNative.dylib", "CommonDylib/libsimple_service.dylib"]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def verify_evidence(manifest_path, evidence_dir):
    manifest = json.loads(manifest_path.read_text())
    errors = []
    for name, info in manifest.items():
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or not relative.parts or relative.parts[0] != "evidence":
            raise SystemExit("Invalid evidence manifest path")
        path = evidence_dir.joinpath(*relative.parts[1:])
        if not path.is_file() or path.stat().st_size != info["size_bytes"] or sha256(path) != info["sha256"]:
            errors.append(name)
    if errors:
        raise SystemExit(f"Evidence verification failed: {errors}")
    return len(manifest)


def protocol_facts(logs):
    findings = []
    seen = set()
    for path in sorted(logs.glob("products_708_mw*.log")):
        for line_number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            for fact, pattern in [
                ("connection", r"connectDevice\(\) result\(0\): (\{.*\})$"),
                ("driver_mode", r"setDeviceMode - set device to driver mode with result (\{.*\})$"),
            ]:
                match = re.search(pattern, line)
                if not match or fact in seen:
                    continue
                try:
                    data = json.loads(match[1])
                except json.JSONDecodeError:
                    continue
                # Preserve numeric status/mode and short packet data only. Never
                # retain the complete connection object, device IDs, or profiles.
                value = {}
                if isinstance(data.get("status"), int):
                    value["status"] = data["status"]
                mode = data.get("jsonData")
                if isinstance(mode, dict):
                    for key in ("mode", "parameter"):
                        if isinstance(mode.get(key), int):
                            value[key] = mode[key]
                packet = data.get("dataSend")
                if isinstance(packet, str) and re.fullmatch(r"[0-9a-fA-F ]{1,128}", packet):
                    value["dataSend"] = packet
                elif isinstance(packet, list) and len(packet) <= 64 and all(type(n) is int and 0 <= n <= 255 for n in packet):
                    value["dataSend"] = packet
                findings.append({"source": path.name, "line": line_number, "fact": fact, "value": value})
                seen.add(fact)
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, default=ROOT / "analysis/private/handoff/evidence",
                        help="Optional privately obtained vendor evidence directory")
    parser.add_argument("--manifest", type=Path, default=ROOT / "docs/research/initial-handoff/MANIFEST.json")
    parser.add_argument("--installer", type=Path, default=ROOT / "analysis/vendor/installer/RazerSynapseInstaller.pkg")
    parser.add_argument("--engine-contents", type=Path,
                        default=Path.home() / "Library/Razer/RazerAppEngine/Razer.app/Contents")
    parser.add_argument("--output", type=Path, default=ROOT / "analysis/local/environment.json")
    args = parser.parse_args()
    report = {"verifiedEvidenceFiles": None, "installerSha256": None, "notes": []}
    if args.evidence_dir.is_dir():
        report["verifiedEvidenceFiles"] = verify_evidence(args.manifest, args.evidence_dir)
    else:
        report["notes"].append("Optional vendor evidence not provided")
    if args.installer.is_file():
        report["installerSha256"] = sha256(args.installer)
    else:
        report["notes"].append("Optional vendor installer not provided")
    report["macOS"] = command("sw_vers")
    report["architecture"] = command("uname", "-m")
    report["relatedSystemExtensions"] = [line for line in command("systemextensionsctl", "list").splitlines()
                                         if re.search("razer|overdrive|karabiner", line, re.I)]
    report["relatedProcesses"] = [line for line in command("ps", "-axo", "pid,comm").splitlines()
                                  if re.search("razer|overdrive|karabiner", line, re.I)]
    engine = args.engine_contents
    info = engine / "Info.plist"
    report["installedEngineVersion"] = plistlib.loads(info.read_bytes()).get("CFBundleShortVersionString") if info.is_file() else None
    report["installedHashes"] = {name: sha256(engine / name) for name in LIBRARIES if (engine / name).is_file()}
    devices = plistlib.loads(subprocess.check_output(["ioreg", "-r", "-c", "IOHIDDevice", "-a"]))
    report["hid"] = []
    for device in devices:
        if device.get("VendorID") != 1678 or device.get("ProductID") != 707 or device.get("Transport") != "Bluetooth Low Energy":
            continue
        selected = {key: device.get(key) for key in ["Product", "VendorID", "ProductID", "Transport",
            "PrimaryUsagePage", "PrimaryUsage", "MaxInputReportSize", "MaxOutputReportSize", "MaxFeatureReportSize"]}
        selected["ReportDescriptor"] = device.get("ReportDescriptor", b"").hex()
        report["hid"].append(selected)
    report["historicalProtocolFacts"] = protocol_facts(Path.home() / "Library/Application Support/Razer/RazerAppEngine/User Data/Logs")
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    args.output.chmod(0o600)
    print(f"Saved scoped local metadata to {args.output}. No input device was opened.")


if __name__ == "__main__":
    main()
