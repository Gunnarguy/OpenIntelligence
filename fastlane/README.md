# fastlane

Automates App Store submission for OpenIntelligence.

## Available Lanes

| Lane | Description |
|------|-------------|
| `fastlane beta` | Build and upload to TestFlight |
| `fastlane release` | Build and upload to App Store Connect |
| `fastlane build` | Build IPA only (no upload) |
| `fastlane bump` | Increment build number |
| `fastlane validate` | Validate metadata without uploading |

## Quick Start

### First-Time Setup

1. **Authenticate with App Store Connect:**
   ```bash
   fastlane spaceauth -u gunnarhostetler@icloud.com
   ```
   This caches your session for CI/CD.

2. **Or use API Key (recommended for CI):**
   Create an API key in App Store Connect → Users & Access → Integrations → App Store Connect API.
   Save as `fastlane/api_key.json`:
   ```json
   {
     "key_id": "YOUR_KEY_ID",
     "issuer_id": "YOUR_ISSUER_ID",
     "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
   }
   ```

### Submit to TestFlight

```bash
fastlane beta
```

### Submit for App Store Review

```bash
fastlane release
```

## Metadata

All App Store metadata lives in `fastlane/metadata/en-US/`:

- `name.txt` - App name (30 chars max)
- `subtitle.txt` - Subtitle (30 chars max)
- `description.txt` - Full description
- `keywords.txt` - Search keywords (100 chars, comma-separated)
- `promotional_text.txt` - Promo text (170 chars, can update without review)
- `release_notes.txt` - What's New
- `privacy_url.txt` - Privacy policy URL
- `support_url.txt` - Support URL

## Screenshots

Place screenshots in `fastlane/screenshots/en-US/`:
- iPhone 6.9": `iPhone 16 Pro Max-*.png`
- iPhone 6.3": `iPhone 16 Pro-*.png`
- iPad Pro 13": `iPad Pro 13-*.png`

## Troubleshooting

**"Multiple teams found"** - Ensure `itc_team_id` is set in Appfile.

**"No valid iOS distribution certificate"** - Open Xcode → Settings → Accounts → Manage Certificates.

**App Store Connect 2FA** - Use `fastlane spaceauth` or API keys.
