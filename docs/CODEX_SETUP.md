# Codex chat keys and status

Ergo Control 0.3.0 adds an optional Codex connection using documented local lifecycle hooks and `codex://threads/<thread-id>` links. It does not emulate a Micro, modify Codex, require Chroma, or need an API key.

## Setup

1. Quit the previous Ergo Control from its menu bar and open `build/Ergo Control.app`. No helper reinstall is required.
2. In **Codex · five chat slots**, enable **Connect to Codex** and click **Install status hooks**.
3. In the Codex CLI, use `/hooks` to review and trust the Ergo Control command. This is Codex's own required review of new hook definitions; Ergo Control does not bypass it. Start a new desktop turn afterward. If an existing session does not load the hooks, restart that session/client after saving your work.
4. The first five observed chats fill M1–M5 in order. Assignments stay fixed. Edit a label or paste a canonical chat link/UUID and click **Save slot** to choose another chat. Clearing a slot makes it available for the next observed chat. Labels default to the project folder's basename, not the chat title.
5. Click **Create Codex mappings profile**. Select that profile and **Use selected as default**, then enable mappings. Existing profiles are preserved. Existing app-specific profiles still take precedence when automatic profile switching is enabled. Alternatively assign **Open Codex chat slot** to any control in an existing profile.
6. Optionally enable **Show Codex status on the macro column**, with brightness above 0%. This works during a Bluetooth mapping session. Turn status lighting off to edit the normal backlight effect.

Settings show all five status dots. The menu lists five labeled chat/status entries that open their chat without requiring keyboard mappings. Status updates do not activate an app. A chat key explicitly opens its chat using the installed `com.openai.codex` desktop application. Chat selection injects no generic keyboard shortcuts, text, or approval keys.

## Status meaning

| Event | Display | Macro color |
| --- | --- | --- |
| UserPromptSubmit / PreToolUse / PostToolUse | Working | Blue |
| PermissionRequest | Approval requested | Amber |
| Stop | Turn ended | Green |
| SessionStart / Interrupt / SessionEnd | Idle | White |
| No event since launch, or 30 minutes without an observed event | No recent status | No override if all slots are unknown |

The shared M1–M5 zone shows the highest-priority assigned state: approval, working, turn ended, idle. Other zones stay static white (RGB 160); global brightness remains adjustable. This replaces an animated background while active. Disabling status lighting, stopping mappings, sleep, and normal quit restore and read back the saved built-in effect.

These are coarse lifecycle observations. **Turn ended is not an unread indicator or a guarantee all stop hooks have finished**: another hook can continue a turn. PermissionRequest does not cover every user question. Recoverable tool errors are not labeled as a failed chat. Subagent lifecycle events are excluded, and explicit subagent identifiers rejected; parent-ID tool events without a distinguishing field cannot be separated reliably. Delayed terminal events with older turn IDs are ignored. Events expire rather than claiming stale chats are still working indefinitely.

Only local Codex sessions executing these trusted hooks are observed. History is not imported, slots do not follow native recent/pinned order, and cloud/remote/non-Codex chat coverage is not promised. Hook `session_id` to desktop deep-link navigation still needs live confirmation on the installed client. Unknown or future non-UUID IDs are ignored. Native Micro voice/reasoning controls, exact selected/unread state, and automatic approval are outside this first integration.

## Local data and removal

On installation, the bundled signed `ErgoCodexHook` executable is copied to Application Support under `ErgoControl/Codex`. Its command path stays stable if the app moves. `CODEX_HOME` is honored when present in Ergo Control's environment; otherwise hooks merge into `~/.codex/hooks.json`. Existing fields/handlers are retained, repeated installation is idempotent, and existing files are backed up beside the original before install/removal. Inline TOML hooks are unchanged; Codex merges both representations and may warn about the combination.

The sender receives JSON on stdin, reads at most 1 MiB plus one byte, and retains only event name, session/turn IDs, project basename, and time. It discards prompts, tool arguments/results, full paths, model, and transcript location. It emits `{}` and exits successfully even when the app is unavailable or input unsupported. There is no network connection. Hooks have a one-second timeout and emit no approval, blocking, or continuation decisions.

Events use an atomic private file queue in `ErgoControl/Codex/events` (128 pending events maximum). The app drains it every half second and deletes consumed/invalid events. The sender queues only while the receiver PID is alive. Events older than five minutes are discarded. Settings retain five chat IDs/labels and opt-in flags; activity exists only in memory and resets to unknown at launch. Folder permissions are 0700, event/settings files 0600, sender 0700. This is same-user IPC, not a boundary against programs already running as that user.

**Remove status hooks** removes this exact command's entries, retains foreign hooks, and makes a backup. **Connect to Codex** off stops reception and releases lighting while preserving assignments. Quit removes the receiver marker. To erase assignments afterward, quit and remove the `ErgoControl/Codex` support folder; remove hooks first to avoid a dangling command path.

## Lighting recovery and verification

The previous canonical firmware effect and region 5 are durably stored inside the existing exact-device Bluetooth `pending-restoration.json` **before** selecting custom effect 8. Frames share the acknowledged controller queue with mode, battery, brightness, and other lighting; unchanged colors send no new frames. Recovery writes the saved effect, verifies readback, and only then clears its record. Rejection/disconnect retains recovery owed and retries back off. Restarting the app, or its existing `--restore-keyboard` command with the GUI quit, recovers the same paired keyboard. Unknown/custom originals are refused because their pixels cannot be recovered from a selector. Pending Lighting Lab recovery blocks new Codex lighting.

Automated coverage checks privacy/validation, config merging/removal, stable slots, event ordering/expiry, status priority, callback-only key dispatch, snapshot-before-write, coalescing, cancellation, rejection, readback mismatch, and restart restoration. Tests never post input. Bluetooth frame capability was previously confirmed live; the integrated renderer with mappings and desktop hook/navigation flow still needs the user's first end-to-end check.

Sources: [Codex hooks](https://learn.chatgpt.com/docs/hooks), [commands and chat links](https://learn.chatgpt.com/docs/reference/commands), [research and limitations](CODEX_AND_CHROMA.md), [device lighting evidence](MACRO_LIGHTING.md).
