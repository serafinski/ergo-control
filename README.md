<img src="resources/AppIcon.png" width="96" height="96" alt="Ergo Control icon">

# Ergo Control

A lightweight native macOS menu-bar app for the **Razer Pro Type Ergo (RZ03-0544)** over Bluetooth. Configure buttons, macros, application profiles, and dials without running Synapse.

Ergo Control uses SwiftUI and macOS frameworks, with no third-party runtime packages. It targets only the keyboard’s Bluetooth identity (`068e:02c3`); other keyboards and mice are outside its capture scope. This is an independent project, not affiliated with Razer.

## Features

- Assign M1–M5, AI, dial controls, media controls, and ordinary keys.
- Run shortcuts, text actions, timed macros, selected scripts, and application actions.
- Show or minimize a chosen application with one button.
- Switch profiles automatically for the active application, or select one manually.
- Configure command-dial modes, including keyboard brightness, zoom, scrolling, browser tabs, and the visible native ⌘Tab switcher.
- Use an alternate layer.
- See a brief popup when changing dial modes. Per-mode physical indicator colors are experimental.
- Press the battery button, or any control assigned **Show battery**, for an on-screen percentage.
- Keep the keyboard icon and battery percentage in the menu bar, without a Dock icon.
- Store profiles locally and restore the keyboard’s saved mode when mappings stop.
- Optionally open five assigned Codex chats with M1–M5, show lifecycle status in the app/menu, and color the shared macro column. See [Codex setup and limits](docs/CODEX_SETUP.md).

## Supported hardware and current status

Version **0.3.0** supports **Bluetooth Low Energy** on the Pro Type Ergo. USB and wireless-receiver mappings are not implemented. A separate [read-only USB dial diagnostic](docs/USB_RESEARCH.md) is available for research. The deployment target is macOS 14 or later; hardware validation so far is on Apple Silicon with macOS 27.0.1.

Live tests confirm distinct M1–M5/AI/dial/battery inputs, keyboard brightness across 0–100%, M1 text output, an M2 timed macro, exclusive keyboard capture with left-dial output, normal-mode restoration after timed sessions, the mode popup, menu-bar battery display, and absence from the Dock. **114 automated tests pass.** The opt-in Codex integration is implemented and awaiting its first live end-to-end check; see [setup](docs/CODEX_SETUP.md). The optional lighting lab produced a user-confirmed moving cyan line over USB and isolated M1–M5 pulsing over both USB and Bluetooth, with effect restoration verified by readback. The user confirmed native Backspace speed, normal D/E typing after navigation, and Magnet’s Control–Option–arrow/Return shortcuts after the build-32 input corrections. Remaining validation includes the physical dial indicator, the new split-key defaults, native application-switcher overlay, app minimize/restore, per-app profiles, alternate layers, non-US layouts, and abnormal recovery. See [setup and verification](docs/APP.md).

The battery popup requests a fresh reading, stays visible for two seconds after the result, and keeps the current app focused. The user confirmed the popup works. Quick reads display the percentage directly; **Checking…** appears only if retrieval takes more than two seconds.

Keyboard backlight brightness is hardware-confirmed and now shows a brief percentage popup. Physical dial-indicator colors are still under investigation: earlier color targets/commands were rejected over Bluetooth. Tests with nonzero backlight still rejected RGB target 39, including the four-byte payload and enabling the indicator first. The on/off command is accepted and read back, but physical illumination is unconfirmed; The current diagnostic path reads literal LED IDs and types, without new indicator writes; these reads also returned status 7. Native colors return over Bluetooth when mappings are off, even with Ergo Control open. Razer’s own Mac/Bluetooth color writes were also rejected with its drivers enabled. Recovering dedicated dial control while mappings are active remains unresolved. Mode colors remain experimental; no physical indicator success is claimed. Unsupported lighting commands leave mappings active. Built-in keyboard backlight effects are available in the Keyboard lighting panel (Off, Static, Breathing, Spectrum cycling, and Wave; effects omitted from the Bluetooth list can be tried explicitly and are checked by readback). Static and Breathing have color choices; Wave has direction controls. General per-zone/custom animation settings are not implemented in the regular app; optional Codex status uses the shared macro zone with a white background; the optional Lighting Lab experiments with USB/Bluetooth zone patterns. Firmware updates, onboard macro storage, and Fn-row primary-mode writes are not implemented. Profiles and macros run on the Mac while mappings are enabled. There is no signed/notarized release download yet.

## Build

Install Xcode or its Command Line Tools with **Swift 5.9 or newer**, plus Python 3. The packaging scripts use macOS’s signing, Keychain, and installer tools and an `openssl` executable. Build on macOS:

```sh
git clone https://github.com/serafinski/ergo-control.git
cd ergo-control
swift test
zsh tools/build_app.sh
```

**Ergo Control is the only app needed for everyday use.** “Ergo Control Preview” was a development name for the same app, not a second product. Builds now always produce `build/Ergo Control.app`, with its own app icon and matching menu-bar mark.

Open `build/Ergo Control.app` in Finder. The script creates the app and optional helper installer packages; it does not install or start the helper.

Local builds create a persistent development signing identity in the ignored `build/local-signing/` directory. Keep that directory private and preserve it between builds to retain the same signing identity. Developer ID signing/notarization is a separate distribution step. See [helper and signing details](docs/INPUT_HELPER.md).

## Setup and use

1. Keep PT Ergo connected over Bluetooth. Quit the diagnostic apps and the Synapse/App Engine GUI before enabling mappings.
2. Grant **Ergo Control** Input Monitoring and Accessibility in System Settings → Privacy & Security. Accept its Bluetooth prompt.
3. For full dial/keyboard replacement, click **Install input helper…**, complete the macOS administrator installer, then grant the installed helper its own Input Monitoring entry. Its path is `/Library/PrivilegedHelperTools/dev.local.ergocontrol.inputhelper`.
4. Configure a simple M1 **Type text** action, save it, and use **60-second test** before regular sessions. Focus **Try your mappings** and press M1.
5. Use **Enable mappings** for normal operation. Close Settings to leave the app in the menu bar; reopen it through **Settings…** there. **Stop mappings** releases input and requests a verified restoration. **Quit Ergo Control** exits after restoration when required.

The optional input helper is this project’s small, narrowly scoped launch daemon; it is not a Razer driver or a kernel/system extension. A limited non-seizing extra-button mode is available without full capture, but cannot replace ordinary keys or dial/media actions. See [setup and limitations](docs/APP.md) and [the helper’s trust boundary](docs/INPUT_HELPER.md).

Settings live under `~/Library/Application Support/ErgoControl/Settings/`. The mapping app does not save ordinary typed text; the optional probe records raw input only during explicitly started tests. Captures, Bluetooth diagnostics, vendor research artifacts, installers, and signing material are excluded from Git.

## Documentation and development

- [App setup, mappings, and validation](docs/APP.md)
- [Helper architecture, signing, and installation](docs/INPUT_HELPER.md)
- [Recovered Bluetooth and input protocol](docs/PROTOCOL.md)
- [Macro-key lighting capabilities and Chroma research](docs/MACRO_LIGHTING.md)
- [Optional lighting pattern tests and recovery](docs/LIGHTING_LAB.md)
- [Chroma value and adapting Codex Micro to five macro keys](docs/CODEX_AND_CHROMA.md)
- [Optional diagnostic apps and tools](docs/DIAGNOSTICS.md)
- [Research and hardware-test history](docs/research/INVESTIGATION.md)
- [Contributing](CONTRIBUTING.md)

The research archive preserves provenance and the distinction between static findings and observed hardware behavior. It contains documentation and hashes, not vendor binaries or extracted vendor source. A fresh clone can build and test the app without those artifacts or an installed Razer application.

## License

[MIT](LICENSE), copyright © 2026 serafinski. Razer product names and trademarks belong to their respective owners. The license applies to this project’s source and documentation, not to separately obtained vendor artifacts.

Razer's lighting map groups M1–M5 into one shared zone; separate macro-key colors are not exposed. Custom USB/Bluetooth zone control is available through the optional lighting lab, with isolated macro-column pulsing confirmed on both connections; it is not part of normal mapping sessions. See [the findings](docs/MACRO_LIGHTING.md) and [roadmap](docs/ROADMAP.md) for possible whole-column status lighting.
