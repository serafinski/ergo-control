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

Normal mode was `[0, 0]`; driver mode is `[3, 0]`. Driver mode exposes the extra controls and independent left-dial turns. Runtime writes preserve the original mode durably before changing it, verify driver mode by read-back, and restore/read-verify the saved mode afterward. No firmware, onboard macro, or general hardware key-mapping writes are implemented. The app now implements the brightness and transient dial-light writes described below.

## Keyboard brightness and command-dial indicator

The product module defines `backlightStep: 5`, a green Keyboard brightness dial mode, and `obmSupportFeature.knobId: 39`. The shared command-dial switch task routes its selected RGB color to the `knobLighting` task. That task uses LED class 1 and the product-specific knob ID (39), writes RGB, enables the light, then disables it after three seconds. The default 36 in shared code belongs to other devices and is not used here. These are targeted live control commands, not onboard macro/matrix writes.

| Operation | Class / ID | Arguments / payload | Evidence |
| --- | --- | --- | --- |
| Read lighting regions | `10 / 80` | Arguments 6/7 = `0/1`; region = each returned byte & 63 | Static recovery; hardware check pending |
| Read keyboard brightness | `10 / 85` | Profile 1; first discovered region; one raw byte returned | Static recovery; hardware check pending |
| Set keyboard brightness | `10 / 05` | Profile 1 / AllRegion 0; one byte `floor(percent × 255 / 100)` | Static recovery; hardware check pending |
| Read dial state | `06 / 82` | LED class 1 / LED ID 39 | Live accepted, initial state 0 |
| Set dial state | `06 / 02` | LED class 1 / LED ID 39; `[0]` or `[1]` | Static recovery; hardware check pending |
| Read dial RGB | `06 / 84` | LED class 1 / LED ID 39 | Live rejected with status 7 |
| Set dial RGB | `06 / 04` | LED class 1 / LED ID 39; `[red, green, blue]` | Static recovery; visual confirmation pending |

The generic RGB command template advertises four payload bytes, but the inspected `Zo` implementation actually allocates three via `Po[0]`. Its attempted fourth-byte assignment is outside that buffer, and `_createDataSend` encodes the actual buffer length. The app therefore matches the vendor’s three-byte wire encoder; it does not infer a fourth brightness byte from the template. Color write acknowledgement alone is not a visual RGB verification.

The first live 0.2.6 session established that this keyboard supports dial-state reads but rejects RGB reads. The initial implementation disconnected on every command failure, stopping otherwise working mappings; normal mode was restored and verified. Fully assembled negative acknowledgements now leave the channel connected. Only incomplete/timed-out/malformed exchanges force reconnection. On status 7 with a previously off light, the app can durably preserve the off state and attempt the vendor RGB setter, then restore off after three seconds. An already lit light is left unchanged if its color cannot be preserved. No unrelated LED IDs or speculative commands are tried.

Brightness uses the first discovered region for read-back, matching the vendor’s default getter, and profile 1 / AllRegion 0 for writing, matching its live brightness task. Turns are applied in order in five-percent steps, so at 100%, clockwise then counterclockwise ends at 95%. Future turns stay queued during a write/read-back exchange. Indicator and brightness chains share the existing one-command transport; mapping restoration has priority and cancels new lighting work. Normal input mode is restored before optional indicator recovery. Brightness is intentionally retained as a user setting.

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
