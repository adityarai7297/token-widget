# Notarized Mac releases

For maintainers who ship Gatekeeper-friendly downloads.

## One-time setup

1. Install a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates, or [developer.apple.com](https://developer.apple.com/account/resources/certificates/add)).
2. Create an App Store Connect API key ([Integrations](https://appstoreconnect.apple.com/access/integrations/api)) and store a notary profile:

```bash
xcrun notarytool store-credentials "token-widget-notary" \
  --key /path/to/AuthKey_XXXXXX.p8 \
  --key-id XXXXXX \
  --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Ship a release

```bash
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
export NOTARY_PROFILE=token-widget-notary
export PUBLISH=1
export RELEASE_TAG=vX.Y.Z
./scripts/notarize-release.sh
```

Verify:

```bash
spctl --assess --type execute -v "/path/to/Token Widget.app"
# expected: accepted / source=Notarized Developer ID
```
