# Commit Message Examples for HueV2 Project

## Good Commit Messages (Specific & Clear)

### Features
```
feat: add bridge auto-discovery via SSDP
feat: implement color temperature control
feat: add scene activation from QuickApp interface
feat: support for Hue motion sensors
feat: add device grouping by room functionality
```

### Bug Fixes
```
fix: handle null response in HueV2Engine.getDevices()
fix: prevent crash when bridge is unreachable
fix: resolve race condition in device initialization
fix: correct color conversion for RGB values
fix: handle missing device properties gracefully
```

### Refactoring
```
refactor: extract HTTP client to separate module
refactor: simplify device state synchronization logic
refactor: move authentication to HueV2Engine class
refactor: consolidate error handling in API calls
```

### Performance
```
perf: cache device states to reduce API calls
perf: batch device updates to minimize requests
perf: optimize scene loading with lazy initialization
```

## Bad Examples to Avoid

❌ `Implement feature X to enhance user experience`
❌ `Fix bug Y in module Z`  
❌ `Update code to improve functionality`
❌ `Enhance performance and fix issues`
❌ `Implement code changes to enhance functionality`

## Context Clues for Copilot

When committing changes to files, include specific details:

- **HueV2QA.lua**: Main QuickApp entry point, UI interactions
- **HueV2Engine.lua**: Core Hue bridge communication, device management
- **HueV2App.lua**: Application logic, device control
- **HueV2Map.lua**: Device mapping and discovery
- **HueV2File.lua**: File operations, configuration

## File-Specific Patterns

```
# When changing HueV2Engine.lua
fix: resolve timeout in HueV2Engine.discoverBridge()
feat: add retry logic to HueV2Engine.authenticate()

# When changing HueV2QA.lua  
feat: add device status display to main UI
fix: handle missing device in QuickApp interface

# When changing configuration
chore: update build script for new release format
docs: add bridge setup instructions
```