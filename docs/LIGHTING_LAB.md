# Lighting Lab

This optional test tool compares the keyboard's native effects and tries independently generated 19-zone animations. It uses the signed Ergo Control executable, not a Razer/Chroma installation. Normal app use never runs these tests.

**A moving line across the keyboard is plausible; a line moving separately through M1, M2, M3, M4, and M5 is not exposed.** Those five buttons share one lighting zone in [Razer's device map](MACRO_LIGHTING.md). The macro-column tests change them together.

## Run a test

Build the current app, then quit Ergo Control through its menu bar. Also quit Probe, Bluetooth diagnostics, and Razer's configuration apps so their commands do not overlap. Leave brightness above 0%; the lab deliberately does not change brightness or input mode.

Double-click **`tools/Lighting Lab.command`** in Finder. Options 1/2 compare built-in presets; option 3 tests USB zone patterns, and option 6 tests Bluetooth zone patterns. USB requires a data cable **and the keyboard's wired connection selected**; a charging cable connected while Bluetooth remains selected may expose no USB configuration interface. Receiver zone writes are not implemented in this lab.

The menu runs each native preset for six seconds, or a selected zone animation for six seconds. It prints the current test name and writes a private local report. Press **Control+C** to stop early and restore the previous effect. Watch the physical output: an acknowledged command alone does not establish that an effect is visible.

Developer commands from the repository root:

```sh
python3 tools/lighting_lab.py list
python3 tools/lighting_lab.py run bluetooth --pattern presets --seconds 6
python3 tools/lighting_lab.py run usb --pattern scan --seconds 8
python3 tools/lighting_lab.py run usb --pattern macro-pulse --seconds 8
python3 tools/lighting_lab.py run bluetooth --pattern macro-pulse --seconds 10 --experimental-frames
python3 tools/lighting_lab.py run bluetooth --pattern throughput --seconds 5 --experimental-frames
python3 tools/lighting_lab.py run bluetooth --pattern native-wave --seconds 6 --experimental-frames
```

Durations must be 2–30 seconds. For throughput, the duration applies to each of three stages, plus connection/restoration time. For `presets` this is the duration **per step** (nine steps); for a zone pattern it is the total duration. Bluetooth zone patterns require the explicit research flag (the menu adds it). Commands do not accept arbitrary opcodes, effect IDs, rates, profiles, region addresses, or dimensions.

## Patterns

| Name | Output | Connection |
| --- | --- | --- |
| `throughput` | Current serial path, queued verified frames, isolated vendor-style stream; measured rates | Bluetooth lab only |
| `native-wave` | Fixed native Wave palette probe; observed rainbow despite blue/black parameters | Bluetooth lab only |
| `presets` | Red/green/blue static, one-color/two-color/random breathing, spectrum, Wave left/right | Bluetooth or experimental USB |
| `macro-solid` | Cyan shared M1–M5 column; other zones dark | USB / Bluetooth lab |
| `macro-pulse` | Gentle two-second pulse on the shared macro column | USB / Bluetooth lab; observed on both |
| `macro-colors` | Amber/green/red status colors on the shared macro column | USB / Bluetooth lab |
| `scan` | One cyan zone steps through all 19 zones | USB / Bluetooth lab |
| `chase` | Moving cyan line with a four-zone fading trail | USB / Bluetooth lab; observed on USB |
| `progress` | Progress bar fills, then resets | USB / Bluetooth lab |
| `rainbow` | Moving rainbow across the 19 zones | USB / Bluetooth lab |

The zone index order comes from Razer's one-row matrix and should be checked visually; this tool does not claim that all zones are equal-width physical columns. Custom frames temporarily replace the whole backlight. Macro-only tests turn the other 18 zones off, then restore the previous effect at the end.

## Recovery and evidence

Before the first write, the lab saves the current built-in effect, exact connection, and a device identity in a private recovery journal. USB stores a hash of a stable device identifier and refuses writes if no identifier is available. This keyboard exposes no standard USB serial (`iSerialNumber=0`), so the lab can obtain it through the read-only vendor serial getter instead; raw serials are never printed or logged. Bluetooth uses the paired peripheral identity. Bluetooth zone snapshots also preserve profile 0 and the actual reported region, so recovery reads/writes that same target; older Bluetooth preset snapshots retain their profile-1 behavior. The journal is removed only after the saved effect is restored and readback matches. Tests refuse an unfamiliar/noncanonical starting effect or an existing custom frame, since an effect selector alone cannot reconstruct custom pixel data. Select a normal built-in effect before testing in that case.

Normal completion, Control+C, terminal hangup, termination, and command rejection attempt restoration. Unplugging, loss of Bluetooth, a crash, force kill, power loss, or closing the computer can prevent immediate restoration; reconnect the **same keyboard over the same connection** and use menu option 4/5 or:

```sh
python3 tools/lighting_lab.py restore bluetooth
python3 tools/lighting_lab.py restore usb
```

These restore only an existing saved snapshot, never select a new arbitrary effect. Do not delete the journal to bypass recovery. A pending ordinary mapping-mode journal must first be resolved in Ergo Control; the lighting lab does not consume or alter it. A process lock prevents simultaneous lab sessions, and the lab refuses to run while another Ergo Control GUI instance is open. Other external lighting software does not share this lock and must remain quit.

Reports and the recovery record live under `~/Library/Application Support/ErgoControl/LightingLab/` with private permissions. Reports contain pattern names, normalized effect parameters, frame counts, errors, and restoration results; no typed keys or device serials. Existing Bluetooth diagnostic logs remain private under the neighboring Bluetooth folder. The tools do not enter driver mode, seize input, install drivers, write macros/firmware, or change onboard profiles.

## Protocol boundary and verification status

Bluetooth preset tests reuse the app's established protocol-3.0 effect writer and verified readback (`10/03`, `10/83`). The separate opt-in zone path uses profile 0 and a hardware-reported lighting region. Existing app hardware tests confirm the presets broadly; the lab's complete nine-step sequence still requires observation, particularly two-color breathing.

Bluetooth custom frames were recovered from the same model's `rzDevice30.a29e745b43244151d1fa.js` and its `setChromaFrameLightingEngine`/`je` encoder. The tested sequence is:

1. Read the lighting-region list using `10/80`, arguments `0/1`. The live keyboard returned `[5]` (Backlight).
2. Read and save the current effect using `10/83`, arguments `0/5`.
3. Select custom effect using `10/03`, arguments `0/5`, payload `[8,0,0,0]`; verify effect ID 8 by readback.
4. Send `10/04`, arguments `0/5`, payload `[4,0,0,0,18]` followed by 57 RGB bytes. Type 4 selects rectangular RGB data, rows 0…0, columns 0…18. Commands are acknowledged and serialized; the lab caps scheduling at four frames/sec (live throughput was about two).
5. Restore the exact saved effect using `10/03` at the same `0/5` target; verify readback before removing recovery.

The generic AllRegion target `0/0` accepted custom-effect selection but rejected frame data with status 7. Retrying against the **reported** region 5 succeeded. This is not a target-ID scan. The vendor's hardware-effects-only/no-Studio flags do not establish a firmware prohibition on custom frames. Normal mapping sessions and the regular app effect picker still do not send custom frames.

USB templates were recovered by static inspection of this model's `rzDevice25.72e2cedb9d2be4eb79fd.js` (hash/provenance in [PROTOCOL.md](PROTOCOL.md)), independently implemented in Swift:

- Read effect: class `0f`, ID `82`, 80-byte request template, profile 0 / region 0.
- Read serial (identity fallback only): class `00`, ID `82`, 22-byte zero template; validated ASCII serial is hashed locally.
- Set effect: class `0f`, ID `02`, `[profile=0, region=0, effect, flags, rate, count, RGB…]`.
- Select custom frames: the same setter with effect 8, flags/rate/count 0.
- Frame: class `0f`, ID `03`, `[profile=0, region=0, row=0, start=0, end=18, 57 RGB bytes]`.

The report is 90 bytes, using the same feature-report envelope/checksum as the read-only USB inspector. The lab validates transaction/opcode/checksum/status, serializes commands, checks custom-mode selection, and limits animation updates to at most five frames per second. It currently requires each frame's acknowledgement; the vendor streamer sometimes skips those reads, so unsupported frame acknowledgements could stop a test even if writes are supported. No unbounded retries or blind alternate opcodes are attempted. Unknown starting effects abort before any write.

On 15 October 2026, live USB tests entered custom-frame mode and completed eight-second `chase` and `macro-pulse` runs, each with 35 acknowledged frames. The original effect was restored and independently read back after each run; no recovery remained pending. The user confirmed a cyan line moving across the keyboard and a visible pulsing pattern. A subsequent 20-second USB macro pulse sent 87 acknowledged frames, and the user confirmed **only M1–M5 pulse, with all other keys dark**.

The subsequent ten-second **Bluetooth-only** macro pulse targeted reported region 5 and sent 20 acknowledged frames. The user confirmed the same isolated M1–M5 pulse; saved-effect restoration was read-back verified. Neither test required Chroma or a Razer driver. Other generated patterns and physical interruption recovery remain untested. The existing `ErgoUSBInspector` remains read-only. Receiver transport, direct indicator RGB control, per-key LEDs, and Codex integration are not added by this tool.


## Bluetooth speed comparison (0.6.8)

The throughput test keeps every ATT write acknowledged. Its final phase follows the vendor's separate frame-stream behavior: queue the header and 20-byte payload pieces, finish the frame at write completion, observe keyboard response headers separately, and drain replies at the end. It uses an isolated configuration connection, then disconnects before the normal controller reconnects to restore/read-verify the saved effect. The regular Codex renderer does not use this experimental stream. [Apple documents write completion separately from application-level responses](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)).

A five-second-per-stage comparison on 16 October 2026 measured serial 2.55 fps (13 frames; median 466 ms), queued-with-command-verification 2.15 fps (11; 470 ms), and streaming 2.01 fps (11; 521 ms). All 11 streamed frames had successful zero-payload keyboard replies by the drain boundary, and the original effect was restored and verified. This sample shows no speed improvement from queueing/streaming; it does not establish an absolute Bluetooth/hardware ceiling.

The native-wave experiment uses the existing common effect envelope with exactly [4,2,40,2,0,120,255,0,0,0] at profile 0 / reported region 5. The keyboard acknowledged it and returned that exact payload, then restored its original effect. The user subsequently confirmed a **rainbow moving right to left**, rather than blue/black motion. This tested native Wave ignores the supplied palette despite successful readback; it does not establish that every possible colored firmware animation is unsupported. The regular effect picker continues to refuse Wave palettes. Retain this probe for reproducibility, not as a supported colored effect.

A subsequent complete-payload write experiment failed despite CoreBluetooth advertising a 512-byte acknowledged-write maximum. The keyboard's configuration channel remained busy across reconnects until the user power-cycled/reconnected it; saved-effect recovery then succeeded and was read-back verified. The experimental larger-write code was removed. Normal and retained lab paths still use twenty-byte payload pieces; do not infer protocol support from the platform's maximum write size.

### Production follow-up (0.8.2)

After the settings/UI workload changed, production timing logs showed 300–350 ms gaps between serially submitted pieces in some frames. The status renderer now queues the same small with-response pieces together while retaining complete ATT and keyboard acknowledgements. Four initial live working frames took 149–165 ms, whereas the prior session ranged from 194 to 840 ms over 17 frames. This small non-controlled observation differs from the older isolated lab result above; it does not invalidate that historical measurement or establish a hardware maximum. Production still has one outstanding protocol transaction and does not use the experimental frame-response stream or larger payload chunks.
