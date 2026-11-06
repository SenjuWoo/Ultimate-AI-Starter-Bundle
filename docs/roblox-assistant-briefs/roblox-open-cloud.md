---
name: roblox-open-cloud
description: Open Cloud REST APIs and HttpService - API keys/OAuth, v2 patterns, data/memory stores from outside, publishMessage, place publishing, server restarts, Luau execution, bans, configs/experiments, notifications, webhooks with roblox-signature verification, rate limits, Secrets. Use when building external tools, dashboards, bots, CI/CD, admin panels, or calling web APIs from a game.
enabled: true
---
# Roblox Open Cloud and HttpService

Base URL: `https://apis.roblox.com`. Prefer **Open Cloud** endpoints (API key or OAuth 2.0, stable).
Legacy cookie-authenticated `*.roblox.com` web APIs can break without notice — don't build on them.

## Authentication

- **API keys** (Creator Dashboard → Open Cloud → API Keys): for your own/your group's resources and
  automation. Grant the minimum scopes per universe, set an **IP allowlist** (CIDR) and **expiration**,
  store as a secret (CI secret, vault), send as header `x-api-key: <key>`. Group-owned resources need a
  key created under the group. Introspect a key with `POST /api-keys/v1/introspect`.
- **OAuth 2.0** (authorization code + PKCE): apps acting on behalf of other users (third-party tools).
- Never ship keys in game scripts, attributes, or client code.

## Common endpoints (v2 unless noted)

| Task | Endpoint |
| --- | --- |
| Data store entries | `GET/POST /cloud/v2/universes/{u}/data-stores/{ds}/entries`, `GET/PATCH/DELETE .../entries/{id}`, `:increment`, `:listRevisions`; scopes via `/scopes/{scope}/entries` |
| Ordered data stores | `/cloud/v2/universes/{u}/ordered-data-stores/{ods}/scopes/{scope}/entries[...]` |
| Memory stores | `/cloud/v2/universes/{u}/memory-store/sorted-maps/{map}/items`, `/queues/{q}/items[:read|:discard]`, `memory-store:flush` |
| Cross-server message into live servers | `POST /cloud/v2/universes/{u}:publishMessage` `{ "topic": "...", "message": "..." }` |
| Publish a place file | `POST /universes/v1/{u}/places/{p}/versions?versionType=Published|Saved` (body: `.rbxl`) |
| Restart servers (after an update) | `POST /cloud/v2/universes/{u}:restartServers` |
| Run Luau in a cloud server | `POST /cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks` |
| Bans | `PATCH /cloud/v2/universes/{u}/user-restrictions/{userId}?updateMask=gameJoinRestriction` (scope `universe.user-restriction:write`), `user-restrictions:listLogs` |
| Experience notifications | `POST /cloud/v2/users/{userId}/notifications` |
| Secrets store | `/cloud/v2/universes/{u}/secrets` |
| Configs / experiments | `/creator-configs-public-api/v1/configs/universes/{u}/repositories/{repo}[/draft|/publish]`, `/experimentation/...` |
| Universe/place settings | `GET/PATCH /cloud/v2/universes/{u}`, `/cloud/v2/universes/{u}/places/{p}` |
| Assets, badges, game passes, developer products, groups, users, inventory | See the Open Cloud reference by feature. |

The authoritative list with scopes and per-endpoint rate limits is the Open Cloud reference
(`create.roblox.com/docs/cloud/reference`) and its OpenAPI description — check it before writing a client.

## Patterns

- **Pagination**: pass `maxPageSize`; follow `nextPageToken` → `pageToken` until empty.
- **Long-running operations**: some calls return an operation `path`; poll `GET /cloud/v2/{path}` until `done`.
- **Filtering**: `filter` query parameter on list endpoints that support it.
- **Rate limits**: read the `x-ratelimit-*` response headers; on `429`, back off exponentially with jitter.
  Data store budgets are **shared** between Open Cloud and live game servers — throttle bulk scripts so they
  don't starve the game (see `roblox-data-stores`).
- **Errors**: JSON `{ code, message }`; retry only `429` and `5xx`.
- **Legacy web APIs** (cookie or unauthenticated IP): after Oct 19, 2026, limits on the badges, datastores,
  game-persistence, inventory, thumbnails, and users APIs drop sharply (often to 100 requests/min). Open Cloud
  limits don't change: use Open Cloud with an API key for tools and bots, and cache responses.
- **Thumbnails**: from Oct 26, 2026 an unapproved or broken thumbnail returns `200` with a completed
  operation containing an `error` object (not `503`); check `error` before reading `response.imageUri`.

```bash
# Read one player's data store entry
curl -s "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/data-stores/PlayerData/entries/User_$USER_ID" \
  -H "x-api-key: $ROBLOX_API_KEY"

# Announce to all live servers (the game subscribes to the "Announcements" topic)
curl -s -X POST "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID:publishMessage" \
  -H "x-api-key: $ROBLOX_API_KEY" -H "Content-Type: application/json" \
  -d '{"topic":"Announcements","message":"{\"text\":\"Update in 5 minutes\"}"}'
```

## HttpService inside games

- Enable **Allow HTTP Requests** (Experience Settings → Security). Server-side only.
- Limits: 500 requests/min per server for external URLs; Open Cloud calls have a separate
  2,500/min per server budget. Always `pcall`; handle non-2xx (`response.Success`).
- Store keys in the experience **Secrets store** (Creator Hub) and read with `HttpService:GetSecret(name)`,
  which returns an opaque `Secret` usable in headers (and `AddPrefix`/`AddSuffix`), not a readable string.
- Only a **subset** of Open Cloud endpoints can be called from games (assets, bans, configs, data/memory
  stores, messaging, notifications, and more — check the in-game HTTP docs list). Calls to other
  `roblox.com` domains are blocked.

```luau
--!strict
local HttpService = game:GetService("HttpService")

local function postToWebhook(url: string, payload: { [string]: any }): boolean
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
	end)
	if not ok then
		warn("HTTP request failed to send:", response)
		return false
	end
	if not response.Success then
		warn(`HTTP {response.StatusCode}: {response.StatusMessage}`)
	end
	return response.Success
end

local function banViaOpenCloud(universeId: number, userId: number, reason: string): boolean
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `https://apis.roblox.com/cloud/v2/universes/{universeId}/user-restrictions/{userId}?updateMask=gameJoinRestriction`,
			Method = "PATCH",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = HttpService:GetSecret("OpenCloudKey"),
			},
			Body = HttpService:JSONEncode({
				gameJoinRestriction = { active = true, displayReason = reason, privateReason = reason },
			}),
		})
	end)
	return ok and response.Success
end

return { postToWebhook = postToWebhook, banViaOpenCloud = banViaOpenCloud }
```

In-game, prefer native APIs (`Players:BanAsync`, `DataStoreService`) over calling Open Cloud for the same thing.
Never log or send player chat/PII to third parties without a legitimate purpose and compliance review.

## Webhooks (Roblox → your server)

Configure in Creator Hub → Account Settings → Webhooks (max 5; for group games only the group owner).
Triggers: subscription purchased/renewed/cancelled/refunded/resubscribed, right-to-erasure requests,
commerce order paid/refunded, **transaction refunded** (Robux refunds/chargebacks of developer products,
passes, private servers, Paid Access — revoke developer product benefits yourself).
Verification details and a Node/Python verifier: [references/webhooks.md](#reference-references-webhooks-md).

## Related skills

`roblox-data-stores` (budgets, schema), `roblox-tooling` (CI publishing), `roblox-testing` (Luau
execution tests), `roblox-analytics-liveops` (configs, experiments), `roblox-security` (bans, secrets).

---

<a id="reference-references-webhooks-md"></a>

## Appendix: references/webhooks.md

### Verifying Roblox webhooks

When a webhook has a secret, Roblox sends header `roblox-signature: t=<timestamp>,v1=<signature>`.
Signature = Base64( HMAC-SHA256( key = secret, message = `<timestamp>.<raw JSON body>` ) ).
Reject requests whose signature doesn't match, and requests older than a few minutes (replay protection).
Use the **raw** request body bytes, not a re-serialized object.

## Node.js (Express)

```javascript
import crypto from "node:crypto";
import express from "express";

const app = express();
const SECRET = process.env.ROBLOX_WEBHOOK_SECRET;

app.post("/roblox-webhook", express.raw({ type: "application/json" }), (req, res) => {
  const header = req.get("roblox-signature") ?? "";
  const parts = Object.fromEntries(header.split(",").map((kv) => kv.split("=", 2)));
  const timestamp = parts.t;
  const signature = parts.v1;
  if (!timestamp || !signature) return res.sendStatus(401);

  const ageSeconds = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (ageSeconds > 300) return res.sendStatus(401);

  const expected = crypto
    .createHmac("sha256", SECRET)
    .update(`${timestamp}.${req.body.toString("utf8")}`)
    .digest("base64");
  const ok =
    expected.length === signature.length &&
    crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
  if (!ok) return res.sendStatus(401);

  const event = JSON.parse(req.body.toString("utf8"));
  // Idempotency: store processed event IDs; Roblox retries failed deliveries and may send duplicates.
  console.log("webhook", event.EventType ?? event.eventType, event);
  res.sendStatus(200);
});

app.listen(3000);
```

## Python (Flask)

```python
import base64, hashlib, hmac, os, time
from flask import Flask, request, abort

app = Flask(__name__)
SECRET = os.environ["ROBLOX_WEBHOOK_SECRET"].encode()

@app.post("/roblox-webhook")
def roblox_webhook():
    header = request.headers.get("roblox-signature", "")
    parts = dict(p.split("=", 1) for p in header.split(",") if "=" in p)
    ts, sig = parts.get("t"), parts.get("v1")
    if not ts or not sig or abs(time.time() - int(ts)) > 300:
        abort(401)
    body = request.get_data(as_text=True)
    expected = base64.b64encode(hmac.new(SECRET, f"{ts}.{body}".encode(), hashlib.sha256).digest()).decode()
    if not hmac.compare_digest(expected, sig):
        abort(401)
    event = request.get_json()
    # handle event idempotently
    return "", 200
```

## Handling events

- **Right to erasure**: delete the user's data from every data store/key and any external storage; see
  automated RTBF in `roblox-data-stores` (preferred when keys follow static patterns).
- **Transaction Refunded** (developer products, passes, private servers, Paid Access; fires immediately on
  a refund or chargeback): `EventPayload` carries the buyer's user ID, product type and ID, Robux amount
  (the product's original price, not what the buyer paid), universe and place, transaction/receipt ID,
  and refund time. Pass and avatar-item ownership is revoked by Roblox; developer product benefits must be
  removed by you — queue a revocation in the player's data store entry (Open Cloud) or notify live servers
  with `publishMessage`. A delivery missed while your endpoint is down isn't re-sent, so keep it available.
- Subscription refunds use the subscription webhooks, not Transaction Refunded.
- **Commerce order paid**: may be delivered more than once — deduplicate by order ID.
- Respond `2xx` quickly and process asynchronously; failed deliveries are retried.
