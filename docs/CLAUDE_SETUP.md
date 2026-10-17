# Claude Code chat keys and status

Ergo Control offers Claude Code alongside Codex in **Chat apps**. The selected provider owns unmapped M1–M5 and the shared status lights. Explicit Codex/Claude slot mappings keep opening their own provider, regardless of this selector. Each provider retains its own opt-in settings and assignments. Existing Codex files and profile actions keep their original meaning.

## Setup

1. Open the rebuilt Ergo Control app, select **Chat apps → Claude Code**, and turn on **Connect to Claude Code**.
2. Under **Setup and advanced options**, select **Install status hooks**. Start a new local session in Claude Desktop's Code tab afterward. This is an explicit setup action; merely selecting Claude does not install hooks.
3. Use **Most recent chats**, **Starred chats · newest first**, or **Fixed assignments**. Fixed slots offer a saved-chat chooser and accept `claude://code/continue?session=local_<uuid>` links or `local_<uuid>` desktop IDs. A hook/CLI UUID is a different identifier and cannot be used as a desktop target.
4. Enable keyboard mappings. Unmapped M1–M5 use the selected provider. If an existing profile explicitly assigns Codex actions, change those actions, use Default, or create a separate Claude mappings profile; choosing Claude does not rewrite explicit actions.
5. Optionally enable **Show Claude Code status lights**. All existing signal styles, wave speeds, working pulse, dark background and visual tests use the same renderer and saved-effect recovery as Codex. Keyboard brightness must be above zero.

Under **Status lights → Colors for Claude Code**, choose separate Working, Approval requested and Turn ended colors. Claude defaults to **purple / pink / cyan**; Codex keeps **blue / amber / green**. Each provider saves its own palette, with a reset button for its defaults. The chosen colors apply to solid signals, wave heads/trails, working pulses and the visual test. Editing a live color updates the signal without replaying a completed wave. This does not change which provider owns the lights: the Chat apps selector still chooses that source.

The default catalog is `~/Library/Application Support/Claude/claude-code-sessions/<account>/<organization>`. A single account/organization is discovered automatically. With several, choose the intended folder under **Claude session catalog**. Lists are never combined across accounts. **Use automatic catalog** clears that folder override. Metadata reads continue in Fixed mode to match desktop IDs to the engine UUIDs reported by hooks.

## Behavior and limits

| Observation | Status |
| --- | --- |
| Prompt or tool activity | Working color (purple by default) |
| Permission request or AskUserQuestion tool | Approval color (pink by default) |
| Normal Stop | Brief turn-ended color (cyan by default), then idle and normal effect |
| StopFailure or SessionEnd | Idle, without a completion signal |
| Idle notification | Clears working status, but never dismisses a pending approval |

Claude does not emit Stop for a user interrupt. Its later idle notification can clear working status. If no notification arrives, use **Clear observed status**; ordinary stale work also expires after 30 minutes. A known pending approval remains until a later status, explicit reset, disabling the connection, or app exit. API failure means the turn stopped, not completed successfully. Newer prompt IDs protect against delayed terminal events from earlier prompts; older engines may omit them. Subagent events and events with explicit subagent identifiers are excluded. Parent-ID events without a distinguishing field cannot reliably be separated.

Only local desktop Code sessions are listed. Archived records, child sessions, SSH/cloud targets and other session types are excluded. Hooks can also run in the CLI, but an engine UUID must match a listed desktop record before it can color a selected chat. No agent is started to obtain metadata. Ordinary Claude chat and Cowork are outside this adapter.

The local catalog and existing-session `continue` route are internal desktop interfaces. Static inspection of installed Claude Desktop **2.42304.0** established the record fields and that Claude itself generates this link for existing sessions. Starred records are ordered by activity time, with a stable ID tie-breaker; exact native sidebar pin order is not claimed. An unfamiliar catalog format clears dynamic slots instead of retaining a potentially wrong M1–M5 list. Fixed targets remain saved, with unknown status if metadata is unavailable. The terminal CLI and Desktop's engine update separately; no terminal CLI version or installed SDK is required by this adapter.

## Local data and removal

The signed `ErgoClaudeHook` sender is bundled with the app and copied, on explicit installation, into `Application Support/ErgoControl/Claude`. Hooks merge into `~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json` when present in Ergo Control's environment. Existing handlers, matchers, permission rules and unrelated settings are preserved. Installation is idempotent; install/removal backs up existing settings before writing. **Remove status hooks** removes only this exact sender command. Hook installation respects Claude's normal settings and managed-policy behavior.

The sender reads at most 1 MiB plus one byte. Before queueing, it discards prompt/answer text, tool input/output, notification text, model and transcript/full directory paths. It retains only normalized lifecycle event, engine session ID, optional prompt ID, project basename and timestamp. It returns `{}` and exits successfully even if unsupported or Ergo Control is unavailable; it supplies no permission or continuation decisions. Notification handlers match only permission and idle notifications. The queue has at most 128 pending files and is drained every half second; stale events are discarded. Folder/file permissions follow the existing 0700/0600 Codex bridge rules, and activity is transient across launches.

Catalog reads run off the main thread every ten seconds and after relevant hooks. The reader projects only IDs, title, activity time and starred state, ignoring other JSON fields. It opens no transcript files, reads no credentials, launches no CLI, and calls no network API. It bounds file counts, per-file size, aggregate bytes and read time, and refuses catalog/file symlinks. Metadata is held in memory; assignments, catalog folder override and opt-in choices are saved locally. These are same-user files, not a security boundary against other software running as that user.

Disabling the selected connection or stopping mappings releases lighting through existing restoration. Switching providers cancels previews and releases the old lighting source. Both providers may remain connected for their explicit mappings, but only the selected one drives default macro keys and lights. To erase Claude assignments, quit, remove its hooks first, then remove `Application Support/ErgoControl/Claude`. The provider choice is stored separately in `ErgoControl/chat-provider.json`; absent settings default to Codex.

## Validation

Synthetic local tests cover hook filtering/privacy, prompt ordering, failure/idle behavior, config merge/removal, safe navigation IDs, catalog filtering/scope/limits, desktop-to-engine ID mapping, settings migration and callback-only action dispatch. Palette tests also cover independent provider defaults/persistence/reset, matching RGB values across states, custom wave/pulse/solid frames, and color edits without wave replay. Existing Codex bridge and keyboard restoration tests remain part of the same suite. Tests do not post input, change real hook settings, or access hardware.

Live validation remains necessary: create local Claude desktop sessions; compare recent/starred slots; verify M1–M5 select the exact session without sending a message; observe working, approval, completion and interruption; switch providers while a signal is active; and confirm effect restoration on the keyboard. No real Claude desktop session was available during initial implementation, so these behaviors are not yet claimed as hardware-confirmed.

## References

- [Claude Desktop shared configuration](https://code.claude.com/docs/en/desktop#shared-configuration)
- [Claude Code hook reference](https://code.claude.com/docs/en/hooks)
- [Claude settings locations](https://code.claude.com/docs/en/settings)
- [Documented desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link) cover new Code sessions; the existing-session route above was established by local static inspection, not inferred from the mobile routes.
