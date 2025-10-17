# Release Scripts - Universal Configuration

This directory contains generalized release automation scripts that can be easily adapted for multiple Lua projects.

## Files

- **`project-config.sh`** - Project-specific configuration (EventRunner6 settings)
- **`project-config.sh.example`** - Template for adapting to other projects
- **`create-release.sh`** - Main release automation script
- **`setversion.sh`** - Updates version numbers in source files
- **`forum-post-generator.sh`** - Generates HTML forum posts for releases

## Features

✅ Automated version bumping (semantic versioning)  
✅ Git tag creation and pushing  
✅ GitHub release creation with artifacts  
✅ Changelog generation from git commits  
✅ Forum post generation with download links  
✅ Configurable artifact building (`.fqa`, `.zip`, etc.)  
✅ Pre/post-release hooks for custom actions  
✅ Preview mode for testing release notes

## Quick Start

### For EventRunner6 (Current Project)

```bash
# Interactive release creation
./scripts/create-release.sh

# Preview release notes without creating release
./scripts/create-release.sh --preview

# Update version only
./scripts/setversion.sh 1.2.3
```

### For Other Projects

1. **Copy the scripts directory to your project:**
   ```bash
   cp -r EventRunner6/scripts /path/to/your-project/
   ```

2. **Copy and customize the configuration:**
   ```bash
   cd /path/to/your-project/scripts
   cp project-config.sh.example project-config.sh
   ```

3. **Edit `project-config.sh`:**
   - Update `PROJECT_NAME`
   - Update `GITHUB_REPO` (owner/repo)
   - Configure `VERSION_FILES` (files containing version strings)
   - Configure `ARTIFACTS` (build commands)
   - Configure `RELEASE_FILES` (files to commit)
   - Optionally add `FORUM_URL`

4. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

5. **Test with preview mode:**
   ```bash
   ./scripts/create-release.sh --preview
   ```

## Configuration Guide

### Basic Settings

```bash
PROJECT_NAME="MyProject"
GITHUB_REPO="myusername/myproject"
FORUM_URL="https://forum.example.com/my-thread/"  # Optional
```

### Version File Management

The scripts can update version strings in multiple files:

```bash
declare -a VERSION_FILES=(
    "src/main.lua:^local VERSION"           # Matches: local VERSION = "1.0.0"
    "package.json:\"version\""               # Matches: "version": "1.0.0"
    "src/constants.py:^VERSION"              # Matches: VERSION = "1.0.0"
)
```

### Artifact Configuration

Define what artifacts to build:

```bash
declare -a ARTIFACTS=(
    # Fibaro .fqa files using plua
    "src/main.lua:dist/MyApp.fqa:plua -t pack {SOURCE} {OUTPUT}"
    
    # Zip archives
    "src/:dist/source.zip:zip -r {OUTPUT} {SOURCE}"
    
    # Simple copy
    "README.md:dist/README.md:cp {SOURCE} {OUTPUT}"
    
    # Custom build command
    "src/:dist/bundle.js:npm run build && cp build/bundle.js {OUTPUT}"
)
```

### Release Files

Specify which files to commit during releases:

```bash
declare -a RELEASE_FILES=(
    ".version"
    "CHANGELOG.md"
    "src/main.lua"
    "dist/MyApp.fqa"
    "package.json"
)
```

### Optional Hooks

Add custom logic before/after releases:

```bash
# Run tests before release
pre_release_hook() {
    echo "Running tests..."
    npm test || return 1
    return 0
}

# Notify team after release
post_release_hook() {
    local version=$1
    echo "Notifying team about v$version..."
    curl -X POST $SLACK_WEBHOOK -d "{\"text\":\"Released v$version\"}"
    return 0
}

# Build additional artifacts
custom_artifact_build() {
    echo "Creating documentation..."
    make docs
    cp -r docs dist/
    return 0
}
```

## Usage Examples

### Interactive Release

```bash
./scripts/create-release.sh
```

Follow the prompts to:
1. Select version bump type (patch/minor/major)
2. Choose release notes generation method
3. Confirm and create release

### Preview Release Notes

```bash
./scripts/create-release.sh --preview
```

Shows what the release would look like without creating it.

### Manual Version Update

```bash
./scripts/setversion.sh 2.0.0
```

Updates version in all configured files.

### Generate Forum Post for Existing Release

```bash
./scripts/create-release.sh --forum-only 1.5.0
```

Creates forum post HTML for an existing GitHub release.

## Requirements

- **git** - Version control
- **gh** (GitHub CLI) - Creating GitHub releases
  ```bash
  brew install gh
  gh auth login
  ```
- **bash** 4.0+ - Script interpreter
- **plua** (optional) - For building `.fqa` files for Fibaro
  ```bash
  pip install plua
  ```

## Project Structure

Your project should have:

```
your-project/
├── scripts/
│   ├── project-config.sh         # Your configuration
│   ├── create-release.sh         # Main script
│   ├── setversion.sh             # Version updater
│   └── forum-post-generator.sh   # Forum post generator
├── src/
│   └── main.lua                  # Your source files
├── dist/                          # Build artifacts (auto-created)
├── .version                       # Version file (auto-created)
├── CHANGELOG.md                   # Changelog (auto-updated)
└── README.md                      # Your documentation
```

## Customization Examples

### Node.js Project

```bash
PROJECT_NAME="MyNodeApp"
GITHUB_REPO="user/my-node-app"

declare -a VERSION_FILES=(
    "package.json:\"version\""
    "src/index.js:^const VERSION"
)

declare -a ARTIFACTS=(
    "src:dist/bundle.js:npm run build && cp build/bundle.js {OUTPUT}"
    "dist:dist/app.tar.gz:tar -czf {OUTPUT} build/"
)
```

### Python Project

```bash
PROJECT_NAME="MyPythonLib"
GITHUB_REPO="user/my-python-lib"

declare -a VERSION_FILES=(
    "setup.py:version="
    "mylib/__init__.py:^__version__"
)

declare -a ARTIFACTS=(
    ".:dist/mylib.tar.gz:python setup.py sdist && mv dist/*.tar.gz {OUTPUT}"
)

pre_release_hook() {
    pytest || return 1
    return 0
}
```

## Troubleshooting

### "Configuration file not found"

Ensure `project-config.sh` exists in the `scripts/` directory.

### "GitHub CLI is not authenticated"

Run `gh auth login` and follow the prompts.

### Version not updating in files

Check that your VERSION_FILES patterns match the actual format in your files:
```bash
# Debug: Check what grep finds
grep "^local VERSION" src/main.lua
```

### Artifacts not building

Verify:
1. Source files exist
2. Build commands work when run manually
3. Required build tools are installed (plua, npm, etc.)

## Tips

1. **Always test with `--preview` first** before creating real releases
2. **Keep artifacts in `.gitignore`** except for releases
3. **Use semantic versioning** (major.minor.patch)
4. **Write meaningful commit messages** - they become release notes
5. **Tag commits with prefixes** like `feat:`, `fix:`, `docs:` for better release notes

## Support

For issues or questions:
- Check the example configuration: `project-config.sh.example`
- Review the EventRunner6 configuration: `project-config.sh`
- Open an issue on GitHub

## License

These scripts are part of the EventRunner6 project and follow the same license.
