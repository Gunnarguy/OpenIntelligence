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

# Update the global MARKETING_VERSION (used for iOS) with sed. 
# This strictly matches "MARKETING_VERSION = x.y.z;" to avoid breaking macOS specific overrides like "MARKETING_VERSION[sdk=macosx*]" = 1.0;
sed -i '' -E "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $LATEST_VERSION;/g" OpenIntelligence.xcodeproj/project.pbxproj

echo "Successfully synchronized Xcode project version with CHANGELOG.md ($LATEST_VERSION) while preserving macOS version target!"
