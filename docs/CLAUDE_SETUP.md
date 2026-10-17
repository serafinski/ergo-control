# Claude Code chat keys and status

Ergo Control offers Claude Code alongside Codex in **Chat apps**. **App settings** switches the page you are viewing. **Automatic keys → Default chat app** selects the provider for unmapped M1–M5, while **Keyboard status lighting → Lighting mode** independently selects Automatic (both apps), Codex only or Claude Code only. Explicit Codex/Claude slot mappings keep opening their own provider. Each provider retains its own opt-in settings and assignments. Existing Codex files and profile actions keep their original meaning.

**Macro keys for Claude Code** shows the actual M1–M5 destinations for the active profile and the Standard or Alternate layer you choose to inspect. Keys assigned to Codex say **Unassigned to Claude Code**, with their current Codex destination underneath. Available chats are listed separately as **Slot 1–5**, with the macro keys mapped to each slot. Having a chat in a slot does not assign a physical key. **Edit mappings** opens that profile and layer in Keyboard settings.

## Setup

1. Open the rebuilt Ergo Control app, select **Chat apps → Claude Code**, and turn on **Connect to Claude Code**.
2. Under **Setup and advanced options**, select **Install status hooks**. Start a new local session in Claude Desktop's Code tab afterward. This is an explicit setup action; merely selecting Claude does not install hooks.
3. Use **Most recent chats**, **Starred chats · newest first**, or **Fixed assignments**. Fixed slots offer a saved-chat chooser and accept `claude://code/continue?session=local_<uuid>` links or `local_<uuid>` desktop IDs. A hook/CLI UUID is a different identifier and cannot be used as a desktop target.
4. Enable keyboard mappings. To use Claude for keys set to Default, choose **Automatic keys → Default chat app → Claude Code** and enable **Use unmapped M1–M5 for Claude Code chats**. If an existing profile explicitly assigns Codex actions, use **Edit mappings** to change individual actions or create a separate Claude mappings profile. Browsing Claude settings does not rewrite mappings or change lighting mode.
5. Optionally enable **Show Claude Code status lights**. **Automatic · Both apps** is the default lighting mode; **Claude Code only** limits signals to Claude. Each included app needs its connection and status lights enabled. All existing signal styles, wave speeds, working pulse, dark background and visual tests use the same renderer and saved-effect recovery as Codex. Keyboard brightness must be above zero. Tests temporarily override live lighting for their duration, then resume live status; only one test runs at a time.

Under **Status lights → Colors for Claude Code**, choose separate Working, Approval requested and Turn ended colors. Claude defaults to **orange / magenta / cyan**; Codex uses **blue / red / green**. The exact default RGB values are listed below. Each provider saves its own palette, with a reset button for its defaults. The chosen colors apply to solid signals, wave heads/trails, working pulses and the visual test. Editing a live color updates the signal without replaying a completed wave. **Keyboard status lighting → Lighting mode** controls which apps can supply signals.

| Provider | Working | Approval requested | Turn ended |
| --- | --- | --- | --- |
| Codex | `#0010FF` (0, 16, 255) | `#FF0012` (255, 0, 18) | `#00FF00` (0, 255, 0) |
| Claude Code | `#FF5700` (255, 87, 0) | `#FF01EB` (255, 1, 235) | `#00FFFF` (0, 255, 255) |

These defaults match the palettes selected in the app. Existing saved overrides are preserved; Reset colors returns to the defaults above.

The default catalog is `~/Library/Application Support/Claude/claude-code-sessions/<account>/<organization>`. A single account/organization is discovered automatically. With several, choose the intended folder under **Claude session catalog**. Lists are never combined across accounts. **Use automatic catalog** clears that folder override. Metadata reads continue in Fixed mode to match desktop IDs to the engine UUIDs reported by hooks.

## Behavior and limits

Automatic lighting considers the chats in each app's selected recent/starred/pinned/fixed slot list, independently of physical key mappings. Pending approval has highest priority, and the most recent pending request wins if both need approval. Each normal completion then briefly interrupts working signals: a full out-and-back wave, or four seconds of its app's completion color for solid styles. Afterward, the newest ongoing working turn resumes its color; if none remains, normal lighting returns. Repeated tool hooks and resuming after approval keep the original turn's recency and cannot steal or prolong a completion notification. Equal working/approval timestamps use a stable provider/session tie-breaker.

For example: Claude starts orange, Codex starts later and turns blue, Claude finishes and shows a cyan completion wave, then Codex blue resumes. Codex's final finish shows green and restores normal lighting. Claude approval preempts that sequence in magenta. Close-together completions play in order; completions arriving during approval wait until it clears, even after the short hook-status window expires. A completion interrupted by a new approval restarts its wave afterward. Duplicate Stop hooks do not replay an already announced turn. Each winning app uses its own palette, signal style, speed, pulse and background preferences. Handoffs preserve the original keyboard-effect snapshot, and an already shown working sweep does not replay on return. **Current signal** identifies the app and activity supplying the lights. Manual modes apply the same priority rules within their one app.

The transient completion queue is bounded to 33 notifications including an interrupted active signal. Disabling a provider, removing a chat from its selected slots, changing lighting mode, stopping mappings or quitting cancels affected pending signals. Nothing is persisted. Waves return control after the keyboard acknowledges their final frame; a 30-second fallback releases a stalled or unavailable renderer. Solid notifications have a fixed four-second deadline that tool events do not extend.

| Observation | Status |
| --- | --- |
| Prompt or tool activity | Working color (orange by default) |
| Permission request or AskUserQuestion tool | Approval color (magenta by default) |
| Normal Stop | Cyan completion wave/color, then remaining work's color or the normal effect |
| StopFailure or SessionEnd | Idle, without a completion signal |
| Idle notification | Clears working status, but never dismisses a pending approval |

Claude does not emit Stop for a user interrupt. Its later idle notification can clear working status. If no notification arrives, use **Clear observed status**; ordinary stale work also expires after 30 minutes. A known pending approval remains until a later status, explicit reset, disabling the connection, or app exit. API failure means the turn stopped, not completed successfully. Newer prompt IDs protect against delayed terminal events from earlier prompts; older engines may omit them. Subagent events and events with explicit subagent identifiers are excluded. Parent-ID events without a distinguishing field cannot reliably be separated.

Only local desktop Code sessions are listed. Archived records, child sessions, SSH/cloud targets and other session types are excluded. Hooks can also run in the CLI, but an engine UUID must match a listed desktop record before it can color a selected chat. No agent is started to obtain metadata. Ordinary Claude chat and Cowork are outside this adapter.

The local catalog and existing-session `continue` route are internal desktop interfaces. Static inspection of installed Claude Desktop **2.42304.0** established the record fields and that Claude itself generates this link for existing sessions. Starred records are ordered by activity time, with a stable ID tie-breaker; exact native sidebar pin order is not claimed. An unfamiliar catalog format clears dynamic slots instead of retaining a potentially wrong M1–M5 list. Fixed targets remain saved, with unknown status if metadata is unavailable. The terminal CLI and Desktop's engine update separately; no terminal CLI version or installed SDK is required by this adapter.

## Local data and removal

The signed `ErgoClaudeHook` sender is bundled with the app and copied, on explicit installation, into `Application Support/ErgoControl/Claude`. Hooks merge into `~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json` when present in Ergo Control's environment. Existing handlers, matchers, permission rules and unrelated settings are preserved. Installation is idempotent; install/removal backs up existing settings before writing. **Remove status hooks** removes only this exact sender command. Hook installation respects Claude's normal settings and managed-policy behavior.

The sender reads at most 1 MiB plus one byte. Before queueing, it discards prompt/answer text, tool input/output, notification text, model and transcript/full directory paths. It retains only normalized lifecycle event, engine session ID, optional prompt ID, project basename and timestamp. It returns `{}` and exits successfully even if unsupported or Ergo Control is unavailable; it supplies no permission or continuation decisions. Notification handlers match only permission and idle notifications. The queue has at most 128 pending files and is drained every half second; stale events are discarded. Folder/file permissions follow the existing 0700/0600 Codex bridge rules, and activity is transient across launches.

Catalog reads run off the main thread every ten seconds and after relevant hooks. The reader projects only IDs, title, activity time and starred state, ignoring other JSON fields. It opens no transcript files, reads no credentials, launches no CLI, and calls no network API. It bounds file counts, per-file size, aggregate bytes and read time, and refuses catalog/file symlinks. Metadata is held in memory; assignments, catalog folder override and opt-in choices are saved locally. These are same-user files, not a security boundary against other software running as that user.

Disabling an app's connection or status lights removes it from arbitration; another included app can take over. Stopping mappings restores the normal effect. Changing **Lighting mode** cancels previews and releases the old signal before applying the new mode; changing the default chat-key app or browsing **App settings** leaves lighting unchanged. To erase Claude assignments, quit, remove its hooks first, then remove `Application Support/ErgoControl/Claude`. The default key provider and lighting mode share `ErgoControl/chat-provider.json`. Legacy single-provider preferences retain their key provider and adopt Automatic lighting; new/missing preferences default to Codex keys and Automatic lighting. Existing palettes, profiles and per-app opt-ins are preserved.

## Validation

Synthetic local tests cover hook filtering/privacy, prompt ordering, failure/idle behavior, config merge/removal, safe navigation IDs, catalog filtering/scope/limits, desktop-to-engine ID mapping, settings migration and callback-only action dispatch. Mapping tests cover explicit Codex keys with available Claude chats, mixed provider/slot destinations, alternate-layer inheritance, disabled actions and automatic fallback changes. Keyboard dispatch and the assignment display share the same resolver. Arbitration tests cover newest-turn handoff, approvals and resumption, completion queues and duplicate suppression, expiry, stale acknowledgments, fixed solid deadlines, wave fallback, ties, manual modes, opt-outs, previews and independent preference migration/persistence. Renderer tests verify final-frame acknowledgments, one restoration snapshot across provider handoffs, and resuming working without replaying the sweep. Palette tests also cover independent provider defaults/persistence/reset, matching RGB values across states, custom wave/pulse/solid frames, and color edits without wave replay. Existing Codex bridge and keyboard restoration tests remain part of the same suite. Tests do not post input, change real hook settings, or access hardware.

Live validation remains necessary: create local Claude desktop sessions; compare recent/starred slots; verify M1–M5 select the exact session without sending a message; observe working, approval, completion and interruption; switch providers while a signal is active; and confirm effect restoration on the keyboard. No real Claude desktop session was available during initial implementation, so these behaviors are not yet claimed as hardware-confirmed.

## References

- [Claude Desktop shared configuration](https://code.claude.com/docs/en/desktop#shared-configuration)
- [Claude Code hook reference](https://code.claude.com/docs/en/hooks)
- [Claude settings locations](https://code.claude.com/docs/en/settings)
- [Documented desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link) cover new Code sessions; the existing-session route above was established by local static inspection, not inferred from the mobile routes.
