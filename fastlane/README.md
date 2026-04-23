fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app for App Store submission

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit to App Store Connect for review

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Build, upload, and submit the current App Store version for review

### ios submit_review_existing_build

```sh
[bundle exec] fastlane ios submit_review_existing_build
```

Submit the current App Store version for review using the latest uploaded build

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload to TestFlight

### ios bump

```sh
[bundle exec] fastlane ios bump
```

Increment build number

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push metadata to a draft App Store version (requires new version in ASC)

### ios metadata_live

```sh
[bundle exec] fastlane ios metadata_live
```

Update live App Store listing (description, keywords, promo text)

### ios validate

```sh
[bundle exec] fastlane ios validate
```

Validate app metadata and screenshots

### ios verify_iap

```sh
[bundle exec] fastlane ios verify_iap
```

Verify StoreKit products match subscription config

### ios iap_checklist

```sh
[bundle exec] fastlane ios iap_checklist
```

Print App Store Connect setup checklist for subscriptions

### ios verify_iap_live

```sh
[bundle exec] fastlane ios verify_iap_live
```

Verify products exist in App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
