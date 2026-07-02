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

### ios build_and_upload

```sh
[bundle exec] fastlane ios build_and_upload
```

Archive + upload build to App Store Connect (no review submission)

### ios asc_status

```sh
[bundle exec] fastlane ios asc_status
```

Print current ASC version + build status

### ios set_app_privacy_and_rights

```sh
[bundle exec] fastlane ios set_app_privacy_and_rights
```

Set content rights declaration (no third-party content) via API

### ios create_subscriptions

```sh
[bundle exec] fastlane ios create_subscriptions
```

Create ASC subscriptions (group + monthly/yearly + localizations + prices)

### ios check_chn_price

```sh
[bundle exec] fastlane ios check_chn_price
```

TEMP: fix + check CHN subscription prices

### ios ci_build_and_upload

```sh
[bundle exec] fastlane ios ci_build_and_upload
```

CI: archive + upload to ASC (runs on a macOS runner with full Xcode)

### ios ci_release_and_submit

```sh
[bundle exec] fastlane ios ci_release_and_submit
```

CI: build + upload (wait for processing) + submit for review — full auto

### ios submit_version

```sh
[bundle exec] fastlane ios submit_version
```

Attach build + metadata to a version and submit for App Store review

### ios cancel_and_submit

```sh
[bundle exec] fastlane ios cancel_and_submit
```

Cancel the in-progress review submission, then submit for review

### ios upload_all_metadata

```sh
[bundle exec] fastlane ios upload_all_metadata
```

Upload all text metadata for all languages (no build, no screenshots, no submit)

### ios upload_release_notes

```sh
[bundle exec] fastlane ios upload_release_notes
```

Upload What's-New (release notes) for all languages to a specific version

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only (no metadata, no build)

### ios upload_all

```sh
[bundle exec] fastlane ios upload_all
```

Upload metadata + screenshots (no build, no review submission)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
