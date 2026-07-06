#!/bin/sh
# Xcode Cloud runs this immediately after cloning the repo, before it resolves
# Swift packages and builds. This project uses XcodeGen: Bike.xcodeproj is
# generated from project.yml and is intentionally gitignored, so a fresh clone
# has no .xcodeproj. Without this step Xcode Cloud fails with
# "Bike.xcodeproj does not exist at the root of the repository".
set -e
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

# Install XcodeGen (Homebrew is preinstalled on Xcode Cloud runners).
which xcodegen >/dev/null 2>&1 || brew install xcodegen

# Generate Bike.xcodeproj at the repo root from project.yml.
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "ci_post_clone: generated Bike.xcodeproj"
