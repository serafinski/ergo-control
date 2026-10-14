# Ergo Control — first mapping build

Build: `zsh tools/build_app.sh`. Application: `build/Ergo Control.app`, bundle ID `dev.local.ergocontrol.app`.

This native SwiftUI app has local profiles, app-based automatic switching, ordinary-key and extra-control assignments, configurable command-dial modes, an alternate layer, gaming-mode shortcut blocking, and a menu-bar control. Actions include shortcuts, timed macros, text, app launch, selected zsh scripts, scrolling, media, dial-mode cycling, and battery display.

## Current verification boundary

Version 0.2.2 now opens PT Ergo exclusively through the installed helper. The user confirmed the live ordinary-typing/clockwise-dial test works with a saved **Type text → CW** mapping. `Settings/input-status.json` records `fullKeyboard`, open result 0. The 60-second session returned mode 0/parameter 0 through verified Bluetooth read-back, removed its pending-restoration record, and the helper exited with code 0. A separate authenticated read-only helper check reports Input Monitoring granted (0) and also exits cleanly without opening a keyboard. See [INPUT_HELPER.md](INPUT_HELPER.md) for the installation and permission evidence.

Earlier hardware tests confirmed M1 text output and an M2 macro combining text, pauses and Command+A. The input protocol and battery query are hardware-verified; 29 core tests pass. Full input access was originally denied to the GUI, so the tested non-seizing extra-button route remains available without the helper. App-specific switching, alternate layers, launch/script actions, menu-bar interactions, other dial/media output paths, less common keys, and failure recovery still need live verification. The revised layout keeps the selected action editor visible on the right and collapses advanced settings. Native UI automation is intermittent, so recent hardware testing was user-directed.

Keyboard lighting/brightness writes, RGB configuration, firmware updates, onboard macro storage, and Fn-row primary-mode writes are not implemented. Profiles and macros run on the Mac while the app is enabled. The alternate layer uses an explicitly assigned hold button; it does not assume the firmware exposes a separate Hypershift/Fn key.

## First setup

1. Open Ergo Control. Keep mappings off initially.
2. Grant **Ergo Control** its own **Input Monitoring** and **Accessibility** entries in System Settings → Privacy & Security. The diagnostic apps' grants do not cover this separate bundle. Input Monitoring permits reading input; Accessibility permits emitting mapped keyboard actions. The code matches only Bluetooth PT Ergo `068e:02c3`.
3. Quit Ergo Probe, Ergo Bluetooth, and the Razer Synapse/App Engine GUI before enabling mappings. The app checks these exact app bundle IDs; it does not stop services or alter drivers.
4. Configure a harmless M1 **Type text** action such as `Ergo test`, then save. Use the **60-second test** button for the first test. Allow the app's expected Bluetooth prompt to connect to the paired keyboard.
5. For full dial/keyboard replacement in this development build, use **Install input helper…** and complete macOS Installer's administrator authorization. Add `/Library/PrivilegedHelperTools/dev.local.ergocontrol.inputhelper` to **Input Monitoring** separately from the GUI. Reopen the app, **Refresh status**, and use **Check helper permission** with mappings off. See [INPUT_HELPER.md](INPUT_HELPER.md) if setup fails.
6. Click inside **Try your mappings** and press M1. The saved text should appear. In extra-button mode, ordinary typing and native dial/media input continue through macOS; their replacement mappings are unavailable. Check stop/quit returns the keyboard to its saved mode before daily use.

For **Command dial modes**, leave both left-dial direction mappings set to **Default** and leave left dial click at **Default**. The click cycles enabled modes. An explicit clockwise/counterclockwise action overrides that direction's current mode; the saved `CW` assignment is only the test action and should be replaced or reset for normal use. Mode cycling itself still needs live validation.

**Enable mappings** is the regular session control. Closing the settings window leaves the menu-bar app available. **Stop mappings** releases the keyboard and requests a read-verified mode restoration. Quit defers termination while restoration remains owed.

## Implementation

- `ErgoCore` contains packet codecs, snapshot decoders, profile models, shortcut validation, and the macro parser.
- `ErgoDevice` contains the shared serial Bluetooth configuration controller. Neither app links or loads vendor libraries.
- `ErgoControl` contains the settings UI, profile store, action engine, and exclusive HID relay.
- The relay matches exactly one Bluetooth PT Ergo. It first attempts exclusive access; when macOS returns `kIOReturnNotPrivileged`, it opens the keyboard non-exclusively and processes only physical report 5. In this mode it never synthesizes native key, pointer, dial, or media input. It creates no global event tap and opens no other input devices.
- Extra-button mode supports M1–M5, AI, left click, battery, and their alternate-layer assignments. Custom dial modes, media replacement, ordinary-key remapping, and gaming-mode blocking remain unavailable without full keyboard access. The UI disables unavailable controls after detecting this mode. Driver mode still changes the left dial to horizontal-pan input; stopping restores the saved normal mode.
- Version 0.2.2 uses an optional, scoped input helper for exclusive capture, with an explicit local installer and SMAppService for notarized distribution builds. The settings app remains unprivileged. The local helper is installed and its exclusive input route now works on this Mac. No Razer driver was installed or changed by this project. See [INPUT_HELPER.md](INPUT_HELPER.md) for its trust boundary and activation steps. Open results are saved in `Settings/input-status.json`, without raw key data.
- Unknown keyboard/media/report layouts stop mapping and return native input rather than silently swallowing an unsupported control. This needs hardware validation, especially for less common Fn-row/system keys.
- A renewed 60-second lease keeps driver mode active while the relay is running. Stop, quit, sleep, disconnect, and detected failures release input and request restoration. The deadline uses monotonic uptime. A durable saved-mode record supports restoration on a later launch after a process failure; the app cannot promise restoration while its process is killed or the keyboard is disconnected.
- Shortcuts are key chords. Macro text uses one shortcut per line, `wait 200` for a 200 ms delay, and `text Hello` for text. Macros allow at most 200 steps and 60 seconds of waits; only one macro runs at a time. Stopping mappings cancels pending macro work and releases generated held keys.
- Scripts run through `/bin/zsh` with the selected file as an argument, with output discarded. The app terminates its launched shell after 10 seconds; arbitrary descendant processes created by a script are outside this guarantee.

Settings are stored locally in `~/Library/Application Support/ErgoControl/Settings/profiles.json`, with an atomic write and a `.backup` of the previous version. Settings contain user-chosen app/script paths and macro text; they should not be committed to a public repository. The main app does not record ordinary typed text. Its in-app test pad is not persisted. Bluetooth transaction/recovery logs remain local under `ErgoControl/Bluetooth/`.

The earlier build used an ad-hoc signature. Version 0.2.2 uses a persistent, isolated local development certificate by default, or ERGO_CODESIGN_IDENTITY when supplied. The first signing-identity change may require refreshed macOS grants. Developer ID signing/notarization and publication are deferred; the optional helper requires separate macOS administrator authorization. Bundled Service Management registration failed for the local build; the explicit local installer, helper permission grant, and first full-control session now work on this Mac. Removal and distribution signing remain unverified.
