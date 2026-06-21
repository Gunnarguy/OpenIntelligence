#!/bin/sh

echo "Extracting latest version from CHANGELOG.md..."

# We search for the first heading starting with "## " followed by a number
# For example: "## 4.3.1 - Unreleased"
LATEST_VERSION=$(grep -m 1 "^## [0-9]" ../CHANGELOG.md | awk '{print $2}')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not extract version from CHANGELOG.md"
    exit 1
fi

echo "Latest version found: $LATEST_VERSION"

# Change directory to the project root
cd ..

# Use agvtool to bump the marketing version matching the changelog
xcrun agvtool new-marketing-version $LATEST_VERSION

echo "Successfully synchronized Xcode project version with CHANGELOG.md ($LATEST_VERSION)!"
