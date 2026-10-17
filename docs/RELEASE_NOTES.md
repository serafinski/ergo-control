Version 0.8.4 slows the optional working pulse to 1.4 seconds per bright/dim phase, a 2.8-second cycle: half the previous frequency. The toggle remains off by default. No helper or hook update is needed after 0.8.3.

Version 0.8.3 adds an optional **Pulse macro keys while working** toggle in Codex → Status lights, off by default. When enabled, M1–M5 alternate bright/dim blue every 0.7 seconds after the starting sweep, until work ends or approval begins. Missed phases are skipped rather than queued. Smooth is the default for new/missing speed preferences; existing choices are preserved. The Caps Lock white indicator is synchronized through its standard HID LED output while full keyboard control is active. **Update the input helper from Setup & diagnostics** for Caps Lock indicator support; hooks do not need reinstalling. Hardware confirmation of the new indicator and pulse remains pending.

Version 0.8.2 reduces uneven status-wave timing by queuing each frame’s existing small Bluetooth writes together. Every write acknowledgement and the full keyboard success reply are still required before advancing. Initial live frames completed in 149–165 ms; Bluetooth timing may still vary. Quick/Smooth geometry, complete macro-side return and previous-effect restoration are unchanged.

Version 0.8.1 adds Quick/Smooth status-wave speed. Quick (default unless a choice is saved) uses fewer, wider steps for shorter sweeps; Smooth retains the previous motion. Packet diagnostics run off the main input/UI thread, and unnecessary packet-by-packet UI refreshes are removed from the main app. Full command acknowledgements and keyboard restoration are preserved.

Version 0.8.0 reorganizes Keyboard into Buttons, Dials, Lighting, Function keys and Profiles. Control cards show their actions and open a focused mapping editor with Save/Cancel, replacing the permanent side editor. Rare keys and the test pad are expandable; dial details expand one mode at a time. Setup & diagnostics is a separate sidebar section for permissions, the input helper and advanced checks. App remains for startup/installation. Existing profiles, mappings, helper, Codex integration and lighting behavior are preserved.

Version 0.7.11 lets the green completion sweep finish its acknowledged return to the macro keys before restoring the prior effect, including when Bluetooth is slow or the chat status has expired to idle. Explicit disable, new work, errors and mapping shutdown still interrupt it. The profile-name field has more vertical space so its text fits.

Version 0.7.10 makes expandable section headings clickable across the arrow, text and empty row space. Removed the unsupported physical dial-indicator color pickers, experimental guidance and automatic diagnostics; mode changes continue to show an on-screen popup. Existing saved mode settings remain compatible.

Version 0.7.9 moves sidebar keyboard focus to the section being opened, so the previous Keyboard row no longer retains its focus outline after navigation. Profile names now use a visibly bordered text field with a Profile name label.

Version 0.7.8 makes the entire sidebar navigation and profile rows clickable, including their padding and empty space. GitHub test and DMG workflows now run only when manually dispatched; pushing commits or tags does not start builds.

Version 0.7.7 accepts valid PT Ergo pointer reports with auxiliary button/wheel/movement fields, preventing dial-mode clicks from stopping mappings. Horizontal pan remains the rotation input; auxiliary pointer fields do not generate duplicate mode changes or mouse events. A new App logs sidebar section keeps recent local status/errors, with filter, copy and clear controls.

Version 0.7.6 removes the lighting-tool unused-binding warning and explicitly labels test callbacks. Keyboard behavior is unchanged.

The first GitHub build exposed an older Swift compiler limitation in a test expression. Version 0.7.5 simplifies that expression; keyboard behavior is unchanged from 0.7.4.

Install by dragging Ergo Control to Applications, ejecting the DMG, then opening the Applications copy.

**This release is self-signed and is not Apple-notarized.** macOS may require Privacy & Security → Open Anyway for the app and its optional helper installer. See Read me first.txt in the disk image. Input Monitoring and Accessibility are also required for mappings; the optional full-control helper has its own Input Monitoring permission.

Early development installations with a conflicting bundled-helper registration now offer Repair helper startup under Keyboard → Full dial control. Complete the updated helper installer to migrate to the separate local service; existing profiles are preserved.

Startup reconnects the exact paired endpoint saved in its recovery record without waiting for a live HID node, and reacts immediately to keyboard arrival. Duplicate polls cannot restart an in-flight connection. Readiness no longer expires after two minutes; activation errors still require a manual retry. Recovery records are retained until restoration is verified. Login launches also attach restoration handling before any window or menu appears.

Keyboard mappings start independently of Codex/ChatGPT. The optional chat reader waits while Codex is closed and reconnects automatically when it opens; slow metadata process launch or communication no longer blocks the keyboard/UI main thread.

App → Startup offers launch at login and automatic activation of saved mappings. Profiles and Codex choices survive app updates.

Requires macOS 14 or later. Includes Apple Silicon and Intel binaries; hardware validation to date is on Apple Silicon. Mapping support is Bluetooth only. The physical dial's colored mode indicator remains unresolved. Custom Codex status waves over Bluetooth are slower than the native rainbow effect.

If switching from a locally built app signed with another certificate, remove its input helper using the old app before installing the release helper. Keep the old app until that migration is complete.

The release contains no Razer software, captured user data, or private research files. SHA-256 checksums are provided alongside the DMG.
