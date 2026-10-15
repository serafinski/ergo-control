# Deferred work

## Lighting and Codex status

The user requested future investigation of Razer Chroma as a source of keyboard-lighting protocol information, with the eventual goal of coloring macro buttons according to Codex status. This is deferred explicitly: the current change covers keyboard brightness and the command-dial mode indicator only.

Before implementing macro-button status lighting, establish whether this model exposes individually controllable macro LEDs over Bluetooth, recover supported addresses and commands from primary evidence, and preserve existing lighting behavior. Do not infer per-key RGB support from the colored command-dial indicator or from another Razer keyboard. Define how Codex status is obtained only when that integration is requested. No Chroma software or Razer driver has been installed for this work.

## Remaining hardware validation

- Brightness long-term behavior; backlight control, 0–100% read-back, and percentage popup are now confirmed.
- Resolve physical dial-mode colors: recover the dedicated dial control under driver mode. Both decoded and literal LED-list/type/RGB reads were rejected. Native colors return over Bluetooth when mappings are disabled with the app still open; separate firmware mode from capture and recover a Bluetooth equivalent of the now-confirmed USB knob getter. USB stage/color tracking succeeded; two read-only Bluetooth adaptations and the normal-mode RGB baseline were rejected. Positive-backlight tests, four-byte RGB payloads, and enabling the recovered switch first still reject RGB target 39. The native indicator’s backlight prerequisite is user-confirmed; no successful host-driven RGB control is claimed.
- Split-space/B/Backspace defaults, native application-switcher overlay, app minimize/restore.
- App-specific profiles, alternate layers, non-US layouts, sleep/disconnect/crash recovery.

USB/receiver support, custom per-zone lighting animations, firmware updates, onboard macro storage, and Fn-row primary-mode writes are outside the current implementation. Version 0.2.7 adds the keyboard’s built-in firmware effects as a separate global lighting setting.

## Chroma and driver comparison

A documentation check requested on 2026-10-14 confirmed Razer advertises [19-zone Chroma RGB](https://www.razer.com/productivity/razer-pro-type-ergo?page=tech-specs) for this keyboard and a [Chroma app preview for macOS](https://www.razer.com/synapse-4-mac). Neither establishes a public SDK address for the small command-dial indicator. The older [SDK setup guide](https://developer.razer.com/works-with-chroma/setting-up/) and [SDK FAQ](https://developer.razer.com/works-with-chroma/chroma-faq/) describe vendor SDK components/services; their Windows-oriented examples should not be treated as a current Mac compatibility statement. Independent access to each macro button's LED is unverified, despite the keyboard's zone lighting.

The installed Razer HID Driver Extension was disabled and its Virtual HID Driver Extension enabled during the successful USB getter reads. Ergo Control/helper were stopped and no restoration journal remained before asking the user to enable the existing Razer HID driver for a controlled Bluetooth-only custom-color test. The controlled test subsequently enabled both Razer extensions, but the user saw no indicator response. Fresh Razer logs show its class-6/ID-4 RGB writes rejected as Target ID Not Support, and mode 3/0 being selected. This reproduces our failure with the vendor driver enabled. Native firmware fallback is the leading explanation; there is no working custom Bluetooth color path from this test to capture. General Chroma support does not establish that the mode LED is a public Chroma target. No driver or Chroma package has been installed by this project, and the tool does not depend on vendor code. Custom Chroma animations and Codex macro-button status integration remain deferred; the built-in backlight effects added in 0.2.7 use the keyboard’s own firmware.
