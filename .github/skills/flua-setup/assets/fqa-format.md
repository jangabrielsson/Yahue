# The .fqa format (HC3 QuickApp package)

Produced by `flua export script.lua -o script.fqa` (the `--tool pack` tool, via
`engine.qa_export`); reversed by `flua unpack script.fqa -d project/`. Plain JSON, one
file that the HC3 imports as a new device.

## Structure

```json
{
  "name": "MyQA",
  "type": "com.fibaro.binarySwitch",
  "apiVersion": "1.3",
  "initialInterfaces": [],
  "initialProperties": { "...": "see below" },
  "files": [
    { "name": "main", "isMain": true, "isOpen": false, "content": "-- code" }
  ]
}
```

- `name` — device name; `type` — the device type (default `com.fibaro.binarySwitch`);
  `apiVersion` — `"1.3"`.
- `initialInterfaces` — the device's interfaces **minus** `quickApp`.
- `files` — the main file plus every `--%%file` extra, each `{name, isMain, isOpen,
  content}` (flua omits the optional `type` field the HC3 accepts). `--%%file:$lib.lua`
  bundled libraries are included like any extra file.
- `initialProperties` — a **whitelisted subset** of the device properties:
  `viewLayout`, `uiView`, `useUiView`, `uiCallbacks`, `quickAppVariables`,
  `typeTemplateInitialized`, `userDescription`. The real HC3 rejects packages carrying
  dynamic properties (the system fills those at device creation), and private
  `__`-prefixed UI callbacks never travel.

## The properties that matter

- `quickAppVariables` — always a JSON **array** of `{name, value}` (values are strings).
  Values come from the `--%%var` directives: `flua export` (a *distribution* package)
  bakes each variable's declared `"<placeholder>"` PACKAGE value where one was declared,
  the evaluated value otherwise; a personal upload (`--tool uploadQA`) bakes the real
  evaluated values. Unset (`nil`) variables are dropped from the package.
- `uiView` / `uiCallbacks` — the UI definition, from the `--%%u` directives; also
  serialized as arrays. Without `uiCallbacks` (element + event → method name), the
  buttons do nothing.
- `viewLayout` — the legacy `$jason` layout, written when `useUiView` is false.

## Semantics on the HC3

- **Import always creates a new device (new id)** — web UI upload or `POST /api/quickApp/`
  with the `.fqa` JSON as the body. Scenes referencing the old id must be updated, so for
  version updates prefer `flua uploadQA` / `updateQA` (`PUT /api/quickApp/{id}/files`):
  the id, variables, icon and scene references are kept and the QA restarts.
- A `.fqa` carries **no icon** — icons are uploaded separately (`POST /api/icons`, see the
  hc3-rest-api skill, `assets/misc.md`).
- `type` must match an existing device template or the import fails.
- Stale packages are a classic "the fix did not work" — re-export after every code change.

## Verify before committing

`flua -t pack main.lua -o dist/MyQA.fqa -f` (`-f` overwrites an existing
file), then:

- parse the JSON and check `initialProperties.quickAppVariables` — PACKAGE
  placeholders, not real values (the dist policy above);
- grep the .fqa for secrets (passwords, tokens, keys) — a distribution
  package must never carry them;
- confirm it is a normal (non-proxy) build — proxy leftovers in the header
  produce proxy packages that misbehave off the controller;
- `flua unpack dist/MyQA.fqa -d /tmp/check/` — the reversed project should
  be a clean flua project that re-packs.
