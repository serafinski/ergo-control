# Optional full keyboard input helper

Ergo Control 0.2.0 bundles `ErgoInputHelper` to address the live `kIOReturnNotPrivileged` failure when the ordinary settings app attempts exclusive IOHID access. It is a small root launch daemon managed by Apple's `SMAppService`, not a Razer component or a kernel/system extension. The settings app still runs as the logged-in user. The helper is not registered, started, or approved by the build script.

## Scope and trust boundary

- Capture matches exactly one Bluetooth Low Energy PT Ergo (`068e:02c3`). Neither Logitech devices nor USB keyboards qualify.
- The XPC API contains only begin, renew, and end. It cannot execute commands, load plugins, accept a device identity/path, synthesize events, or write Bluetooth/device configuration.
- The server enforces the GUI's designated signing requirement through `NSXPCConnection.setCodeSigningRequirement`. The requirement is embedded in the helper's signed Mach-O Info.plist. Development builds pin the app identifier and local certificate fingerprint; another signing identity uses its designated requirement. Ad-hoc signatures are rejected by the packaging tool.
- The client requires the bundled helper's identifier and exact code-directory hash. Both sides validate signatures; an identifier alone does not authorize a client.
- Only the current non-root console user's XPC connection is accepted. Only one connection can own capture. Requests are checked against their originating connection before executing on the main run loop. User switching ends capture.
- Every captured report gets a sequence number. The app acknowledges reports only after processing them. A heartbeat every 0.5 seconds extends a three-second monotonic lease only when the client is caught up or making progress. A stalled receiver cannot keep the lease alive with heartbeats. A backlog of 256 reports releases capture.
- Stop, XPC interruption/invalidation, disconnection, unsupported helper packets, active-user changes, lease expiry, and normal termination close the physical device. The watchdog checks every 0.2 seconds while capturing. Process exit also closes its HID connection through the OS.
- No raw input is written to disk. The helper is idle when no mapping session owns the keyboard. The GUI handles ordinary-key output and configured actions under its existing Accessibility grant.

The helper releases exclusive input; it does not restore the firmware's Bluetooth mode itself. The GUI retains the existing read-verified restoration and durable recovery journal. If the GUI is killed, ordinary keyboard input should return after the helper lease ends, but mode 3 can remain until the GUI is relaunched and performs recovery. This behavior still requires live testing. Secure input/password fields and non-US keyboard layouts also require validation before a daily-use release.

## Local development signing

`tools/build_app.sh` uses `ERGO_CODESIGN_IDENTITY` when provided. Otherwise `tools/setup_local_signing.py` creates a persistent self-signed code-signing identity in `build/local-signing/ErgoDevelopment.keychain-db`. This directory is private and ignored by Git. The certificate is **not** added to macOS's trust stores; the build selects its isolated keychain explicitly. Creation restores the user's keychain search list. Temporary private-key/PKCS#12 exports are deleted after import. Preserve this private directory for consistent local signing; do not publish it or its keychain password.

The initial certificate-signed build replaces the previous ad-hoc identity and may need fresh macOS grants. The local certificate is a development identity, not Developer ID signing or notarization. Whether this Mac accepts Service Management registration with it must be verified; a failed approval/registration should be reported, not bypassed with a manual root install. A distribution build should use the developer's proper signing identity and a reviewed update strategy.

Build a separate preview without replacing the working app:

```sh
ERGO_APP_NAME='Ergo Control Preview' zsh tools/build_app.sh
```

The package script verifies the GUI against the embedded client requirement, validates both signatures, and runs `ErgoInputHelper --self-check`. Self-check validates the helper and its containing app without opening a device, registering a daemon, or running as root.

## Activation and removal

The settings window has **Full dial control** with **Enable full dial control…**, approval-status refresh, and **Remove input helper**. Registration occurs only when the enable button is clicked. macOS may require approval in General → Login Items & Extensions. The helper may also require its own Input Monitoring permission; an open failure reports the returned code instead of silently claiming success. Removal stops mappings, releases the input connection, then unregisters the daemon.

When approved, the next mapping session uses the helper's exclusive input route. Existing command-dial modes, left-click cycling, media controls, ordinary-key mappings, and gaming mode use the full report stream. This route remains unverified on hardware. When no helper is enabled, the tested non-seizing extra-button path is retained.

## Verification so far

- Release preview builds with a persistent local certificate. Both signatures and the embedded app-signature policy pass checks. The earlier ad-hoc app fails that policy, confirming that the same bundle identifier alone is insufficient.
- 29 core tests pass, including idle lease expiry, progress-based renewal, stale/forged acknowledgements, backlog limits, and ended-session handling.
- The preview's settings window has not been inspected: the native computer-use bridge still returns `Sky Computer Use native pipe closed before response`.
- Registration, system approval, authenticated live XPC, exclusive open, ordinary typing through the helper, dial replacement, stop/crash release, and permission refresh are pending. No launch daemon or driver was installed during these checks.

Apple references: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [XPC peer signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)), and [IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen).
