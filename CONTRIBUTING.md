# Contributing

Build and test on macOS with Swift 5.9 or newer. Run `swift test` and compile the affected release products before submitting a change. GitHub Actions performs tests and unsigned release compilation; it does not install a helper or open a keyboard.

The source is organized as follows:

| Directory | Responsibility |
| --- | --- |
| `Sources/ErgoCore` | Packet codecs, input/state models, profiles, and validation without device I/O |
| `Sources/ErgoDevice` | Serial Bluetooth configuration and mode restoration |
| `Sources/ErgoControl` | Settings, menu bar, scoped input relay, and action output |
| `Sources/ErgoIPC`, `Sources/ErgoInputHelper` | Authenticated helper protocol and exclusive capture |
| `Sources/ErgoProbe`, `Sources/ErgoBluetooth` | Optional diagnostic applications |
| `Tests` | Core behavior and action-engine tests with keyboard output suppressed |
| `tools`, `resources` | Local builds, signing, helper packaging, and static research tools |
| `docs/research` | Observed hardware results and historical research provenance |

Keep device access matched to the exact supported keyboard. Codec/state tests should use synthetic or sanitized packets. A passing codec test does not establish a hardware feature: document the actual control, connection, mode, and observed result separately. Preserve the saved-mode recovery and helper signing/lease boundaries when changing input handling.

Never commit raw typing captures, user profiles, signing keys/keychains, local logs, vendor installers, or extracted vendor code. The app must build without an installed Razer runtime or those research artifacts. Downloaded source is for static inspection only.

For a GUI-only local update with unchanged helper/IPC/signing policy, the build supports `ERGO_REUSE_HELPER=1` against an existing bundle. A fresh clone needs the normal full build. Neither build mode installs the helper; installation requires the user's normal macOS administrator approval.

Describe behavior changes and the validation performed in pull requests. Contributions are made under the repository's [MIT license](LICENSE).
