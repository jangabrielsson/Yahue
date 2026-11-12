---
name: plua-migration
description: Checklist and compatibility matrix for migrating a plua QuickApp project to flua — directive renames, tool equivalents, emulated API surface, known behavioral differences, and the gotchas found during real migrations (EventRunner7, Dirigera). USE FOR: converting a plua project or QA to flua, translating plua build/release scripts, understanding why a plua QA behaves differently under flua.
---

# Migrating a plua project to flua

The shortest version: run `flua --check` on every file first — every
`-- %%`-with-a-space spelling is flagged with its line number, and those
warnings are the migration map. Then walk this checklist.

## Directive mapping

| plua | flua | notes |
|---|---|---|
| `--%%headers:FILE` | `--%%include:FILE` | **accepted as an alias** — respell when convenient; paths relative to the file that declares them |
| `--%%name=value` | `--%%name:value` | **accepted** — the pre-plua `=` form parses like `:` (respell when convenient) |
| `-- %%save:NAME.fqa` | *(gone)* | use `flua export -o NAME.fqa` / `flua --tool pack -o` |
| `-- %%proxy:true` | `--%%mode:proxy` | proxy needs online mode |
| `-- %%port=N` | *(gone)* | no per-QA port in flua |
| `--%%desktop` | `--ui [PORT]` / `--%%u` rows | the viewer serves the sim API; HC3-real UI is proxy mode |
| `--%%conceal:name=value` | `--%%clobber:name=value` | package-value spelling |
| `--%%var:name=expr` | same, plus `--%%var:name=expr,"<placeholder>"` | the quoted trailing value ships in distribution packages; your own uploads keep the real value |

## Tool mapping

| plua | flua |
|---|---|
| `plua -t pack SRC OUT` | `flua --tool pack SRC -o OUT -f` (`-f` overwrites) |
| `plua -t uploadQA` / `updateQA` / `downloadQA` | `flua --tool uploadQA` / `updateQA` / `downloadQA` |
| `plua -t uploadFile` | `flua --tool uploadFile` (reads `--%%deviceId`/`--%%qaFile` from the file) |
| `plua -t createDB` | `flua --tool createDB` |

## Emulated plua/HC3 surface (verified by probing)

- `plugin.*` (getChildDevices, createChildDevice, restart, …) — provided
- `__TAG` — provided
- `json.encode`/`json.decode` + `json.util.InitArray` — provided; the
  encoder is compact like the HC3 (`[2,4,6]`)
- `net.HTTPClient` / `net.WebSocketClientTls` — provided, and they make
  **real network connections even in offline mode** (only the HC3 REST
  surface is mocked)
- `$sha2.lua`, `$qwikchild.lua` system-file references — resolve in flua
- `class`, `QwikAppChild` — provided inside a QA
- `fibaro.getIPaddress` — **not found** in probes; check the specific call
  before relying on it

## Known behavioral differences (current flua)

- **`--api remote` wins over the main QA's `--%%mode:offline`** — the flag
  outranks the header; *secondary* QAs' `--%%mode:offline` pins still hold.
  `_FLUA.mode` reports the effective mode.
- **`plugin.restart()` aborts the current turn** like the HC3 — code after
  the call never runs, and the new instance boots right away.
- **Path rules**: `--%%include`/`--%%file` anchor to the declaring file;
  `io.open`/`dofile` inside QA code stay cwd-relative (start flua from the
  project root).
- **Virtual time**: `--instant` and `--step` are both deadline-ordered
  fast-forward — each callback observes its own deadline in `os.time()`
  (0.1.111 made instant deadline-ordered; the old "instant is unsafe for
  os.time()-relative logic" caveat no longer applies). `--speed N` is the
  continuous clock (virtual time also passes while code executes).
  `--run-for N` exits 1 when the wall cap cuts work short; tag perpetual
  housekeeping loops `_FLUA.background(fn)` so they fire while the run
  lives but never keep it alive.

## Migration checklist

1. `flua --tool migrate .` — the one-pass scan flags every plua-ism
   (directive spellings, script invocations, stale packages, baked IPs) and
   exits 1 until the project is clean; `flua --check` each file for syntax.
2. Rename directives per the table; drop `save`/`port`.
3. Replace plua invocations in scripts (`pack`, `uploadQA`, …) — the old
   `plua -t pack` fails on sources that reference `$`-system files.
4. Regenerate stale `dist/*.fqa` artifacts (pack from current sources) and
   delete pre-flua-format packages.
5. Bake package values for private credentials/IPs
   (`--%%var:IP="192.168.50.165","<your-hub-ip>"`).
6. Smoke-test: boot offline (real network works), `flua --tool ui` for the
   UI, `flua export` + re-unpack for the package round-trip.
7. If the project runs online: `--api remote` (the main QA's pin no longer
   fights it).

## Gotchas found during real migrations

- `-- %%`-space spellings **silently do nothing** — flua warns, per line.
- Release scripts referencing `plua` break at the pack step — grep `scripts/`.
- `dist/` artifacts drift from sources (baked vars, stale files) — repack.
- "offline" still has real network (`net.*`); only the HC3 surface is mocked.
- The old plua `.fqa` format (`"type":"lua"` entries) predates flua's pack
  format — regenerate, don't patch.
