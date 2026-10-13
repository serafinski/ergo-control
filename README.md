# ErgoControl

Bluetooth-first investigation and standalone macOS replacement for Synapse on the Razer Pro Type Ergo (RZ03-0544).

The current deliverable is **Ergo Probe**, a native diagnostic application. It identifies only the Bluetooth keyboard with vendor/product `068e:02c3`, records raw HID reports and decoded HID values, and can separately observe its Razer Bluetooth configuration characteristic. The complete mapping application is not implemented yet; missing controls must first be verified on this keyboard.

Build with `zsh tools/build_probe.sh`. Open `build/Ergo Probe.app`.

1. Enable **Ergo Probe** under **System Settings → Privacy & Security → Input Monitoring**. If it is absent, use **+** to add the app from this repository's `build` folder. Relaunch if macOS requests it.
2. Keep the keyboard connected over Bluetooth. Select a control in the left sidebar and click **Start Test**. Capture starts and labels the test automatically.
3. Operate only that control three times, then click **Finish Test**. Capture stops, and the result remains in that control's section. Each attempt gets its own JSONL file, named for the control.
4. Select **Baseline**, start a test, leave the keyboard alone for five seconds, then finish. Test **Ordinary key** by pressing A three times; this positive control distinguishes missing controls from a non-working capture.
5. Test both dials, clicks, Shift + left click, M1–M5, AI, media, and battery controls separately. Record the left dial's current mode in your notes. You cannot switch controls while a test is recording; finish or clear the active test first.
6. If an attempt goes wrong, click **Clear Test** to reset just that section, then **Start Test** to retry. Clear stops an active recording and marks it discarded. Earlier recording files remain locally for reference; the saved test list contains only the current result for each control.
7. **Show This Test's File** reveals the selected control's recording; **Show All Recordings** opens the folder. Recordings and the persistent `tests-index.json` are in `~/Library/Application Support/ErgoControl/Captures/`. A new attempt replaces that control's displayed result when finished; other controls' results remain unchanged.

Optional: expand **Connection options** and enable Bluetooth observation before starting a test. This connects only to the paired peripheral identifier obtained from the matched keyboard and subscribes to its known Protocol 30 characteristic. Subscription changes the connection's notification setting; it sends no Razer configuration commands.

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
