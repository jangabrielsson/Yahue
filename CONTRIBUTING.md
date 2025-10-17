# Contributing to HueV2

## Commit Message Format

We follow conventional commits to generate meaningful release notes. Each commit message should be structured as follows:

```
<type>: <description>

[optional body]

[optional footer]
```

### Types
- **feat**: A new feature
- **fix**: A bug fix  
- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **perf**: A code change that improves performance
- **test**: Adding missing tests or correcting existing tests
- **chore**: Changes to the build process or auxiliary tools

### Examples
```
feat: add device auto-discovery for Hue bridge
fix: resolve connection timeout when bridge is unreachable
docs: update installation instructions
refactor: simplify authentication logic
```

### Guidelines
- Use present tense ("add feature" not "added feature")
- Use imperative mood ("move cursor to..." not "moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line
- Write meaningful descriptions - they become release notes

## Development Workflow

1. Always test with `--preview` first before creating real releases
2. Keep artifacts in `.gitignore` except for releases  
3. Use semantic versioning (major.minor.patch)
4. Write meaningful commit messages - they become release notes
5. Tag commits with prefixes like `feat:`, `fix:`, `docs:` for better release notes