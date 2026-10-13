# Local investigation — 13 October 2026

## Status

Ergo Probe builds and opens on this Mac. Its inventory detects exactly one matching Bluetooth HID device and obtains one paired CoreBluetooth identifier. After the user enabled Input Monitoring, HID open succeeded. A labeled positive control recorded exactly three A presses (`01 00 04 00 00 00 00 00 00 00 00 00`) and three releases (`01 00 00 00 00 00 00 00 00 00 00 00`), physical report ID 1. Subsequent per-control tests recovered left-dial rotation but no reports for left click, M1, or AI in the current configuration. **No successful Bluetooth notification capture or mode query has happened yet.** No Razer commands have been sent by this project.

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

No report IDs 5 or 6 were observed in these completed tests. The current firmware mode has not yet been read, so do not call these normal-mode results as an established fact. M2–M5, the right roller, and other controls have not been newly established by these captures. Further baseline repetition alone does not resolve the activation question.

## Bluetooth mode helper

A separate native `Ergo Bluetooth.app` now builds from `Sources/ErgoBluetooth/`, preserving Ergo Probe's working executable and Input Monitoring permission. It verifies the exact paired HID identity without opening input devices, then uses only the matching CoreBluetooth identifier and the proven Protocol 30 service. Runtime transport uses acknowledged sequential writes, one outstanding command, the tested bounded response assembler, and a five-second timeout.

The helper first reads the current mode. Temporary driver mode remains unavailable until a successful response identifies normal mode. The implemented temporary change saves and synchronizes a recovery record before writing, verifies mode 3, schedules restoration after 60 seconds, verifies the original mode after restoration, retries restoration after failures, and defers normal app termination while restoration remains owed. These state-changing and recovery behaviors have not yet been exercised on hardware.

At the current checkpoint, CoreBluetooth had not delivered an initial state callback or exposed the helper in the Bluetooth permission list. The current helper was selected in System Settings → Privacy & Security → Bluetooth → Add, and the user was asked to complete that permission step. No query or mode write had been sent. Resolve permission/connection startup before attempting a temporary change.

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

Its descriptor contains input report IDs 1–6. Report 1 carries keyboard modifiers and an array of key usages; report 2 describes pointer/scroll input; report 3 describes consumer usages; report 4 describes system controls. Reports 5 and 6 each declare an 11-byte input array under Generic Desktop page 1 / application usage 0. They are **not declared under a vendor-defined usage page**. Their semantics remain unknown.

The product middleware separately defines `{4: "razerKeyReportID", 5: "hardwareEventReportID"}`. Its Protocol 30 hardware parser removes a leading byte before reading a logical type, with 4 meaning Razer keys and 5 meaning notifications. **Do not equate these logical IDs with physical HID report IDs without capturing the intervening layout.** The probe saves the callback's report ID and complete bytes so this can be resolved.

## Per-control evidence

The earlier observed behavior is preserved from the handoff; none was newly replayed during this local run. Vendor key IDs below are configuration identifiers, not confirmed USB/BLE packet offsets or HID usage IDs.

| Control | Earlier observed input | Ergo-specific static identifier | Activation / remaining question |
| --- | --- | --- | --- |
| Left dial CW/CCW, zoom mode | Command + keypad plus/minus | Default dial mapping uses `ScrollRight` / `ScrollLeft` | Capture raw scroll/key reports and note current dial mode |
| Left dial click | None in earlier remappers | `DKM_KB_LEFTKNOB`, key 96 (`0x60`) | Source routes command-dial output to next mode; Shift modifiers select previous; raw event unconfirmed |
| Right roller CW/CCW | Consumer volume up/down | Default `ScrollUp` / `ScrollDown` mappings | Capture actual report and determine independence from left dial |
| Right roller click | Consumer mute | `DKM_KBMK_04`, key 82 (`0x52`), named `DIAL_CLICK` | Confirm physical association in labeled test |
| M1 | No earlier event | `DKM_M_01`, key 32 (`0x20`) | Driver mode may be required; capture before altering device |
| M2 | No earlier event | `DKM_M_02`, key 33 (`0x21`) | Same |
| M3 | No earlier event | `DKM_M_03`, key 34 (`0x22`) | Same |
| M4 | No earlier event | `DKM_M_04`, key 35 (`0x23`) | Same |
| M5 | No earlier event | `DKM_M_05`, key 36 (`0x24`) | Same |
| AI button | No earlier event | `DKM_SB_247`, key 247 (`0xf7`), named `AI_Launcher` | Free assignment remains the app requirement; runtime exposure unconfirmed |
| Media single/double/triple | Play/pause, next, previous | `DKM_KBMK_02` key 85, `DKM_KBMK_03` key 83, `DKM_KBMK_01` key 84 | Confirm the multi-press timing and actual raw reports |
| Battery button | No earlier event | No physical button mapping established | May only display device status internally |
| Battery percentage | Not captured earlier | Protocol 30 `getBatteryList`, `getBatteryLevel`, `getChargingStatus` | Request/response code recovered; no local query sent yet |
| Additional keys | Unverified | `DKM_D41` key 65 and `DKM_SB_251–253` | Physical identity and meaning need labeled testing |

Confidence is high for the downloaded source identifiers and historical successful Protocol 30 connection; runtime exposure of missing controls is still unverified. No control is declared permanently unsupported from a failed or empty generic capture.

## Recovered configuration commands — not executed

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

Historical successful driver-mode request: `04 02 00 00 01 02 00 00 03 00`, transaction 4. Response assembly matches byte 0 against the transaction and checks byte 7 for status 2. The vendor generally treats the first response notification as a 20-byte header and subsequent notifications as payload, with an 8-byte fallback in its unpacker. This requires dedicated reassembly and timeout tests before enabling writes.

The vendor also returns to normal mode on window unload. Before a controlled initialization test, capture baseline, read/preserve the existing mode, confirm the exact target, implement restoration and failure handling, then compare the same labeled controls. Merely understanding Set Device Mode does not prove it alone enables M1–M5.

## Verification and next milestone

Completed: release build, native app launch and visual inspection, strict device-matching tests (including exclusion of Logitech and USB identities), inventory on the real keyboard, successful non-seizing HID open after permission grant, and a three-press A positive control. Permission denial is explicitly logged rather than treated as an empty successful recording.

The offline Protocol 30 codec now has nine tests covering the historical mode-request fixture, header/payload write boundaries, read-query fields, transaction rollover, unrelated responses, 8/20-byte headers, payload fragments, failure status, and malformed/oversized responses. It performs no I/O and is not connected to the runtime Bluetooth observer. No device-mode write has been enabled.

Next: use the per-control test flow to collect labeled baseline controls with Synapse's app stopped. If extra controls are absent, connect the tested Protocol 30 query/reassembly codec to a single-command Bluetooth transport, followed by reversible device-mode initialization. Preserve the MX Master configuration and never install a generic all-device interception layer.
