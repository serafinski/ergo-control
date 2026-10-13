# Razer Pro Type Ergo: local Codex handoff

## Project goal

Build a standalone macOS configuration application that replaces Synapse for the user's Razer Pro Type Ergo (RZ03-0544), rather than just a dial workaround. The user uses a MacBook Pro with Apple Silicon (M4 Pro) and wants daily operation over Bluetooth. Confirm the installed macOS version locally. RGB is optional and lower priority.

The application should support custom mappings for every accessible keyboard control: left Command Dial rotation/click/modes; right media roller rotation/click; M1–M5 macro keys; AI Prompt Master button; media button; other extra keys; battery status if available; general key remaps; and app-specific profiles. Actions should include shortcuts, macros, app launching, scripts, and optional AI workflows. The AI button must be freely assignable, not tied to Razer's AI feature. Provide a settings UI, saved profiles, and a lightweight background component. Razer software should not be required at runtime.

## User constraints

- Bluetooth is the required daily connection. Do not substitute a wired-only implementation.
- Preserve the existing Logitech MX Master 3 configuration and input handling. USB Overdrive took over that mouse and changed its pointer feel during testing. Avoid generic all-device interception.
- Prefer Python for diagnostics/prototypes where practical. A native Swift/macOS application is a reasonable final implementation choice, subject to project judgment.
- Prioritize recovering controls before polishing the UI. Record unsupported controls honestly.
- Do not install/run the Razer installer, change installed Razer files, or change system-wide drivers as part of static analysis. Test new input access initially without writing to the keyboard. Keep runtime changes reversible and scoped to this keyboard.

## What has been tested

Karabiner-Elements was installed and its setup completed. EventViewer eventually identified PT Ergo (Razer), vendor ID 1678 (0x068e), product ID 707 (0x02c3). USB Overdrive independently reported the same identity and explicitly showed Bluetooth LE as the transport.

Recognized inputs in Karabiner's device-specific raw event capture:

| Physical action | Observed event |
| --- | --- |
| Left dial rotation in zoom mode | left_command + keypad_plus; left_command + keypad_hyphen |
| Right roller rotation | consumer_key_code volume_increment / volume_decrement |
| Right roller click | consumer_key_code mute |
| Media button single press | consumer_key_code play_or_pause |
| Media button double press | consumer_key_code scan_next_track |
| Media button triple press | consumer_key_code scan_previous_track |

The user reported no events for the left dial click, M1–M5, AI button, or battery button, including a subsequent Raw Input Records test. This establishes the result of those tools in this tested configuration; it does NOT prove that the keyboard sends no vendor-specific reports or Bluetooth notifications. Raw Input Records must not be assumed to capture every possible BLE/GATT path.

Razer's manual documents left dial clicking as next-mode selection (Shift + click selects the previous mode), and a battery button that displays status on the keyboard. These may be handled internally and need not be ordinary keyboard events. Whether custom software can independently observe/override them remains unknown.

USB Overdrive detected the keyboard but full custom-control support was not established. The user declined wired testing and reported the mouse regression. BTT was researched but has NOT been tested. Do not claim it failed.

## Razer processes and current machine state

The user disabled the two Razer driver extensions and restarted. Remaining services were identified from Terminal:

- User service com.razer.gms: executable under ~/Library/Razer/GameManagerService3/RazerGameManagerService.app/Contents/MacOS/.
- User service com.razer.SynapseHelper (idle at the time).
- System service com.razer.elevationservice.daemon: /Library/Application Support/Razer/Razer Elevation Service.app/Contents/MacOS/Razer Elevation Service.
- System service com.razer.UninstallerWatcher (idle at the time).

The user was instructed to temporarily bootout SynapseHelper, gms, and elevationservice. Verify current state locally; this handoff does not prove every command succeeded or prevent services returning after a restart. USB Overdrive was subsequently instructed to be disabled to release the mouse; completion is not verified. Keep Razer and alternative input tools from competing during runtime tests.

## Analysis already performed

The official Mac installer was downloaded and statically extracted in a separate Linux workspace. It was NOT executed. XAR entries, gzip/CPIO payloads, and Electron ASAR contents were extracted. Initial inspection covered readable JavaScript and native strings/symbols; no native assembly was fully decompiled and no hardware experiment was conducted by the analyzing agent.

Official download page: https://www.razer.com/synapse-4-mac

Official redirect: https://rzr.to/synapse-4-mac-download

Resolved package URL: https://dl.razerzone.com/drivers/Synapse4/mac/RazerSynapseInstaller.pkg

Analyzed package:

- Size: 176220841 bytes.
- SHA-256: 51f6f67e88698c7852196f2e5840a4e0c0284df17e935f60bb7d6a24728085cd
- Server Last-Modified: 2026-04-14.
- EngineInstall.pkg metadata: version 4.4.25.
- Includes EngineInstall.pkg, SynapseInstall.pkg, and ChromaInstall.pkg.

This installer may differ from the user's updated installed application. Device-specific modules/resources may be downloaded after installation. Inspect relevant installed components if the base package is insufficient. Do not assume the installer contains all current Ergo-specific code.

## Included evidence files

Paths are relative to the extracted payload, preserved inside evidence/payload/:

- Razer/RazerAppEngine/Razer.app/Contents/Resources/app.asar (entire original Electron archive, for independent extraction).
- Razer/RazerAppEngine/Razer.app/Contents/CommonDylib/libmapping_engine.dylib
- Razer/RazerAppEngine/Razer.app/Contents/CommonDylib/libSysUtilsNative.dylib
- Razer/RazerAppEngine/Razer.app/Contents/CommonDylib/libsimple_service.dylib
- Applications/Razer Synapse.app/Contents/Library/SystemExtensions/ (both driver bundles, regular files; symlinks and original permissions are not reconstructed).
- Selected app Info.plist files.

evidence/electron/ contains the already-extracted Electron application JavaScript, excluding its node_modules and non-code image assets. It is analysis material, not a runnable reconstructed application. The entire app.asar is included if more context/dependencies are needed.

evidence/package-metadata/ contains Distribution and the three PackageInfo files. MANIFEST.json records SHA-256 and sizes of packaged evidence files.

## Confirmed code locations and clues

Readable JavaScript paths under evidence/electron/:

- main.js: IPC handler rzBleDeviceAction, routes allowed actions to the BLE action map; references libmapping_engine.dylib, libSysUtilsNative.dylib, libsimple_service.dylib.
- preload.js: doBleDeviceAction invokes rzBleDeviceAction.
- modules/noble/index.js: BLE orchestration; inspect this first with strategies and endpoint detection.
- modules/noble/constants.js: shared BLE protocol constants and vendor IDs [5426, 1678].
- modules/noble/cross-platform/mac/common.js: macOS-specific BLE helper code.
- modules/noble/endpoint-detect/: endpoint detection.
- modules/noble/strategy/: standard, protocol30, protocol30Layla, protocol40, protocolAudiowise.
- modules/noble/strategy/protocol40.js: service/characteristic discovery, writes and notifications; write response handling compares byte 1 with a transaction ID; notify handler forwards notifications whose byte 1 equals 2 as rz-ble-notify-<id>.
- modules/mapping_engine/mac/index.js and modules/mapping_engine/index.js: JS/native mapping bridge.
- UsbRzDeviceAction.js and Protocol/: another transport/protocol implementation worth cross-referencing.

CRITICAL: The protocol40 behavior above is generic code that was read. It has NOT been identified as the Pro Type Ergo's protocol. Do not send inferred commands from this finding alone.

Protocol30 UUID constants found in the shared module (also NOT established as the Ergo's service):

- Service: 52401523f97c7f900e7f6c6f4e36db1c
- Write: 52401524f97c7f900e7f6c6f4e36db1c
- Read/notify: 52401525f97c7f900e7f6c6f4e36db1c

Native strings/symbols in libmapping_engine.dylib include:

- mapping_engine::HardwareEventThread::OnInputReport
- mapping_engine::HardwareEventEndpointMac
- mapping_engine::KeyboardRawInputHandlerMac and ValueChangedCallback
- ProbeFilterDriverEndpoint / ProbeHidEndpoints
- mapping_engine::kDial
- mapping_engine::MappingDataControlPod::SetDial
- IOHIDManagerRegisterInputValueCallback
- Bluetooth / Bluetooth LE
- RazerGenericHIDDriverKit / RazerVirtualHIDDevice

These identify candidate analysis targets, not proven call paths for the Ergo. libSysUtilsNative.dylib imports CoreBluetooth and references CBCentralManager, askForBlueToothAccess, and bluetoothAuthStatus; those could relate only to permission handling rather than the device protocol.

Targeted initial string searches did not identify a direct Pro Type Ergo / RZ03-0544 reference. That is a limited negative result, not evidence that support is absent. IDs may be numeric, encoded, in downloaded device definitions, or in other files.

## Next investigation

1. Read this handoff and verify the evidence manifest. Confirm local macOS/app versions and present process/driver state. Create a project with Git checkpoints.
2. Trace the Electron BLE IPC handlers and device/endpoint configuration. Find the configuration for the Ergo's Bluetooth identity. Determine whether its support lives in an updated/downloaded device module or the installed app.
3. Distinguish normal HID input, vendor HID reports, CoreBluetooth/GATT notifications, and Razer DriverKit input paths. Determine which is actually used for M1–M5, AI button, dial click, and dial mode selection.
4. Use native disassembly/decompilation where needed. REA (https://github.com/morluto/rea) is optional orchestration for Ghidra/Hopper/IDA, not a replacement for those engines. JavaScript can be read without REA. No REA/decompiler was installed during the earlier analysis.
5. Produce an evidence-backed per-control matrix (transport, event/report bytes, activation requirements, semantics, confidence, unresolved questions). Do not invent UUIDs, packet layouts, or function behavior from names.
6. Build a narrowly scoped, read-only Bluetooth/HID input probe, record labeled actions, then implement reversible keyboard-specific initialization only after understanding commands. Never touch the MX Master.
7. First functional milestone: identify clockwise/counterclockwise actions, clicks, M1–M5, and the AI button independently, with Synapse stopped. If a control cannot be exposed, report the specific limitation and evidence.
8. Then implement configurable actions, per-app profiles, persistence, a settings UI and background component. Swift is suitable for the final native app; Python is appropriate for diagnostics when supported.

## Sources used during earlier research

- Razer keyboard manual: https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf
- REA: https://github.com/morluto/rea
- REA Apple application analysis: https://github.com/morluto/rea/blob/main/docs/apple-application-analysis.md
- Karabiner raw capture: https://karabiner-elements.pqrs.org/docs/manual/operation/eventviewer/
- USB Overdrive device configuration: https://www.usboverdrive.com/step-by-step/

Proceed with analysis and implementation of the Bluetooth-first keyboard configuration app. Preserve the distinction between observed behavior, static code facts, and hypotheses throughout.
