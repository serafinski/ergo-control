# Macro-key lighting investigation

Investigated 15 October 2026. **Razer exposes M1–M5 as one shared lighting zone, not five individually addressable colors.** Independent colors for individual macro buttons are not exposed by that map. The optional Lighting Lab now sends custom zone frames over USB and Bluetooth. The user confirmed that **only M1–M5 pulse together while all other keys stay dark on both connections**, and confirmed a moving cyan line over USB. Saved-effect restoration was read-back verified. Regular mapping sessions now use the journaled Codex status renderer for opt-in macro-column or whole-keyboard signals; idle restores the previous effect.

## Device-specific evidence

Razer advertises [19-zone Chroma RGB](https://www.razer.com/productivity/razer-pro-type-ergo?page=tech-specs). To determine which keys share each zone, we inspected the device manifests used by Razer's current Mac Chroma lighting engine, rather than assuming that a generic Chroma keyboard/keypad SDK layout matches this keyboard.

The US layout (`ledConfig_0_1`, layout 1) in all three manifests has a 1 × 19 lighting matrix. Its `LedInputMap` associates the independently observed macro input IDs with these lighting coordinates:

| Button | Vendor input (`dkm`) | Lighting row, column |
| --- | --- | --- |
| M1 | `[32, 16]` | `[0, 0]` |
| M2 | `[33, 16]` | `[0, 0]` |
| M3 | `[34, 16]` | `[0, 0]` |
| M4 | `[35, 16]` | `[0, 0]` |
| M5 | `[36, 16]` | `[0, 0]` |

The matching `svg_0_1` diagram independently corroborates the grouping: one `.led` path with `data-row="0" data-col="0"` contains the five stacked macro-key shapes. The map also associates dial input `[96, 16]` with this coordinate; an input association does **not** establish control of the separate small command-dial indicator. That indicator remains a separate unresolved investigation.

These are lighting-zone coordinates, not HID key codes or class-6 LED target IDs. They must not be substituted into earlier dial-indicator RGB commands. Other regional entries in the supplied manifests contain differing dimensions/product metadata; the conclusions above specifically use the matching product's US layout. No additional per-key target was found.

## Connection limits and Chroma's role

| Connection | Product ID | Relevant manifest declarations |
| --- | --- | --- |
| Bluetooth | 707 (`02c3`), vendor 1678 | `isBLE: true`, `isHardwareEffectsOnly: true`, `isChromaSupported: true`, `isChromaStudioSupported: false` |
| USB | 708 (`02c4`), vendor 5426 | `isChromaStudioSupported: true`; device transport `rzDevice25` |
| Wireless receiver | 706 (`02c2`), vendor 5426 | `isChromaStudioSupported: true` |

The Bluetooth configuration uses `rzDevice30`. The manifest flags limit what Razer's software offers; **they are not a firmware restriction on custom frames**. A live test accepted custom effect 8 at the generic AllRegion target but rejected its frame data (status 7). Reading the keyboard's actual region list returned `[5]`. Custom rectangular RGB frames succeeded at profile 0 / region 5, and the user confirmed isolated macro-column pulsing over Bluetooth only. See the exact [tested sequence](LIGHTING_LAB.md#protocol-boundary-and-verification-status).

Chroma provides useful device-specific mapping/protocol evidence. It cannot provide five separate macro colors through a map that exposes one shared target. The standalone Lighting Lab implements USB and Bluetooth custom frames with independently written codecs and no Chroma dependency. It restores the previous effect after a test. Its macro-only patterns deliberately turn the other 18 zones off; preserving an existing animated background would require additional rendering/state work. USB/receiver mappings remain outside the app's current support.

The optional [Lighting Lab](LIGHTING_LAB.md) provides temporary whole-column and 19-zone pattern experiments, with exact-device/region restoration records and verified effect recovery. Macro-column isolation is now confirmed over USB and Bluetooth; the remaining generated patterns and interruption recovery still need observation. The optional Codex adapter now uses lifecycle hooks and a journaled status renderer; see [setup](CODEX_SETUP.md). Individual M1–M5 status lights should not be promised on this device based on the supported map.

## Reproducibility and provenance

The public Mac Chroma lighting engine resolves device manifests under `/synapse/products/<parent-product>/mw/lighting-manifests/DeviceManifest_<product>_<edition>.json`. The current engine's `getManifestData` uses parent product 708 for these variants.

| Official source | SHA-256 of downloaded artifact |
| --- | --- |
| [Bluetooth manifest 707](https://apps-mac.razer.com/synapse/products/708/mw/lighting-manifests/DeviceManifest_707_0.json) | `6f22027cb337fde6b9ae0dec56355a7f5403aef4f0c184a554fc6e99264d3dbe` |
| [USB manifest 708](https://apps-mac.razer.com/synapse/products/708/mw/lighting-manifests/DeviceManifest_708_0.json) | `becb755dda902061f4f7afebe83d04e76a3f98e6f4171795c26519a42e45a9c0` |
| [Receiver manifest 706](https://apps-mac.razer.com/synapse/products/708/mw/lighting-manifests/DeviceManifest_706_0.json) | `f0c2fc3cfd98f02ce14abcd76f60e4376ec2450a11af37c6e434df2fc86ed9e3` |
| [Lighting engine JavaScript](https://apps-mac.razer.com/synapse/lighting-engine/static/js/main.ac5078b4.js) | `17d8b2844b7ab1096bb574b9b8196fdacda0fb4307d01ba80a3a798eea406cc5` |
| [Studio JavaScript](https://apps-mac.razer.com/synapse/chroma-studio/static/js/main.a68256bf.js) | `913989a042a9aa69eacfb7411a54e3a887107f381a6ed1ac55a1dc04d07f44e0` |
| [Official Mac Chroma installer](https://dl.razerzone.com/drivers/Chroma/mac/RazerChromaInstaller.pkg), linked from [Razer's Mac page](https://www.razer.com/synapse-4-mac) | `bcb6def18b9a0954c9e2ce3b9fd3cd7741d4e71c8cd819bb842d1f0b530a9c91` |

The installer was downloaded and expanded for static inspection only. No installer scripts or vendor executables were run, no Chroma package was installed, and no driver/permission settings were changed. The initial static investigation made no lighting writes; the subsequent USB/Bluetooth Lighting Lab tests are recorded above. Raw vendor packages, JavaScript, manifests, and embedded diagrams remain under ignored `analysis/vendor/chroma-mac/`; they are not redistributed in this repository. The app has no new dependency. Documentation records independently summarized facts and provenance only.
