# Pro Type Ergo Bluetooth and input protocol

This is a concise reference for the protocol recovered during this project's hardware investigation. The [research history](research/INVESTIGATION.md) records provenance and individual tests. Codecs live in `Sources/ErgoCore`; encoding a command there performs no I/O.

## Custom Bluetooth zone frames (research lab)

The optional [Lighting Lab](LIGHTING_LAB.md) has a hardware-confirmed Bluetooth path for custom macro-column lighting, separate from the regular app's firmware-effect picker. Read regions with class `10` / ID `80`, arguments `0/1`; the tested keyboard reports `[5]` (Backlight). At profile 0 / region 5, save the original effect (`10/83`), select effect 8 (`10/03`, payload `[8,0,0,0]`), then send rectangular RGB frames (`10/04`, payload `[4,0,0,0,18]` plus 57 RGB bytes for one row of 19 zones). AllRegion 0 accepts the selector but rejects frame data with status 7. Do not infer that rejection or Razer's no-Studio flag means Bluetooth custom lighting is impossible.

The user confirmed only M1–M5 pulse while other keys are dark, over Bluetooth only and over USB. M1–M5 map to the shared first zone; this does not establish independent per-key colors or resolve the separate small dial indicator. The lab saves the exact peripheral/profile/region in its recovery record and verifies restoration at the same target before clearing it. Normal mapping sessions do not call this path. Live Bluetooth throughput was 20 acknowledged frames in a ten-second test, below the lab's four-frames/sec scheduling cap. See the lab documentation for USB's distinct class-15 format, interruption limits, and source provenance.

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

Build 19's low-six-bit targets 0–5 all returned status 7. Build 20 follows the LED-list method more literally: it reads the exact returned targets 64, 65, 194, 195, 196, and 197, queries their types using `06/81`, arguments `0/target`, then RGB using `06/84`, arguments `1/target`. These are bounded reads only; neither the old target-39 color write nor its on/off write is attempted during new discovery. The public codec names are now `readLEDList` and `readLEDType`, matching the source. High bits are kept opaque, not assigned a meaning or stripped using the different Chroma-region parser. All six literal IDs subsequently returned status 7 for both type and RGB reads.

The user confirmed native colors operate over Bluetooth without Razer software and return when mappings are disabled while Ergo Control remains open. Build 20 reproduces their loss without sending new indicator writes. The mapping session's firmware driver mode (3/0) is therefore a leading cause to investigate; exclusive capture also changes during that session, so this comparison alone does not isolate the two. Preserving normal mode is not an equivalent replacement: the earlier normal-mode captures did not expose the extra macro inputs needed by the application.

The USB implementation exposes dedicated knob controls that rzDevice30 does not implement: `getKnobConfigurationInformation` (class 3, ID 0x92, 50-byte template) and `getCurrentKnobMode` (class 3, ID 0x93, eight-byte template). USB current-mode data is `[ledClass, ledID, disabled, stage, modeID, red, green, blue]`. Their USB setters use IDs 0x12 and 0x13. These are static USB facts, not recovered Bluetooth equivalents. Only the bounded read-only adaptations described below have been tried; no Bluetooth knob setter has been recovered or sent. This may explain why a generic LED address is insufficient for the native mode indicator.

Read-only USB inspection subsequently succeeded on product `1532:02c4`, configuration interface 3. Both dedicated getters returned success (2). Before a native dial click, current stage/mode was 2/2, RGB `0,0,255`; afterward it was 3/3, RGB `255,255,0`. The eight-stage table contained four enabled green/red/blue/yellow stages. This correlates the dedicated getter with native physical mode switching. The configuration table was unchanged between reads. No knob or LED setter was sent.

A bounded normal-mode Bluetooth comparison used class 6, arguments 1/39: the original RGB getter 0x84 returned status 7, while USB-derived knob getter candidates 0x93 and 0x95 returned status 5. The 0x95 offset was an explicit unverified hypothesis based on the LED-state getter's USB-to-Bluetooth +2 offset. None is a supported Bluetooth knob API. Normal-mode RGB rejection also shows that driver mode alone does not explain failure of that getter. The native indicator still works when mappings are off. The observed Bluetooth HID descriptor has only a two-byte feature payload and one-byte keyboard LED output payload (plus report IDs), not a 90-byte USB configuration channel. These facts do not prove that another GATT command is impossible. See [USB_RESEARCH.md](USB_RESEARCH.md) for the tested reader and packet layout.

Static provenance (vendor sources remain local and ignored):

| Artifact in `analysis/vendor/708/mw/` | SHA-256 |
| --- | --- |
| `main.c8f8537456ab6ae7c847.js` | `7ffb823c6fb1586bcc19e44781b2be4076f44e6589d98797b52029f8c80c1a55` |
| `6737.5b007c860f4efa22ab87.js` | `4b1973cfa843afc214f8166ab14e5428ed9814f5a5c6b866cfa8e0ecfd939a86` |
| `rzDevice25.72e2cedb9d2be4eb79fd.js` | `647f673dfbc34f928cf99d8c73762d6d5258b6b3314161e6e76332905418a642` |
| `rzDevice30.a29e745b43244151d1fa.js` | `09da5fc929809723c8589ce28008ccf87b476a027e2f69ba32540f2f2e994637` |

## Input reports

| Physical report | Format and purpose |
| --- | --- |
| 1 | 12-byte ordinary keyboard snapshot: report ID, modifiers, ten held HID usages |
| 2 | 9 bytes: five button bits in byte 1, constant padding in byte 2, signed horizontal pan at byte 3, signed wheel at byte 4, signed little-endian 16-bit X/Y at bytes 5–8. Driver-mode left rotation uses pan; the product default maps vertical wheel to right-roller volume in 0.9.5. Only button/movement fields remain auxiliary. |
| 3 | 12-byte consumer snapshot; little-endian usage at bytes 1–2, zero on release |
| 4 | System input; not currently relayed by the mapping app |
| 5 | 12-byte extra-key snapshot: `[5, 4, key set…]`, ten identifier bytes |
| 6 | Vendor envelope: logical record 5 notifications; logical record 2 momentary media commands (added in 0.9.4; live confirmation pending) |

The following report-5 identifiers were captured independently in verified driver mode. All-zero key sets release held keys; duplicate snapshots do not retrigger actions.

| Control | Extra identifier |
| --- | --- |
| M1–M5 | 32–36 (`20`–`24` hexadecimal) |
| AI | 247 (`f7`) |
| Left dial click | 96 (`60`) |
| Battery button | 65 (`41`) |

Static product-table media identifiers (0.9.5; live validation pending): right roller click 82 (`52`), next/double 83 (`53`), previous/triple 84 (`54`), play-pause/single 85 (`55`). The same exact product table maps MouseInput ScrollUp to VolumeUp and ScrollDown to VolumeDown. These enter the existing canonical media controls rather than being exposed as duplicate mapping cards. Source artifact `main.c8f8537456ab6ae7c847.js`, SHA-256 already recorded above. Only numeric protocol/default associations are reimplemented.


Example M1 press: `050420000000000000000000`; release: `050400000000000000000000`. The shared report ID does not make the controls identical.

Clockwise left rotation: `020000010000000000`; counterclockwise: `020000ff0000000000`. Both were captured three times in a verified driver-mode window. Consumer captures identify right-roller volume up/down (`00e9`/`00ea`), mute click (`00e2`), and media single/double/triple (`00cd`/`00b5`/`00b6`); the mode of those self-directed captures was not established.

The vendor product's static default table maps extra identifiers 251, 252, and 253 to ordinary Backspace (HID 42), B (HID 5), and Space (HID 44). The full-control app now forwards those defaults with held-key ownership and repeat. This association comes from static inspection and the reported right-space failure; live split-key verification is still pending.

## Evidence boundary

The application uses its own source and macOS frameworks. Vendor JavaScript/libraries were inspected statically and are not linked, executed, or distributed. The initial installer/evidence hashes are archived under `research/initial-handoff/`. Raw captures and device identifiers remain local. USB/receiver transport, undocumented writes, and other Razer models must not be inferred from this Bluetooth result.

## Built-in keyboard backlight effects (0.2.7)

Recovered independently from the product’s protocol-3.0 device module and shared LightingHelper. These use **New Chroma IDs**, not the legacy LED-matrix IDs (legacy Breathing=3/Static=6 must not be used here).

| Operation | Class / ID (hex) | Arguments / payload |
| --- | --- | --- |
| Advertised effect IDs | `10 / 82` | `0/0`, no payload; returned bytes are effect IDs |
| Current effect | `10 / 83` | `1/0` (live profile / AllRegion), no payload |
| Apply effect | `10 / 03` | `1/0`; effect, flags, rate, color count, then RGB triples |

Implemented IDs: Off=0, Static=1, Breathing=2, Spectrum=3, Wave=4. Static uses flags/rate=0 and one color. Breathing uses flags=color count (0=random, 1=one, 2=two), rate=0. Wave uses flags 1=left or 2=right, rate=40, no colors. Off and Spectrum use zeros and no colors. The setter sends exactly 4+3×color-count bytes. Getter parsing checks the minimum header, bounded color count, and complete triples, accepting trailing padding. Unknown received effects can be displayed but cannot be sent by the writer. The picker offers the five independently documented built-in effects. Advertised IDs remain metadata; effects omitted from that list are marked and attempted only after explicit Apply, with validated payloads and readback. Unknown/streamed/custom IDs cannot be written.

Evidence: `rzDevice30` exports `newChroma_getChromaEffectIDList`, `getChromaEffect`, and `setChromaEffectCommon`; shared module 70953 defines effect flags/rate/color conversion, and shared hardware-event handling reads live profile 1 / region 0. Source hashes are listed above. The [official master guide](https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf), page 11, independently lists the same five built-in effects. This is whole-keyboard firmware lighting, not the physical dial mode LED and not a Chroma SDK integration.

Live Bluetooth read on 15 October 2026: effect-ID list `[0,1,2]`; current-effect payload `[3,0,0,0]` (Spectrum cycling). This establishes readable native Spectrum state but does not establish that Spectrum or Wave can be written over this Bluetooth path. Build 24 restricted the picker to Off/Static/Breathing. Build 25 also offers Spectrum/Wave after the user compared Synapse’s complete menu. Their omission from this reply is no longer treated as proof of rejection; they can be explicitly applied and verified, without an automatic probe. Subsequent live readbacks verified Spectrum `[3,0,0,0]` and Wave `[4,1,40,0]` / `[4,2,40,0]`; the user confirmed the combined visual/function test works. The pending mode-0 restoration journal from a prior disconnect was recovered and verified before these reads.

Build 25 separates user lighting availability from per-command transport activity. A single pending Read/Apply waits for both the current command and any dial-brightness chain to finish, then runs once on the same serialized connection. Mandatory restoration and disconnect cancel queued requests. Buttons remain enabled during unrelated periodic mode/battery reads, eliminating their recurring dimming without dropping clicks or overlapping commands.

### Wave speed investigation (15 October 2026)

The inspected product defaults expose only a Wave direction. Shared `LightingHelper.getEffectRate` hardcodes Wave to decimal 40 rather than reading a user speed setting; the official master guide page 23 likewise describes direction only. The protocol-3.0 setter has a rate byte and passes it through, but no supported range, timing unit, or alternative value has been verified on this keyboard.

As related evidence only, [OpenRazer’s extended-matrix Wave implementation](https://github.com/openrazer/openrazer/blob/master/driver/razerchromacommon.c) uses 0x28 (40) and notes faster rates on at least one other device. That uses another transport/command family (`0f/02`) and is not proof that Pro Type Ergo accepts a variable Wave rate over Bluetooth (`10/03`). No rate experiment, speed slider, host-side animation, or claim of adjustable speed was added. Current native Wave remains rate 40, with left/right direction control. This records an unverified possible capability, not an established firmware limitation.

## Consumer pulse release recovery (0.2.8)

Physical report 3 contains one little-endian consumer usage and trailing zero bytes. Original labeled single-media captures show play/pause `03cd00…` followed by a neutral `030000…` roughly 30–45 ms later. The old relay retained the last nonzero usage indefinitely until a distinct usage arrived. A missing neutral could therefore leave the synthesized key down and cause later identical usages to be dropped, with a volume/mute report finally releasing the old key.

The runtime now uses ConsumerKeyState. It retains state deduplication and immediate neutral/change releases, but caps only the three momentary gesture usages `00cd`, `00b5`, `00b6` at 300 ms. Expiry releases and clears the usage, including when expiry is first observed on the next report rather than by its run-loop timer. A late neutral does not release twice. Invalid reports do not mutate held state. Right-dial volume/mute, screen brightness, and genuine seek usages `00b3`/`00b4` are not subject to this timeout. Stopping capture cancels the timer and resets the decoder; the engine releases outstanding output.

This behavior is regression-tested with missing neutral reports and through an output-suppressed ActionEngine. It does not establish that a release was missing in the user’s particular incident; no fresh failing hardware trace was collected. The helper and protocol transport are unchanged.

## Standard Caps Lock indicator (0.8.3)

The observed BLE HID report descriptor exposes output report ID 1 with three one-bit variable LED usages (page 8, usages 1–3) followed by five padding bits. Caps Lock is usage 2. This is separate from region-5 RGB lighting and the unresolved small command-dial color indicator. The implementation selects only the standard Caps output element and calls IOHIDDeviceSetValue with 0/1 on the already-open keyboard, leaving other LED elements untouched. Descriptor evidence is read-only; hardware LED behavior still needs confirmation.

## Macro-zone updates and read-only power queries (0.8.6)

The recovered type-4 frame supports bounded rows and columns. A pulse-only update uses class 16 / command 4, profile 0, reported region 5, payload `[4,0,0,0,0,R,G,B]`: row 0 only, column 0 only. The existing 19-zone row remains `[4,0,0,0,18,...57 RGB bytes]`. Short updates are eligible only when all other acknowledged pixel values are unchanged; otherwise the full frame initializes/repaints the row. A short-update rejection falls back to the full frame and disables further short attempts for that renderer. Partial frames retain complete ATT/keyboard acknowledgements. An isolated three-second Bluetooth pulse check on this keyboard accepted one full-row frame (five writes) followed by seven column-0 frames (two writes each). The previous effect was restored and verified, with no remaining recovery journal. Physical appearance and battery runtime were not measured in that check.

Read-only power inspection uses the recovered class 5 getters `84` (sleep timer), `85` (charging), `87` (automatic sleep), `8a` (idle dimming), profile 0 / battery 1, no payload. Unknown/rejected results are reported individually. The read-only normal-mode hardware test returned `84: [132,3]`, `85: [0]`, `87: [1]`, `8a: [1,44,1,20]`. Little-endian time values are seconds (900 and 300), independently confirmed by model UI minute conversions. Driver-mode dimming behavior remains unverified; no power setters or sleep toggles are added.

## Native power writes and automatic lighting-off (0.9.0)

The fixed recovered setters use class 5: dimming `0a` with argument6/profile 0, argument7/battery 1 and exactly four payload bytes `[enabled, secondsLow, secondsHigh, dimPercentage]`; sleep time `04` uses arguments 0/0 and two little-endian seconds bytes; automatic sleep `07` uses arguments 0/1 and one enable byte. The vendor allocator reserves five dim bytes, but its explicit packet-size argument truncates the transmitted payload to four; the independent encoder implements that four-byte wire format. Dimming is constrained to 60–900 seconds and sleep to 60–3600 seconds. UI minute choices use the existing native bounds. Getters validate response sizes/booleans/percentage before displaying values. Writes are followed by independent getter readback.

The percentage slider uses the previously verified class 16 / command 5, profile 1 / all regions (0), and checks class 16 / `85`, profile 1 / region 5. Automatic display/idle blackout uses those same brightness commands, with a separate exact-target raw-brightness recovery journal written before setting zero. Native dim/sleep user choices are persistent and are not put into the temporary mode/lighting recovery journal.

An isolated `--keyboard-power-test` saves a durable exact-target native-settings backup, changes brightness/dim/sleep, verifies getters, exercises blackout/recovery, and restores/verifies every original native value. Re-running an interrupted test restores its existing backup instead of starting another experiment. It requires the GUI quit and both ordinary recovery journals clear; the GUI blocks native power edits while that test backup is pending. The hardware check passed: all requested native values matched getter readback, blackout/recovery was verified, then all original values matched a separate final read. Its test backup and brightness recovery journal were removed only after verification. Subsequent live getters from the settings UI also succeeded with full mappings active. Real inactivity/display notification timing is separate from this verified brightness write/recovery path.


## Driver-mode media envelope (0.9.4)

The original Protocol 30 hardware-event parser declares logical `MEDIA_KEYS = 2`, `RAZER_KEYS = 4` and `NOTIFICATION_EVENTS = 5`. Its media parser combines the two bytes following the logical record into a consumer usage. The app's blanket physical-report-6 notification branch therefore missed a possible driver-mode media path. The new decoder accepts only twelve bytes beginning `[6, 2]`, reads the little-endian usage at bytes 2–3 and requires bytes 4–11 to be zero. Zero-usage records do not generate a command. Each nonzero driver record generates a press/release pair; native report 3 retains its existing key lifetime and timeout logic. Matching usages across the two forms within 80 ms are correlated, without suppressing repeated records from the same source. No vendor implementation is copied or shipped.

This is based on static protocol evidence and the user's repeated media tests producing no native report-3 entries while other driver-mode controls worked. The physical envelope and momentary behavior still require live confirmation; notification record 5 is not reinterpreted as input. Local evidence artifact: `rzHardwareEventsProtocol30Parser.474e82350be705232b6f.js`; SHA-256 `011b29b41e3279a91f21d44013870c50600569a2056c2632afea022858eac59b`.
