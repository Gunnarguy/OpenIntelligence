# Release Checklist

## Pre-Release Validation

### Code Quality
- [ ] All tests pass (`⌘U` in Xcode)
- [ ] No compiler warnings (treat warnings as errors)
- [ ] SwiftLint passes with zero violations
- [ ] Secret scan passes (`python3 scripts/secret_scan.py`)
- [ ] No `// TODO:` or `// FIXME:` comments in release code

### Smoke Test
Follow [smoke_test.md](../../smoke_test.md):
- [ ] Fresh install on simulator (iPhone 17 Pro Max)
- [ ] Ingest `TestDocuments/sample_technical.md`
- [ ] Query "What is covered?" and verify relevant response
- [ ] Telemetry badges show Vector and BM25 hits
- [ ] Export conversation works
- [ ] Settings toggles persist across app restarts

### Privacy & Compliance
- [ ] `PRIVACY.md` is current and matches app behavior
- [ ] Cloud transmission consent flow works correctly
- [ ] All network calls respect `SettingsStore.allowCloudTransmission`
- [ ] No user data logged in release builds (`Log.debug` stripped)

### StoreKit
- [ ] Products load from App Store (or StoreKit Config for sandbox)
- [ ] Pro tier purchase flow completes
- [ ] Document Pack add-on grants correct limits
- [ ] Restore purchases works for prior subscribers
- [ ] Preview tickets decrement correctly
- [ ] Quota enforcement blocks at limits

### Performance
- [ ] Ingestion of 10-page PDF < 30 seconds
- [ ] Query response time < 5 seconds
- [ ] Memory usage < 500MB during normal operation
- [ ] No main-thread blocking (use Instruments Time Profiler)

---

## Version Bump

### Semantic Versioning
- **MAJOR**: Breaking API/UX changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, no new features

### Update Version Numbers

1. **Info.plist** (Xcode → Project → Target → General)
   - `CFBundleShortVersionString`: `X.Y.Z`
   - `CFBundleVersion`: Build number (increment each submission)

2. **CHANGELOG.md**
   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD
   ### Added
   - Feature description
   ### Fixed
   - Bug fix description
   ### Changed
   - Modification description
   ```

---

## Archive & Submission

### Create Archive

```bash
# Build for distribution
xcodebuild archive \
  -scheme OpenIntelligence \
  -archivePath ./build/OpenIntelligence.xcarchive \
  -destination 'generic/platform=iOS'

# Export IPA
xcodebuild -exportArchive \
  -archivePath ./build/OpenIntelligence.xcarchive \
  -exportPath ./build/Export \
  -exportOptionsPlist Docs/reference/exportOptions.plist
```

### Pre-Submission Checks
- [ ] Archive builds without errors
- [ ] App thinning report shows acceptable sizes
- [ ] No missing entitlements warnings

### App Store Connect
1. Upload via Xcode Organizer or `altool`
2. Wait for processing (5-15 minutes)
3. Select build for submission
4. Complete App Store metadata:
   - [ ] Screenshots (all device sizes)
   - [ ] App description and keywords
   - [ ] Privacy policy URL
   - [ ] Support URL
   - [ ] What's New text
5. Submit for review

---

## Post-Release

### Monitor
- [ ] Check App Store Connect for rejection feedback
- [ ] Monitor crash reports in Xcode Organizer
- [ ] Review user feedback in App Store reviews
- [ ] Watch for memory/CPU spikes in analytics

### Rollback Plan
If critical issues found:
1. Expedited review request for hotfix
2. Or: Remove current version from sale
3. Document issue in `CHANGELOG.md` under Hotfix section

---

## Automation Scripts

### Preflight Check
```bash
./scripts/preflight_check.sh
```
Validates:
- Build succeeds
- No compiler warnings
- Secret scan passes

### Package for Submission
```bash
./scripts/package_submission.sh
```
Creates:
- Archived `.xcarchive`
- Exported `.ipa`
- Symbols for crash reporting

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.0.0 | TBD | Initial App Store release |
