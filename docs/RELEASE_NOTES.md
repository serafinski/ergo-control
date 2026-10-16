Install by dragging Ergo Control to Applications, ejecting the DMG, then opening the Applications copy.

**This release is self-signed and is not Apple-notarized.** macOS may require Privacy & Security → Open Anyway for the app and its optional helper installer. See Read me first.txt in the disk image. Input Monitoring and Accessibility are also required for mappings; the optional full-control helper has its own Input Monitoring permission.

Early development installations with a conflicting bundled-helper registration now offer Repair helper startup under Keyboard → Full dial control. Complete the updated helper installer to migrate to the separate local service; existing profiles are preserved.

Startup reconnects the exact paired endpoint saved in its recovery record without waiting for a live HID node, and reacts immediately to keyboard arrival. Duplicate polls cannot restart an in-flight connection. Readiness no longer expires after two minutes; activation errors still require a manual retry. Recovery records are retained until restoration is verified. Login launches also attach restoration handling before any window or menu appears.

Keyboard mappings start independently of Codex/ChatGPT. The optional chat reader waits while Codex is closed and reconnects automatically when it opens; slow metadata process launch or communication no longer blocks the keyboard/UI main thread.

App → Startup offers launch at login and automatic activation of saved mappings. Profiles and Codex choices survive app updates.

Requires macOS 14 or later. Includes Apple Silicon and Intel binaries; hardware validation to date is on Apple Silicon. Mapping support is Bluetooth only. The physical dial's colored mode indicator remains unresolved. Custom Codex status waves over Bluetooth are slower than the native rainbow effect.

If switching from a locally built app signed with another certificate, remove its input helper using the old app before installing the release helper. Keep the old app until that migration is complete.

The release contains no Razer software, captured user data, or private research files. SHA-256 checksums are provided alongside the DMG.
