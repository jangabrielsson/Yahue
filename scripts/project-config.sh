#!/bin/bash

# Project Configuration for Release Scripts
# This file contains all project-specific settings that vary between projects.
# Copy this file to your other projects and modify the values accordingly.

# ============================================================================
# PROJECT IDENTIFICATION
# ============================================================================

# Project name (used in messages and titles)
PROJECT_NAME="Yahue"

# GitHub repository (format: owner/repo)
GITHUB_REPO="jangabrielsson/Yahue"

# Forum thread URL (optional - leave empty if not applicable)
FORUM_URL="https://forum.fibaro.com/topic/76207-yahuev2-yet-another-hue-app-using-hue-api-v2/#comment-282679"

# ============================================================================
# VERSION MANAGEMENT
# ============================================================================

# Version file location (relative to project root)
VERSION_FILE=".version"

# Source files that contain version declarations
# Format: "path:pattern" where pattern is the sed search pattern
# Example: "src/main.lua:^local VERSION"
declare -a VERSION_FILES=(
    "HueV2App.lua:^local VERSION"
)

# ============================================================================
# ARTIFACT GENERATION
# ============================================================================

# Directory for build artifacts (relative to project root)
DIST_DIR="dist"

# Artifacts to build
# Format: "source_file:output_file:build_command"
# The build_command can use {SOURCE} and {OUTPUT} placeholders
declare -a ARTIFACTS=(
    "HueV2QA.lua:dist/Yahue.fqa:plua -t pack {SOURCE} {OUTPUT}"
)

# Files to include in git commits for releases
declare -a RELEASE_FILES=(
    ".version"
    "CHANGELOG.md"
    "HueV2App.lua"
    "HueV2Engine.lua"
    "HueV2File.lua"
    "HueV2Map.lua"
    "HueV2QA.lua"
    "dist/Yahue.fqa"
)

# ============================================================================
# DOCUMENTATION
# ============================================================================

# Directory for release notes/forum posts (relative to project root)
NOTES_DIR="doc/notes"

# Main documentation file
DOCUMENTATION_URL="https://github.com/$GITHUB_REPO/blob/main/README.md"

# ============================================================================
# RELEASE CUSTOMIZATION
# ============================================================================

# Commit message template for releases
# Variables: {VERSION}, {NOTES}
RELEASE_COMMIT_TEMPLATE="chore: release v{VERSION}

- Update version to {VERSION} in all files
- Update CHANGELOG.md with release notes
- Generate release artifacts"

# Tag message template
# Variables: {VERSION}, {NOTES}
TAG_MESSAGE_TEMPLATE="Release v{VERSION}

{NOTES}"

# ============================================================================
# OPTIONAL HOOKS
# ============================================================================

# Pre-release hook (optional) - runs before any release operations
# Uncomment and customize if needed
# pre_release_hook() {
#     echo "Running pre-release checks..."
#     # Add your custom checks here
#     return 0
# }

# Post-release hook (optional) - runs after successful release
# Uncomment and customize if needed
# post_release_hook() {
#     local version=$1
#     echo "Running post-release actions for v$version..."
#     # Add your custom actions here
#     return 0
# }

# Artifact build hook (optional) - custom artifact generation
# Uncomment and customize if needed
# custom_artifact_build() {
#     echo "Building custom artifacts..."
#     # Add your custom build commands here
#     return 0
# }

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get artifact file names (for uploading to GitHub releases)
get_artifact_files() {
    local files=()
    for artifact in "${ARTIFACTS[@]}"; do
        IFS=':' read -r source output command <<< "$artifact"
        if [ -f "$output" ]; then
            files+=("$output")
        fi
    done
    echo "${files[@]}"
}

# Get artifact base names (for display)
get_artifact_names() {
    local names=()
    for artifact in "${ARTIFACTS[@]}"; do
        IFS=':' read -r source output command <<< "$artifact"
        names+=("$(basename "$output")")
    done
    echo "${names[@]}"
}

# Validate configuration
validate_config() {
    local errors=0
    
    if [ -z "$PROJECT_NAME" ]; then
        echo "Error: PROJECT_NAME is not set"
        ((errors++))
    fi
    
    if [ -z "$GITHUB_REPO" ]; then
        echo "Error: GITHUB_REPO is not set"
        ((errors++))
    fi
    
    if [ -z "$VERSION_FILE" ]; then
        echo "Error: VERSION_FILE is not set"
        ((errors++))
    fi
    
    return $errors
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

# Export functions so they can be used by other scripts
export -f get_artifact_files
export -f get_artifact_names
export -f validate_config
