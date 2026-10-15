# Lighting Lab

This optional test tool compares the keyboard's native effects and tries independently generated 19-zone animations. It uses the signed Ergo Control executable, not a Razer/Chroma installation. Normal app use never runs these tests.

**A moving line across the keyboard is plausible; a line moving separately through M1, M2, M3, M4, and M5 is not exposed.** Those five buttons share one lighting zone in [Razer's device map](MACRO_LIGHTING.md). The macro-column tests change them together.

## Run a test

Build the current app, then quit Ergo Control through its menu bar. Also quit Probe, Bluetooth diagnostics, and Razer's configuration apps so their commands do not overlap. Leave brightness above 0%; the lab deliberately does not change brightness or input mode.

Double-click **`tools/Lighting Lab.command`** in Finder. Choose Bluetooth for built-in presets, or USB for experimental custom patterns. USB requires a data cable **and the keyboard's wired connection selected**; a charging cable connected while Bluetooth remains selected may expose no USB configuration interface. Receiver zone writes are not implemented in this lab.

The menu runs each native preset for six seconds, or a selected zone animation for six seconds. It prints the current test name and writes a private local report. Press **Control+C** to stop early and restore the previous effect. Watch the physical output: an acknowledged command alone does not establish that an effect is visible.

Developer commands from the repository root:

```sh
python3 tools/lighting_lab.py list
python3 tools/lighting_lab.py run bluetooth --pattern presets --seconds 6
python3 tools/lighting_lab.py run usb --pattern scan --seconds 8
python3 tools/lighting_lab.py run usb --pattern macro-pulse --seconds 8
```

Durations must be 2–30 seconds. For `presets` this is the duration **per step** (nine steps); for a zone pattern it is the total duration. Commands do not accept arbitrary opcodes, effect IDs, rates, profiles, region addresses, or dimensions.

## Patterns

| Name | Output | Connection |
| --- | --- | --- |
| `presets` | Red/green/blue static, one-color/two-color/random breathing, spectrum, Wave left/right | Bluetooth or experimental USB |
| `macro-solid` | Cyan shared M1–M5 column; other zones dark | Experimental USB |
| `macro-pulse` | Gentle two-second pulse on the shared macro column | Experimental USB |
| `macro-colors` | Amber/green/red status colors on the shared macro column | Experimental USB |
| `scan` | One cyan zone steps through all 19 zones | Experimental USB |
| `chase` | Moving cyan line with a four-zone fading trail | Experimental USB |
| `progress` | Progress bar fills, then resets | Experimental USB |
| `rainbow` | Moving rainbow across the 19 zones | Experimental USB |

The zone index order comes from Razer's one-row matrix and should be checked visually; this tool does not claim that all zones are equal-width physical columns. Custom frames temporarily replace the whole backlight. Macro-only tests turn the other 18 zones off, then restore the previous effect at the end.

## Recovery and evidence

Before the first write, the lab saves the current built-in effect, exact connection, and a device identity in a private recovery journal. USB stores a hash of a stable device identifier and refuses writes if no identifier is available. Bluetooth uses the paired peripheral identity. The journal is removed only after the saved effect is restored and readback matches. Tests refuse an unfamiliar/noncanonical starting effect or an existing custom frame, since an effect selector alone cannot reconstruct custom pixel data. Select a normal built-in effect before testing in that case.

Normal completion, Control+C, terminal hangup, termination, and command rejection attempt restoration. Unplugging, loss of Bluetooth, a crash, force kill, power loss, or closing the computer can prevent immediate restoration; reconnect the **same keyboard over the same connection** and use menu option 4/5 or:

```sh
python3 tools/lighting_lab.py restore bluetooth
python3 tools/lighting_lab.py restore usb
```

These restore only an existing saved snapshot, never select a new arbitrary effect. Do not delete the journal to bypass recovery. A pending ordinary mapping-mode journal must first be resolved in Ergo Control; the lighting lab does not consume or alter it. A process lock prevents simultaneous lab sessions, and the lab refuses to run while another Ergo Control GUI instance is open. Other external lighting software does not share this lock and must remain quit.

Reports and the recovery record live under `~/Library/Application Support/ErgoControl/LightingLab/` with private permissions. Reports contain pattern names, normalized effect parameters, frame counts, errors, and restoration results; no typed keys or device serials. Existing Bluetooth diagnostic logs remain private under the neighboring Bluetooth folder. The tools do not enter driver mode, seize input, install drivers, write macros/firmware, or change onboard profiles.

## Protocol boundary and verification status

Bluetooth preset tests reuse the app's established protocol-3.0 effect writer and verified readback (`10/03`, `10/83`). They do not unlock custom Bluetooth frames. Existing app hardware tests confirm the presets broadly; the lab's complete nine-step sequence still requires observation, particularly two-color breathing.

USB templates were recovered by static inspection of this model's `rzDevice25.72e2cedb9d2be4eb79fd.js` (hash/provenance in [PROTOCOL.md](PROTOCOL.md)), independently implemented in Swift:

- Read effect: class `0f`, ID `82`, 80-byte request template, profile 0 / region 0.
- Set effect: class `0f`, ID `02`, `[profile=0, region=0, effect, flags, rate, count, RGB…]`.
- Select custom frames: the same setter with effect 8, flags/rate/count 0.
- Frame: class `0f`, ID `03`, `[profile=0, region=0, row=0, start=0, end=18, 57 RGB bytes]`.

The report is 90 bytes, using the same feature-report envelope/checksum as the read-only USB inspector. The lab validates transaction/opcode/checksum/status, serializes commands, checks custom-mode selection, and limits animation updates to at most five frames per second. It currently requires each frame's acknowledgement; the vendor streamer sometimes skips those reads, so unsupported frame acknowledgements could stop a test even if writes are supported. No unbounded retries or blind alternate opcodes are attempted. Unknown starting effects abort before any write.

**USB zone output and restoration remain hardware-unverified until a real test succeeds.** The existing `ErgoUSBInspector` remains read-only. Receiver transport, direct indicator RGB control, per-key LEDs, and Codex integration are not added by this tool.
