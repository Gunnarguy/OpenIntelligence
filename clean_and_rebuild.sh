#!/bin/bash
# Clean and rebuild OpenIntelligence to force UI updates

echo "🧹 Cleaning build artifacts..."
cd "$(dirname "$0")"

# Clean Xcode build folder
xcodebuild -project OpenIntelligence.xcodeproj -scheme OpenIntelligence clean

# Remove derived data
echo "🗑️  Removing derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/OpenIntelligence-*

echo "✅ Clean complete! Now:"
echo "   1. DELETE the app from your simulator/device"
echo "   2. Run: ⌘R in Xcode"
