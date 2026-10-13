# ErgoControl

Bluetooth-first investigation and standalone macOS replacement for Synapse on the Razer Pro Type Ergo (RZ03-0544).

The current deliverable is **Ergo Probe**, a native diagnostic application. It identifies only the Bluetooth keyboard with vendor/product `068e:02c3`, records raw HID reports and decoded HID values, and can separately observe its Razer Bluetooth configuration characteristic. The complete mapping application is not implemented yet; missing controls must first be verified on this keyboard.

Build with `zsh tools/build_probe.sh`. Open `build/Ergo Probe.app`.

1. Enable **Ergo Probe** under **System Settings → Privacy & Security → Input Monitoring**. If it is absent, use **+** to add the app from this repository's `build` folder. Relaunch if macOS requests it.
2. Keep the keyboard connected over Bluetooth. Start **Keyboard Capture**.
3. Optionally start **Observe Bluetooth** and grant the Bluetooth prompt. This connects only to the paired peripheral identifier obtained from the matched keyboard and subscribes to its known Protocol 30 characteristic. Subscription changes the connection's notification setting; it sends no Razer configuration commands.
4. Select **Baseline**, click **Mark Test**, and leave the keyboard alone for five seconds.
5. Select **Ordinary key**, mark the test, and press A three times. This positive control distinguishes missing controls from a non-working capture.
6. Select and mark each physical control before operating it three times. Test both dials, clicks, Shift + left click, M1–M5, AI, media, and battery controls separately. Record the left dial's current mode in your notes.
7. Click **Stop & Save**, then **Show Capture File**. Captures are local JSONL files in `~/Library/Application Support/ErgoControl/Captures/`.

Capture includes ordinary keys from PT Ergo while active, so stop before entering private text. No other input device is opened, no input is seized or suppressed, and no driver, startup service, or mapping is installed. Disconnect/reconnect the keyboard before retrying a capture after a connection change; hotplug recovery is not implemented yet.

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
