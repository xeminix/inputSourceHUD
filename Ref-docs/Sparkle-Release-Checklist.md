# Sparkle Release Checklist

## Current Integration

- Sparkle is integrated through Swift Package Manager.
- `Check for Updates…` is exposed in the menubar menu.
- Update preferences are exposed in `Settings > General > Updates`.
- Sparkle is intentionally inactive until these two build settings are filled:
  - `SPARKLE_APPCAST_URL`
  - `SPARKLE_PUBLIC_ED_KEY`

## Before First Public Release

1. Generate Sparkle keys.
   - Use Sparkle's `generate_keys` tool.
   - Store the private key safely.
   - Copy the public EdDSA key into `SPARKLE_PUBLIC_ED_KEY`.

2. Host an appcast.
   - Publish `appcast.xml` on your update server.
   - Set its URL in `SPARKLE_APPCAST_URL`.

3. Build and sign your release app.
   - Use your Developer ID signing identity.
   - Notarize the release.

4. Package the release.
   - A notarized `dmg` is supported and is the recommended website distribution format.
   - Sparkle can also update from `zip`.

5. Generate the appcast entry.
   - Put the release archive into your updates folder.
   - Run Sparkle's `generate_appcast` tool against that folder.

6. Upload both.
   - Upload the release archive.
   - Upload the updated `appcast.xml`.

## Notes

- The app currently defaults to automatic update checks being enabled.
- Automatic download is user-toggleable from settings.
- If `SPARKLE_APPCAST_URL` or `SPARKLE_PUBLIC_ED_KEY` is empty, the UI will show `Release Setup Required` and update checks stay disabled.
