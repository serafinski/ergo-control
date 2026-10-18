# Music app fallback

Under **Keyboard → Buttons → Music app when nothing can resume**, choose **macOS default**, **Apple Music**, or **Spotify**. The choice saves immediately and applies to PT Ergo's Play/Pause button and mappings using the Play/Pause action. It does not change global file associations or other keyboards.

With macOS default, playback keeps the original native media-key behavior. With an explicit app selected:

- A recognised current system player keeps normal Play/Pause, including a paused session.
- With no identified system player and the selected app closed, the first press opens it by exact bundle identifier, without choosing a track or sending another Play command.
- With no identified player and the selected app already open, the next press uses that app's own accessible playback control. It does not send a global media key, which can otherwise launch Apple Music before Spotify publishes a media session.
- A missing, disabled, ambiguous or unconfirmed playback control produces a notice without retrying as a global toggle. A track may need to be chosen in the player first. Next/Previous, volume and mute keep their existing routes.

The experimental focus-first option remains separate and off by default. If enabled, a recognised focused/remembered accessible player still owns the command. Only its final system fallback uses the music-app choice. A focus change, mapping stop or preference change cancels an unresolved request. An uncertain AX press never triggers a second global Play command.

## Compatibility and privacy

Apple's public [Now Playing information center](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) publishes the calling app's media session; it does not provide this app with the system-wide target. Explicit music-app choices use a guarded, read-only MediaRemote lookup (`MRNowPlayingRequest.localNowPlayingPlayerPath`, client and process identifier). It is a private macOS interface and may change or fail to identify a running player. Selector signatures are checked before invocation, and replies are reduced to available/none/unknown. No song, artist, artwork, URL or playlist metadata is requested from MediaRemote, logged or saved.

The lookup runs off the input/UI thread on an applicable Play/Pause press, with one in-flight query and a 750 ms response deadline. Unknown results use the running preferred app's playback control when possible; otherwise native playback remains available. Selecting macOS default with focus-first routing off avoids this lookup entirely.

The preferred app's transport uses the existing Accessibility permission and Apple's [AX press action](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction). A bounded snapshot recognises whole English/Polish button and slider labels, requires supporting transport controls, and rejects ambiguous players, incomplete reads and disabled controls. This shares discovery with the focus-first router but targets only the selected app's process and does not activate another app or type a shortcut. Button/slider labels are read transiently to locate the transport; page content, track titles and labels are not logged or saved. Discovery has a one-second deadline and a 1.2-second response timeout; late requests cannot press after expiry. No follow-up global command is sent after an uncertain action.

App launch uses [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)), without AppleScript, a new Automation permission, a network API or background polling. Launches and transport requests are coalesced while pending.

## Regression and verification

The initial fallback repeatedly opened Spotify and swallowed Play/Pause. A running-process bypass restored playback once Spotify owned a media session, but the user found that a cold launch followed by a second press still opened Apple Music. The second press was a global media key before Spotify had published a session. The current implementation queries the target first and uses the preferred app's own transport when no target is identified, including an unknown result with the preferred app already running.

All **350 tests pass** (175 Core, 104 Control, 71 Device). Regressions cover cold launch followed by app-specific playback without a global key, no-target and unknown-target open players, preservation of a recognised system player while Spotify is open, cancellation, uncertain presses without a second command, pending-request coalescing, disabled or ambiguous controls, multiple player windows, incomplete reads, and the existing native media paths. Tests inject callbacks and inert AX identities; they do not start playback or read a live UI. Native UI inspection confirmed the installed Polish Spotify app exposes a transport group containing Previous, Play, Next and a timeline. This confirms control availability, not the corrected app's live press behavior.

For a physical check, close Apple Music and Spotify and any browser media sessions, then press PT Ergo's Play/Pause button: Spotify should open. Press again: its existing track should start through its own playback control, without opening Apple Music. Press again to pause. Check an existing browser player and macOS default separately. These corrected-build hardware interactions remain a user check.
