---
name: network-device-test
description: How to test and debug a QA that talks to real LAN devices over sockets (WebSocket, MQTT-over-WS, HTTP) with flua — the offline+real-network hybrid, bounded repro QAs, the byte-level ws trace, the --tool ws probe, and the "connect → burst → watch disconnect → assert stability" loop. USE FOR: debugging real device communications, Sonos/bridge/mqtt QAs, deciding whether a bug is in the device, the QA, or the emulator, writing self-terminating repro QAs for socket protocols.
---

# Testing QAs against real network devices

flua's offline mode is **a simulated HC3 with real network**: `api.*` hits
the sim's house state, `net.*` (WebSocket/HTTP/MQTT clients) reaches the
real LAN. A QA under test therefore runs the exact HC3 code path against
the real device — without the HC3.

## The verification loop for a comms bug

```bash
flua --check qa.lua                    # 1. static: syntax, directives, APIs
flua --run-for 30 --debug ws qa.lua    # 2. run: sim HC3, real device,
                                       #    byte-level ws trace (CLI flag,
                                       #    no header edit needed)
flua --tool ws ws://host:port/ \       # 3. isolate: probe the endpoint the
  --send '{"cmdId":"1"}' --soak 20     #    same way the emulator would —
                                       #    exit 2 = the DEVICE drops
```

The three steps separate the suspects: `--check` catches QA-side mistakes,
the trace shows the emulator↔device conversation, and the probe answers
"is it the device or the emulator?" (the probe drives the same `WsClient`
the emulator uses; a drop the probe reproduces is the device's).

## Bounded repro QA pattern

Turn the failure into a minimal QA that always terminates. The pair that
makes this deterministic:

- `--run-for N` — hard wall-clock cap on the run.
- `_FLUA.exit(0)` in a watchdog timer — clean exit once the scenario
  played out (or once it clearly failed).

```lua
--%%name:WsTest
--%%type:com.fibaro.binarySwitch
function QuickApp:onInit()
  local sock = net.WebSocketClientTls({timeout=10000})
  sock:addEventListener("connected", function()
    for i=1,7 do sock:send(json.encode({cmdId=tostring(i)})) end  -- burst
  end)
  sock:addEventListener("dataReceived", function(d) print("RX:", d) end)
  sock:addEventListener("disconnected", function()
    print("DISCONNECTED"); setTimeout(function() _FLUA.exit(1) end, 100)
  end)
  sock:addEventListener("error", function(e) print("ERROR:", e) end)
  sock:connect("wss://<device>:<port>/<path>", { ["Header"] = "value" })
  setTimeout(function() print("watchdog"); _FLUA.exit(0) end, 10000)
end
```

Assert with the exit code: 0 = survived the burst + soak window, 1 =
dropped. A repro QA that fails 100% on the bug and passes 100% after the
fix becomes the regression test.

## Reading the ws trace

`--debug ws` (CLI) or `--%%debug:ws=true` (header) prints the byte-level
story. Each line is labeled with its connection and host:

```
ws[c1 192.168.50.223] connect handshake ok
ws[c1 192.168.50.223] tx text 106b '{"namespace":"playerVolume",...}'
ws[c1 192.168.50.223] rx text 2059b '{"type":"volume",...}'
ws[c1 192.168.50.223] rx close code=1000 reason=''
ws[c1 192.168.50.223] disconnected: None
```

- `c1` = the QA's first socket — with several connections open (Sonos:
  household + one per player) the id is how you tell them apart.
- Close codes and reasons explain server-initiated teardown (`1000` is a
  clean close; the trace line before it is the server's last word).
- Credential-ish values (`auth`, `token`, `password`, ...) are masked in
  previews; the QA's own `dataReceived` still gets the real payload.
- A **disconnect/reconnect loop** in the trace = the stability bug. Watch
  whether the QA re-sends its subscriptions after a reconnect — many
  libraries flush their send buffer once and go deaf (SonosLib did).

## Stability assertion

```bash
# the probe must survive a 20s soak with liveness pings (exit 0):
flua --tool ws wss://player:1443/websocket/api \
  --header "X-Sonos-Api-Key: ..." --soak 20

# the QA must show zero disconnect events over a bounded run:
flua --run-for 90 --debug ws SonosPlayer.lua
```

## Facts worth pasting into bug reports

- `flua --version` includes the Python interpreter (e.g. 3.14.3) — TLS
  behavior is version-dependent, and `net.*` bugs live in that layer.
- The structured `net` trace events (`wsConnect` url/ok/error, `wsEvent`
  event/binary/bytes) are in `--log json` / the timeline — the same stream
  the ws trace prints, machine-readable.
- Wss connections skip certificate verification by default (like the
  HC3) — self-signed device certs work; `--check-certificate` (probe) or
  `{checkCertificate = true}` (QA) opts back in.

Worked example: `docs/sonos_flua.md` — a real Sonos player debugged end to
end with exactly this loop.
