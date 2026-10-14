# Pro Type Ergo Bluetooth and input protocol

This is a concise reference for the protocol recovered during this project's hardware investigation. The [research history](research/INVESTIGATION.md) records provenance and individual tests. Codecs live in `Sources/ErgoCore`; encoding a command there performs no I/O.

## Target and configuration channel

Match vendor `0x068e`, product `0x02c3`, and transport **Bluetooth Low Energy**. The paired CoreBluetooth peripheral is resolved from the matched HID device's physical unique ID at runtime. No fixed peripheral identifier is shipped.

| Endpoint | UUID |
| --- | --- |
| Protocol 30 service | `52401523-F97C-7F90-0E7F-6C6F4E36DB1C` |
| Acknowledged write | `52401524-F97C-7F90-0E7F-6C6F4E36DB1C` |
| Response notifications | `52401525-F97C-7F90-0E7F-6C6F4E36DB1C` |

Requests have a separate eight-byte header: transaction, three little-endian payload-length bytes, command class, command ID, argument 6, argument 7. Transactions cycle through 1–31. Payload is sent in separate chunks of at most 20 bytes, awaiting each write acknowledgement. Only one command may be outstanding.

Responses have a 20-byte header (the codec also supports the vendor's eight-byte variant), followed by separately notified payload fragments. Byte 7 is status; 2 is success. Only the announced payload length is consumed, excluding padding. Hardware sometimes returns status 3 before success for the same transaction, so retry statuses 1/3 wait until success or the five-second deadline. Completion requires both response assembly and every write acknowledgement.

| Operation | Class / ID | Arguments or payload | Evidence |
| --- | --- | --- | --- |
| Read mode | `01 / 82` | No payload | Live verified |
| Set mode | `01 / 02` | `[mode, parameter]` | Temporary driver mode and restoration verified |
| Read battery IDs | `05 / 80` | Argument 7 = 1 | Live result `[1]` |
| Read battery level | `05 / 81` | Argument 7 = battery ID | Live verified, percent = `raw × 100 / 255` |

Normal mode was `[0, 0]`; driver mode is `[3, 0]`. Driver mode exposes the extra controls and independent left-dial turns. Runtime writes preserve the original mode durably before changing it, verify driver mode by read-back, and restore/read-verify the saved mode afterward. No firmware, onboard macro, or general hardware key-mapping writes are implemented. The app implements the verified brightness writes below. Indicator writes are disabled in the current diagnostic path; older recovery journals remain supported.

## Keyboard brightness and command-dial indicator

The product module defines `backlightStep: 5`, a green Keyboard brightness dial mode, and `obmSupportFeature.knobId: 39`. The shared command-dial switch task routes its selected RGB color to the `knobLighting` task. That task uses LED class 1 and the product-specific knob ID (39), writes RGB, enables the light, then disables it after three seconds. The default 36 in shared code belongs to other devices and is not used here. These are targeted live control commands, not onboard macro/matrix writes.

| Operation | Class / ID | Arguments / payload | Evidence |
| --- | --- | --- | --- |
| Read lighting regions | `10 / 80` | Arguments 6/7 = `0/1`; region = each returned byte & 63 | Live brightness read/write verified |
| Read keyboard brightness | `10 / 85` | Profile 1; first discovered region; one raw byte returned | Live brightness read/write verified |
| Set keyboard brightness | `10 / 05` | Profile 1 / AllRegion 0; one byte `floor(percent × 255 / 100)` | Live brightness read/write verified |
| Read dial state | `06 / 82` | LED class 1 / LED ID 39 | Live accepted, initial state 0 |
| Set dial state | `06 / 02` | LED class 1 / LED ID 39; `[0]` or `[1]` | Live accepted; read-back on/off verified, physical illumination unconfirmed |
| Shared RGB+brightness getter | `06 / 84` | LED class 1 / LED ID 39 | Live rejected with status 7 |
| Shared RGB+brightness setter | `06 / 04` | LED class 1 / LED ID 39; RGB three bytes or RGB+brightness four bytes | Both live rejected with status 7 |
| RGB-only read candidate | `06 / 88` | LED class 1 / LED ID 39 | Live rejected with status 5 (command not supported) |
| RGB-only write candidate | `06 / 08` | LED class 1 / LED ID 39; `[red, green, blue]` | Live rejected with status 5 (command not supported) |

The generic RGB command template advertises four payload bytes, but the inspected `Zo` implementation actually allocates three via `Po[0]`. Its attempted fourth-byte assignment is outside that buffer, and `_createDataSend` encodes the actual buffer length. Build 9/10 matched that three-byte wire encoder. The subsequent live setter was rejected as well. The same module retains a separate paired three-byte template `06/88` / `06/08`; build 11 investigates that RGB-only interpretation. These constants are primary static evidence, but they are unused by the inspected high-level RGB method, so support on this device must be established by hardware responses. The RGB-only getter and setter were subsequently both rejected with status 5; no successful color write is claimed. Build 17 also tested the declared four-byte RGB+brightness payload, preserving that fourth byte in recovery snapshots when readable; it was rejected with status 7 too. Writes remain limited to the recovered class 1 / ID 39 address. A successful getter enables RGB read-back verification; otherwise acknowledgement alone is not a visual RGB verification.

The first live 0.2.6 session established that this keyboard supports dial-state reads but rejects RGB reads. The initial implementation disconnected on every command failure, stopping otherwise working mappings; normal mode was restored and verified. Fully assembled negative acknowledgements now leave the channel connected. Only incomplete/timed-out/malformed exchanges force reconnection. On status 7 with a previously off light, the app can durably preserve the off state and attempt the scoped RGB setter, then restore off after three seconds. An already lit light is left unchanged if its color cannot be preserved. No unrelated LED IDs are written. Both RGB command families are tied to recovered templates; the RGB-only family was also rejected.

Brightness uses the first discovered region for read-back, matching the vendor’s default getter, and profile 1 / AllRegion 0 for writing, matching its live brightness task. Turns are applied in order in five-percent steps, so at 100%, clockwise then counterclockwise ends at 95%. Future turns stay queued during a write/read-back exchange. Indicator and brightness chains share the existing one-command transport; mapping restoration has priority and cancels new lighting work. Normal input mode is restored before optional indicator recovery. Brightness is intentionally retained as a user setting. The user confirmed backlight adjustment and the percentage popup, with live read-back covering both limits and rapid turns.

Additional bounded read-only discovery used adjacent templates `06/80` (no arguments) and `06/81` (arguments `1/0`). The first returned raw bytes `4041c2c3c4c5`; the second returned status 7. These replies have not been assigned a reliable class/target interpretation, so no other LED addresses or metadata argument variants are written based on them. Early tests left the switch off. Build 18 explicitly enabled it first: the setter was acknowledged and the state getter returned 1, yet both RGB getter and four-byte setter still returned status 7. The switch was restored after three seconds. This verifies command state, not physical illumination. The command-dial indicator is still unresolved on this Bluetooth connection.

The vendor’s own status-description array identifies 5 as unsupported command/class, 6 as unsupported profile, and 7 as unsupported target ID. Thus a status-7 reply does not establish that RGB control is impossible; it rejects the requested address for that command. Comparing the connection used by Razer is the next investigation step.

Razer’s [official master guide](https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf) labels the small physical light beneath the left dial as the Command Dial mode indicator LED (diagram on page 2). Pages 9–10 describe its default mode colors; this is the physical LED being investigated here, independently of the app’s on-screen popup. The guide does not provide the Bluetooth command/address needed to control it.

Existing local Razer middleware logs independently show the same failed `06/04`, arguments `1/39`, three-byte RGB write for BLE product 707, reported as “Target ID Not Support” on 2026-10-13. They also show attempts to call `setKnobConfigurationInformation` failing because the corresponding object is undefined. Raw Razer logs are not committed. This corroborates the rejection using Razer’s own client; it does not establish whether another Bluetooth API, native firmware mode cycling, or another transport can drive the light. The current app runs indicator discovery once per process and records read results; brightness/mapping sessions continue normally.

The user then checked native operation with Ergo Control stopped and identified another prerequisite: keyboard backlight must be above 0% for the physical mode light to show colors. Build 16 returns to Razer’s original `06/84` / `06/04` pair and reads actual keyboard brightness before attempting a flash. A zero read sends no RGB command, records a deferred request, and displays the backlight requirement. Raising brightness retries once; stopping cancels the request. Rejected APIs are cached only after an attempt with nonzero brightness. The controlled test logged positive backlight (raw 12 and later 25); RGB target 39 was still rejected with status 7. The RGB-only pair remains rejected and is no longer the active color path.

Build 17 read RGB using candidate classes 0–5 and target 39; all returned status 7. Build 19 instead reads RGB at class 1 for low-six-bit target IDs 0–5 derived from the inventory. This interpretation is provisional and enables no writes. Subsequent source inspection identified the existing `getLedIDList` method: `06/80` is named **Get LED List**, and `06/81` is **Get LED Type**, with arguments `0/LED-ID`. Its generic enum lists IDs 0–17; the firmware's returned bytes lie outside that range, so their flag encoding remains unverified. Earlier helper names “classes”/“targets” were speculative and should not be treated as protocol facts. Any successful RGB read must be correlated with native dial-mode changes before choosing a writable physical indicator address.

Build 19's low-six-bit targets 0–5 all returned status 7. Build 20 follows the LED-list method more literally: it reads the exact returned targets 64, 65, 194, 195, 196, and 197, queries their types using `06/81`, arguments `0/target`, then RGB using `06/84`, arguments `1/target`. These are bounded reads only; neither the old target-39 color write nor its on/off write is attempted during new discovery. The public codec names are now `readLEDList` and `readLEDType`, matching the source. High bits are kept opaque, not assigned a meaning or stripped using the different Chroma-region parser. Hardware results for the literal IDs remain pending.

Static provenance (vendor sources remain local and ignored):

| Artifact in `analysis/vendor/708/mw/` | SHA-256 |
| --- | --- |
| `main.c8f8537456ab6ae7c847.js` | `7ffb823c6fb1586bcc19e44781b2be4076f44e6589d98797b52029f8c80c1a55` |
| `6737.5b007c860f4efa22ab87.js` | `4b1973cfa843afc214f8166ab14e5428ed9814f5a5c6b866cfa8e0ecfd939a86` |
| `rzDevice30.a29e745b43244151d1fa.js` | `09da5fc929809723c8589ce28008ccf87b476a027e2f69ba32540f2f2e994637` |

## Input reports

| Physical report | Format and purpose |
| --- | --- |
| 1 | 12-byte ordinary keyboard snapshot: report ID, modifiers, ten held HID usages |
| 2 | 9-byte pointer report; driver-mode left rotation uses signed horizontal pan at byte 3 |
| 3 | 12-byte consumer snapshot; little-endian usage at bytes 1–2, zero on release |
| 4 | System input; not currently relayed by the mapping app |
| 5 | 12-byte extra-key snapshot: `[5, 4, key set…]`, ten identifier bytes |
| 6 | Device notification, distinct from key actions |

The following report-5 identifiers were captured independently in verified driver mode. All-zero key sets release held keys; duplicate snapshots do not retrigger actions.

| Control | Extra identifier |
| --- | --- |
| M1–M5 | 32–36 (`20`–`24` hexadecimal) |
| AI | 247 (`f7`) |
| Left dial click | 96 (`60`) |
| Battery button | 65 (`41`) |

Example M1 press: `050420000000000000000000`; release: `050400000000000000000000`. The shared report ID does not make the controls identical.

Clockwise left rotation: `020000010000000000`; counterclockwise: `020000ff0000000000`. Both were captured three times in a verified driver-mode window. Consumer captures identify right-roller volume up/down (`00e9`/`00ea`), mute click (`00e2`), and media single/double/triple (`00cd`/`00b5`/`00b6`); the mode of those self-directed captures was not established.

The vendor product's static default table maps extra identifiers 251, 252, and 253 to ordinary Backspace (HID 42), B (HID 5), and Space (HID 44). The full-control app now forwards those defaults with held-key ownership and repeat. This association comes from static inspection and the reported right-space failure; live split-key verification is still pending.

## Evidence boundary

The application uses its own source and macOS frameworks. Vendor JavaScript/libraries were inspected statically and are not linked, executed, or distributed. The initial installer/evidence hashes are archived under `research/initial-handoff/`. Raw captures and device identifiers remain local. USB/receiver transport, undocumented writes, and other Razer models must not be inferred from this Bluetooth result.
