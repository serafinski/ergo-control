# Local investigation — 13 October 2026

## Status

Ergo Probe builds and opens on this Mac. Its inventory detects exactly one matching Bluetooth HID device and obtains one paired CoreBluetooth identifier. After the user enabled Input Monitoring, HID open succeeded. A labeled positive control recorded exactly three A presses (`01 00 04 00 00 00 00 00 00 00 00 00`) and three releases (`01 00 00 00 00 00 00 00 00 00 00 00`), physical report ID 1. Subsequent per-control tests recovered left-dial rotation but no reports for left click, M1, or AI in the current configuration. The separate Bluetooth helper subsequently read mode 0/parameter 0, temporarily set and verified mode 3/parameter 0, and exposed M1–M5, AI, left dial click, and the battery button as distinct physical report-5 inputs. Each completed test window was followed by a read-verified restoration to mode 0/parameter 0. See the driver-mode evidence below.

The keyboard briefly disappeared from the local device inventory, then returned with a new registry entry while the user was typing. The original unscheduled HID manager retained an empty device set; restarting the probe restored detection and the successful open. Device enumeration now creates a fresh strictly matched manager on each Start Test, avoiding that stale cache. Do not infer disconnection solely from the old probe's message.

The user's initial attempt mixed controls without separate markers, so it cannot establish extra-control semantics. Version 0.2 separates each control into its own saved test, with Start/Finish/Clear, an automatically labeled file per attempt, and a persistent per-control result index. Cleared active attempts are marked `test_discarded`; old files remain local.

The 0.2 update changed the ad-hoc executable signature. macOS showed the old Input Monitoring entry as enabled, but the current process reported access state 1 and `IOHIDDeviceOpen` returned `kIOReturnNotPermitted`. Toggling the entry and relaunching did not restore it; re-adding the current app did. Subsequent HID opens returned 0. No driver or Logitech permission was changed.

Live UI verification of the new flow completed: Start opened the actual PT Ergo and automatically labeled the baseline; Finish wrote a zero-input baseline result; selecting M1 showed its own empty section; starting and clearing an M1 attempt wrote `test_discarded`, reset M1, and preserved the baseline result. The saved baseline reappeared after quitting and reopening the app. The discarded M1 attempt is UI verification only, not a physical M1 key test.

## New labeled baseline captures

The user then ran the per-control tests. A scoped summary is saved in `analysis/local/control-baseline-summary.json`; originals remain in the local capture folder. The recorded tests are:

| Test | Raw reports | Recorded behavior |
| --- | ---: | --- |
| Hands-off baseline | 0 | No input |
| A | 6 | Three makes and three releases, physical report 1 |
| Left dial clockwise | 12 | Command modifier `08`, keypad-plus usage `57`, then releases, physical report 1 |
| Left dial counterclockwise | 12 | Command modifier `08`, keypad-minus usage `56`, then releases, physical report 1 |
| Left dial click | 0 | No report in this attempt |
| M1 | 0 | User explicitly confirmed no event when pressing M1 |
| AI button | 0 | No report in this attempt |

No report IDs 5 or 6 were observed in these initial tests. They preceded the first project mode write; a subsequent query read mode 0/parameter 0. There was no simultaneous mode query during the initial captures. M2–M5, the right roller, and other controls have not been newly established by these captures. Further baseline repetition alone does not resolve the activation question.

## Bluetooth mode helper

A separate native `Ergo Bluetooth.app` now builds from `Sources/ErgoBluetooth/`, preserving Ergo Probe's working executable and Input Monitoring permission. It verifies the exact paired HID identity without opening input devices, then uses only the matching CoreBluetooth identifier and the proven Protocol 30 service. Runtime transport uses acknowledged sequential writes, one outstanding command, the tested bounded response assembler, and a five-second timeout.

The helper reads the current mode, saves and synchronizes a recovery record before any write, verifies temporary mode 3, schedules restoration after 60 seconds, and reads back the original mode before clearing recovery state. Normal-mode queries, battery list/level queries, temporary driver-mode writes, periodic verification, and manual early restoration have now succeeded on hardware. Timer expiry, forced process exit, and disconnect recovery remain untested failure paths.

Bluetooth permission was granted and refreshed for helper 0.1.1. Service discovery confirmed the known write characteristic (property 8) and read/notify characteristic (properties 18) on the exact paired keyboard. Query responses arrive as a 20-byte header followed by a padded 20-byte payload; only the announced two payload bytes belong to the mode result. One initial query returned status 3 (vendor name “Command Failure”), then success for the same transaction about 30 ms later. The assembler now waits through vendor retry statuses 1/3 until success or timeout. Exchange completion also waits for every header/payload write acknowledgement, preventing the following command from consuming a previous write acknowledgement.

## Confirmed driver-mode extra keys

The user operated each control in a separate recording. Every listed input used physical report 5, logical record 4, with the key set starting at byte 2. Sharing a physical report ID does not mean sharing a key identifier.

| Control | Full press report, hexadecimal | Press/release pairs captured |
| --- | --- | ---: |
| M1 | `050420000000000000000000` | 4 |
| M2 | `050421000000000000000000` | 3 |
| M3 | `050422000000000000000000` | 3 |
| M4 | `050423000000000000000000` | 3 |
| M5 | `050424000000000000000000` | 3 |
| AI | `0504f7000000000000000000` | 3 |
| Left dial click | `050460000000000000000000` | 3 |
| Battery button | `050441000000000000000000` | 3 |

All eight used release snapshot `050400000000000000000000`. M1 was requested three times, but the recording contains four complete cycles; do not silently normalize that discrepancy. These captures confirm static key identifiers 32–36, 247, 96, and 65 on this keyboard; key 65 (`DKM_D41`) is now physically identified as the battery button. They required no Razer physical driver or Synapse runtime. No mapping writes were performed.

Local source recordings: `m1-9F7C5694-3875-469B-9F60-863F218B7C96.jsonl`, `m2-9FA7A4B3-2C4E-4399-9788-CC1EFF8C2CCE.jsonl`, `m3-919714BA-581B-456B-8452-10595CB5FB3A.jsonl`, `m4-8E6D3C0A-6C60-4BBF-8E35-509BD62EEB21.jsonl`, `m5-45A96C98-4544-47FE-B97E-4771155A4400.jsonl`, and `ai-button-A3EFBE35-6D09-43CC-BBAD-F9FFD72EB933.jsonl`, under the local capture directory. Mode requests and read-back verification are in `bluetooth-5E11E47A-F3E7-43D6-92BB-A6219B6F6C22.jsonl` under the Bluetooth log directory. These private logs remain outside Git.

The click/battery retests were recorded inside the verified 20:12:05–20:12:42 UTC driver-mode window. Their files are `left-dial-click-F9EB0B46-EF88-4B68-AA67-68A18B069139.jsonl` and `battery-button-707C998F-095D-4036-B004-6C3AD9702F6F.jsonl`. Restoration to mode 0/parameter 0 was verified and the recovery file removed.

A separate battery list query returned `[1]`; battery ID 1 returned raw level 168, converted using the vendor formula to 65%. No button press is required to query battery status. These queries are in `bluetooth-24FD90E6-E536-43C1-A516-265977CC4C81.jsonl`.

`ExtraKeyDecoder` now produces per-key press/release differences from report-5 snapshots, deduplicates held keys, and ignores unrelated or malformed reports without releasing held keys. The source UI integration displays button names, consumer actions, and brightness notifications, and re-decodes compatible saved recordings on launch. Shift + left click is explicitly optional and remains untested. Probe 0.3 adds named descriptions and re-decodes saved recordings. Rebuilding changes the ad-hoc signature, so the existing Input Monitoring grant needs refreshing for the current executable.

The full standalone mapping app remains the goal. Input discovery comes first; shortcuts, macros, scripts, app launching, AI-button assignments, saved profiles, app-specific switching, and a background agent remain to implement after the input path is validated.

## Verified local state

- Apple Silicon arm64, macOS 27.0.1, build 26A434; Swift 6.4 toolchain available.
- Installer SHA-256 matches the handoff: `51f6f67e88698c7852196f2e5840a4e0c0284df17e935f60bb7d6a24728085cd`.
- All 105 files in the handoff evidence manifest verified, with no mismatches.
- Installed engine is 4.4.25 (`4.4.25.194`). Its ASAR and the three analyzed native libraries have exactly the same hashes as the handoff copies.
- Installed Synapse launcher: 0.8.11. GameManagerService: 3.0.7.0.
- Razer physical HID driver: activated, disabled. USB Overdrive driver: activated, disabled.
- Razer virtual HID driver: activated, enabled, process present. Karabiner virtual HID driver: enabled, process present.
- Razer Elevation Service is running. GameManagerService and SynapseHelper were not running in the inspected process snapshot.
- No services or extensions were stopped, installed, enabled, or disabled during this investigation.

Reproduce the scoped snapshot with `python3 tools/collect_evidence.py`; output is in `analysis/local/environment.json`. The snapshot intentionally omits keyboard serial numbers, Bluetooth addresses, user profile contents, and unrelated device details.

## Device-specific Bluetooth path established

Historical local Synapse logs provide evidence beyond the generic modules in the original handoff:

- `products_708_mw id-2784107687.log:43` records a successful `rzDevice30.connectDevice()` and discovered service/characteristics.
- The same file at line 155 records a successful Set Device Mode request with mode 3, parameter 0, named `Driver_Mode` by the vendor code. This is a historical vendor operation, not one performed by Ergo Probe.
- Product module 708 explicitly defines `productId:708`, `bleId:707`, `dongleId:706`. The BLE HID vendor is 1678; the product module's generic vendor field is 5426. Do not substitute the latter for macOS HID matching.

The service is `52401523-f97c-7f90-0e7f-6c6f4e36db1c`; command-write characteristic ends in `1524`, with `write` property; response characteristic ends in `1525`, with `read` and `notify` properties. The rest of each UUID is identical to the service. These UUIDs are now linked to this device by its historical log, not merely by shared constants.

The app's UI/middleware is hosted separately from the installer. Starting at the URL found in the local log, the investigation fetched public sources without executing them:

`https://apps-mac.razer.com/synapse/products/708/mw/index.html`

`tools/fetch_device_sources.py` preserves 48 files in `analysis/vendor/708/mw/`, with URLs, lengths, and SHA-256 hashes in `SOURCES.json`. The middleware page reports version 1.0.0, build 2603160912. Some unused chunks and `sw.js` were unavailable. The downloader resolves Webpack chunk aliases instead of assuming numeric filenames.

Relevant sources:

| File | Specific evidence |
| --- | --- |
| `main.c8f8537456ab6ae7c847.js` | Product 708 device definition; BLE product 707; DKM key identifiers; default dial modes; firmware report mappings |
| `6737.5b007c860f4efa22ab87.js` | Device mode initialization; native hardware event registration; left dial mode-switch processing; hardware parser constants |
| `rzDevice30.a29e745b43244151d1fa.js` | Exact command construction, service UUIDs, battery queries, mode read/write, response unpacking |
| `rzHardwareEventsProtocol30Parser.474e82350be705232b6f.js` | Removes a leading byte before interpreting logical record type; Razer keys are returned as an array; notification/media decoding |
| `rzBLE.435f35b8ac228f829498.js` | Renderer-to-Electron Bluetooth bridge |
| Handoff `evidence/electron/modules/noble/strategy/protocol30.js` | 8-byte request header, separate payload writes, notification response assembly; `notify()` returns `state:false` |

## Configuration and input are separate paths

Protocol 30 Bluetooth notifications are used for command responses. Its generic Electron `notify()` function explicitly returns failure; it does not implement a general key-event forwarding subscription. The diagnostic app can observe the characteristic directly to test behavior, but no evidence yet establishes that missing controls arrive there.

Native disassembly provides a concrete driver-input path:

- `libmapping_engine.dylib`, arm64 `HardwareEventEndpointMac::Start` at `0x11c934` calls `IOConnectCallAsyncStructMethod` at `0x11ca60`.
- `HardwareEventEndpointMac::OnIOCompleted` at `0x11ce3c` checks the input structure's type against 5, then forwards a nonzero report length and buffer to its delegate. That structure type must not be confused with HID report ID 5.
- `MappingEngineInputDevice::OnHandleRazerKeyOnDeviceThread` at `0x77594` tracks a set of key bytes, skips a leading byte, and scans subsequent nonzero bytes. It builds `MappingDataRazerKey` objects and make/break differences. This is static native behavior, not a proven on-wire payload layout for this device.
- Driver bundle `com.razer.appengine.driver.dext` has an IOKit personality `BLEKBDriverKit` matching vendor 1678 and keyboard/mouse usage pairs.
- Its `RazerGenericHIDDriverKit::handleReport` at `0x100006b80` copies report bytes and report metadata into `GetHWReportData`; the default path calls `GenericHIDDriverClient::NormalDataCallback` at `0x1000070a8` before calling the superclass report handler.

Disassembly and selected functions are preserved under `analysis/local/`. Native libraries and the driver were inspected statically and never loaded or activated by this project.

## Local Bluetooth HID descriptor

The connected `PT Ergo` has vendor 1678 (`0x068e`), product 707 (`0x02c3`), transport `Bluetooth Low Energy`, primary usage page 1 / usage 6. The maximum input report size is 12 bytes, output 2 bytes, feature 3 bytes.

Its descriptor contains input report IDs 1–6. Report 1 carries keyboard modifiers and an array of key usages; report 2 describes pointer/scroll input; report 3 describes consumer usages; report 4 describes system controls. Reports 5 and 6 each declare an 11-byte input array under Generic Desktop page 1 / application usage 0. They are **not declared under a vendor-defined usage page**. Physical report 5/logical record 4 is now confirmed for macro/AI key snapshots; physical report 6/logical record 5/event 8 is now associated with keyboard brightness changes during left-dial rotation.

The product middleware separately defines `{4: "razerKeyReportID", 5: "hardwareEventReportID"}`. Its Protocol 30 hardware parser removes a leading byte before reading a logical type, with 4 meaning Razer keys and 5 meaning notifications. The new captures establish `[physical ID 5, logical record 4, key set…]` for M1–M5 and AI. This does not establish the layout of other logical records or physical report 6.

## Per-control evidence

Earlier normal-input behavior is preserved from the handoff. Macro/AI identifiers are now confirmed on wire by labeled local captures; remaining static identifiers still require separate hardware validation.

| Control | Earlier observed input | Ergo-specific static identifier | Activation / remaining question |
| --- | --- | --- | --- |
| Left dial CW/CCW, zoom mode | Command + keypad plus/minus | Default dial mapping uses `ScrollRight` / `ScrollLeft` | Verified driver mode: report 2 signed horizontal pan +1/−1; earlier captures also show zoom keys and brightness notifications |
| Left dial click | None in earlier remappers | `DKM_KB_LEFTKNOB`, key 96 (`0x60`) | Confirmed report 5/logical 4/key 96 in driver mode |
| Right roller CW/CCW | Consumer volume up/down | Default `ScrollUp` / `ScrollDown` mappings | Labeled captures confirm report 3 consumer volume up/down, separate from left report 2 |
| Right roller click | Consumer mute | `DKM_KBMK_04`, key 82 (`0x52`), named `DIAL_CLICK` | Labeled capture confirms right click as report 3 consumer mute; raw key 82 is still static only |
| M1 | No earlier event | `DKM_M_01`, key 32 (`0x20`) | Confirmed report 5/logical 4/key 32 in driver mode |
| M2 | No earlier event | `DKM_M_02`, key 33 (`0x21`) | Confirmed report 5/logical 4/key 33 in driver mode |
| M3 | No earlier event | `DKM_M_03`, key 34 (`0x22`) | Confirmed report 5/logical 4/key 34 in driver mode |
| M4 | No earlier event | `DKM_M_04`, key 35 (`0x23`) | Confirmed report 5/logical 4/key 35 in driver mode |
| M5 | No earlier event | `DKM_M_05`, key 36 (`0x24`) | Confirmed report 5/logical 4/key 36 in driver mode |
| AI button | No earlier event | `DKM_SB_247`, key 247 (`0xf7`), named `AI_Launcher` | Confirmed report 5/logical 4/key 247 in driver mode; action assignment remains to implement |
| Media single/double/triple | Play/pause, next, previous | `DKM_KBMK_02` key 85, `DKM_KBMK_03` key 83, `DKM_KBMK_01` key 84 | Three labeled trials each confirm consumer play/pause, next, and previous |
| Battery button | No earlier event | `DKM_D41`, key 65 (`0x41`) | Confirmed report 5/logical 4/key 65 in driver mode |
| Battery percentage | Not captured earlier | Protocol 30 `getBatteryList`, `getBatteryLevel`, `getChargingStatus` | Live query returned 65% (raw 168), battery ID 1 |
| Additional keys | Unverified | `DKM_SB_251–253` | Physical identity and meaning need labeled testing |

Confidence is high for the downloaded source identifiers and historical successful Protocol 30 connection; runtime exposure is confirmed for the requested primary controls; optional Shift + click remains untested. No control is declared permanently unsupported from a failed or empty generic capture.

## Self-directed dial/media tests

The user separately recorded all other controls except optional Shift + left click. The Bluetooth log contains no new mode-change window during the 20:04–20:06 UTC captures, and the user was unsure whether they enabled the helper; mark their mode as unverified rather than claiming driver-mode coverage.

- Left clockwise: report 6, logical record 5, event 8, values 12 → 25 → 38.
- Left counterclockwise: the same structure, values 25 → 12 → 0. The vendor event enum defines 8 as brightness change, with an absolute level in the next byte. This establishes keyboard-brightness changes, not unrestricted relative turn events at the limits.
- Right clockwise/counterclockwise/click: physical consumer report 3, usages `00e9` / `00ea` / `00e2`, each with three makes and zero-usage releases.
- Media single/double/triple: report 3, usages `00cd` / `00b5` / `00b6`, each with three makes and releases.
- Left click and battery initially had no reports in this batch; the later verified driver-mode retests above resolved both.

The official manual, page 9, documents plain left click as next mode and Shift + click as previous mode. Page 11 describes the battery button's local status display and long-press power-saving function. These are documentation claims; optional Shift + click and battery long-press were not tested. Source: https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf

## Recovered configuration commands

`rzDevice30` constructs requests as:

| Byte | Meaning in source |
| --- | --- |
| 0 | Transaction ID, cycles 1–31 |
| 1–3 | Payload length, little endian, 24 bits |
| 4–5 | Command class and command ID |
| 6–7 | The third and fourth `sendCommand` arguments, generally zero for device mode |
| 8 onward | Payload |

The transport writes the 8-byte header separately, then splits payload into chunks of up to 20 bytes. Do not write the logged combined `dataSend` array as one BLE characteristic write. The local log and characteristic properties indicate acknowledged writes.

| Operation | Command class / ID | Payload / argument |
| --- | --- | --- |
| Get device mode | `01 / 82` | No payload |
| Set device mode | `01 / 02` | `[mode, parameter]`; source uses `[3,0]` for driver mode and `[0,0]` for normal mode |
| Get battery list | `05 / 80` | No payload; middleware passes 1 as its battery-list selector |
| Get battery level | `05 / 81` | No payload; battery ID in request byte 7; result scales first byte by `floor(value / 255 * 100)` |
| Get charging status | `05 / 85` | No payload; battery ID in request byte 7 |

Historical successful driver-mode request: `04 02 00 00 01 02 00 00 03 00`, transaction 4. Response assembly matches byte 0 against the transaction and checks byte 7 for status 2. The vendor generally treats the first response notification as a 20-byte header and subsequent notifications as payload, with an 8-byte fallback in its unpacker. The runtime transport now uses tested assembly and acknowledgement gating; mode read/write/read-back sequences have succeeded on hardware.

The vendor also returns to normal mode on window unload. Before a controlled initialization test, capture baseline, read/preserve the existing mode, confirm the exact target, implement restoration and failure handling, then compare the same labeled controls. The project's controlled mode-3 tests now establish that this change exposes M1–M5 and AI through the non-seizing HID probe.

## Verification and next milestone

Completed: release build, native app launch and visual inspection, strict device-matching tests (including exclusion of Logitech and USB identities), inventory on the real keyboard, successful non-seizing HID open after permission grant, and a three-press A positive control. Permission denial is explicitly logged rather than treated as an empty successful recording.

The core suite now covers strict target matching, Protocol 30 encoding/reassembly/acknowledgement ordering, the actual failure-then-success response sequence, and key snapshot decoding using the captured macro/AI identifiers. No Logitech device is opened or changed.

A final verified driver-mode window at 20:15:06–20:15:37 UTC exposed independent left-dial rotation on physical report 2, with nine-byte packets. Clockwise produced `020000010000000000` three times; counterclockwise produced `020000ff0000000000` three times. Byte 3 is signed horizontal pan, +1/−1, consistent with the descriptor's AC Pan field. The files are `left-dial-clockwise-438FA987-4580-440A-9F39-841DA6E8565C.jsonl` and `left-dial-counterclockwise-ACB8F47B-82B0-40BE-8935-203F33813643.jsonl`. Normal mode 0/parameter 0 was restored and verified afterward.

Input discovery now confirms independent left/right rotation and clicks, M1–M5, AI, media multi-press outputs, battery button, and battery-level query over Bluetooth. Optional Shift + click remains untested. The right roller and media consumer captures are real inputs, but their self-directed mode was not established; do not claim those specific captures were in driver mode.

Next: implement configurable actions, saved app-specific profiles, and scoped background operation with safe mode restoration. Preserve the MX Master configuration.

## Updated diagnostic apps

Ergo Bluetooth 0.1.2 successfully discovers battery ID 1 and displays its live level. Ergo Probe 0.3 was rebuilt after all hardware recordings finished; saved left-click, battery-button, and clockwise recordings were visually verified with decoded names. Re-adding over the stale Input Monitoring entry did not restore the new executable. Quitting the probe, removing only its old entry, adding the current build, and reopening restored access; a brief stopped baseline verified access status 0 and HID open result 0. Existing Logitech permissions were preserved. The suite passes 19 tests. Both capture and temporary mode are stopped.

## Mapping-app access failure and fallback

The user granted the new Ergo Control app Accessibility and Input Monitoring. Its Bluetooth configuration query read normal mode successfully, but exclusive HID open failed with `-536870207` (`0xe00002c1`). The local macOS SDK defines this as `kIOReturnNotPrivileged`; `kIOReturnExclusiveAccess` is a different value (`0xe00002c5`). No driver-mode change was made during that failed start. Process inspection found no running probe, Bluetooth helper, Karabiner grabber, Synapse GUI, or Razer App Engine GUI; the previously noted virtual driver processes and Razer Elevation Service remained present. This does not establish that the full keyboard path can be made available by merely closing another app.

Build 0.1.1 retries non-seizing access only for that privilege error. Extra-button mode filters out report IDs 1, 2, 3, 4 and 6 before copying/processing input; it accepts only physical report 5, so ordinary key and dial input is never re-emitted. Unsupported dial/media/ordinary-key controls are disabled in the UI. The saved M1 Type text action was verified on disk. Twenty-five core tests pass, including capability/routing isolation. No privileged helper, driver installation, or changes to Logitech handling were performed.

## First live mapping success

The user confirmed that physical M1 inserts the saved `Ergo test` text in Ergo Control's test pad using the non-seizing fallback. Local `Settings/input-status.json` recorded access mode `macroButtons`, open result 0, at `2026-10-13T21:16:17Z`. The Bluetooth session read normal mode 0/parameter 0, verified temporary driver mode 3, and restored mode 0/parameter 0 after the 60-second test. `bluetooth-B6E09FD2-8F25-4DA5-8422-9BE40843EAA8.jsonl` records `original_mode_restored` at `2026-10-13T21:17:15Z`; the pending-restoration file was absent afterward. This establishes text-action output and automatic restoration for this session, not full keyboard relaying or all action types.

In a second test, the user saved M2 as `text one\nwait 300\ncmd+a\nwait 300\ntext Macro works`, enabled a 60-second session, focused the app's test pad, and pressed physical M2. The user confirmed that only `Macro works` remained. The Default profile's `extra:33` mapping on disk matches the requested macro. The same Bluetooth log records normal mode 0/parameter 0 at `2026-10-13T21:21:37Z`, verified driver mode at `2026-10-13T21:21:38Z`, and read-verified restoration to mode 0/parameter 0 at `2026-10-13T21:22:37Z`; the pending-restoration file was removed. This validates text output, the Command+A shortcut, macro sequencing with delays, and another automatic restoration. Exact delay timing was not measured.

## Optional helper implementation (2026-10-14)

Version 0.2.0 adds a bundled SMAppService launch daemon for exclusive PT Ergo input. It uses mutual XPC signing requirements, active-console-user checks, a three-second progress-based input lease, a bounded report backlog, and connection-specific teardown. It exposes only capture lifecycle methods, with no privileged command execution or Bluetooth writes. The build now uses a persistent certificate in an isolated, ignored local keychain; no trust-store certificate was added and the original keychain search list was preserved. The preview release, both signatures, and embedded app-policy self-check pass; 29 core tests pass. Activation, authenticated live XPC, exclusive open, native typing, and dial remapping are not hardware-verified. No service was registered or driver installed. Native UI inspection remains blocked by the computer-use bridge. See [INPUT_HELPER.md](../INPUT_HELPER.md).

## Local registration refusal and installer (2026-10-14)

The user attempted bundled helper registration and received “Operation not permitted”; no approval entry appeared in Settings. The 17:08–17:09 Warsaw-time smd/Background Task Management logs show the local preview with `disposition=[enabled, disallowed, not notified]`. The current SDK explicitly requires notarization for apps containing LaunchDaemons, which the self-signed local preview does not have. The exact internal trust check is not identified by the available log. Version 0.2.1 therefore supplies an explicit local administrator-approved installer and uninstaller, with a root-owned executable/plist and the same narrowly authenticated XPC service. Package inspection verifies its two-file payload, protected root/wheel ownership/modes, valid extracted signature, and script guards. Scripts reject unprivileged execution; none were run as root. Core tests still pass (29). Live installation and full keyboard/dial output remain pending. See [INPUT_HELPER.md](../INPUT_HELPER.md).

The user subsequently completed the local installer. Both installed files are regular files owned by root (755 executable, 644 plist), and the executable's signature validates. Its code-directory hash `dc614375e922fcaa9db5b2e8431caaa8da2bb33f` matches the preview helper exactly. The launchd job is now a LaunchDaemon at the expected protected path, not the earlier partial Service Management submission; it has not run before the first mapping test. No Razer or Logitech driver/configuration was changed. Installation is confirmed; exclusive capture and full-control output remain pending.

The first full-control start launched the daemon and completed its authenticated XPC/device-discovery path, but exclusive HID open returned `-536870174` (`kIOReturnNotPermitted`, local SDK value `0xe00002e2`). The helper requested system TCC `ListenEvent` access. Live Settings inspection shows only the preview's grant; the separate installed helper is absent. Adding that exact helper to Input Monitoring is the next user approval step. Keyboard capture and dial output remain unverified; this is a permission failure, not evidence of a competing device client. The native UI bridge is working again.

After the helper's Input Monitoring grant was verified on, another user start returned the same `kIOReturnNotPermitted`. PID 23690 was still running from before that grant. A targeted noninteractive launchd restart could not proceed because sudo required a password. Version 0.2.2 now releases and exits after client disconnection and adds an authenticated read-only `IOHIDCheckAccess` RPC, available through the GUI and signed app `--helper-access-status`. Its installer will replace/restart the old process. The release/packages/signatures and 29 core tests pass; updated installation and post-restart access/capture checks remain pending. An earlier cached denial is a hypothesis rather than a confirmed diagnosis.

## Full-control hardware success (2026-10-14)

After the 0.2.2 helper update, the user confirmed the ordinary-typing/left-clockwise test worked. The saved clockwise action is Type text `CW`; the local open-status file records `fullKeyboard` and result 0 at `2026-10-14T16:37:34Z`. The latest Bluetooth log (`bluetooth-FEAB54E3-512A-4111-8724-86FB86FFF464.jsonl`) records verified restoration to mode 0/parameter 0 at `16:38:34Z`, and the recovery journal is gone. Launchd confirms the helper exited with code 0 after the session. The first read-only CLI check overlapped active capture and was refused by the single-client policy. A later idle check returned Input Monitoring granted (0) without opening a device and also ended with a clean helper exit. Full access, the tested clockwise assignment, automatic restoration, and fresh-process permission checking are now confirmed; remaining output paths and abnormal recovery are not yet confirmed.

## Split-key defaults and dial switcher correction (2026-10-14)

The user reported that app switching was instant with no Command+Tab overlay and that the right half of Space stopped working while mappings were enabled. The engine sent Command+Tab down followed by Tab up with only physical modifiers, releasing Command after each step. The full-control extra-key path decoded report 5 but gave ordinary split keys no native default action.

Static inspection of the ignored PT Ergo product bundle `analysis/vendor/708/mw/main.c8f8537456ab6ae7c847.js` found defaults `DKM_SB_251 → KEY_BACKSPACE`, `DKM_SB_252 → KEY_B`, `DKM_SB_253 → KEY_SPACEBAR` in both standard and alternate layers. The associated table uses keyboard page 7, IDs 42/5/44, and physical button keys 251/252/253 (scancode redirects 14/48/57). This is static vendor evidence, not a newly captured hardware report. The attached layout and right-space failure are consistent with this interpretation; the exact physical halves of B/Backspace still need live confirmation. No vendor script was executed or included in the app.

Preview 0.2.3 forwards these defaults as held native keys under exclusive capture, including modifiers and repeat. Source ownership prevents duplicate key-down or premature key-up when both halves hold the same native key. Dial-only Command+Tab shortcuts now hold Command across turns, release after one second of inactivity, and clean up on other input/actions, mode/profile changes, and stop. Reverse turns retain Command while applying Shift to Tab; normal button/macro chords are unchanged. Added an explicit Show / minimize application action for the user's requested AI-button toggle, with window restore scoped to the chosen application.

All 39 automated tests pass, including real action-engine output-sequence/timer/repeat tests that suppress system input, split-report ownership tests, and toggle selection/settings round-trip tests. The release preview's signature and reused helper signing-policy self-check pass. Its bundled helper remains `ed5d3eb6d0f533893cc90c217104d903db48b40c`, matching the installed helper; no administrator update or permissions change was made. Native app inspection again returned “Sky Computer Use native pipe closed before response,” so the new physical-key/overlay/minimize behavior is pending user verification. Existing mappings and local settings were preserved.

## Dial-mode indication and menu-bar operation (2026-10-14)

The user requested an on-screen mode indication when clicking the dial, a menu-bar keyboard icon with battery percentage, and no Dock icon. Preview 0.2.4 adds a non-activating, click-through SwiftUI-backed NSPanel, shown only after command-dial cycling. It displays the actual selected mode/profile for 1.5 seconds and reuses one panel across clicks. The menu-bar label now includes a structured percentage published by the existing Protocol 30 battery read; polling is throttled to five minutes, reconnect attempts to one minute, with activation/busy/restoration guards and an explicit refresh action. The bundle uses LSUIElement and accessory activation policy. No mappings, helper installation, permissions, Razer components, or Logitech settings were changed.

All 43 tests pass, including initial read/reconnection cadence, deferred manual refresh, and priority for mapping preparation and restoration on the serial configuration channel. The release/signatures and reused helper self-check pass. The computer-use bridge still closes its native pipe when selecting Ergo Control, even after reset. A user-directed visual check is pending for the HUD, percentage label, and absence from the Dock; there is no new live battery-query or popup evidence for this version yet.

The user then quit/reopened the updated preview and answered **“All three work”** to the requested check of the menu-bar keyboard icon/battery percentage, absence from the Dock, and the popup after left-dial mode cycling with mappings enabled. These three behaviors are now user-verified on this Mac. No independent screenshot or timed five-minute refresh measurement was collected; full-screen/multi-display HUD placement remains pending.

## Source repository preparation (2026-10-14)

The user approved an MIT license and requested pushing this project to GitHub. The repository was organized around the current app, setup/helper documentation, a concise protocol reference, optional diagnostics, and this research archive. The original installer and 105 extracted evidence files were moved under ignored `analysis/` paths and their hashes reverified; no vendor payload was discarded or added to Git. Local signing identities, generated apps/packages, profiles, and captures remain excluded. The existing commit history was reviewed for binary payloads and credential material before the initial push.

A clean source snapshot built the complete app and both helper installer packages with its own isolated development signing identity. Signature and embedded peer-policy checks passed without vendor evidence in that snapshot and without installing or starting a helper. The existing working preview and installed helper were left unchanged. The local 43-test suite, shell/Python/workflow syntax, and internal documentation links pass. A macOS GitHub Actions workflow runs tests and unsigned release compilation; the initial remote run is checked separately after pushing.

The initial push to `serafinski/razer-ergo` retained the existing history, set `main` as the tracked/default branch, and preserved the repository's private visibility. GitHub detects the MIT license. [The first remote CI run](https://github.com/serafinski/razer-ergo/actions/runs/38609541069) passed tests, app/helper release compilation, and script syntax checks. Its checkout action emitted a Node 20 deprecation annotation; the workflow now pins the official v6 checkout revision, whose declared runtime is Node 24. The separate clean source snapshot also passed all 43 tests and was removed afterward, along with its temporary signing keychain. Original local evidence, signing material, and the working app were preserved.

## Battery-button popup (2026-10-14)

The user reported that Show battery did not provide useful feedback and requested the same indication as dial-mode switching. Preview 0.2.5 replaces the earlier attempt to activate the settings window with a shared non-activating popup. A structured battery-read state publishes completion/failure, so the popup uses the fresh result rather than reading an asynchronous status string too early. Busy-channel requests are deferred through the existing polling schedule, and repeated presses share an in-flight read. Presentation IDs suppress late results after another indicator replaces the panel or mappings stop. Successful readings show the percentage and battery icon for two seconds; failed reads show Unavailable. No device command format or helper/permission scope changed.

All 43 regression tests pass. The release preview, signatures, and reused helper policy self-check pass; bundled and installed helper bytes are identical. The user was asked to reopen the preview and verify that the physical button shows the percentage while the current app keeps focus. That visual result is pending; no live success is claimed yet.

The user confirmed the battery popup works, but reported that Checking appeared for about half a second and requested suppressing it unless a read takes over two seconds. The revised preview reserves the popup request without showing a panel, cancels its two-second Checking timer when the result arrives, and displays the percentage directly for quick reads. Slower reads show Checking while preserving the same presentation ID, so the eventual result can update it. The initial live percentage display is confirmed; the final delayed-Checking behavior and slow/failure paths still need separate live verification.

## Gaming-mode removal and keyboard lighting (2026-10-14)

The user requested removing gaming mode, adding Keyboard brightness to the left dial, and reproducing the colored physical dial-mode indicator. Chroma/Codex-status macro-button lighting was explicitly deferred and recorded in the roadmap. Gaming fields, UI and shortcut blocking were removed; schema-1 profile migration preserves mappings and existing mode order, appending brightness once. Schema 2 saves serializable per-mode RGB colors and preserves a deliberately deleted brightness mode.

Static inspection of the ignored product-708 middleware identified `backlightStep:5`, a green brightness mode, and the model-specific knob LED ID 39. The shared switch-command-dial task exports `hS` from module 85225 to the RGB/state flash task `dt`, which uses LED class 1 and a three-second timeout. The brightness task uses profile 1 / AllRegion 0. The region getter reads the first discovered region. Exact command tables, file hashes, and the generic RGB encoder’s three-byte-versus-four-byte-template discrepancy are documented in PROTOCOL.md. No vendor code was run, copied into the application, or committed.

The first user test of preview 0.2.6 build 9 reported that enabling mappings stopped them after about one second. Local Bluetooth logs showed verified driver mode, accepted `06/82` LED-state read returning 0, then rejected `06/84` RGB read with status 7. The old broad failure path disconnected the channel, causing the mapping model to stop. Both observed sessions restored mode 0/parameter 0 by read-back and removed their recovery journal; no RGB/state writes had been sent. Build 10 separates complete negative acknowledgements from failed/incomplete exchanges, so an unsupported optional command does not disconnect mappings. It permits the documented transient RGB setter only when the saved light was off; an initially lit light with unreadable color is left unchanged. Color writes are acknowledged and light state is read-verified; physical color still requires visual confirmation.

Brightness batches read current hardware, apply ordered bounded 5% steps, write, and read-verify. Incoming turns remain queued for a later batch. The dial’s visible state is durably saved before writing and restored after three seconds or stop/reconnect. Normal input mode is restored first when stopping; optional light recovery cannot postpone that mode change. Profiles, pending journals, raw logs, original middleware and signing keys remain excluded from Git. The GUI-only preview reuses helper 0.2.2 and requires no new installation or permission scope. The suite passes 52 tests, including migration, packet encodings, ordered brightness boundaries, negative acknowledgement policy, initially-off fallback and journal compatibility. Corrected brightness/indicator hardware results remain pending.

The corrected build kept mappings active during the next user test. The user confirmed keyboard brightness works and asked for a battery-style percentage popup; logs recorded acknowledged writes/read-back over the full 0–100% range, including rapid turns and both limits. No physical mode indicator was visible: `06/04` color write was also rejected with status 7, and the light remained off. The scoped state-only restoration path had no visible change to undo. No success is claimed for that color family.

Build 11 adds the non-activating two-second brightness percentage popup, refreshed after each completed read-back. It also investigates the separate RGB-only `06/88` getter and `06/08` setter templates retained in rzDevice30, with the same class 1 / LED 39 address and exactly three RGB bytes. This is an explicit interpretation of primary static constants, not an already verified product API. The app first checks current light state/color, preserves recovery information before writing, and reads color back when supported. Initially off lights with an unsupported getter can be restored to off; an already lit light with unknown color remains untouched. Physical RGB results and the new popup’s visual check are pending. The first lighting commit’s GitHub run passed all 52 tests and release/script checks: https://github.com/serafinski/razer-ergo/actions/runs/38623731217.

The revised suite passes 53 tests. The added rejection-exchange regression confirms that a status-7 reply is not treated as complete until both header and payload writes have been acknowledged; only then is retaining the Bluetooth connection safe.

The user then confirmed the brightness percentage popup works and clarified that the desired indicator is the small physical LED beneath the left command dial. The Razer official master guide identifies this as the Command Dial mode indicator LED (diagram page 2, default mode colors pages 9–10). The RGB-only getter `06/88` returned status 5; the next preview saved an initially off state and tried the recovered three-byte setter `06/08`, which also returned status 5. Its state-only cleanup read the light as off. Fully acknowledged rejections did not disconnect mappings. The primary vendor status array distinguishes unsupported command/class (5) from unsupported target ID (7); the earlier `06/84`/`06/04` rejection was a target rejection, not proof of missing RGB support generally.

Bounded read-only inventory-template queries produced raw `4041c2c3c4c5` from `06/80`, and status 7 from `06/81` with arguments `1/0`. Their precise meaning remains unverified and they are not used to guess other writable LED IDs. No RGB write has succeeded, so the UI marks physical mode colors experimental and the protocol reference records the exact failed requests. No Chroma investigation or Codex-status integration was started. The user was asked which connection Razer used when the physical LED colors worked; that missing fact will guide a capture/comparison rather than more repeated blind RGB variants. Native UI selection still times out, so hardware tests remain user-directed. The unchanged input helper is reused; current GUI version is 0.2.6 build 14.

A targeted read of existing local Razer product-708 middleware logs found an independent match: BLE product 707’s `Set LED RGB Brightness` writes used arguments 1/39 and three RGB bytes, and returned “Target ID Not Support” on 2026-10-13. Those logs also contain undefined-object failures on `setKnobConfigurationInformation`. Only the command/error facts are recorded here; the private logs, device serial/header bytes, application profiles, and macro data are not copied into Git. This establishes that the inspected Razer Bluetooth path failed in the same way, rather than proving all Bluetooth indicator control is impossible. Built-in firmware mode cycling or a different transport/API remains a hypothesis until compared with the working behavior the user remembers. The official guide is linked in PROTOCOL.md.

Build 15 retains the confirmed brightness popup and gaming-mode removal, marks physical keyboard colors experimental, and caches indicator API rejection for the remainder of the process so repeated mapping sessions do not repeat those probes. The next useful step depends on identifying the working Razer connection/path; no further blind RGB opcode or address variants were sent. All 53 tests pass locally, and the unchanged helper remains bundled with the same installed bytes.

The user stopped Ergo Control and confirmed a native-operation prerequisite: the keyboard backlight must be at least slightly on for the small mode LED to display colors. The app’s previous rejection cache prevented later brightness changes from reattempting color control. Build 16 returns to Razer’s original `06/84` / `06/04` wire pair, and reads the actual backlight level before each flash attempt. At zero it defers instead of sending RGB or declaring permanent failure. A user brightness increase retries the deferred mode color once; stopping cancels that deferred request. A new regression test covers zero, the smallest positive raw brightness, one-time retry, and cancellation. All 54 tests pass. No forced brightness increase or unrelated LED address is introduced. A fresh test with at least 25% backlight is pending; no successful physical color is claimed yet.

Build 16's positive-backlight test logged raw brightness 12 and still rejected the original RGB path with status 7. Build 17 sent the complete declared four-byte RGB-plus-brightness payload and read candidate classes 0–5 at target 39; all RGB operations still returned status 7. Build 18 enabled the recovered class-1/target-39 switch first and verified state 1, then retried RGB. Both getter and setter still returned status 7 with nonzero backlight. The saved off state was restored. The user reported the status message; physical illumination was not independently confirmed. Build 19 corrects the message from “indicator switch works” to “on/off command acknowledged.”

Build 19 performs bounded read-only RGB queries at class 1, using low-six-bit target IDs 0–5 from inventory `4041c2c3c4c5`. No inferred target is written. A more complete inspection found rzDevice30's `getLedIDList`: template `06/80` is named Get LED List, and `06/81` Get LED Type, queried with arguments 0/LED-ID. The generic implementation filters IDs 0–17 and therefore does not explain these firmware bytes directly. Earlier “class inventory” naming was speculative. Successful reads, if any, must be correlated with native mode-color changes before enabling another address. Brightness percentage is user-confirmed, and the same installed input helper is reused.

The build-19 hardware session logged backlight raw 25, an acknowledged on/off state change, and status 7 for every low-six-bit RGB target 0–5. This did not identify a usable address. Build 20 queries the LED list's literal bytes (64, 65, 194–197), then Get LED Type with arguments 0/target and RGB with arguments 1/target. It removes the known-rejected RGB writes and experimental switch writes from new discovery. Existing recovery journals are still handled, but these new diagnostic reads create no indicator-restoration obligation. The user was also asked to identify Bluetooth/USB/receiver connection in the working Razer/native test; the earlier reply established only the backlight prerequisite. The confirmed brightness popup remains unchanged, with the same installed helper and no new permission requirement. Literal-ID hardware results are pending.

The build-20 hardware test returned status 7 for all literal targets (64, 65, 194–197), both Get LED Type and RGB reads. The user clarified that native colors work over Bluetooth without opening Razer: stopping Ergo Control is sufficient. A comparison with Ergo Control left open and mappings disabled also restored native colors. Because build 20 sends no new indicator writes, rejected RGB/state experiments cannot explain its loss of native colors. The mapping session changes both firmware mode (verified 3/0) and input capture; driver mode replacing native dial processing is the leading explanation, rather than proof that the physical light cannot function over Bluetooth.

Further static inspection found dedicated USB knob commands in rzDevice25: Get/Set Knob Configuration Information use class 3 IDs 0x92/0x12, with 50-byte payload templates; Get/Set Current Knob Mode use class 3 IDs 0x93/0x13, with eight-byte templates. The current-mode reply carries LED class, ID, disabled, stage, mode ID, red, green, and blue. Those methods are absent from the inspected rzDevice30 Bluetooth implementation. This is evidence for another control path, not permission to send USB opcodes or port their setters to Bluetooth. Native firmware behavior must be kept separate from host-controlled RGB. No USB knob write or guessed Bluetooth knob opcode has been sent. The next useful investigation is a read-only comparison of native versus driver behavior and recovery of the dedicated knob interface, rather than repeating the failed generic LED writes. The build-20 commit's GitHub tests/build passed: https://github.com/serafinski/razer-ergo/actions/runs/38636673232.

The user connected an Apple USB-C charging cable; macOS enumerated product 1532:02c4, including interface 3's 90-byte configuration feature report. A new read-only USB inspector encodes only fixed-address getters, never captures input or seizes the keyboard. Initial opening of the entire matching HID manager was denied. Removing that unnecessary broad open and enumerating first allowed opening just the configuration collection without additional permissions. The successful method is in ErgoUSBResearch; the temporary GUI USB command workaround was removed.

USB current-mode and configuration reads both returned success. Current stage/mode 2/2, blue, changed to 3/3, yellow, after the user's native dial click; the configuration table retained enabled green/red/blue/yellow stages. This is a live correlation with the desired indicator, not a successful host color write. All requests were getters; no native setting was changed. Source rzDevice25 SHA-256 is recorded in PROTOCOL.md. Additional generic USB state/RGB getter templates are included in the reader but were not hardware-tested before returning to Bluetooth.

After the user returned to Bluetooth and quit the GUI to prevent battery polling overlap, the signed app's research-only --native-dial-read command compared three reads in normal mode, without entering driver mode. Class 6 / ID 0x84 at 1/39 still returned unsupported-target status 7. USB-derived current-knob candidates 0x93 and 0x95 both returned unsupported-command status 5. Bluetooth metadata reports a three-byte maximum feature report and two-byte maximum output report (including IDs); descriptor parsing identifies a two-byte keyboard feature and one-byte standard lock-LED output, so there is no exposed USB-sized HID configuration channel. Another GATT control path remains possible but unrecovered. All 58 tests pass, covering the USB getter templates, checksum, reply transaction/address/opcode validation, and negative replies. The installed input helper remains unchanged.

The user then asked whether Chroma or Razer's driver could provide the missing control. Official product specifications confirm 19-zone Chroma RGB, and the current Razer Mac page advertises a Chroma app preview; these do not document the small indicator's public SDK target. The local Razer HID extension was installed/activated but disabled, while its Virtual HID extension was enabled. USB knob reads succeeded under that state. With Ergo Control/helper no longer running and no restoration owed, the user was asked to enable the existing Razer HID driver and test a clearly changed mode color over Bluetooth only, restoring the original color afterward. This comparison remains pending and must distinguish custom host color control from the autonomous default color cycle. No vendor package was installed or extension state changed by the agent. Sources and the boundary of deferred Chroma/Codex lighting are in ROADMAP.md.

The user enabled Razer's HID extension and reported no indicator response while testing in Razer. Both HID and Virtual HID extensions were verified activated/enabled. New product-708 Razer logs on 2026-10-14 at 23:34–23:36 local time show Set LED RGB Brightness (class 6, ID 4) rejected as Target ID Not Support, repeated knob-configuration/current-mode calls, and device mode 3/0 being selected. Only normalized command/error facts are retained here; raw logs and device headers remain private. This repeats the failure in Razer's own Mac/Bluetooth implementation with its driver enabled, rather than establishing a missing-driver fix. Native colors with mappings off are consistent with an autonomous firmware fallback; firmware mode and capture were not independently isolated, so do not state that every Bluetooth host-control path is impossible. No additional color-write experiments are warranted without new primary evidence. The 58-test GitHub run passed: https://github.com/serafinski/razer-ergo/actions/runs/38641304594.

Test cleanup verified Razer HID Driver Extension disabled again in both System Settings and systemextensionsctl; its pre-existing Virtual HID extension remains enabled. The native app inventory showed the Razer GUI already closed. No other driver was changed. The System Settings “Unknown” group displayed Karabiner VirtualHIDDevice and OverdriveDriver, not Ergo Control; this project uses a local launch-daemon helper instead of DriverKit. Setup documentation now records that distinction and the tested Razer driver state.

The user reported a battery display increase from roughly 61% to 81% after the Razer comparison. Existing Ergo Control logs show raw 163 -> 63% before the USB test, raw 168 -> 65% at 2026-10-14 21:10 UTC, and raw 209 -> 81% at 21:43:56/21:44:02 UTC. There is a roughly 34-minute gap while the app was closed for research and the keyboard was connected to USB during part of that interval; these samples do not prove an instantaneous increase on launching Razer. The inspected rzDevice30 battery getter uses floor(raw / 255 * 100), identical to our integer conversion. Razer's own normalized logs show 98%, 95%, 93%, 90%, then 89% during the comparison, with charging status 0 in the later samples. USB charging and a changing/reassessed device estimate are plausible, but the exact cause and actual charge increase are unproven. No conversion bug was found and no smoothing or battery-setting writes were added. Raw logs remain private. Razer's [master guide](https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf), page 5, documents USB charging and use while plugged in.

## 15 October 2026 — built-in backlight effects

Added app 0.2.7/build 24 with a whole-keyboard lighting panel. Static analysis recovered the New Chroma supported-ID/current-effect/set-effect commands (`10/82`, `10/83`, `10/03`) and the flags/rate/color conversion from the already inventoried product middleware. The official master guide page 11 independently lists Off, Static, Breathing, Spectrum cycling, and Wave. The app offers only understood IDs advertised by the connected keyboard, with Static/Breathing colors and Wave direction. It reads back applied settings, preserves brightness, and allows normal-mode use without starting mappings or the input helper. It does not write the unresolved dial indicator.

All 62 automated tests pass (54 core, 5 action engine, 3 device recovery), including new protocol fixtures, malformed/truncated read responses, invalid colors/directions, unknown-write rejection, and supported-effect filtering. The release preview builds and validates signatures. The bundled input helper remains byte-for-byte unchanged (0.2.2/build 5). Native app control timed out during verification; the current mapping session must be stopped before the separate read-only diagnostic can run. No live effect-command or physical-effect success is claimed at this point. Local raw Bluetooth logs remain uncommitted.

After the user quit, the diagnostic correctly refused to run because the last mapping session had disconnected with mode restoration still journaled. A dedicated `--restore-keyboard` CLI now invokes the existing exact-device recovery, with a 30-second limit and no journal deletion unless readback verifies success. It restored mode 0/parameter 0 successfully. The subsequent read-only lighting check completed: `10/82` returned `[0,1,2]`, while `10/83`, live profile 1/AllRegion 0, returned `[3,0,0,0]` (Spectrum cycling). The current Bluetooth endpoint therefore advertises only Off/Static/Breathing, although its native firmware is currently using Spectrum. The picker continues to restrict writes to advertised effects. No unadvertised Spectrum/Wave write was attempted and no physical animation result is claimed. GitHub CI for the initial lighting commit passed.

## 15 October 2026 — lighting feedback and complete preset choices (build 25)

The user reported that Breathing appears to work and that Read/Apply buttons dim periodically. Fresh normalized logs include successful effect readbacks for Static (ID 1, one RGB color), random Breathing (ID 2, no colors), and Off (ID 0). The same session verifies driver mode about every five seconds. UI availability depended on the transport’s short-lived `busy` flag, explaining the recurring dimming. Build 25 queues one explicit lighting request behind the current command/dial operation; normal background checks no longer disable the controls. Restoration/disconnect cancel pending requests, and the request is consumed only once. Two additional tests cover busy waiting, a bounded pending slot, one-time consumption, and read/write cancellation.

The user supplied a Synapse screenshot whose menu contains Breathing, Spectrum Cycling, Static, and Wave alongside a Bluetooth-limitation notice. The official master guide independently lists these four presets plus Off. Since a native Spectrum read had already succeeded, the advertised `[0,1,2]` response was an overly restrictive basis for hiding the other two presets. All five recovered, validated effect types are now selectable. Spectrum/Wave carry a note explaining their absence from the advertised list; explicit Apply sends their known command followed by readback. No automatic unadvertised-effect probes or custom/frame writes are added. Acceptance and physical Spectrum/Wave output still need verification.

## 15 October 2026 — Wave confirmation and speed check

The user confirmed the combined build-25 Spectrum/Wave and steady-button test works. Normalized Bluetooth reads independently show Spectrum (ID 3, flags/rate 0), Wave left (ID 4, flags 1, rate 40), and Wave right (ID 4, flags 2, rate 40). This confirms that the advertised `[0,1,2]` list was incomplete as a restriction on selectable effects.

The user asked whether Wave speed could be adjusted, clarifying that leaving it unchanged was fine if no native control exists. Razer product defaults store only Wave direction, shared LightingHelper fixes its rate to 40, and master guide page 23 documents direction only. The raw setter has a rate field, and another Razer command family in OpenRazer documents speed semantics, but neither verifies another rate on this BLE keyboard. No additional device writes or app controls were added; adjustable speed remains unverified. See the protocol notes for source links and the transport distinction.

## 15 October 2026 — intermittent media response (0.2.8/build 26)

The user reported needing to turn the right dial or toggle mute before media-button playback resumed, but could not confirm whether it also happened with mappings off and said the issue was minor. Existing saved media-single captures contain normal report-3 play/pause presses followed by neutral reports after approximately 30–45 ms. Code inspection found the app held the last consumer usage indefinitely and ignored repeated identical usages; a lost neutral could reproduce the symptom by keeping play/pause held until a volume/mute report changed the usage.

A scoped fallback now releases/rearms play/pause, next, and previous gestures after 300 ms if no neutral arrives. Normal releases remain immediate, duplicate packets within a pulse remain deduplicated, and held volume/seek semantics are retained. Four decoder tests cover normal/duplicate pulses, missing release recovery including delayed timers, changed controls/late neutrals, and invalid reports/held controls. Two action-engine tests exercise balanced media output and shutdown with an output sink, without posting media keys to the Mac. All 70 tests pass. The original incident remains unconfirmed by a fresh failing trace; this is a regression-tested defense against the identified stuck-state path. The existing input helper is reused unchanged.

## 15 October 2026 — app consolidation and original branding (build 27)

The user asked why multiple apps existed and requested a logo. Local inventory found an obsolete Ergo Control 0.1.1/build-2 bundle without a helper and the active development Preview at 0.2.8/build 26. With neither running, the old bundle was preserved under `build/archive/` as a `.bundle-archive`, Preview was moved to `build/Ergo Control.app`, and optional Probe/Bluetooth app bundles were moved under `build/diagnostics/`. Build scripts now preserve these roles: a single canonical product path, separate opt-in diagnostics. Source targets remain available for future research; no settings, captures, or recovery journal was deleted.

Added original split-keyboard/dial vector artwork rendered through AppKit into a full ICNS iconset and PNG previews, plus 1×/2× monochrome menu-bar marks. The product bundle declares CFBundleIconFile, copies the artwork before signing, and uses the same mark in the menu bar and settings header. Assets and editable renderer are MIT project material, independent of vendor art. The app retains bundle ID/certificate identity and reuses the byte-identical installed helper; no helper reinstall is part of this change.

Validation: all 70 existing tests pass, all shell scripts parse, and the signed release bundle verifies. AppKit loaded the packaged app icon at 16–1024 pixel representations and the menu mark at 18/36 pixels; the rendered artwork was visually inspected. The bundled helper SHA256 remains `94df36722903fa18c5b6ab487ab94e90bfe90f8760ef5d61a51f34c5bdba0876`. Exactly one top-level product app remains. Native UI inspection could not complete because the computer-use pipe closed, so no live settings/menu-bar screenshot is claimed.

## 15 October 2026 — macro lighting zone map

The user requested investigation of individual macro-key colors, including Chroma as a possible source. Static inspection of the official Mac Chroma installer and public lighting-engine/Studio assets located the product-708 lighting manifest directory. The Bluetooth (707), USB (708), and receiver (706) manifests all map M1–M5 inputs 32–36 to lighting coordinate `[0, 0]` in the matching US layout's 1 × 19 matrix. Its embedded Studio diagram has one LED path containing all five macro-key shapes, independently corroborating a shared macro column. No separate per-macro RGB targets are exposed by the supported map. The nearby command-dial indicator is not established as the same target by the map's dial-input association.

Bluetooth explicitly declares hardware-effects-only and no Chroma Studio support; USB and receiver declare Studio support. This identifies a plausible route for future whole-column status lighting, not a working custom-frame implementation. No keyboard writes, Chroma installation, vendor binary execution, driver changes, or permission changes were performed. The read-only USB inventory did not expose a Razer target during this investigation. The app/helper and their existing tests were unchanged. Raw vendor artifacts remain ignored; sources, hashes, interpretation limits, and a prospective restoration-aware hardware test are recorded in [MACRO_LIGHTING.md](../MACRO_LIGHTING.md). Codex status integration remains unimplemented.

## 15 October 2026 — bounded lighting pattern experiments (build 28)

The user asked to test moving lines and other possible patterns. Added an optional Lighting Lab entry point inside the signed Ergo Control app, a Python wrapper, and a double-click menu. Bluetooth compares nine known built-in preset variants, including both Wave directions. The USB branch targets only the Pro Type Ergo wired configuration interface and independently implements the recovered protocol-2.5 class-15 effect selector/frame templates. The profile-0, region-0 19-zone experiments include a scan, fading chase, progress bar, rainbow, and shared macro-column solid/pulse/status colors. No separate M1–M5 lighting targets are invented, no unknown effect/rate scan is performed, and the existing USB inspector remains read-only.

Each run snapshots a supported starting effect before its first write, pins recovery to the same device/connection, and retains its private journal until restoration is read-back verified. Tests refuse an unrestorable initial custom frame or malformed/unsupported starting effect. Signal handlers stop the sequence and attempt restoration; connection loss or forced termination can leave recovery pending for an explicit retry. USB frames require valid acknowledgements, with at most five updates per second. The implementation does not install Chroma, enter driver mode, change brightness, capture input, or change the input helper. The USB protocol family is class 15, distinct from the existing Bluetooth class 16.

Validation: all 77 automated tests pass, including zone boundaries/shared-column behavior, frame fixtures/checksum validation, rejection of malformed replies and unrestorable snapshots, and preservation of recovery records after device mismatch, write failure, or readback mismatch. Wrapper/menu syntax, native listing, invalid duration/connection combinations, and refusal while the GUI is running were checked without lighting writes. The signed build succeeds and the bundled helper hash remains unchanged. No USB interface is currently available; custom zone output and physical restoration still need hardware observation. See [Lighting Lab](../LIGHTING_LAB.md) for operation, recovery, protocol details, and limits.

## 15 October 2026 — first USB animation tests and identity fallback (build 29)

After the user connected wired USB and quit Ergo Control, the read-only inspector found one eligible configuration interface. The initial lab attempt correctly aborted before lighting writes because HID properties had no stable identity. Read-only USB registry inspection confirmed `iSerialNumber=0`; no port/location-only identity fallback was used. Static vendor protocol evidence supplies a 22-byte serial getter at class 0 / ID 0x82. The lab now uses that read-only getter when HID identity properties are absent, validates its response and hashes the serial locally. Raw serials are neither printed nor logged. A new test covers the exact getter envelope and absent/placeholder/invalid serial rejection.

Live USB `chase` and `macro-pulse` tests then each ran for eight seconds and sent 35 acknowledged frames. Both verified custom effect selection, restored the original effect, and verified that restoration by readback. The recovery journal is absent after completion. The user was asked whether the moving cyan line and shared pulsing macro column were physically visible; that observation remains pending. Command acknowledgements are not recorded as proof of visible animation. Other generated patterns and interruption-on-hardware remain untested. The input helper remains byte-identical; no Razer components, drivers, brightness changes, or input-mode changes were involved.

The user subsequently confirmed a pulsing pattern and the cyan line moving across the keyboard. They did not focus on whether the remaining keys were dark during the pulse; therefore visible animation is confirmed, but macro-column isolation is not. Documentation distinguishes these observations from the stronger unsupported claim that every zone/background behavior was tested. All 78 automated tests pass after the serial-getter fix, and build 29 verifies with the unchanged helper signature/hash.

## 15 October 2026 — isolated macro lighting confirmed over USB and Bluetooth (build 30)

At the user's request, a 20-second USB macro pulse was repeated (87 acknowledged frames), followed by verified saved-effect restoration. The user confirmed only M1–M5 pulsed, with all other keys dark. This closes the earlier isolation uncertainty for the shared macro zone.

The user then switched to Bluetooth only with the cable unplugged and Ergo Control quit. Static inspection of `rzDevice30` recovered its lighting-engine frame encoder: custom effect 8, profile 0, frame type 4, rectangular row/column bounds followed by RGB data. A separate opt-in lab API was added; the regular app's effect writer remains limited to the original five firmware effects. The first probe at AllRegion 0 accepted and read back custom effect 8, but rejected the first frame with status 7. Original effect restoration at the same target succeeded and was verified, with no pending recovery.

Rather than scanning target IDs, the next probe queried the existing region-list getter (`10/80`, arguments `0/1`). The keyboard returned `[5]`. At profile 0 / region 5, it accepted custom mode and 20 acknowledged frames over ten seconds. The user confirmed **only M1–M5 pulse over Bluetooth**, with the other keys dark. Saved-effect restoration at `0/5` was read-back verified and the journal cleared. This establishes working custom RGB zone output over Bluetooth despite the vendor's hardware-effects-only/no-Studio flags. The earlier AllRegion rejection was a target issue on the tested path, not a demonstrated Bluetooth firmware prohibition.

Recovery records now optionally preserve the Bluetooth profile/region; legacy preset journals retain profile-1 behavior. Two additional tests cover the exact Bluetooth frame/header/bounds/chunk fixtures, known-effect-only restoration, region discovery/addressing, legacy decoding, and invalid recovery-target metadata. All 80 tests pass. The wrapper requires `--experimental-frames` for Bluetooth zone tests; menu option 6 supplies it. No brightness/input-mode changes, Razer installation, driver changes, or helper update were needed. The separate physical dial indicator, other generated patterns, and active-mapping coexistence remain unverified.

## 16 October 2026 — repeat timing and global arrow shortcuts (build 31)

The user reported much faster Backspace deletion with mappings enabled and failing Control–Option–arrow shortcuts in Magnet. Inspection found both global repeat preference keys absent, which the relay interpreted as zero and clamped to a 250 ms delay / 15 ms interval. AppKit instead reported the effective system values as 500 ms / approximately 83.33 ms. The relay now reads `NSEvent.keyRepeatDelay` and `keyRepeatInterval` in seconds, preserving valid custom timings and using sane fallbacks only for invalid values. No system preferences were changed.

Read-only CGEvent construction showed native arrows include keypad/function flags and modifier keys include side-specific device bits. The relay replaced those flags with a generic modifier mask. It now retains intrinsic arrow metadata and emits the documented left/right modifier bits. Keyboard transitions are ordered so modifier presses precede ordinary-key presses and ordinary-key releases precede modifier releases, with the correct modifier state at each step. This also handles combined modifier/arrow reports rather than relying on separate hardware packets. The event source/input helper and stored mappings are unchanged.

Six new tests cover seconds-based timing and invalid/missing-value fallback, left/right Control–Option arrow ordering, releases and staggered presses, actual CGEvent metadata, and Backspace repeat delay/cancellation using a suppressed-output sink. All 86 tests pass and the signed app builds with the byte-identical helper. The user was asked to restart the app and check real Backspace/Magnet behavior; physical/third-party confirmation remains pending.

## 16 October 2026 — Chroma and Codex Micro feasibility

Completed the requested [feasibility report](../CODEX_AND_CHROMA.md), comparing official Chroma effect/editor/ecosystem features against our verified direct frame path. Additional host-generated animations and composition are feasible; no additional macro LED granularity was established. For Codex, official Micro behavior and documented keyboard/deep-link/hook/App Server surfaces were checked. A supported-shortcut plus opt-in lifecycle-hook adapter is the proposed initial route, with explicit limits on unread/selected/cloud state and exact native control parity.

Public Micro emulator sources were inspected as interoperability research, and the installed app was read statically without running third-party code. The installed Work Louder package declares UNLICENSED; no code/assets were copied into the project. The app's Node-options fuse is disabled and ASAR protections enabled, so the community launch-shim example is not a verified solution for this build. A true virtual Micro endpoint would require resolving Apple entitlement/signing and current-version compatibility. No shim was installed, Codex relaunch performed, hook trusted/configured, session content read, or app/feature state modified. Sources, pinned reference commits, installed build, package/license facts, and code hashes are retained in the report; raw references remain ignored.

## 16 October 2026 — prevent inherited Fn/keypad flags (build 32)

The user confirmed Backspace repeat was fixed and Magnet's arrow shortcuts now worked, but reported D invoking dictation, E opening emoji, and Control–Option–Return not working. Build 31 derived intrinsic Fn/keypad metadata from each newly constructed event, whose source can contain flags inherited from preceding navigation. Preserving that state on letters/Return was a regression. Metadata is now selected from the current HID key identity rather than the event source's flag state. Letters, modifiers, Backspace, and main Return get no implicit Fn/keypad flag; arrows retain their native function/keypad identity, and keypad Enter remains distinct from main Return. Native function/navigation/keypad categories were checked by read-only CGEvent construction, without posting input or recording user typing.

Two new tests seed events with stale Fn/keypad and unrelated modifier flags, then verify D/E/Return and modifier events discard them. They also exercise Control–Option–Return after arrow construction and confirm main Return (keycode 36) versus keypad Enter (76) have distinct metadata on press/release. All 88 tests pass, the signed GUI builds, and the helper remains byte-identical. The macOS repeat timing and modifier-before-arrow ordering corrections are retained. The user was asked to restart and verify D/E and the Return shortcut; that check remains pending.

The user subsequently confirmed “All working now” for the build-32 test after a Magnet arrow shortcut: D/E type normally, and Control–Option–Return works. Backspace repeat and the arrow shortcuts were already confirmed fixed. This closes the reported input regressions; no helper reinstall or system preference changes were needed.
