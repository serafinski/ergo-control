# Chroma value and a five-key Codex companion

Research completed 16 October 2026. This report records the feasibility investigation; the subsequent opt-in 0.3.0 implementation is documented in [Codex setup](CODEX_SETUP.md). No Codex settings, hooks, app files, permissions, or hardware identities were changed for this research.

## Recommendation

Keep Ergo Control independent of Chroma. Build a small status renderer and a Codex adapter on the direct lighting path we already verified. Chroma adds a substantial editor and ecosystem, but no additional independently addressable macro LEDs were found. Five separate chat-selection buttons are feasible; five different colors on M1–M5 simultaneously are not exposed by this keyboard's shared macro zone.

For Codex, start with documented shortcuts/deep links and lifecycle hooks. Treat native Micro emulation as a separate research option with distribution/compatibility constraints, rather than a prerequisite for the first useful version.

## What Chroma adds

Razer's [Mac preview page](https://www.razer.com/synapse-4-mac) advertises device synchronization. Its [Studio guide](https://dl.razerzone.com/master-guides/RazerChromaApp/RazerChromaApp-en.pdf) describes effect layers, selection tools, and effect properties. [Effect instructions](https://mysupport.razer.com/app/answers/detail/a_id/13713/kw/Chroma%20Configurator) list static, breathing, spectrum, wave, reactive, ripple, fire, and starlight. Feature/device support and the Mac preview vary; a Windows SDK example is not evidence that every integration is available on Mac.

| Capability | Chroma's value | Independent Ergo Control route |
| --- | --- | --- |
| Rich effect editor | Visual selection, effect layers, previews, configurable properties | Optional future UI; not needed for a status light |
| More animations | Ready-made effects and composition | Generate RGB frames in Swift: pulse, chase, progress, rainbow, reactive fades, etc. |
| Multiple devices | Shared scene/device layout and compatible ecosystem integrations | Consider a separate optional adapter if users actually need this |
| Existing Chroma-enabled games/apps | Vendor ecosystem/SDK integration | Separate compatibility project; no claim of transparent Mac SDK compatibility |
| Five individual macro colors | No additional targets found in the device map | M1–M5 remain one shared zone |
| Codex chat status | No verified built-in Codex-specific integration found | Obtain status from Codex; send it to our renderer |

We have already sent arbitrary 19-zone frames without Chroma: isolated M1–M5 pulsing is user-confirmed over USB and Bluetooth; a moving cyan line is confirmed over USB. See [protocol and hardware evidence](LIGHTING_LAB.md). The inference is that additional **host-rendered patterns** and adjustable animation speed can be implemented using those frames, not that every Chroma feature has been reproduced or that new firmware effects exist. This can provide a speed control for our own wave even though the built-in firmware Wave has no verified adjustable speed.

The macro bank can pulse, fade, cycle colors, or show a steady state as one group. An animation moving separately through M1, M2, M3, M4, M5 would require separate targets that the supported map does not expose. Other keyboard zones could display additional status colors, but those are groups of ordinary keys, not individual macro-key lamps.

A production renderer still needs background composition, cancellation/restoration, scheduling alongside battery/mode commands, reconnect handling, and tests with active mappings. The lab currently darkens non-macro zones for a macro-only test; preserving an animated background requires composing the background and status overlay into one frame. Conservative measured lab throughput was about two acknowledged frames/sec on Bluetooth and four on USB; these are measured lab settings/transport timings, not established hardware maximums. Prefer event-driven steady colors or short pulses for status rather than continuous unnecessary streaming.

Razer's SDK setup documentation describes vendor SDK/services. We have not verified an officially supported standalone Mac REST integration for this keyboard. Requiring Chroma would add an external process/dependency and another writer competing for the same device. No hidden hardware unlock, onboard programmable animation engine, or independent per-macro LED was established by installing it; it was not installed for this investigation.

## What the Micro actually integrates

The [official Codex Micro documentation](https://learn.chatgpt.com/docs/features/codex-micro) describes six agent slots, configurable commands, a dial/joystick, voice controls, and live per-chat lighting. Its agent keys follow recent, pinned, prioritized, or explicitly assigned chats. It is a bidirectional device/app integration, beyond keyboard macros.

The following is a proposed adaptation, not a change to saved user mappings:

| Ergo control | Proposed use | Evidence/limit |
| --- | --- | --- |
| M1–M5, normal layer | Open five recent chats, or five explicitly assigned chat links | Documented recent-chat shortcuts or canonical deep links |
| Whole macro bank | Selected chat's state; alternatively the most urgent tracked state | One shared color/pattern, hardware verified |
| Menu/HUD | Five labeled status dots showing which slot needs attention | Software UI can show what five shared LEDs cannot |
| Alternate layer | Selected Codex commands: new chat, review, attention navigation, voice, send, etc. | Use documented/configured commands; availability must be verified per action |
| Dial | Chat scroll, previous/next chat, or later reasoning controls | Scroll/shortcuts feasible; exact native Micro dial UI is not yet reproduced |

Use an app-specific profile, preserving mappings outside Codex. An optional layer key can expose command actions without consuming all five chat-selection keys. Full Micro parity includes more controls than five physical keys, so some actions need layers or the existing dials/AI key.

## Supported integration route

### Chat navigation and commands

The [official Commands reference](https://learn.chatgpt.com/docs/reference/commands) documents macOS recent-chat shortcuts `Command+Option+1…6`, next-attention navigation, configurable shortcuts, and `codex://threads/<thread-id>` links. M1–M5 could use the first five recent slots, or explicit links for stable assignments. Recent-slot shortcuts follow app ordering; they do not automatically implement pinned/priority/custom modes.

Target the intended app/window before dispatching a command and confirm focus. Generic Enter/Escape are context-sensitive; they are not unconditional approval/decline APIs. Any approval mapping must require an explicit physical press and a verified pending approval context. Exact push-to-talk, background-only chat switching, reasoning control, and enabled-skill execution need an available command/integration rather than invented shortcuts. Avoid stealing focus for background status updates.

### Status events

Codex's [documented hooks](https://learn.chatgpt.com/docs/hooks) can deliver lifecycle events, with `session_id` and optional turn identifiers. A small opt-in hook sender can forward only those identifiers, an event name, and time to private local Ergo Control IPC. It should discard prompt/tool/transcript contents, emit no behavioral decisions, never block approval, and do nothing harmful when the app is closed. Hooks require Codex's own definition review/trust; none have been configured here.

Suggested coarse mapping: submission/activity → working; an actual permission request → attention; turn stop → finished/idle; interruption/end → idle. Avoid treating every recoverable tool error as a failed chat. A permission hook does not cover every arbitrary user question. Hooks alone do not establish app unread flags, selected/pinned order, cloud-chat coverage, or the exact Micro error/attention semantics. Event ordering, stale events, subagents sharing the parent session ID, and stop hooks that can continue a turn need deliberate handling and runtime validation.

The [App Server reference](https://learn.chatgpt.com/docs/app-server) documents thread status notifications and approval/input requests on an owned connection. That is another possible adapter for sessions our integration actually observes. Starting a second server must not be assumed to mirror every loaded thread in the desktop app. Shared desktop-server attachment, authentication, subscriptions, cloud/remote coverage, and unread state remain unverified; the documented server/transport is experimental. The agent's current app-tools connector is not a public background API that Swift can simply call outside an agent turn.

A renderer can use white for idle, blue for working, green for a completed update, amber for attention, red for a verified error, and off/unknown when disconnected. With one bank, choose either the selected slot or a documented priority rule. Display all five slot states separately in a menu/HUD. Do not claim an unread update when the chosen source only tells us a turn stopped.

## Native Micro compatibility route

Public interoperability projects exist: [Stream Deck emulator](https://github.com/mpociot/codex-micro-stream-deck-emulator) and [Codex Micro Lab](https://github.com/42libft/codex-micro-lab). These are community implementations, not OpenAI-supported extension APIs. Their own development notes describe a virtual Micro RPC endpoint, native app status messages, and key notifications.

Read-only inspection of the installed ChatGPT app corroborated that it bundles a Micro service and Work Louder device kit. The discovery filter targets vendor `303a`, products `8360` / `8297` / `8298`, vendor usage page `ff00`. Our Razer identity is different, so changing shortcut mappings alone cannot make it a native Micro.

Two routes described by the emulator:

1. A launch-time `node-hid` shim supplied through `NODE_OPTIONS`. **The installed app has that loading mechanism disabled**, so the published launcher cannot be assumed to work unchanged. Its older demonstration is not proof of compatibility with this build. No injection or application modification was attempted.
2. A real OS virtual HID endpoint. The project reports a gated Apple entitlement requirement. Apple documents [`com.apple.developer.hid.virtual.device`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device). Entitlement/signing/distribution must be investigated and obtained if needed; this project's existing input-capture helper does not grant that capability. No virtual device was created here.

An independent compatible bridge could translate the first five Micro agent slots to M1–M5, retain native commands/layers/dial events, and consume the app's status feed. This offers closer native parity if discovery can be solved sustainably. It still cannot produce five independent macro colors on this hardware. Consider an optional research module only after verifying current-version compatibility and a distributable transport; do not make normal Ergo Control require a patched ChatGPT app.

The installed `@worklouder/device-kit-oai` package declares `UNLICENSED`. No package code or assets should be copied into the MIT project on that basis. Use independently implemented protocol facts and appropriately licensed public references, preserving any required attribution if code is later adopted.

## Suggested implementation sequence

1. Validate input-relay stability, including native repeat and Magnet shortcuts.
2. Add a Codex profile with five targeted chat-selection actions and a five-slot menu/HUD; preserve existing user profiles.
3. Implement the shared-bank renderer, composition, and restoration within the existing serialized Bluetooth controller; test alongside active mappings.
4. Add an opt-in hook adapter and prove basic local-session status transitions. Clearly label incomplete/unknown state and coverage.
5. Evaluate App Server/native Micro transport separately for exact status/navigation/command parity. Extend only what is demonstrated on the installed build.

No implementation estimate or full-parity promise is implied. The actionable finding is that lighting transport works already; reliable desktop state/control integration is the remaining substantial work. Chroma would not solve that part.

## Evidence inventory

- Installed app: `26.1007.71326`, build `20398`, inspected read-only on 16 October 2026.
- Packaged Micro service `.vite/build/service-C1gZiKOP.js`: SHA-256 `91c2646890d4a35e4269a1b2e6c3d49209522368ccc376e214e13ecd6236145e`.
- Packaged main bundle `.vite/build/main-CwxgTOle.js`: SHA-256 `87d52265eb13608a380fabcac47ecf13a39b981115c0960c18af563ea6d32d51`.
- Work Louder kit version `0.2.1`, package license field `UNLICENSED`. Static type/protocol inspection only; no vendor code was run by the research scripts.
- Installed framework fuse readout: Node-options and CLI inspection disabled; ASAR integrity and ASAR-only loading enabled. No fuse was changed.
- Stream Deck emulator reference commit: [`7093bd48f0bcb953f623b40c727470e545b48df3`](https://github.com/mpociot/codex-micro-stream-deck-emulator/tree/7093bd48f0bcb953f623b40c727470e545b48df3).
- Micro Lab reference commit: [`99b6f11b04946155d8956e1e72c0ddb45646dfcf`](https://github.com/42libft/codex-micro-lab/tree/99b6f11b04946155d8956e1e72c0ddb45646dfcf).
- Downloaded research references remain ignored under `analysis/codex-chroma-research/`. No third-party executables, Codex state modification, Chroma installation, or keyboard writes were needed for this report.
