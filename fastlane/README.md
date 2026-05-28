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

### ios upload_release_metadata

```sh
[bundle exec] fastlane ios upload_release_metadata
```

Upload release metadata for the App Store version

### ios upload_release_build

```sh
[bundle exec] fastlane ios upload_release_build
```

Build and upload the current release build to App Store Connect

### ios submit_release

```sh
[bundle exec] fastlane ios submit_release
```

Submit the current App Store version for review using an existing processed build

### ios release_to_review

```sh
[bundle exec] fastlane ios release_to_review
```

Push metadata, upload build, and submit version for review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
