# AGENTS.md — QuickApp development with flua

Guidance for AI agents (Copilot, Claude Code, Codex, Cursor, or plain LLM
tooling) working on QuickApp code in this project. Humans: see
`flua --help` and the user guide at
https://github.com/jangabrielsson/flua/blob/main/USAGE.md

## What this project is

Lua QuickApps for a Fibaro HC3 controller. The files run **unchanged** on
the HC3 and in the flua emulator — the same QA file works in both places.

- Run a QA: `flua qa.lua` (defaults to the **offline simulator**; declare
  `--%%mode:online|proxy` in the header — or pass `--api remote` — to use
  the real HC3).
- Static check: `flua --check qa.lua` (no execution; syntax, `--%%`
  directives, deprecated APIs).
- `--%%` directives in the file header drive flua (mode, db, name, type,
  variables, UI); the HC3 ignores them.

## flua vs the HC3: detect the emulator

flua sets the global table **`_FLUA`**; on the HC3 it does not exist.
`if _FLUA then` is the one-line emulator check. There is **no
`fibaro.plua`** — old plua code uses that name and it is `nil` under flua.

Useful `_FLUA` members (full list: `## flua extensions (_FLUA)` in
USAGE.md):

- `_FLUA.mode` — this QA's effective mode: `"offline"` / `"online"` /
  `"proxy"` (the QA's own directives are in `_FLUA.config`)
- `_FLUA.uiEvent(element, eventType[, value])` — inject a UI event
- `_FLUA.postRefreshEvent(event)` — inject a refreshStates event
- `_FLUA.millitime()` — virtual time in milliseconds (sub-second timing)
- `_FLUA.exit(code)` — stop the engine (in a QA, `exit()`/`os.exit()`
  stop only that QA)
- `_FLUA.qa(id)` / `_FLUA.loadQAfromFile(path, directives?)` — reach or
  load other QAs at runtime

## QA directives (`--%%`)

Directives are Lua comments parsed by flua, ignored by the HC3. One per
line mostly; parsing stops at the end-of-header marker.

| Directive | Meaning |
|---|---|
| `--%%name:x` / `--%%type:com.fibaro.binarySwitch` | QA name / device type |
| `--%%uid:...` / `--%%description:...` / `--%%build:7` | fqa metadata |
| `--%%property:value=true` | raw device property (repeatable, merges) |
| `--%%var:name=expr` | QuickApp variable initializer — `expr` is a **Lua expression**: `'text'`, `42`, `{a=1}`, `config.color`. Strings need quotes (`--%%var:X=London` reads the nil global `London`). Optional package value: `--%%var:name=expr,"<placeholder>"` |
| `--%%clobber:name=value` | plua-style package value. **Raw string — no quotes** (`--%%clobber:X="<v>"` bakes the quote characters into the value) |
| `--%%file:lib.lua,lib` | extra QA file, loads before main |
| `--%%u:{label='x', text='...'}` | one UI row (repeatable) |
| `--%%mode:offline\|online\|proxy[,noUI]` | pin the mode; proxy is **online-only** (HC3 credentials required) |
| `--%%offline:true` / `--%%proxy:true` | legacy aliases for the mode directive |
| `--%%debug:true` / `--%%debug:api=true,http=true` | debug channels (global) |
| `--%%db:house.json` / `--%%db:+house.json` | seed the sim / seed **and persist** state back |
| `--%%location:latitude=59.33,longitude=18.07` | pin the sim's location (deterministic sun times) |
| `--%%time:speed=2,instant=true,start=2027/10/6 12:00:20` | virtual time settings (global) |

### plua directives flua does not know

- `--%%conceal:name="<v>"` → use `--%%clobber:name=<v>` (no quotes!) or
  the package-value form of `--%%var`
- `--%%save:path.fqa` → flua ignores it; pack output is set with `-o`
- `--%%desktop:true` → no flua equivalent; use the `--ui [PORT]` flag or
  `flua --tool ui`
- `fibaro.plua` → `_FLUA` (see above)

## Tools

`flua --tool` (bare) lists the installed tools; `flua --tool NAME --help`
shows one tool's usage. The ones you will actually use:

- `pack` — package a QA project (main + `--%%file` extras) into a `.fqa`.
  Needs `-f` to overwrite an existing file.
- `unpack` — unpack a `.fqa` back into a flua project
- `ui` — print a QA's UI as text (elements, callbacks, options), no browser
- `downloadQA` / `uploadQA` / `updateQA` / `uploadFile` — round-trip a QA
  with the real HC3 (credentials required)
- `newQA` — scaffold from a standard device-type template
- `catalog` — list the device types the sim supports
- `createDB` — build an offline db from a real HC3

`flua export script.lua -o out.fqa` and `flua unpack out.fqa -d dir/` are
the CLI spellings of pack/unpack.

## Building and verifying the .fqa artifact

The deploy artifact is a JSON file (despite the name): top-level `name`,
`type`, `apiVersion`, `files` (array of `{name, isMain, content}`),
`initialProperties`, `initialInterfaces`.

Variables land in `initialProperties.quickAppVariables`, and the policy
depends on the destination:

- **Distribution** (`pack` / `export` — the .fqa you share): the package
  value (from the `--%%var` package-value or `--%%clobber`) where declared,
  otherwise the evaluated value. Expressions evaluating to nil are left
  out. The main file's `--%%var` lines are rewritten to the baked literals
  — no expression, and no secret literal, travels.
- **Your own HC3** (`uploadQA`): always the real evaluated values.
- `updateQA` never syncs variables — runtime values on the HC3 win.

Packaging evaluates `--%%var` expressions (scope: `{config, os}`) but
**never runs QA code**; a faulty expression is a loud error naming the
variable.

Before committing a `.fqa`, verify it:

```bash
flua --tool pack main.lua -o dist/App.fqa -f
python3 - <<'EOF'
import json
fqa = json.load(open('dist/App.fqa'))
print(fqa['name'], fqa['type'])
print(fqa['initialProperties'].get('quickAppVariables'))
EOF
```

Check: the QA name is the normal name (not a `*_Proxy` build — proxy mode
packages differ), placeholders are in place, and no real credential appears
anywhere in the JSON.

## Agent skills

This project ships Copilot skills under `.github/skills/` (flua-setup,
quickapp-api, quickapp-patterns, quickapp-types, hc3-rest-api,
flua-troubleshooting, ...). Use them when their descriptions match the
task; `.github/copilot-instructions.md` and
`.github/instructions/quickapp-dev.instructions.md` apply to all `*.lua`
work automatically.

## Configuration and secrets

- Config table for `config.*` in `--%%var` expressions: `.flua.lua` in the
  directory you run from, then `~/.flua.lua`, then the legacy
  `~/.plua/config.lua`.
- `os.getenv(name)` reads `.env` in the current directory, then `~/.env`,
  then the shell environment (plain `KEY=value` lines, re-read on change).
- Online/proxy mode needs HC3 credentials in the environment.

## Rules of thumb

- QuickApps are single-file Lua programs; `QuickApp:onInit()` is the entry
  point, actions are `QuickApp:<method>` methods called through
  `fibaro.call` or the UI.
- Preserve HC3 compatibility: `api.*`/`fibaro.*` calls are the controller's
  own REST surface — don't invent endpoints.
- A QA's own variables should be `self:setVariable` (quickApp variables),
  not globals. Use `--%%db:+file.json` to persist emulator state between
  runs.
- Examples live in the flua repo's `examples/` directory — copy the pattern
  closest to the task instead of writing from scratch.
- `flua --check` before running; it catches syntax errors and deprecated
  APIs without executing anything.

## Tests

QuickApp projects are usually QA files, not test suites. When a change
needs verification, prefer a small terminating QA that prints its results
and run it with `flua --api local qa.lua` — with virtual time for timer
logic, so tests never wait for real time:

```bash
flua --api local --instant qa.lua                 # timers fire immediately
flua --api local --start '2027/10/6 12:00:00' qa.lua   # pin the virtual date
flua --api local --speed 60 qa.lua                # 60x virtual speed
```

Use the built-in assertions library instead of hand-rolled expect():
`local Test = require("flua-test"); local t = Test.new()` — `t:expect`,
`t:assert_eq`, `t:assert_json`, `t:finish()` (prints the summary and exits
with the failure count). It is provided by flua itself and never travels
in a packaged .fqa. UI behavior folds into the same QA:
`_FLUA.uiEvent(element, eventType[, value])` injects a UI event (values
arrive as strings), `self:getView()` reads the rendered view, and
`flua --tool ui qa.lua` prints the UI as text. For machine-readable runs,
`--log json` emits one JSON object per log line (`{time, level, tag, qaid,
msg}`) with the verdict on stderr; `--logfile FILE` writes a log copy. The
`quickapp-test` skill has the full loop.

## Where to look when stuck

1. The installed package is the ground truth: `flua --version`, then read
   `site-packages/flua/` — it is exactly what this machine runs.
2. USAGE.md (bundled with flua, and in the repo linked at the top) — the
   manual: directives, modes, variables-in-packages, `_FLUA`, HC3 REST
   reference.
3. `flua --examples` — installed example QAs.
4. `.github/skills/` — flua-setup, quickapp-api, quickapp-patterns,
   quickapp-types, quickapp-test, hc3-rest-api, ... load the one whose
   description matches the task.
