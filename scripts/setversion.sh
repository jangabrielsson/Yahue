#!/bin/bash

# setversion.sh - Update version number in multiple files
# Usage: ./scripts/setversion.sh <new_version>
# Example: ./scripts/setversion.sh 0.0.1

set -e  # Exit on any error

# Get script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/project-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please create project-config.sh with your project settings."
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"

# Validate configuration
if ! validate_config; then
    echo "Error: Invalid configuration in $CONFIG_FILE"
    exit 1
fi

# Check if version argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.0.1"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (basic check for semantic versioning)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z (e.g., 0.0.1)"
    exit 1
fi

echo "Setting version to: $NEW_VERSION for $PROJECT_NAME"

# Update .version file (if configured)
if [ -n "$VERSION_FILE" ]; then
    echo "$NEW_VERSION" > "$VERSION_FILE"
    echo "✓ Updated $VERSION_FILE"
fi

# Update all configured source files
for file_config in "${VERSION_FILES[@]}"; do
    IFS=':' read -r filepath pattern <<< "$file_config"
    
    if [ -f "$filepath" ]; then
        # Check if the pattern exists in the file
        if grep -q "$pattern" "$filepath"; then
            sed -i.bak "s/${pattern} = \".*\"/${pattern} = \"$NEW_VERSION\"/" "$filepath"
            rm "${filepath}.bak"  # Remove backup file
            echo "✓ Updated $filepath"
        else
            echo "⚠ Warning: VERSION pattern '$pattern' not found in $filepath"
        fi
    else
        echo "⚠ Warning: $filepath not found"
    fi
done

echo ""
echo "Version update complete! 🎉"
echo "Files updated with version: $NEW_VERSION"

# Show what was changed
echo ""
echo "Changed files:"
if [ -n "$VERSION_FILE" ] && [ -f "$VERSION_FILE" ]; then
    echo "  $VERSION_FILE: $(cat "$VERSION_FILE")"
fi

for file_config in "${VERSION_FILES[@]}"; do
    IFS=':' read -r filepath pattern <<< "$file_config"
    if [ -f "$filepath" ] && grep -q "$pattern" "$filepath"; then
        echo "  $filepath: $(grep "$pattern" "$filepath")"
    fi
done

echo ""
echo "Version update complete! 🎉"
echo "Files updated with version: $NEW_VERSION"

# Show what was changed
echo ""
echo "Changed files:"
if [ -f ".version" ]; then
    echo "  .version: $(cat .version)"
fi
if [ -f "src/rule.lua" ] && grep -q "^local VERSION" src/rule.lua; then
    echo "  src/rule.lua: $(grep "^local VERSION" src/rule.lua)"
fi
if [ -f "src/eventrunner.lua" ] && grep -q "^local VERSION" src/eventrunner.lua; then
    echo "  src/eventrunner.lua: $(grep "^local VERSION" src/eventrunner.lua)"
fi
if [ -f "src/updater.lua" ] && grep -q "^local VERSION" src/updater.lua; then
    echo "  src/updater.lua: $(grep "^local VERSION" src/updater.lua)"
fi