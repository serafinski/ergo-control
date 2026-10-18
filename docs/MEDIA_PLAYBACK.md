# Music app fallback

Choose **Keyboard → Buttons → Music app fallback → macOS default / Apple Music / Spotify**. The choice saves immediately and applies to PT Ergo's Play/Pause button and mappings using the Play/Pause action. It does not change global file associations or other keyboards.

With **macOS default** and the experimental focus option off, playback keeps the original native media-key behavior.

With **Apple Music or Spotify** explicitly selected, Play/Pause follows these rules:

1. A recognised player in the focused window owns the command. YouTube in the active Vivaldi tab takes priority over an open Spotify. This check does not remember older windows by default.
2. Otherwise, the selected app opens if closed. Opening does not choose a track or send a second Play command.
3. If the selected app is already open, its own native Play/Pause menu action controls its loaded track.

Explicit app selection uses this focused-window/preferred-app policy, rather than macOS's remembered background media target. Choose macOS default if you want macOS to choose between background sessions. The former private MediaRemote target reader was removed: stale identities caused both unwanted Apple Music launches and missed browser handoffs.

Missing, disabled, ambiguous or unconfirmed controls show a notice without retrying as a global toggle. A track may need to be chosen in the selected player first. Next/Previous, volume and mute keep their existing routes. Media notices are separate from mapping/reconnect failures.

The experimental focus-first option remains separate and off by default. It additionally remembers the last accessible media window and applies focused/remembered routing to Next/Previous. Stopping mappings, changing preferences, quitting or a focus change cancels stale pending actions.

## Accessibility and compatibility

The focused player uses the existing Accessibility permission, bounded transport discovery and Apple's [AX press action](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction). The currently focused accessible control/region and up to four nearby ancestors are checked first (160 elements and 150 ms per local scan), using the same generic transport discovery with no application, website or region-name allowlist. If no player is found there, the current window is scanned. Whole English/Polish transport labels are recognised, including YouTube's expanded shortcut suffix (“Odtwórz skrót klawiszowy k”). A small group must include a unique Play/Pause control plus supporting transport controls. Playlist/track Play buttons alone do not qualify. Individual attributes are read because Chromium elements can decline batched requests. Discovery is bounded to 2,500 elements, depth 40 and 1.5 seconds; incomplete or ambiguous player reads do not act on another player.

The preferred app's native menu lookup is bounded separately to 400 elements, depth 12 and one second, with a 1.2-second response timeout. It requires one enabled whole Play/Pause menu-title match and a supported Press or Pick action. No follow-up global command is sent after an uncertain action. UI labels are transient and not logged or saved. There is no private media API, AppleScript, new Automation permission, network API or background media polling.

App launch uses [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) and the exact bundle identifier. Launch/playback requests are coalesced while pending. **Try Play / pause in 3 seconds** uses the same engine action as the keyboard, allowing you to focus the player before it runs. Stop, preference changes and a newer test cancel an older scheduled test.

## Verification

All **351 tests pass** (179 Core, 101 Control, 71 Device). Regressions cover deterministic launch/control without a global Play, repeated cold launches, missing apps, cancellation, rapid presses, uncertain actions without a second command, foreground browser dispatch, native defaults/navigation, experimental mode, exact English/Polish menu names, duplicate/disabled actions, and YouTube shortcut labels. Tests inject callbacks and menu descriptions without starting playback or reading a live UI. Tests for the removed private reader were removed with it.

The prior native-menu build passed open → play → pause through the app's test control, but the user's broader close-everything/relaunch test exposed a stale system-target branch. The current code removes that branch entirely. Final installed-build live checks are recorded below.

Final installed-build check: after closing Spotify and Apple Music, the shared engine action opened Spotify and its direct menu route played and paused the loaded track. With Spotify left paused, a temporary browser video was played and paused through the general focused-window route; the app log confirmed `focused window` for both actions. The video tab was then closed and Spotify quit. Running the same action from a normal browser page opened Spotify again, while Apple Music remained closed. This covers the previously failing post-browser cold-launch flow. The three-second test control exercised the same action as the physical button with the intended app in focus. Spotify was left open without starting playback; the temporary tab was closed. Other native players, websites and unsupported locales are not claimed as individually validated.
