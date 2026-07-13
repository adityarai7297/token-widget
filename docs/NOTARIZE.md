# Notarized Mac releases (Gatekeeper-friendly)

Public downloads open cleanly on macOS only when the app is signed with a
**Developer ID Application** certificate and **notarized** by Apple.

## One-time setup

### 1. Developer ID certificate

You currently need a **Developer ID Application** cert (not “Apple Development”).

**Option A — Xcode (easiest)**

1. Open **Xcode → Settings → Accounts**
2. Select your team → **Manage Certificates…**
3. Click **+** → **Developer ID Application**
4. Confirm Keychain Access shows:  
   `Developer ID Application: Your Name (TEAMID)`

**Option B — Developer portal + CSR**

1. Open [Create a new certificate](https://developer.apple.com/account/resources/certificates/add)
2. Choose **Developer ID Application**
3. Upload  
   `build/signing/TokenWidget_DeveloperID.certSigningRequest`  
   (generated locally; not committed)
4. Download the `.cer` and double-click to install into **login** keychain

### 2. Notary credentials (App Store Connect API key)

1. [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api)
2. Create a key with **Developer** access (or Admin)
3. Download `AuthKey_XXXXXX.p8` once
4. Copy the **Issuer ID** (UUID at the top of that page) and **Key ID**

Store a reusable profile:

```bash
xcrun notarytool store-credentials "token-widget-notary" \
  --key ~/Downloads/AuthKey_XXXXXX.p8 \
  --key-id XXXXXX \
  --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Build + notarize + publish

```bash
export DEVELOPMENT_TEAM=XK6AQX4LZN
export NOTARY_PROFILE=token-widget-notary
export PUBLISH=1
export RELEASE_TAG=v1.2.1
./scripts/notarize-release.sh
```

Or pass the API key directly:

```bash
export APPLE_API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_7V5M44TZCG.p8"
export APPLE_API_KEY_ID=7V5M44TZCG
export APPLE_API_ISSUER="your-issuer-uuid-here"
export PUBLISH=1 RELEASE_TAG=v1.2.1
./scripts/notarize-release.sh
```

Output: `build/release/Token-Widget-macOS.zip` (stapled). Users can open it without right-click → Open.

## Verify

```bash
spctl --assess --type execute -v "/path/to/Token Widget.app"
# expected: accepted / source=Notarized Developer ID
```
