# Codex chat keys and status

Ergo Control 0.5.1 keeps Codex chat keys and status controls in a dedicated sidebar section. It uses local metadata listings, lifecycle hooks, and `codex://threads/<thread-id>` links. It does not emulate a Micro, modify Codex, require Chroma, or need an API key.

## Setup

1. Quit the previous Ergo Control from its menu bar and open `build/Ergo Control.app`. No helper reinstall is required.
2. Choose **Codex** in the sidebar and enable **Connect to Codex**. For first-time status setup, open **Setup and advanced options** and click **Install status hooks**. Already-approved hooks need no reinstall.
3. Review and trust **ErgoCodexHook** if the ChatGPT desktop app asks. If you already accepted these hooks there, no CLI review is needed. Start a new desktop turn afterward. If the desktop app does not offer review, `/hooks` in the Codex CLI is an alternative. This is Codex's own review; Ergo Control does not bypass it. If an existing session does not load the hooks, restart that session/client after saving your work.
4. **Most recent chats** is the default: M1–M5 follow the first five local Codex chats in ChatGPT's recency ordering. **Pinned chats** follows their pinned section order. Both update automatically without assigning individual conversations. **Fixed assignments** retains the earlier manual mode and saved chat links; it is optional. In that mode, empty slots fill from newly observed hook sessions and can be edited with **Save slot**.
5. Leave **Use unmapped M1–M5 for Codex chats** on and enable mappings. Macro keys set to **Default** now open their current chat slots automatically. Explicit mappings and alternate-layer actions take precedence. Use **Open chat slot** when deliberately replacing an existing custom action. **Create Codex mappings profile** is an optional shortcut for creating all five explicit actions in a separate profile; choose **Use selected as default** to make that profile active. Existing profiles are preserved.
6. Optionally enable **Show Codex status on the macro column**, with brightness above 0%. This works during a Bluetooth mapping session. Turn status lighting off to edit the normal backlight effect.

The Codex panel and menu identify the selected Codex list and show how many of the five macro keys have a chat. Empty slots say No other pinned/recent Codex chat. Ordinary ChatGPT conversations are not supported. The 0.5.0 ChatGPT source was removed after its conversation links opened a browser instead of the native chat. Saved Codex assignments and selection are preserved on upgrade, including when ChatGPT had been selected. The app no longer reads ChatGPT sidebar preferences. The recent Codex list remains the default.

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

Recent and pinned selection use the local saved Codex catalog, including chats that have not emitted a hook during this app session. Only sessions executing trusted hooks have live activity status; older chats remain unknown until new events arrive. Ordinary ChatGPT conversations and remote-only chats are not included. The user reported that opening this conversation works after assigning Open Codex chat slot; broader navigation testing remains useful. Unknown or future non-UUID IDs are ignored. Native Micro voice/reasoning controls, exact selected/unread state, and automatic approval are outside this first integration.

## Testing status lighting (0.5.1)

1. Keep keyboard brightness above 0%, connect to Codex, and enable mappings from the sidebar. The lights require an active Bluetooth mapping session.
2. In **Codex → Status lights**, enable **Show Codex status on the macro column** and click **Test status lights · 20 seconds**.
3. Watch **M1–M5 together**: blue (working), amber (approval), green (turn ended), white (idle), then the previous keyboard effect. Each stage lasts four seconds; the screen labels the current test stage. Other keys stay white during status frames.
4. Afterward, actual observed status resumes. **Stop test**, turning off status lighting or the connection, stopping mappings, sleep, and quit cancel the test. Turning lighting/mappings off restores the original effect. No synthetic hook events or chat status changes are made; hooks continue to be observed during the test.
5. To verify real desktop activity, choose Most recent chats so this conversation is included, leave status lighting on, and send a reply here. It should turn blue during tool activity and green when the turn ends, unless another assigned chat has a higher-priority status. Approval amber can be checked with the visual test without creating a real approval request.

This test uses the same bridge callback, serialized Bluetooth queue, shared-zone frame builder, and durable snapshot/readback restoration as live Codex lighting. Automated tests confirm the sequence, real-event retention, cancellation, finite timing, frame zone selection, and restoration. Physical colors and real-hook lighting alongside mappings still need the user's confirmation; earlier USB/Bluetooth pattern tests alone do not establish this end-to-end behavior.

## Local data and removal

On installation, the bundled signed `ErgoCodexHook` executable is copied to Application Support under `ErgoControl/Codex`. Its command path stays stable if the app moves. `CODEX_HOME` is honored when present in Ergo Control's environment; otherwise hooks merge into `~/.codex/hooks.json`. Existing fields/handlers are retained, repeated installation is idempotent, and existing files are backed up beside the original before install/removal. Inline TOML hooks are unchanged; Codex merges both representations and may warn about the combination.

The sender receives JSON on stdin, reads at most 1 MiB plus one byte, and retains only event name, session/turn IDs, project basename, and time. It discards prompts, tool arguments/results, full paths, model, and transcript location. It emits `{}` and exits successfully even when the app is unavailable or input unsupported. There is no network connection. Hooks have a one-second timeout and emit no approval, blocking, or continuation decisions.

Hook events use an atomic private file queue in `ErgoControl/Codex/events` (128 pending events maximum). The app drains it every half second and deletes consumed/invalid events. The sender queues only while the receiver PID is alive. Events older than five minutes are discarded. Settings retain manual chat IDs/labels, the selection mode, and opt-in flags. Dynamic titles/IDs and at most 100 recent hook states exist only in memory; live activity resets to unknown at launch. Folder permissions are 0700, event/settings files 0600, sender 0700. This is same-user IPC, not a boundary against programs already running as that user.

**Remove status hooks** removes this exact command's entries, retains foreign hooks, and makes a backup. **Connect to Codex** off stops reception and releases lighting while preserving assignments. Quit removes the receiver marker and stops the metadata reader. To erase assignments afterward, quit and remove the `ErgoControl/Codex` support folder; remove hooks first to avoid a dangling command path.

## Lighting recovery and verification

The previous canonical firmware effect and region 5 are durably stored inside the existing exact-device Bluetooth `pending-restoration.json` **before** selecting custom effect 8. Frames share the acknowledged controller queue with mode, battery, brightness, and other lighting; unchanged colors send no new frames. Recovery writes the saved effect, verifies readback, and only then clears its record. Rejection/disconnect retains recovery owed and retries back off. Restarting the app, or its existing `--restore-keyboard` command with the GUI quit, recovers the same paired keyboard. Unknown/custom originals are refused because their pixels cannot be recovered from a selector. Pending Lighting Lab recovery blocks new Codex lighting.

Automated coverage checks privacy/validation, config merging/removal, stable slots, event ordering/expiry, status priority, callback-only key dispatch, snapshot-before-write, coalescing, cancellation, rejection, readback mismatch, and restart restoration. Tests never post input. After the user approved hooks in ChatGPT, this desktop conversation produced real PreToolUse events and was automatically assigned to M1. The desktop event path is therefore confirmed; chat opening received a positive user report; dynamic ordering and status lighting alongside mappings still need a user check. Bluetooth frame capability was previously confirmed separately.

## Dynamic history reader (0.4.0)

An opt-in background client launches the CLI bundled inside the installed ChatGPT app as `app-server --stdio`. It reuses that metadata process while automatic selection is enabled, refreshes every ten seconds and shortly after prompt/stop events, and stops it when the connection is disabled, Fixed assignments is selected, or Ergo Control quits. It does not start or resume an agent/chat, subscribe to turns, send messages, respond to approvals, restart the desktop app, or install a daemon. If the reader fails, automatic targets clear and retry; saved fixed assignments stay intact.

The command whitelist is initialize/initialized, thread/list, and threadSection/list. Listings set `archived: false` and `useStateDbOnly: true`, avoiding rollout scans/repair. Recent ordering uses `recency_at` descending; pinned queries discover the existing Pinned section ID and use `section_position` ascending. The installed 0.162.0-alpha.17.2 server silently ignores the newer documented isPinned filter, so the implementation uses its generated schema's actual section API. Duplicate IDs, subagents, ephemeral records, and unsupported IDs are excluded. Only five titles/IDs are displayed. Pagination and response bytes are bounded; failed metadata reads never fall back to a wrong set of chats. The Pinned section is recognized by its existing name, with its ID remembered across renames during the reader session. Renaming it before restarting the reader can prevent discovery; no section is renamed or created by Ergo Control.

Metadata responses may include a preview and other fields supplied by Codex. Ergo Control ignores those fields, never requests turn history, and does not log or retain responses. The separate metadata server does not mirror the desktop's loaded runtime states: a `notLoaded` value is not used to overwrite real hook activity. Hook status and metadata selection remain separate sources. Forks sharing one hook session ID cannot be given independent live status reliably.

Read-only live probes confirmed this conversation first in recency order and the two native pinned chats in their exact sidebar order. The signed app's `--codex-history-check` command verifies its reader without displaying titles or changing chats. Automated coverage checks default/migration behavior, mode changes, dynamic reordering, fixed-setting preservation, status-light selection, metadata filtering, and the read-only method whitelist. General native Micro unread/priority/selected behavior remains outside this adapter.

Sources: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Codex hooks](https://learn.chatgpt.com/docs/hooks), [commands and chat links](https://learn.chatgpt.com/docs/reference/commands), [research and limitations](CODEX_AND_CHROMA.md), [device lighting evidence](MACRO_LIGHTING.md).
