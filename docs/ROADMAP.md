# Deferred work

## Lighting and Codex status

The user requested future investigation of Razer Chroma as a source of keyboard-lighting protocol information, with the eventual goal of coloring macro buttons according to Codex status. This is deferred explicitly: the current change covers keyboard brightness and the command-dial mode indicator only.

Before implementing macro-button status lighting, establish whether this model exposes individually controllable macro LEDs over Bluetooth, recover supported addresses and commands from primary evidence, and preserve existing lighting behavior. Do not infer per-key RGB support from the colored command-dial indicator or from another Razer keyboard. Define how Codex status is obtained only when that integration is requested. No Chroma software or Razer driver has been installed for this work.

## Remaining hardware validation

- Brightness long-term behavior; backlight control, 0–100% read-back, and percentage popup are now confirmed.
- Resolve physical dial-mode colors: recover the dedicated dial control under driver mode. Both decoded and literal LED-list/type/RGB reads were rejected. Native colors return over Bluetooth when mappings are disabled with the app still open; separate firmware mode from capture and compare the USB knob API without assuming it works over Bluetooth. Positive-backlight tests, four-byte RGB payloads, and enabling the recovered switch first still reject RGB target 39. The native indicator’s backlight prerequisite is user-confirmed; no successful host-driven RGB control is claimed.
- Split-space/B/Backspace defaults, native application-switcher overlay, app minimize/restore.
- App-specific profiles, alternate layers, non-US layouts, sleep/disconnect/crash recovery.

USB/receiver support, general lighting effects, firmware updates, onboard macro storage, and Fn-row primary-mode writes are outside the current implementation.
