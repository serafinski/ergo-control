#!/usr/bin/env python3
"""Summarize real capture windows without guessing physical controls from bytes."""
import argparse
from collections import Counter
import json
from pathlib import Path


def summarize(path):
    windows = []
    current = None
    errors = []
    events = Counter()
    for index, line in enumerate(path.read_text().splitlines(), 1):
        try:
            item = json.loads(line)
        except json.JSONDecodeError as error:
            errors.append(f"line {index}: {error}")
            continue
        kind = item.get("kind", "unknown")
        events[kind] += 1
        if kind == "marker":
            current = {"label": item["label"], "line": index, "reports": Counter(), "values": Counter(), "notifications": Counter()}
            windows.append(current)
        elif current is not None:
            if kind == "hid_report":
                current["reports"][(item["reportID"], item["hex"])] += 1
            elif kind == "hid_value":
                current["values"][(item["reportID"], item["page"], item["usage"], item["value"])] += 1
            elif kind == "ble_notification":
                current["notifications"][(item["uuid"], item["hex"])] += 1
    print(f"Capture: {path}\nEvent counts: {dict(events)}")
    if not events["hid_report"] and not events["ble_notification"]:
        print("No raw inputs captured. Check permissions, open/subscribe results, and connection before drawing conclusions.")
    if not windows:
        print("No marked test windows. Physical controls cannot be assigned from an unlabeled recording.")
    for window in windows:
        print(f"\n{window['label']} (marker at line {window['line']})")
        for title, key in [("HID reports", "reports"), ("HID values (report, page, usage, value)", "values"), ("Bluetooth", "notifications")]:
            print(f"  {title}:")
            for payload, count in window[key].most_common():
                print(f"    {payload}: {count}")
            if not window[key]: print("    none")
    if errors:
        print("\nMalformed capture lines:\n" + "\n".join(errors))
        return 1
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    raise SystemExit(summarize(parser.parse_args().capture))
