# Keyboard battery life investigation

## Findings and changes (0.8.6)

The aim is to reduce keyboard radio/LED work while keeping Codex lights active when the user is away. The app does not automatically disable, pause or lower these signals.

A read-only sample of the running 0.8.5 session covered 218.4 seconds and contained 43 completed device-mode reads and 37 full lighting frames. The five-second local lease renewal repeatedly reset its countdown into a value used to trigger a mode read. The revised checker uses monotonic elapsed time since the last successful verification, at 30-second intervals. Startup still verifies immediately, errors still restore the saved mode, and the local lease/input watchdog durations are unchanged. This targets roughly six times fewer background mode reads under the sampled conditions, not six times the battery life.

Working pulses previously resent all 19 zones even when only M1–M5 changed. After an initial full frame, the optimized update uses the recovered column-0 range: 8 payload bytes instead of 62. Including the eight-byte command header, outbound protocol bytes fall from 70 to 16 (about 77%); acknowledged writes fall from five to two (60%). This does not include Bluetooth framing or response traffic, and is not a measurement of radio energy. Full replies and every write acknowledgement are still required. The optimization falls back to full frames if rejected; no unacknowledged streaming is introduced. Wave geometry and the 2.8-second breathing cycle remain unchanged. A controller that sees a changed background sends a full repaint first.

The optional **Keep other keys dark during status lights** setting replaces the RGB 16 white background across the other keys with black. It applies behind status waves as well. The setting defaults off to preserve existing appearance; users can enable it under Codex → Status lights. Whole-keyboard solid signals remain whole-keyboard solid. Global brightness is unchanged, and the normal backlight effect returns through the existing snapshot/readback process. Turning fewer LEDs on should reduce LED consumption, but the actual energy saving depends on firmware, color and brightness.

Static status lights now stop the otherwise unnecessary 10 Hz lighting-pump timer; animations and pending restoration retain it. This reduces host wakeups and does not change the visible signal.

Battery reads remain limited to once per five minutes unless manually requested. The five-second scheduler checks run locally; they are not five-second battery requests. The helper's IPC heartbeats are also local and do not themselves send Bluetooth commands. Reducing those safety watchdogs is not an appropriate battery optimization.

## Native power features

[Razer's Pro Type Ergo manual](https://dl.razerzone.com/master-guides/RazerSynapse4/PROTYPEERGO-00000708-en.pdf), pages 22 and 24, describes display-off/idle lighting control, automatic dimming, and an inactivity sleep timer. Page 11 says holding the battery button for three seconds toggles a deeper power-saving mode that turns lighting off, reduces polling and pauses Synapse connectivity. That mode conflicts with the requested continuous Codex lighting and may interrupt this app's configuration channel. It is not automatically enabled here.

The locally inspected model middleware contains Bluetooth getters for sleep time, charging state, automatic sleep and dimming, plus corresponding setters. This establishes protocol candidates, not support on this keyboard over Bluetooth or in driver mode. No speculative setter is sent. A fixed read-only diagnostic is available:

```sh
'/Applications/Ergo Control.app/Contents/MacOS/ErgoControl' --keyboard-power-read
```

Quit Ergo Control and finish mode/lighting restoration first. The diagnostic refuses a running GUI or pending mode journal, does not seize input, reads four fixed battery-1 queries on the exact paired keyboard and prints raw returned values/errors. No power mode, brightness, timer or persistent firmware setting is changed. Unsupported getters are reported rather than retried at other guessed addresses. Raw timer units must be confirmed before adding controls.

## How to assess the result

Short tests can verify accepted frame sizes, mode-read intervals and appearance. They cannot establish battery-life hours. Keep brightness, wireless connection and normal effect consistent across longer charged/unplugged sessions, note whether Codex pulses/waves were active, and compare battery loss over several hours. Battery percentage is a coarse firmware estimate and may move after charging/reconnecting; do not extrapolate a few minutes or a one-percent change into runtime.

For a larger saving while retaining lights, lower the physical/global backlight brightness using F11 or the brightness dial, and use the optional black status background. This is an optical output tradeoff; it does not require breaking mapping functionality. Native automatic dimming may be a future option once its support and interaction with host frames are validated.

## Live checks on this keyboard

The 0.8.6 read-only Bluetooth diagnostic succeeded: sleep timer `[132,3]` decodes to 900 seconds / 15 minutes; automatic sleep returned `[1]`; idle dimming `[1,44,1,20]` means enabled, 300 seconds / five minutes, 20%. Timer units are confirmed by the locally inspected model UI dividing getter values by 60 and multiplying minute selections by 60 for setters. Charging returned raw `[0]`; no unverified charge-state label is inferred. Nothing was written. Existing native dimming is therefore already configured; actual behavior during host-driven custom frames has not been measured.

The installed app activated full mappings. The first periodic mode read followed initial verification by 30.89 seconds, consistent with the new schedule. The user's pulse preference was off and was preserved. A subsequent isolated three-second macro-pulse check initialized one full frame (five writes), then sent seven macro-only updates (two writes each). All eight received successful keyboard acknowledgements. The previous effect was restored and verified; neither recovery journal remained afterward. This confirms format acceptance and reduced outbound traffic, rather than physical appearance or runtime hours. Dark background remains opt-in. No actual runtime gain in hours is claimed; longer consistent sessions are needed. The helper binary and Codex hooks remain unchanged.

The user's Synapse screenshots independently show dimming enabled at five minutes and wireless sleep enabled at 15 minutes. They also show brightness at 5% and both display-off / idle lighting-off checkboxes unchecked. The app did not change these settings. The reported 5% is the native UI value, not a new raw brightness measurement by this diagnostic.
