Install by dragging Ergo Control to Applications, ejecting the DMG, then opening the Applications copy.

**This release is self-signed and is not Apple-notarized.** macOS may require Privacy & Security → Open Anyway for the app and its optional helper installer. See Read me first.txt in the disk image. Input Monitoring and Accessibility are also required for mappings; the optional full-control helper has its own Input Monitoring permission.

Early development installations with a conflicting bundled-helper registration now offer Repair helper startup under Keyboard → Full dial control. Complete the updated helper installer to migrate to the separate local service; existing profiles are preserved.

Startup now connects to complete saved keyboard recovery before activating mappings; a pending recovery record no longer blocks its own connection.

App → Startup offers launch at login and automatic activation of saved mappings. Profiles and Codex choices survive app updates.

Requires macOS 14 or later. Includes Apple Silicon and Intel binaries; hardware validation to date is on Apple Silicon. Mapping support is Bluetooth only. The physical dial's colored mode indicator remains unresolved. Custom Codex status waves over Bluetooth are slower than the native rainbow effect.

If switching from a locally built app signed with another certificate, remove its input helper using the old app before installing the release helper. Keep the old app until that migration is complete.

The release contains no Razer software, captured user data, or private research files. SHA-256 checksums are provided alongside the DMG.
