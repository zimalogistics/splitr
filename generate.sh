#!/bin/sh
# Generates the Xcode project and patches it for Xcode 15 compatibility
set -e
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Splitr.xcodeproj/project.pbxproj
echo "Done. Open Splitr.xcodeproj in Xcode."
