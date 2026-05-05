# Releasing Clicky (GitHub Releases + Sparkle auto-update)

Clicky uses **Sparkle** for auto-updates. Releases are published via **GitHub Releases** and the app downloads the signed feed from:

`https://github.com/marcodetering-prog/clicky/releases/latest/download/appcast.xml`

## How updates work (DMG + auto-update)

- **Initial install:** distribute a DMG (drag to Applications).
- **Auto-updates:** Sparkle downloads a **zip** containing `Clicky.app` from GitHub Releases and applies the update (typically requires a relaunch).
- **Manual check:** click `Updates` in the Clicky panel footer to force an update check.

Note: For friends/public distribution where the app launches cleanly and auto-updates reliably, you generally need **Developer ID Application** signing + notarization (Apple Developer Program). Unsigned/dev-signed builds can trigger Gatekeeper warnings and may not update cleanly across machines.

## One-time setup

### 1) Sparkle EdDSA keys

The app must embed the public key in `leanring-buddy/Info.plist` (`SUPublicEDKey`).

Generate + export the private key (run locally on your Mac):

```bash
cd /Users/marcodetering/clicky
scripts/sparkle/download_sparkle_tools.sh >/dev/null

# Uses Keychain. Creates the key under the "clicky" account and exports it to a file.
sparkle_tools/2.9.1/bin/generate_keys --account clicky
sparkle_tools/2.9.1/bin/generate_keys --account clicky -x sparkle_private_key_clicky.txt
```

Then add the file contents of `sparkle_private_key_clicky.txt` to a GitHub Actions secret:
- `SPARKLE_ED25519_PRIVATE_KEY`

Do **not** commit the private key.

### 2) Apple Developer signing + notarization secrets

Add these GitHub Actions secrets:
- `MACOS_CERTIFICATE_P12_BASE64` (base64-encoded `.p12` for **Developer ID Application**)
- `MACOS_CERTIFICATE_P12_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

To create the **Developer ID Application** certificate:
1. Open Xcode → Settings → Accounts
2. Select your Apple ID and team
3. “Manage Certificates…” → `+` → “Developer ID Application”
4. Confirm you now see “Developer ID Application” in Keychain Access

To export it to a `.p12`:
1. Open Keychain Access → “My Certificates”
2. Find “Developer ID Application: …”
3. Right click → Export → `.p12` (set a strong password)
4. Base64 encode the file:

```bash
base64 -i /path/to/certificate.p12 | pbcopy
```

## Release

Create and push a tag:

```bash
cd /Users/marcodetering/clicky
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions builds a notarized `Clicky-<version>.zip`, generates a signed `appcast.xml`,
and attaches both to the GitHub Release.

## Test an update locally

1. Install an older version (from a DMG or by copying `Clicky.app` into `/Applications`).
2. Tag + push a new version.
3. Launch Clicky and click `Updates` (or wait for Sparkle’s scheduled check).
