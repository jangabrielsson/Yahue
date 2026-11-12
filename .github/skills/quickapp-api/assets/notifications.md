# Notifications from a QuickApp

## Channels

| Channel | Call | Target IDs | Notes |
|---|---|---|---|
| Push to a phone (direct) | `api.post("/devices/<phoneId>/action/sendGlobalPushNotifications", {args = {text, "false"}})` → **202** | **mobile device** IDs (`type = "iOS_device"`, Android included) | Most reliable. Equivalent `fibaro.call(phoneId, "sendGlobalPushNotifications", text, "false")` (no return code) |
| Push by user | `fibaro.alert("push", {userIds}, text)` | **user** IDs | Maps users → phones whose `properties.lastLoggedUser` is that user. A phone logged in with another account gets **nothing, silently** |
| Block-scene style | `fibaro.alert("simplePush", {phoneIds}, text, false, "", false)` | phone IDs (calls `sendPush` directly) | What block scenes generate; has failed on some firmware where the direct push works |
| E-mail | `fibaro.alert("email", {userIds}, text)` | user IDs | needs the user's e-mail configured on the HC3 |
| Notification centre (bell in web UI / app) | `api.post("/notificationCenter", {...})` | — | not a push; priority colours |

There is **no "critical" push** on the HC3 (one that rings in silent mode). For that, use
an external service over HTTPS (Pushover priority 2 / iOS critical alerts, ntfy, Telegram)
with its token in a QA variable.

List phones: `api.get("/devices?type=iOS_device")` → `id`, `name`, `properties.lastLoggedUser`.
Users: `api.get("/users")` (do not export or print e-mails).

## Notification centre

```lua
api.post("/notificationCenter", {
    type = "GenericDeviceNotification",
    priority = "alert",            -- "alert" (red) | "warning" (orange) | "info" (blue)
    wasRead = false, canBeDeleted = true,
    data = { deviceId = self.id, title = self.name, text = text },
})
```

Map severities: unreachable module / fire / relay failure → `alert`; summary with problems →
`warning`; back to normal / all good → `info`. Make it optional (e.g. a `notifyCenter` QA
variable, default off) so it can be silenced.

## flua notes

- The sim accepts `POST /devices/{id}/action/{action}` (recorded, run through the pump),
  so the direct push call is testable offline.
- The sim has `GET /notificationCenter` (list) but **not** the POST — write the code, then
  verify the POST against a real HC3 with the hc3_compat suite.
- Push delivery itself (phone registration, `lastLoggedUser` mapping) is real-HC3 behaviour:
  treat it as untested unless a live test says otherwise.
