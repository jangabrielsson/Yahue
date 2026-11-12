<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructions-md-file -->

# flua Project Instructions

flua is a Lua engine for Fibaro HC3 QuickApps: [lupa](https://github.com/scoder/lupa) (bundled Lua 5.x) hosted in Python, asyncio-backed cooperative timers on a virtual clock, and a strict message-passing bridge between the two sides. It runs real QuickApps offline (a simulated HC3 REST API + runtime libraries), online against the real controller, and in proxy mode (a mirror QA deployed on the HC3 that funnels actions/UI events back to the emulator). `lupa` is the only runtime dependency.

QA developers start at [USAGE.md](USAGE.md); [ARCHITECTURE.md](ARCHITECTURE.md) is the under-the-hood tour; [AGENTS.md](AGENTS.md) is the framework-agnostic guide for AI agents working in this repo.

`AGENTS.md` is the authoritative repository-wide contribution and agent
workflow. Read it before changing code. Do not contact a real HC3 from tests
or scripts unless the user explicitly asks for it.

## Key components

- **`src/flua/engine.py` — LuaEngine**: owns the lupa VM, the message queues, and the dispatch pump. Lua is entered from exactly one place (`_PY.dispatch(batch)`); Lua→Python traffic is append-only via `_PY.post`.
- **`src/flua/api/` — the HC3 REST API**: offline simulation first, hybrid routing online. `state.py` holds the sim world; `routes/` are pure `(SimState, ApiRequest) -> (data, status)` handlers; `Api.dispatch` forwards unknown entities to the real HC3 when online.
- **`src/flua/lua/` — the HC3 runtime in Lua**: `init.lua` (timers, message handlers, per-QA envs), `quickapp.lua` (QuickApp/QuickAppChild classes), `fibaro.lua`, `net.lua`, `mqtt.lua`.
- **`src/flua/cli.py`** — the `flua` command.
- **`src/flua/proxy.py`** — proxy mode (`--%%mode:proxy`): deploy/reuse a `<name>_Proxy` QA on the HC3, sync properties/UI, funnel actions/UI events back.
- **`src/flua/config.py`** — `--%%` directive parsing (plus `.directives` defaults).
- **`viewer/`** — static UI viewer served by `--ui`.

## Running flua

```bash
.venv/bin/flua script.lua                # one QA per file, isolated envs
.venv/bin/flua --api local script.lua    # offline sim (online is the default)
.venv/bin/flua --seed examples/house.json script.lua
.venv/bin/flua --ui 8090 script.lua      # UI viewer, stays up until Ctrl-C
.venv/bin/flua --watch script.lua        # restart on save
.venv/bin/flua --check script.lua        # static checks
.venv/bin/flua export script.lua -o script.fqa
.venv/bin/flua --debugger script.lua     # mobdebug on port 8172
```

Modes: `--%%mode:online|offline|proxy` in the QA header (or a `.directives` file). An explicit `--api local|remote` wins; the default is ONLINE (HC3 credentials from the `.env` chain). Offline-pinned QAs never see the HC3.

## Development

```bash
.venv/bin/pytest tests/ -q                  # full suite (skips live-HC3 tests)
.venv/bin/pytest tests/test_qa.py -q        # one file
.venv/bin/ruff check src/ tests/            # lint
.venv/bin/ruff format src/ tests/           # format (line length 100)
```

Tests run against local mock servers (threaded HTTP servers), never a real controller — the live-HC3 suites are opt-in via `HC3_TEST=1`. Many tests bind localhost sockets, so run them in an environment that permits local socket binds.

## Conventions

- Message protocol: everything crossing the Lua/Python boundary is a JSON-compatible dict via `messages.py`. Never call into Lua synchronously from a Python handler.
- API handlers are pure functions over `SimState`; side effects go through `req.emit`.
- Synchronous blocking calls (remote HC3, debugger sockets) are documented exceptions that freeze the pump.
- Per-QA isolation: each QA gets its own Lua env; QA ids are engine-assigned (5000+), proxy QAs run under their HC3 id.
- `dev/` is the scratch directory (create test scripts here, don't pollute the top level).
- Keep `_PY` functions minimal; end-user convenience lives in Lua.

For the complete change workflow, compatibility rules, repository map, and
validation checklist, follow `AGENTS.md` and `CONTRIBUTING.md`.

---

## QuickApp Development Skills

Skill version: **1.1.0**

Skills for Fibaro HC3 QuickApp development with flua, auto-discovered from `.github/skills/`.
The instruction file `.github/instructions/quickapp-dev.instructions.md` is auto-applied to all `*.lua` files.

Type a slash command in Copilot chat for detailed reference:

- `/quickapp-api` — full fibaro.*, QuickApp methods, net.HTTPClient, timers
- `/quickapp-types` — all 40+ device types, UI headers, starter templates
- `/quickapp-patterns` — timer loops, refreshStates, HTTP, children, state persistence
- `/hc3-rest-api` — HC3 REST endpoints with examples
- `/lua-basics` — Lua language reference for non-Lua developers
- `/flua-troubleshooting` — startup errors, HC3 connection issues, proxy callbacks, busy ports
- `/flua-setup` — install, HC3 credentials, modes, VS Code integration, CLI flags, directives
- `/quickapp-troubleshooting` — HTML in labels, UI callbacks, property persistence, HC3 vs flua differences
- `/qwikchild` — QwikAppChild library: UID-based children, declarative initChildren, per-child UI
- `/quickapp-test` — offline verification: assert inside the QA, exit codes, driving the sim over HTTP
- `/skill-creator` — create, improve, and evaluate skills
