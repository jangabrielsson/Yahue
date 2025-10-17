#!/bin/bash

# create-release.sh - Automated release creation script
# Creates GitHub releases with version bumping, changelog updates, and artifact generation
# 
# Features:
# - Updates version numbers in source files
# - Generates changelog from git commits
# - Creates artifacts in dist/
# - Creates git tag and pushes to remote
# - Creates GitHub release with artifacts attached
# - Uploads artifact files automatically
# - GitHub automatically generates source code archives
#
# Usage:
#   ./scripts/create-release.sh              # Interactive release creation
#   ./scripts/create-release.sh --preview    # Preview release notes without creating release
#   ./scripts/create-release.sh --dry-run    # Same as --preview

set -e  # Exit on any error

# Get script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/project-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please create project-config.sh with your project settings."
    echo "See project-config.sh.example for a template."
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"

# Validate configuration
if ! validate_config; then
    echo "Error: Invalid configuration in $CONFIG_FILE"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get current version
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" | tr -d '\n'
    else
        echo "0.0.0"
    fi
}

# Function to increment version
increment_version() {
    local version=$1
    local type=$2
    
    IFS='.' read -ra PARTS <<< "$version"
    local major=${PARTS[0]}
    local minor=${PARTS[1]}
    local patch=${PARTS[2]}
    
    case $type in
        "patch")
            patch=$((patch + 1))
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to check git status
check_git_status() {
    info "Checking git repository status..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository!"
        exit 1
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        error "You have uncommitted changes. Please commit or stash them first."
        git status --porcelain
        exit 1
    fi
    
    # Check if we're ahead of remote (unpushed commits)
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "")
    
    if [ -n "$remote_commit" ] && [ "$local_commit" != "$remote_commit" ]; then
        if ! git merge-base --is-ancestor "$local_commit" "$remote_commit"; then
            error "Your branch is behind the remote. Please pull first."
            exit 1
        fi
        
        error "You have unpushed commits. Please push them first before creating a release."
        echo "Unpushed commits:"
        git log --oneline "$remote_commit..HEAD"
        exit 1
    fi
    
    success "Git repository is clean and up-to-date"
}

# Function to check required tools
check_dependencies() {
    info "Checking required dependencies..."
    
    local missing_deps=()
    
    if ! command_exists "git"; then
        missing_deps+=("git")
    fi
    
    if ! command_exists "plua"; then
        missing_deps+=("plua")
    fi
    
    if ! command_exists "gh"; then
        missing_deps+=("gh (GitHub CLI)")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "To install missing dependencies:"
        echo "  - git: https://git-scm.com/downloads"
        echo "  - plua: https://github.com/jangabrielsson/plua"
        echo "  - gh: https://cli.github.com/ or 'brew install gh'"
        exit 1
    fi
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    success "All dependencies available"
}

# Function to get last release tag
get_last_release_tag() {
    git describe --tags --abbrev=0 2>/dev/null || echo ""
}

# Function to generate release notes from commits
generate_release_notes() {
    local last_tag=$1
    local new_version=$2
    
    # Don't use info() here as it might be captured
    
    local commit_range
    if [ -n "$last_tag" ]; then
        commit_range="$last_tag..HEAD"
    else
        commit_range="HEAD"
    fi
    
    local notes="## Changes in v$new_version\n\n"
    
    # Get commit messages and format them
    local commits
    # Use a custom format to separate subject and body clearly
    commits=$(git log $commit_range --pretty=format:"COMMIT_START%s%nCOMMIT_BODY%b%nCOMMIT_END" --no-merges)
    
    if [ -n "$commits" ]; then
        # Process each commit message
        local current_subject=""
        local current_body=""
        local in_body=false
        
        while IFS= read -r line; do
            if [[ $line == COMMIT_START* ]]; then
                # New commit starts
                current_subject="${line#COMMIT_START}"
                current_body=""
                in_body=false
            elif [[ $line == COMMIT_BODY* ]]; then
                # Body section starts - capture any content after COMMIT_BODY
                in_body=true
                body_start="${line#COMMIT_BODY}"
                # Don't capture initial body content here, let it be processed 
                # through the normal body line processing to ensure consistent formatting
                if [ -n "$body_start" ]; then
                    # Add the initial body content as if it were a separate line
                    if [ -n "$current_body" ]; then
                        current_body="$current_body\n$body_start"
                    else
                        current_body="$body_start"
                    fi
                fi
            elif [[ $line == "COMMIT_END" ]]; then
                # Commit ends, process it
                
                # Simple approach: split on common tag boundaries  
                # Replace " fix:" " feat:" etc. with newlines, then process each line
                local split_subject=$(printf "%s" "$current_subject" | sed 's/ \(feat\|fix\|docs\|refactor\|test\):/\n\1:/g')
                
                # Process each line
                while IFS= read -r subject_line; do
                    if [[ -n "$subject_line" && "$subject_line" != " " ]]; then
                        local commit_type_prefix=""
                        local commit_title="$subject_line"
                        
                        # Determine commit type and format
                        if [[ $subject_line == feat:* ]]; then
                            commit_type_prefix="- ✨ **Feature**: "
                            commit_title="${subject_line#feat: }"
                        elif [[ $subject_line == fix:* ]]; then
                            commit_type_prefix="- 🐛 **Fix**: "
                            commit_title="${subject_line#fix: }"
                        elif [[ $subject_line == docs:* ]]; then
                            commit_type_prefix="- 📚 **Docs**: "
                            commit_title="${subject_line#docs: }"
                        elif [[ $subject_line == refactor:* ]]; then
                            commit_type_prefix="- ♻️ **Refactor**: "
                            commit_title="${subject_line#refactor: }"
                        elif [[ $subject_line == test:* ]]; then
                            commit_type_prefix="- 🧪 **Test**: "
                            commit_title="${subject_line#test: }"
                        else
                            commit_type_prefix="- ✨ **Feature**: "
                            commit_title="$subject_line"
                        fi
                        
                        # Clean up the title and add it
                        commit_title=$(echo "$commit_title" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        if [[ -n "$commit_title" ]]; then
                            notes+="$commit_type_prefix$commit_title\n"
                        fi
                    fi
                done <<< "$split_subject"
                
                # Add body details if they exist
                if [ -n "$current_body" ] && [ "$current_body" != " " ]; then
                    # Use a temporary file to process body lines and avoid subshell issues
                    temp_file=$(mktemp)
                    echo -e "$current_body" > "$temp_file"
                    
                    while IFS= read -r body_line; do
                        # Skip empty lines
                        if [ -n "$body_line" ] && [ "$body_line" != " " ]; then
                            # Remove leading/trailing whitespace
                            body_line=$(echo "$body_line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                            if [ -n "$body_line" ]; then
                                # Check if this line is a tagged item (starts with tag:)
                                local line_type_prefix=""
                                local line_title="$body_line"
                                
                                if [[ $body_line == feat:* ]]; then
                                    line_type_prefix="- ✨ **Feature**: "
                                    line_title="${body_line#feat: }"
                                elif [[ $body_line == fix:* ]]; then
                                    line_type_prefix="- 🐛 **Fix**: "
                                    line_title="${body_line#fix: }"
                                elif [[ $body_line == docs:* ]]; then
                                    line_type_prefix="- 📚 **Docs**: "
                                    line_title="${body_line#docs: }"
                                elif [[ $body_line == refactor:* ]]; then
                                    line_type_prefix="- ♻️ **Refactor**: "
                                    line_title="${body_line#refactor: }"
                                elif [[ $body_line == test:* ]]; then
                                    line_type_prefix="- 🧪 **Test**: "
                                    line_title="${body_line#test: }"
                                else
                                    # Regular body line - treat as sub-item
                                    if [[ $body_line == -* ]]; then
                                        # It's already a bullet point, just indent it
                                        notes+="  $body_line\n"
                                    else
                                        # Add bullet point and indent
                                        notes+="  - $body_line\n"
                                    fi
                                    continue
                                fi
                                
                                # Add tagged line as main-level item
                                notes+="$line_type_prefix$line_title\n"
                            fi
                        fi
                    done < "$temp_file"
                    
                    rm "$temp_file"
                fi
                
                # Reset for next commit
                current_subject=""
                current_body=""
                in_body=false
            elif [ "$in_body" = true ]; then
                # Accumulate body lines
                if [ -n "$current_body" ]; then
                    current_body="$current_body\n$line"
                else
                    current_body="$line"
                fi
            fi
        done <<< "$commits"
    else
        notes+="- No new commits since last release\n"
    fi
    
    notes+="\n\n*Generated automatically from git commits*"
    
    echo -e "$notes"
}

# Function to update changelog
update_changelog() {
    local version=$1
    local release_notes=$2
    
    info "Updating CHANGELOG.md..."
    
    local temp_file=$(mktemp)
    local date=$(date '+%Y-%m-%d')
    
    # Create new changelog entry
    echo "# Changelog" > "$temp_file"
    echo "" >> "$temp_file"
    echo "## [v$version] - $date" >> "$temp_file"
    echo "" >> "$temp_file"
    echo -e "$release_notes" >> "$temp_file"
    echo "" >> "$temp_file"
    
    # Append existing changelog if it exists and has content
    if [ -s "CHANGELOG.md" ] && [ "$(head -1 CHANGELOG.md)" != "# Changelog" ]; then
        echo "# Changelog" > CHANGELOG.md
        echo "" >> CHANGELOG.md
    fi
    
    if [ -s "CHANGELOG.md" ]; then
        # Skip the first two lines (# Changelog and empty line) if they exist
        if head -1 CHANGELOG.md | grep -q "# Changelog"; then
            tail -n +3 CHANGELOG.md >> "$temp_file"
        else
            cat CHANGELOG.md >> "$temp_file"
        fi
    fi
    
    mv "$temp_file" CHANGELOG.md
    success "Updated CHANGELOG.md"
}

# Function to create artifacts
create_artifacts() {
    info "Creating release artifacts..."
    
    # Create dist directory if it doesn't exist
    mkdir -p "$DIST_DIR"
    
    # Build each configured artifact
    for artifact in "${ARTIFACTS[@]}"; do
        IFS=':' read -r source output command <<< "$artifact"
        
        if [ -f "$source" ]; then
            info "Creating $output..."
            
            # Replace placeholders in command
            build_cmd="${command//\{SOURCE\}/$source}"
            build_cmd="${build_cmd//\{OUTPUT\}/$output}"
            
            # Execute the build command
            if eval "$build_cmd"; then
                success "Created $output"
            else
                warning "Failed to create $output"
            fi
        else
            warning "$source not found, skipping $output"
        fi
    done
    
    # Call custom artifact build hook if defined
    if declare -f custom_artifact_build >/dev/null; then
        custom_artifact_build
    fi
}

# Function to commit and push changes
commit_and_push() {
    local version=$1
    
    info "Committing release changes..."
    
    # Add all configured release files
    for file in "${RELEASE_FILES[@]}"; do
        if [ -f "$file" ]; then
            git add "$file"
        fi
    done
    
    # Format commit message from template
    local commit_msg="${RELEASE_COMMIT_TEMPLATE//\{VERSION\}/$version}"
    
    # Commit the changes
    git commit -m "$commit_msg"
    
    success "Committed release changes"
    
    info "Pushing changes to remote..."
    # Push changes
    git push origin $(git branch --show-current)
    
    success "Pushed all changes to remote"
}

# Function to create and push tag
create_and_push_tag() {
    local version=$1
    local release_notes=$2
    
    info "Creating and pushing release tag..."
    
    # Format tag message from template
    local tag_msg="${TAG_MESSAGE_TEMPLATE//\{VERSION\}/$version}"
    tag_msg="${tag_msg//\{NOTES\}/$release_notes}"
    
    # Create annotated tag with release notes
    git tag -a "v$version" -m "$tag_msg"
    
    # Push the tag
    git push origin "v$version"
    
    success "Created and pushed tag v$version"
}

# Function to create GitHub release with artifacts
create_github_release() {
    local version=$1
    local release_notes=$2
    
    info "Creating GitHub release with artifacts..."
    
    # Prepare release notes for GitHub (escape special characters)
    local gh_notes
    gh_notes=$(printf '%s' "$release_notes" | sed 's/"/\\"/g')
    
    # Create the release
    local release_url
    release_url=$(gh release create "v$version" \
        --title "Release v$version" \
        --notes "$gh_notes" \
        --verify-tag)
    
    if [ $? -eq 0 ]; then
        success "Created GitHub release: $release_url"
    else
        error "Failed to create GitHub release"
        return 1
    fi
    
    # Get list of artifact files to upload
    local artifact_files=($(get_artifact_files))
    
    if [ ${#artifact_files[@]} -gt 0 ]; then
        info "Uploading release artifacts..."
        
        for artifact in "${artifact_files[@]}"; do
            info "Uploading $artifact..."
            if gh release upload "v$version" "$artifact"; then
                success "Uploaded $artifact"
            else
                warning "Failed to upload $artifact"
            fi
        done
    else
        warning "No artifacts found to upload"
    fi
    
    # The source code archives (zip and tar.gz) are automatically created by GitHub
    info "Source code archives will be automatically generated by GitHub"
    
    success "GitHub release created successfully!"
    local repo_info=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
    info "Release URL: https://github.com/$repo_info/releases/tag/v$version"
    
    # Generate forum post content
    info "📝 Generating forum post..."
    mkdir -p "$NOTES_DIR"
    ./scripts/forum-post-generator.sh "$version" "$release_notes"
    
    # Open the forum post directly in browser
    if command -v open >/dev/null 2>&1; then
        open "$NOTES_DIR/release-v$version.html"
        info "🌐 Forum post opened in your default browser"
    elif command -v code >/dev/null 2>&1; then
        code "$NOTES_DIR/release-v$version.html"
        info "📝 File opened in VS Code"
    else
        info "💡 Open $NOTES_DIR/release-v$version.html in your browser"
    fi
    
    info "📖 Forum post available at: $NOTES_DIR/release-v$version.html"
    if [ -n "$FORUM_URL" ]; then
        info "📋 Ready to copy and paste to $FORUM_URL"
    fi
}

# Function to preview release notes without creating a release
preview_release() {
    echo -e "${CYAN}[INFO] 📋 Release Preview Mode${NC}"
    echo ""
    
    # Check dependencies (but not git status since we're just previewing)
    check_dependencies
    
    # Get current version
    local current_version=$(get_current_version)
    info "Current version: $current_version"
    
    # Get last release tag
    local last_tag=$(get_last_release_tag)
    if [ -z "$last_tag" ]; then
        warning "No previous releases found. Will show all commits."
        last_tag="(none)"
    else
        info "Last release: $last_tag"
    fi
    
    # Check if there are any commits since last release
    local commit_range
    if [ "$last_tag" = "(none)" ]; then
        commit_range="HEAD"
    else
        commit_range="$last_tag..HEAD"
    fi
    
    local commits_count
    if [ "$last_tag" = "(none)" ]; then
        commits_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    else
        commits_count=$(git rev-list --count $commit_range 2>/dev/null || echo "0")
    fi
    
    info "Commits since last release: $commits_count"
    echo ""
    
    if [ "$commits_count" -eq 0 ]; then
        warning "No new commits since last release. Nothing to release."
        return 0
    fi
    
    # Show what the next versions would be
    echo -e "${BLUE}Next version options:${NC}"
    echo "  Patch: $current_version → $(increment_version $current_version patch)"
    echo "  Minor: $current_version → $(increment_version $current_version minor)"
    echo "  Major: $current_version → $(increment_version $current_version major)"
    echo ""
    
    # Generate release notes for each version type
    for version_type in "patch" "minor" "major"; do
        local next_version=$(increment_version $current_version $version_type)
        echo -e "${YELLOW}=== Release Notes for v$next_version ($version_type) ===${NC}"
        
        local release_notes
        if [ "$last_tag" = "(none)" ]; then
            release_notes=$(generate_release_notes "" "$next_version")
        else
            release_notes=$(generate_release_notes "$last_tag" "$next_version")
        fi
        
        echo -e "$release_notes"
        echo ""
    done
    
    # Show recent commits for context
    echo -e "${BLUE}Recent commits that would be included:${NC}"
    if [ "$last_tag" = "(none)" ]; then
        git log --oneline -10
    else
        git log --oneline $commit_range
    fi
    echo ""
    
    success "Preview complete! Use './scripts/create-release.sh' to create an actual release."
    info "The release will include:"
    info "  • Git tag with release notes"
    info "  • GitHub release page with artifacts"
    info "  • Automatic source code archives (zip/tar.gz)"
    info "  • EventRunner6.fqa and ERUpdater.fqa attachments"
}

# Main function
main() {
    echo -e "${CYAN}[INFO] 🚀 GitHub Release Helper for $PROJECT_NAME${NC}"
    echo ""
    
    # Call pre-release hook if defined
    if declare -f pre_release_hook >/dev/null; then
        info "Running pre-release hook..."
        if ! pre_release_hook; then
            error "Pre-release hook failed"
            exit 1
        fi
    fi
    
    # Check dependencies and git status
    check_dependencies
    check_git_status
    
    # Get current version
    local current_version=$(get_current_version)
    info "Current version: $current_version"
    
    # Version selection
    echo ""
    echo "Select version bump type:"
    echo "1) Patch ($current_version → $(increment_version $current_version patch))"
    echo "2) Minor ($current_version → $(increment_version $current_version minor))"
    echo "3) Major ($current_version → $(increment_version $current_version major))"
    echo "4) Custom version"
    echo ""
    
    local new_version
    while true; do
        read -p "Choice (1-4): " choice
        case $choice in
            1)
                new_version=$(increment_version $current_version patch)
                break
                ;;
            2)
                new_version=$(increment_version $current_version minor)
                break
                ;;
            3)
                new_version=$(increment_version $current_version major)
                break
                ;;
            4)
                read -p "Enter custom version (X.Y.Z): " new_version
                if [[ $new_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    break
                else
                    error "Invalid version format. Please use X.Y.Z format."
                fi
                ;;
            *)
                error "Invalid choice. Please select 1-4."
                ;;
        esac
    done
    
    # Release notes selection
    echo ""
    echo "Release notes options:"
    echo "1) Auto-generate from git commits since last release"
    echo "2) Enter custom release notes"
    echo "3) Use simple default message"
    echo ""
    
    local release_notes
    while true; do
        read -p "Choice (1-3): " notes_choice
        case $notes_choice in
            1)
                local last_tag=$(get_last_release_tag)
                if [ -z "$last_tag" ]; then
                    warning "No previous releases found. Generating from all commits."
                else
                    info "Generating release notes from commits since $last_tag..."
                fi
                release_notes=$(generate_release_notes "$last_tag" "$new_version")
                break
                ;;
            2)
                echo "Enter release notes (press Ctrl+D when finished):"
                release_notes=$(cat)
                break
                ;;
            3)
                release_notes="Release v$new_version

This release includes various improvements and bug fixes."
                break
                ;;
            *)
                error "Invalid choice. Please select 1-3."
                ;;
        esac
    done
    
    # Show generated release notes and confirm
    echo ""
    info "Generated release notes:"
    echo -e "$release_notes"
    echo ""
    
    read -p "Use these release notes? (Y/n): " confirm_notes
    if [[ $confirm_notes =~ ^[nN]$ ]]; then
        echo "Enter custom release notes (press Ctrl+D when finished):"
        release_notes=$(cat)
    fi
    
    # Final confirmation
    echo ""
    info "📋 Release Summary:"
    echo "  Version: $new_version"
    echo "  Notes: $release_notes"
    echo ""
    
    read -p "Create this release? (y/N): " final_confirm
    if [[ ! $final_confirm =~ ^[yY]$ ]]; then
        info "Release cancelled."
        exit 0
    fi
    
    # Execute release steps
    echo ""
    info "🚀 Creating release v$new_version..."
    echo ""
    
    # Step 1: Update version in files
    info "Step 1: Updating version in source files..."
    ./scripts/setversion.sh "$new_version"
    
    # Step 2: Update changelog
    info "Step 2: Updating CHANGELOG.md..."
    update_changelog "$new_version" "$release_notes"
    
    # Step 3: Create artifacts
    info "Step 3: Creating release artifacts..."
    create_artifacts
    
    # Step 4: Commit and push all changes
    info "Step 4: Committing and pushing changes..."
    commit_and_push "$new_version"
    
    # Step 5: Create and push tag
    info "Step 5: Creating and pushing release tag..."
    create_and_push_tag "$new_version" "$release_notes"
    
    # Step 6: Create GitHub release with artifacts
    info "Step 6: Creating GitHub release with artifacts..."
    create_github_release "$new_version" "$release_notes"
    
    echo ""
    success "🎉 Release v$new_version created successfully!"
    local repo_info=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
    info "GitHub release: https://github.com/$repo_info/releases/tag/v$new_version"
    
    # Show uploaded artifacts
    local artifact_names=($(get_artifact_names))
    if [ ${#artifact_names[@]} -gt 0 ]; then
        info "Artifacts uploaded: ${artifact_names[*]}"
    fi
    info "Source archives automatically generated by GitHub"
    
    # Call post-release hook if defined
    if declare -f post_release_hook >/dev/null; then
        info "Running post-release hook..."
        post_release_hook "$new_version"
    fi
}

# Run main function with argument parsing
case "${1:-}" in
    --preview|--dry-run|-p)
        preview_release
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --preview, --dry-run, -p    Preview release notes without creating release"
        echo "  --forum-only <version>      Generate forum post for existing release"
        echo "  --help, -h                  Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                          # Interactive release creation"
        echo "  $0 --preview                # Preview release notes"
        echo "  $0 --dry-run                # Same as --preview"
        echo "  $0 --forum-only 1.0.0       # Generate forum post for v1.0.0"
        ;;
    "--forum-only")
        if [ -z "$2" ]; then
            error "Version required for --forum-only option"
            exit 1
        fi
        
        # Generate forum post for existing release
        info "📝 Generating forum post for version $2..."
        
        # Ensure output directory exists
        mkdir -p doc/notes
        
        # Generate the forum post content
        ./scripts/forum-post-generator.sh "$2" "$(gh release view "v$2" --json body --jq '.body' 2>/dev/null || echo 'Release notes not available')"
        
        # Open browser with forum post
        info "🌐 Opening forum post in browser..."
        open "$NOTES_DIR/release-v$2.html"
        
        info "📖 Forum post available at: $NOTES_DIR/release-v$2.html"
        if [ -n "$FORUM_URL" ]; then
            info "📋 Ready to copy and paste to $FORUM_URL"
        fi
        exit 0
        ;;
    "")
        main "$@"
        ;;
    *)
        error "Unknown option: $1"
        echo "Use '$0 --help' for usage information."
        exit 1
        ;;
esac
