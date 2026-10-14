# ErgoControl

Bluetooth-first investigation and standalone macOS replacement for Synapse on the Razer Pro Type Ergo (RZ03-0544).

The first **Ergo Control** mapping app is now implemented and builds as a native SwiftUI menu-bar application. It uses only macOS frameworks and has no third-party runtime packages. The input protocol is hardware-verified. macOS denied exclusive keyboard access with a privilege error; build 0.1.1 falls back to extra-button observation. M1–M5, AI, left click, and battery assignments can use that path; full dial/ordinary-key replacement remains blocked. Physical M1 text output, an M2 macro combining text, pauses and Command+A, and automatic test expiry with verified normal-mode restoration now work on real hardware. Other action types still need live validation. It is a development build, not a finished daily-use release.

Version 0.2.2 now bundles an optional input helper and local administrator-approved installer intended to enable full dial/keyboard replacement. Bundled Service Management registration was rejected for the unnotarized development build. Release builds, signature checks, and installer inspection pass; the 0.2.1 helper installed successfully, but capture remained denied after its Input Monitoring grant. The 0.2.2 update adds fresh processes per session and a read-only permission check; updated installation and capture tests remain pending. See [helper architecture and validation](docs/INPUT_HELPER.md). A separate `build/Ergo Control Preview.app` preserves the working 0.1.1 build.

Build with `zsh tools/build_app.sh`, then open `build/Ergo Control.app`. See [app setup and validation](docs/APP.md). The diagnostic apps below remain available separately.

Build with `zsh tools/build_probe.sh`. Open `build/Ergo Probe.app`.

1. Enable **Ergo Probe** under **System Settings → Privacy & Security → Input Monitoring**. If it is absent, use **+** to add the app from this repository's `build` folder. Relaunch if macOS requests it.
2. Keep the keyboard connected over Bluetooth. Select a control in the left sidebar and click **Start Test**. Capture starts and labels the test automatically.
3. Operate only that control three times, then click **Finish Test**. Capture stops, and the result remains in that control's section. Each attempt gets its own JSONL file, named for the control.
4. Select **Baseline**, start a test, leave the keyboard alone for five seconds, then finish. Test **Ordinary key** by pressing A three times; this positive control distinguishes missing controls from a non-working capture.
5. Test both dials, clicks, Shift + left click, M1–M5, AI, media, and battery controls separately. Record the left dial's current mode in your notes. You cannot switch controls while a test is recording; finish or clear the active test first.
6. If an attempt goes wrong, click **Clear Test** to reset just that section, then **Start Test** to retry. Clear stops an active recording and marks it discarded. Earlier recording files remain locally for reference; the saved test list contains only the current result for each control.
7. **Show This Test's File** reveals the selected control's recording; **Show All Recordings** opens the folder. Recordings and the persistent `tests-index.json` are in `~/Library/Application Support/ErgoControl/Captures/`. A new attempt replaces that control's displayed result when finished; other controls' results remain unchanged.

Optional: expand **Connection options** and enable Bluetooth observation before starting a test. This connects only to the paired peripheral identifier obtained from the matched keyboard and subscribes to its known Protocol 30 characteristic. Subscription changes the connection's notification setting; it sends no Razer configuration commands.

This development build uses an ad-hoc code signature. Rebuilding changes its signature, and macOS may keep an enabled Input Monitoring entry for the previous executable while denying the new one. If toggling the entry and relaunching does not restore access, remove only **Ergo Probe** from that list, then use **+** to add the current `build/Ergo Probe.app` and reopen it. Re-adding the current app restored access during local testing. Other input-tool permissions should remain unchanged.

Capture includes ordinary keys from PT Ergo while active, so finish before entering private text. No other input device is opened, no input is seized or suppressed, and no driver, startup service, or mapping is installed. Start Test refreshes the matched device list after sleep or reconnection. If the keyboard disconnects during a recording, finish it, wake/reconnect the keyboard, then retry; automatic recovery during an active recording is not implemented yet.

Useful commands:

```sh
swift test
python3 tools/collect_evidence.py
python3 tools/fetch_device_sources.py
python3 tools/analyze_capture.py '/absolute/path/to/capture.jsonl'
'build/Ergo Probe.app/Contents/MacOS/ErgoProbe' --inventory
```

The Python tools verify evidence, collect scoped local facts, download public vendor source files for static inspection, and summarize marked captures. Downloaded JavaScript and libraries are never executed. Large vendor artifacts, private capture files, and local analysis remain outside Git.

See [the investigation](docs/INVESTIGATION.md) for observed facts, source locations, control identifiers, and remaining work. The original [handoff](razer-ergo-codex-handoff/HANDOFF.md) retains the project goal and earlier tests.

## Bluetooth configuration investigation

`zsh tools/build_bluetooth.sh` builds a separate `build/Ergo Bluetooth.app`. It leaves the working Ergo Probe app and its Input Monitoring signature unchanged. This helper needs macOS Bluetooth access, but never opens HID input devices.

**Connect & Read Mode** identifies the paired peripheral from the exact PT Ergo HID identity, discovers the vendor service, enables response notifications, and issues the recovered Get Device Mode query. Requests use acknowledged writes, an eight-byte header, separate payload fragments, one active transaction, a bounded response assembler, and a five-second command timeout. Hardware testing successfully read normal mode (0/0), enabled driver mode (3/0), and exposed distinct M1–M5, AI, left-dial-click, and battery-button press/release inputs. They share physical report ID 5 but contain different key identifiers (32–36, 247, 96, and 65).

The temporary-mode button remains disabled until a successful two-byte response identifies normal mode. Its implementation saves the original mode locally before sending a change, verifies driver mode with a read query, restores after 60 seconds, and verifies restoration with another read query. A pending-restoration file survives process exit; the app defers normal termination while restoration is owed and retries after connection loss. Manual early restoration and its read-back verification succeeded after the live tests. Timer expiry and failure recovery are implemented but not yet hardware-validated. Do not treat a disconnected keyboard or an unacknowledged write as successful restoration.

The helper logs command headers, payloads, responses, and restoration state locally under `~/Library/Application Support/ErgoControl/Bluetooth/`. No firmware or key-mapping writes are implemented.

For self-directed driver-mode tests, start a 60-second window in Ergo Bluetooth, then use the existing per-control Start/Finish/Clear flow in Ergo Probe. Finish each recording before restoration; retry a cleared attempt if the countdown expires mid-test. Probe 0.3 decodes extra keys, media actions, left-dial turns, and brightness notifications into readable names and re-labels compatible saved recordings on launch.

The Bluetooth helper also has **Read Battery**, which queries the keyboard without changing its mode. Hardware validation returned battery ID 1, raw level 168, displayed as 65%. This is independent of capturing the battery button. Optional Shift + left click is documented by Razer but remains untested.

Verified driver-mode left-dial rotation produces independent horizontal-pan inputs (+1 clockwise, −1 counterclockwise), separate from its normal brightness behavior. Left dial click and battery button are also exposed in driver mode. Configurable actions and profiles are the next implementation stage; these probes do not yet remap controls.
