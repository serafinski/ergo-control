# Read-only dial investigation

The small mode LED beneath the left dial works natively over Bluetooth with mappings off. It stops showing native colors when mappings are active. Generic Bluetooth LED commands have not reproduced it. This tool investigates the separate dial interface exposed over USB; it does **not** add USB mappings or host color control.

## Scope

`ErgoUSBInspector` selects only USB vendor `1532`, product `02c4`, interface 3, with a feature report of at least 90 bytes. It enumerates without opening every input collection, then opens the configuration collection without exclusive access. It has no input callbacks, device-mode setters, firmware writes, macro writes, or lighting setters. It refuses inspection while the app has an outstanding Bluetooth restoration journal. Do not run it alongside Razer configuration traffic.

Build and enumerate:

```sh
swift build --product ErgoUSBInspector
swift run --skip-build ErgoUSBInspector --list
```

With mappings off and the USB data interface available:

```sh
swift run --skip-build ErgoUSBInspector --read
```

The tested Apple USB-C charging cable carried data. Selecting Bluetooth or unplugging the cable can remove the USB endpoint; the tool then reports zero eligible interfaces. Output contains only status, dial stages, mode IDs, and colors, never keyboard input or device serials.

## Recovered USB requests

The source is Razer's statically inspected `rzDevice25.72e2cedb9d2be4eb79fd.js`; its hash is recorded in [PROTOCOL.md](PROTOCOL.md). Downloaded vendor code remains local and ignored. The implementation uses its own Swift codec and Apple frameworks.

Each request is 90 bytes: status at 0, transaction 1–31 at 1, payload length at 5, command class at 6, ID at 7, arguments at 8, XOR of bytes 2–87 at 88, and reserved byte 89. Getter arguments begin with LED class 1 / ID 39; remaining template bytes are zero. Feature report ID is 0. The tool validates reply size, checksum, transaction, command, payload length, and returned address before interpreting it. Status 1/3 replies wait within a bounded deadline; only status 2 is interpreted as success.

| Getter | Class / ID | Payload template | Hardware evidence |
| --- | --- | --- | --- |
| Current knob mode | `03 / 93` | 8 bytes | Success; follows native dial click |
| Knob configuration | `03 / 92` | 50 bytes | Success; unchanged between reads |
| Indicator state | `03 / 80` | 3 bytes | Static template; not yet tested |
| Indicator RGB | `03 / 81` | 5 bytes | Static template; not yet tested |

Current mode is `[class, ID, disabled, stage, modeID, red, green, blue]`. Configuration is `[class, ID]` followed by eight six-byte entries `[disabled, stage, modeID, red, green, blue]`. The observed native click moved stage/mode 2/2, blue, to 3/3, yellow. The enabled stages had green, red, blue, and yellow colors.

## Bluetooth comparison

The signed development app also provides `--native-dial-read` as a research command. Quit the GUI, disable mappings, ensure restoration has completed, and use the Bluetooth connection before running it. It reads the original RGB baseline and two explicitly unverified USB-derived getter candidates at fixed class 6 / target 1/39. It cannot enter driver mode or set colors. The baseline returned status 7 and both candidates returned status 5 in the hardware test. These requests must not be presented as supported Bluetooth commands.

The Bluetooth HID descriptor exposes short keyboard feature/lock-LED reports rather than this 90-byte USB channel. Recovering another Bluetooth dial-control path remains open work. A successful USB read alone does not establish a Bluetooth setter or justify modifying onboard stages.
