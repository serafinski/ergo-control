# Ergo Control — first mapping build

Build: `zsh tools/build_app.sh`. Application: `build/Ergo Control.app`, bundle ID `dev.local.ergocontrol.app`.

This native SwiftUI app has local profiles, app-based automatic switching, ordinary-key and extra-control assignments, configurable command-dial modes, an alternate layer, gaming-mode shortcut blocking, and a menu-bar control. Actions include shortcuts, timed macros, text, app launch, selected zsh scripts, scrolling, media, dial-mode cycling, and battery display.

## Current verification boundary

The underlying PT Ergo input packets, Bluetooth mode commands, read-back restoration, and battery query were established on real hardware; see [INVESTIGATION.md](INVESTIGATION.md). The mapping app compiles and core tests pass. Its new exclusive keyboard relay, generated output, menu-bar behavior, and settings interactions have not yet been validated live. The user confirmed that the initial settings window opens. Computer-use inspection is unavailable, and the first layout was confusing; the revised layout keeps the selected action editor visible on the right and collapses advanced settings. Save/reload and live output verification remain pending.

Keyboard lighting/brightness writes, RGB configuration, firmware updates, onboard macro storage, and Fn-row primary-mode writes are not implemented. Profiles and macros run on the Mac while the app is enabled. The alternate layer uses an explicitly assigned hold button; it does not assume the firmware exposes a separate Hypershift/Fn key.

## First setup

1. Open Ergo Control. Keep mappings off initially.
2. Grant **Ergo Control** its own **Input Monitoring** and **Accessibility** entries in System Settings → Privacy & Security. The diagnostic apps' grants do not cover this separate bundle. Input Monitoring permits reading input; Accessibility permits emitting mapped keyboard actions. The code matches only Bluetooth PT Ergo `068e:02c3`.
3. Quit Ergo Probe, Ergo Bluetooth, and the Razer Synapse/App Engine GUI before enabling mappings. The app checks these exact app bundle IDs; it does not stop services or alter drivers.
4. Configure a harmless M1 **Type text** action such as `Ergo test`, then save. Use the **60-second test** button for the first test. Allow the app's expected Bluetooth prompt to connect to the paired keyboard.
5. Use **Try your mappings** to verify ordinary typing, modifiers, deletion, key repeat, M1 output, and dial behavior. Check stop/quit returns the keyboard to its saved mode before daily use.

**Enable mappings** is the regular session control. Closing the settings window leaves the menu-bar app available. **Stop mappings** releases the keyboard and requests a read-verified mode restoration. Quit defers termination while restoration remains owed.

## Implementation

- `ErgoCore` contains packet codecs, snapshot decoders, profile models, shortcut validation, and the macro parser.
- `ErgoDevice` contains the shared serial Bluetooth configuration controller. Neither app links or loads vendor libraries.
- `ErgoControl` contains the settings UI, profile store, action engine, and exclusive HID relay.
- The relay opens exactly one matching PT Ergo with `kIOHIDOptionsTypeSeizeDevice`, forwards ordinary keys through Quartz, and substitutes configured actions. It creates no global event tap and opens no other input devices.
- Unknown keyboard/media/report layouts stop mapping and return native input rather than silently swallowing an unsupported control. This needs hardware validation, especially for less common Fn-row/system keys.
- A renewed 60-second lease keeps driver mode active while the relay is running. Stop, quit, sleep, disconnect, and detected failures release input and request restoration. The deadline uses monotonic uptime. A durable saved-mode record supports restoration on a later launch after a process failure; the app cannot promise restoration while its process is killed or the keyboard is disconnected.
- Shortcuts are key chords. Macro text uses one shortcut per line, `wait 200` for a 200 ms delay, and `text Hello` for text. Macros allow at most 200 steps and 60 seconds of waits; only one macro runs at a time. Stopping mappings cancels pending macro work and releases generated held keys.
- Scripts run through `/bin/zsh` with the selected file as an argument, with output discarded. The app terminates its launched shell after 10 seconds; arbitrary descendant processes created by a script are outside this guarantee.

Settings are stored locally in `~/Library/Application Support/ErgoControl/Settings/profiles.json`, with an atomic write and a `.backup` of the previous version. Settings contain user-chosen app/script paths and macro text; they should not be committed to a public repository. The main app does not record ordinary typed text. Its in-app test pad is not persisted. Bluetooth transaction/recovery logs remain local under `ErgoControl/Bluetooth/`.

The build uses an ad-hoc signature. Rebuilding can invalidate existing macOS grants. A stable developer signature is a later distribution task; publication and driver installation are deferred.
