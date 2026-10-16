# DMGs, releases and startup

## Options without Apple Developer membership

- **Self-signed DMG:** the release workflow builds a universal app and optional helper and creates a draft GitHub release. A persistent private certificate signs every release. This lets the helper recognize updates from the same signer, but does not establish Apple trust. macOS may require Privacy & Security → Open Anyway for the app and helper installer, plus separate input permissions.
- **Build from source:** no GitHub signing secrets are needed. The build script creates a persistent private development certificate on that Mac. Preserve `build/local-signing/` across builds.
- **Developer ID and notarization later:** requires Apple Developer membership and Developer ID certificates. The current release workflow targets self-signed distribution, not notarization. A future route must sign all executables with hardened runtime/timestamps, sign installer packages with Developer ID Installer, notarize/staple the nested installers and final app/DMG, and check Gatekeeper on another Mac. Do not disable Gatekeeper globally.

Official references: [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [GitHub certificate import](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications). Self-signed downloads have more first-launch approval steps than notarized downloads.

## Install the current build from a DMG

```sh
ERGO_REUSE_HELPER=1 zsh tools/build_app.sh
zsh tools/build_dmg.sh
```

Reuse requires an existing app containing its working helper and installers. A fresh clone uses `zsh tools/build_app.sh` without that option. Packaging writes an ignored `dist/Ergo-Control-VERSION-ARCH.dmg` plus checksum; it never installs or launches the app/helper or changes permissions.

Quit Ergo Control through its menu bar, open the DMG, drag the app to Applications, eject the DMG, and open `/Applications/Ergo Control.app`. The image includes an Applications shortcut and Read me first.txt. Keep only one copy running.

Profiles and Codex settings stay under `~/Library/Application Support/ErgoControl/`. Hooks use the stable Application Support sender, not the checkout path. Startup preferences use the app's macOS preferences. Moving the app preserves those settings. A local DMG using the same certificate and reused helper should not require helper reinstallation; review permissions for the Applications copy if macOS asks again.

## GitHub signing secrets

The release workflow requires two repository **Actions secrets**:

| Secret | Value |
| --- | --- |
| `SIGNING_CERTIFICATE_P12_B64` | Base64 of a persistent code-signing certificate **and private key**, exported as password-protected P12 |
| `SIGNING_CERTIFICATE_PASSWORD` | Password chosen for that exported P12 |

Reuse this checkout's isolated certificate to preserve the existing signer. Run the following **yourself** in Terminal; it prompts for a new export password and does not upload anything:

```sh
python3 tools/export_signing_identity.py
```

It creates ignored `build/release-signing.p12`. Add the secrets with GitHub CLI:

```sh
base64 -i build/release-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12_B64 --repo serafinski/ergo-control
gh secret set SIGNING_CERTIFICATE_PASSWORD --repo serafinski/ergo-control
```

The second command prompts for the export password. Alternatively use repository Settings → Secrets and variables → Actions. Keep a secure backup of the identity; remove the temporary export after configuring secrets. Do not paste the P12, password or private key into chat, issues or commits. GitHub Actions will have a key that can sign app/helper updates; restrict repository write access accordingly. This self-signed route needs no Apple ID, Apple password, provisioning profile or custom GitHub token.

The workflow imports the persistent identity into an ephemeral keychain, selects it explicitly, and removes it in an always-run cleanup. Credentials are not logged or included in release artifacts. Public pull-request CI has no release secrets. A fresh certificate on every runner would break upgrade identity: the helper refuses replacement/removal by an unrelated signer. To intentionally change signer, remove the old helper using the old app first, then install the new one and review privacy permissions.

## Create a draft release

Update `VERSION` and `docs/RELEASE_NOTES.md`, commit, then create a matching tag:

```sh
git tag v0.7.5
git push origin v0.7.5
```

`.github/workflows/release.yml` tests, builds Apple Silicon + Intel app/hook/helper binaries, signs them, verifies the helper's accepted-client requirement, packages/verifies the DMG and writes a SHA-256 checksum. It creates a **draft** release with the DMG and checksum. You can also run it manually against an existing matching tag. It refuses a tag that disagrees with `VERSION` and never overwrites an existing release. Remove an unsuccessful draft deliberately before rerunning final release creation.

Review/download the draft and test installation, permission grants, optional helper installation, mappings, Codex hooks and login behavior before publishing. Compilation does not establish physical validation on Intel. The GitHub signing workflow has not yet been run with repository secrets. Ordinary local builds do not create tags or releases.

To check a universal build locally without replacing the daily app/helper:

```sh
ERGO_UNIVERSAL=1 ERGO_APP_PATH="$PWD/build/release-check/Ergo Control.app" zsh tools/build_app.sh
zsh tools/build_dmg.sh "$PWD/build/release-check/Ergo Control.app"
```

Universal builds rebuild their helper; reuse is refused. A new helper may need installation even with the same certificate because the client verifies its exact bundled helper hash.

## Repair early development installations

If Full dial control reports a bundled-helper conflict, choose **Repair helper startup…** and complete Installer before enabling mappings. Package 0.2.3 unregisters the old bundled route and uses a distinct local launchd label, preserving the installed executable and privacy identity. Copying a new app alone cannot replace an already registered system job. Installer-only rebuilds can use `ERGO_REUSE_HELPER=1 ERGO_REBUILD_PACKAGES=1 zsh tools/build_app.sh`; no helper binary rebuild is needed for that path.

## Startup

Use the installed app's **App** sidebar section:

- **Launch at login** registers the Applications copy using [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice). macOS may require approval in General → Login Items. The switch reflects actual registration status.
- **Enable mappings automatically** is saved immediately. At the next launch it connects the saved recovery endpoint immediately, or reacts to the paired keyboard appearing. It waits for permissions, keyboard connection, an idle configuration channel and verified recovery, then makes one activation attempt. There is no readiness expiry; an activation error requires manual retry. Stop mappings cancels a pending start. Sleep releases input; wake resumes if this option is on and mappings were active/preparing or awaiting automatic startup before sleep. A normal disconnection still stops mappings and requires manual activation.

Both switches default off. Keyboard startup does not require Codex or ChatGPT to be running. The optional Codex chat reader waits while the desktop is closed and reconnects automatically when it opens; its process launch and pipe I/O run off the keyboard/UI main thread. Codex connection/status-light options already persist and are used when mappings activate. Login launches request no settings window using the [documented login event](https://developer.apple.com/documentation/coreservices/keyaelaunchedasloginitem); manual launch still offers Settings. A full logout/login and sleep/wake need verification after installing in Applications. Closing Settings leaves the menu-bar app running; Quit restores the keyboard and exits.
