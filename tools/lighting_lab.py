#!/usr/bin/env python3
"""Run bounded lighting experiments using the signed Ergo Control executable."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build" / "Ergo Control.app" / "Contents" / "MacOS" / "ErgoControl"


def invoke(arguments):
    if not APP.is_file():
        print("Build Ergo Control first: zsh tools/build_app.sh", file=sys.stderr)
        return 1
    # Pass signals directly to the signed executable so it can restore lighting.
    import os
    os.execv(str(APP), [str(APP), "--lighting-lab", *arguments])


def interactive():
    if not APP.is_file():
        return invoke([])
    print("Ergo Control · Lighting Lab\n")
    print("Quit Ergo Control, Probe, Bluetooth diagnostics, and Razer's apps first.")
    print("Leave keyboard brightness above 0%. Tests preserve its brightness.\n")
    print("1. Bluetooth — compare built-in effects")
    print("2. USB — compare built-in effects")
    print("3. USB — experiment with zone patterns")
    print("4. Restore a Bluetooth test interrupted by a disconnect/crash")
    print("5. Restore a USB test interrupted by a disconnect/crash")
    print("6. Bluetooth — experiment with zone patterns")
    selection = input("Choose 1–6 (or Enter to cancel): ").strip()
    if not selection:
        return 0
    if selection in ("4", "5"):
        return invoke(["restore", "bluetooth" if selection == "4" else "usb"])
    if selection not in ("1", "2", "3", "6"):
        print("No test started.")
        return 2
    connection = "bluetooth" if selection in ("1", "6") else "usb"
    pattern = "presets"
    if selection in ("3", "6"):
        print(f"\n{connection.title()} zone patterns; M1–M5 always share one color.")
        available = subprocess.run([str(APP), "--lighting-lab", "list"],
                                   check=True, text=True, capture_output=True).stdout.splitlines()
        options = [line for line in available if not line.startswith("presets:")]
        for index, line in enumerate(options, 1):
            print(f"{index}. {line}")
        chosen = input("Pattern number (or Enter to cancel): ").strip()
        if not chosen:
            return 0
        if not chosen.isdigit() or not 1 <= int(chosen) <= len(options):
            print("No test started.")
            return 2
        pattern = options[int(chosen) - 1].split(":", 1)[0]
    print("\nEach preset stays on for six seconds; a zone pattern runs for six seconds.")
    print("Press Control+C to stop and restore. A disconnected keyboard needs recovery after reconnecting.\n")
    arguments = ["run", connection, "--pattern", pattern, "--seconds", "6"]
    if selection == "6":
        arguments.append("--experimental-frames")
    return invoke(arguments)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="List patterns without connecting to the keyboard")
    sub.add_parser("interactive", help="Choose a test from a simple menu")
    run = sub.add_parser("run", help="Run a bounded test, then restore the saved effect")
    run.add_argument("connection", choices=("bluetooth", "usb"))
    run.add_argument("--pattern", default="presets",
                     choices=("presets", "macro-solid", "macro-pulse", "macro-colors", "scan", "chase", "progress", "rainbow"))
    run.add_argument("--seconds", type=float, default=6,
                     help="2–30 seconds per preset, or total duration for a zone pattern")
    run.add_argument("--experimental-frames", action="store_true",
                     help="Opt into the separate Bluetooth zone-frame research path")
    restore = sub.add_parser("restore", help="Retry exact-device restoration after a disconnect/crash")
    restore.add_argument("connection", choices=("bluetooth", "usb"))
    args = parser.parse_args()
    if args.command == "interactive":
        return interactive()
    if args.command == "list":
        return invoke(["list"])
    if args.command == "restore":
        return invoke(["restore", args.connection])
    arguments = ["run", args.connection, "--pattern", args.pattern, "--seconds", str(args.seconds)]
    if args.experimental_frames:
        arguments.append("--experimental-frames")
    return invoke(arguments)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nNo test started.")
        sys.exit(130)
