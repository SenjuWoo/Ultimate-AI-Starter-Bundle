---
name: roblox-data-stores
description: Persistence and cross-server data - DataStoreService (UpdateAsync, retries, budgets, limits), session locking with ProfileStore, schema migrations, OrderedDataStore leaderboards, MemoryStore queues/sorted maps/hash maps, MessagingService, right-to-be-forgotten. Use when saving player data, building leaderboards or queues, or fixing data loss, duplication, or throttling.
enabled: true
---
# Roblox data stores and cloud services

## Choose the service

| Need | Service | Notes |
| --- | --- | --- |
| Player progress, inventory, settings | **DataStore** via ProfileStore (session-locked) | One key per player (`User_{UserId}`), ≤ 4 MB. |
| Global leaderboards | `OrderedDataStore` | Integer values only; periodic updates, cached reads. |
| Fast, temporary, cross-server state | `MemoryStoreService` | Sorted maps, queues, hash maps; everything expires (TTL ≤ 45 days). |
| Matchmaking queues, live events, server lists | MemoryStore queue / sorted map | Not durable — never the only copy of valuable data. |
| Broadcast to all servers | `MessagingService` | ≤ 1 kB per message, best effort, no delivery guarantee. |
| Values changed by live-ops without publishing | Experience configs (`ConfigService`) | See `roblox-analytics-liveops`. |

## Player data: use session locking

Two servers must never own the same player's data at once (teleports, fast rejoins), or items duplicate
and progress is lost. **ProfileStore** (loleris) implements session locking, auto-save, and
`BindToClose` flushing, and is the recommended default. Install it from Wally/the Creator Store and put
it in `ServerScriptService`.

```luau
-- ServerScriptService/Server/Services/DataService.luau (ProfileStore)
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local TEMPLATE = {
	version = 1,
	coins = 0,
	inventory = {} :: { [string]: number },
}
type PlayerData = typeof(TEMPLATE)

local PlayerStore = ProfileStore.New("PlayerData", TEMPLATE)
local profiles: { [Player]: typeof(PlayerStore:StartSessionAsync("")) } = {}

local function onPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync(`User_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players -- stop waiting if the player left
		end,
	})
	if profile == nil then
		player:Kick("Could not load your data. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId) -- GDPR / right-to-be-forgotten linkage
	profile:Reconcile() -- fill in fields added to TEMPLATE since this profile was created
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was loaded on another server. Please rejoin.")
	end)
	if player.Parent == Players then
		profiles[player] = profile
	else
		profile:EndSession() -- left while loading
	end
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local profile = profiles[player]
	if profile then
		profile:EndSession() -- saves and releases the lock
	end
end)

local DataService = {}
function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return profile and profile.Data
end
return DataService
```

Mutate `profile.Data` directly on the server (it is cached in memory and auto-saved). Don't
`SetAsync` per change. Check the ProfileStore docs for the exact current API before relying on less
common features (global updates, `MessageAsync`, mock stores for Studio).

## Raw DataStoreService rules (when not using a wrapper)

- **Buffer in memory**: load once on join, mutate the in-memory table, save periodically (e.g. every
  2–5 minutes with random jitter), on leave, at checkpoints (purchases), and in `game:BindToClose`.
- **`UpdateAsync` over `SetAsync`** whenever the write depends on the old value or multiple servers may
  write the key. The transform function must be pure and fast (no yields); return `nil` to cancel.
- **Retry transient errors** with exponential backoff + jitter, capped attempts; process retries for
  a key in order (an old retry must not overwrite newer data). Treat a failed write as "outcome unknown".
- Never save `Instance`s, `Vector3`, `CFrame`, functions, or mixed/sparse tables: store plain tables,
  numbers, strings, booleans, and `buffer`s. Serialize datatypes (`{ x, y, z }`). Validate UTF-8 strings.
- Keys and data store names ≤ 50 characters; value ≤ 4,194,304 characters after JSON encoding.
- Stable key patterns (`User_{UserId}`), never display names. Few data stores, few keys per player.
- Studio needs **File → Experience Settings → Security → Enable Studio Access to API Services**; use a separate test
  universe or a different data store name so testing never touches production data.

Complete raw implementation (session lock, autosave, BindToClose, retries):
[references/raw-datastore.md](#reference-references-raw-datastore-md).

## Budgets and limits (2026)

| Limit | Value |
| --- | --- |
| Experience-wide standard reads / writes | `300 + 40 × CCU` / `300 + 20 × CCU` per minute (shared with Open Cloud) |
| Default per-server reads/writes | `60 + 40 × players` per minute each (configurable) |
| Ordered writes per server | `30 + 5 × players` per minute |
| Per-key throughput | 25 MB/min read, 4 MB/min write |
| Storage (latest versions, compressed) | `500 MB + 1 MB × lifetime users` per experience |
| Queue per request type | 30 pending requests, then errors 301–306 |

- `UpdateAsync` consumes both read and write budget.
- Check `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardWrite)` before
  bulk work; tune per-server limits once at startup with `SetRateLimitForRequestType`.
- Don't pre-compress data; Roblox compresses automatically. Shard only genuinely hot keys.
- Use versions (`ListVersionsAsync`, `GetVersionAtTimeAsync`) to restore data instead of writing backup keys.

## Schema versioning and migrations

Store a `version` field. On load, run ordered migration functions until the data reaches the current
version, then reconcile defaults. Never delete fields in the same release that stops writing them;
never reuse field names with different meanings.

```luau
--!strict
type Data = { [string]: any }

local MIGRATIONS: { (Data) -> () } = {
	[1] = function(data) -- v1 -> v2: "gold" renamed to "coins"
		data.coins = data.gold or 0
		data.gold = nil
	end,
	[2] = function(data) -- v2 -> v3: inventory list -> counts
		local counts: { [string]: number } = {}
		for _, itemId in data.inventory or {} do
			counts[itemId] = (counts[itemId] or 0) + 1
		end
		data.inventory = counts
	end,
}
local CURRENT_VERSION = #MIGRATIONS + 1

local function migrate(data: Data): Data
	local version = data.version or 1
	while version < CURRENT_VERSION do
		MIGRATIONS[version](data)
		version += 1
	end
	data.version = CURRENT_VERSION
	return data
end

print(migrate({ gold = 5, inventory = { "Sword", "Sword" } }))
```

## Leaderboards (OrderedDataStore)

- Values must be integers. Write on a schedule or on meaningful change, not every increment.
- Read top N with `GetSortedAsync(false, 100)` on **one** server loop (e.g. every 60 s), cache the
  result, and replicate to clients. Don't let every server/client read constantly.
- For "this week" boards, include the period in the store name (`Wins_2026W39`) or use a MemoryStore sorted map.
- **Roblox-native leaderboards** (fully released): register the `OrderedDataStore` in Creator Hub (game →
  leaderboards) and toggle "Active leaderboard"; Roblox renders persistent Global and Friends tabs in the
  player list. The store stays the source of truth (one active board per game). Initialize each player's
  score on join so the tabs render correctly.

## MemoryStore essentials

- Quotas are experience-wide: memory `64 KB + 1.2 KB × users`; requests `1000 + 120 × CCU` units/min.
- `MemoryStoreSortedMap`: ranked data, server browsers, live leaderboards (`SetAsync` with expiration,
  `GetRangeAsync`, `UpdateAsync`).
- `MemoryStoreQueue`: matchmaking/work queues (`AddAsync`, `ReadAsync` + `RemoveAsync` with the returned id
  after successful processing, invisibility timeout for crash safety).
- `MemoryStoreHashMap`: high-volume key-value without sorting (`SetAsync`, `GetAsync`, `UpdateAsync`, `ListItemsAsync`).
- Always set expirations; handle throttling (`pcall` + retry); keep items small.

## MessagingService essentials

- Message ≤ 1 kB. Per server: `600 + 240 × players` sends/min; `20 + 8 × players` subscriptions.
- Delivery is **best effort** and not ordered: use it for notifications ("refresh your cache",
  global announcements), never as the source of truth. Pair with DataStore/MemoryStore for state.
- Wrap `SubscribeAsync`/`PublishAsync` in `pcall`; they can fail or yield.

More code (MemoryStore queue matchmaking, cross-server announcement, RTBF): [references/memory-and-messaging.md](#reference-references-memory-and-messaging-md).

## Right to be forgotten

Use static key patterns so **automated RTBF** (configured in Creator Dashboard) can delete player data
templates like `PlayerData/User_{userId}`. Otherwise handle the right-to-erasure webhook (see
`roblox-open-cloud`). Link keys to user IDs: `SetAsync(key, value, { userId })`, return them as the second value from an
`UpdateAsync` transform, or call ProfileStore's `AddUserId`.

## Related skills

`roblox-security` (duplication and trade exploits), `roblox-monetization` (receipts),
`roblox-open-cloud` (external access, bulk operations), `roblox-teleport-matchmaking`.

---

<a id="reference-references-memory-and-messaging-md"></a>

## Appendix: references/memory-and-messaging.md

### MemoryStore and MessagingService recipes

## Matchmaking queue (MemoryStoreQueue)

```luau
--!strict
local MemoryStoreService = game:GetService("MemoryStoreService")

local queue = MemoryStoreService:GetQueue("Ranked1v1", 30) -- 30 s invisibility timeout
local EXPIRATION = 300

local function enqueue(player: Player)
	local ok, err = pcall(function()
		queue:AddAsync({ userId = player.UserId, rating = 1000 }, EXPIRATION)
	end)
	if not ok then
		warn("enqueue failed:", err)
	end
end

-- One matchmaker loop (e.g. on every server, or a dedicated lobby server).
local function matchmakeOnce()
	local ok, items, readId = pcall(function()
		return queue:ReadAsync(2, true, 5) -- exactly 2 items or none; wait up to 5 s
	end)
	if not ok or not items or #items < 2 then
		return
	end
	-- Reserve a server and teleport both players (see roblox-teleport-matchmaking) ...
	-- Only after success, remove the items; otherwise they reappear after the invisibility timeout.
	pcall(function()
		queue:RemoveAsync(readId)
	end)
end

return { enqueue = enqueue, matchmakeOnce = matchmakeOnce }
```

For many game modes and skill-based matching, prefer Roblox's built-in **matchmaking** (configurable
scoring for which server a player joins) where it fits, and see `roblox-teleport-matchmaking`.

## Live leaderboard / server list (MemoryStoreSortedMap)

```luau
--!strict
local MemoryStoreService = game:GetService("MemoryStoreService")

local servers = MemoryStoreService:GetSortedMap("ActiveServers")

local function heartbeat(playerCount: number)
	pcall(function()
		-- value, expiration (s), sort key: sorts by player count
		servers:SetAsync(game.JobId, { players = playerCount, placeId = game.PlaceId }, 60, playerCount)
	end)
end

local function topServers(): { any }
	local ok, entries = pcall(function()
		return servers:GetRangeAsync(Enum.SortDirection.Descending, 20)
	end)
	return if ok then entries else {}
end

return { heartbeat = heartbeat, topServers = topServers }
```

Entries are `{ key, value, sortKey }`. Refresh with a TTL shorter than the heartbeat interval × 2 so
dead servers disappear on their own.

## Atomic counters (MemoryStoreHashMap)

```luau
--!strict
local MemoryStoreService = game:GetService("MemoryStoreService")

local counters = MemoryStoreService:GetHashMap("EventCounters")

local function increment(name: string, by: number): number?
	local ok, result = pcall(function()
		return counters:UpdateAsync(name, function(old: number?)
			return (old or 0) + by
		end, 86400)
	end)
	return if ok then result else nil
end

return increment
```

## Cross-server announcements (MessagingService)

```luau
--!strict
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

local TOPIC = "Announcements"

local function publish(text: string)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, { text = text, from = game.JobId }) -- ≤ 1 kB
	end)
	if not ok then
		warn("publish failed:", err)
	end
end

task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local payload = message.Data -- message.Sent is the publish timestamp
			if typeof(payload) == "table" and typeof(payload.text) == "string" then
				for _, player in Players:GetPlayers() do
					print(`announce to {player.Name}: {payload.text}`)
				end
			end
		end)
	end)
	if not ok then
		warn("subscribe failed:", err)
	end
end)

return publish
```

- Any text shown to players that originated from a player must be filtered (`roblox-text-chat`).
- Messages can be missed (server starting, throttling). For state that must converge, store it in a
  DataStore/MemoryStore and use messages only as a "go re-read" hint.

## Data store vs memory store

| | DataStore | MemoryStore |
| --- | --- | --- |
| Durability | Persistent, versioned | Expires (≤ 45 days); evicted at quota |
| Latency | Higher | Low |
| Use | Player progress, purchases, anything valuable | Queues, live rankings, sessions, locks, caches |

---

<a id="reference-references-raw-datastore-md"></a>

## Appendix: references/raw-datastore.md

### Player data with raw DataStoreService (session-locked)

Use this when a project can't use ProfileStore. It shows every moving part: session lock, retries,
autosave with jitter, and shutdown flushing. Keep it in `ServerScriptService`.

```luau
--!strict
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STORE = DataStoreService:GetDataStore("PlayerData")
local AUTOSAVE_INTERVAL = 180
local LOCK_EXPIRY = 600 -- a lock older than this is considered abandoned (crashed server)
local SERVER_ID = if RunService:IsStudio() then "studio-" .. HttpService:GenerateGUID(false) else game.JobId

type PlayerData = { version: number, coins: number, inventory: { [string]: number } }
type Record = { data: PlayerData, lock: { server: string, time: number }? }

local function defaultData(): PlayerData
	return { version = 1, coins = 0, inventory = {} }
end

local sessions: { [Player]: PlayerData } = {}

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local waitTime = 1
	for attempt = 1, 5 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`{label} failed (attempt {attempt}): {result}`)
		task.wait(waitTime + math.random())
		waitTime = math.min(waitTime * 2, 16)
	end
	return false, nil
end

local function keyFor(player: Player): string
	return `User_{player.UserId}`
end

-- Acquire the session lock and return the data, or nil if another live server holds it.
local function load(player: Player): PlayerData?
	local loaded: PlayerData? = nil
	local ok = withRetries("load", function()
		STORE:UpdateAsync(keyFor(player), function(record: Record?): Record?
			local now = os.time()
			local current: Record = record or { data = defaultData(), lock = nil }
			local lock = current.lock
			if lock and lock.server ~= SERVER_ID and now - lock.time < LOCK_EXPIRY then
				loaded = nil
				return nil -- cancel the write: someone else owns this session
			end
			current.lock = { server = SERVER_ID, time = now }
			loaded = current.data
			return current
		end)
		return true
	end)
	return if ok then loaded else nil
end

local function save(player: Player, release: boolean)
	local data = sessions[player]
	if not data then
		return
	end
	withRetries("save", function()
		STORE:UpdateAsync(keyFor(player), function(record: Record?): (Record?, { number }?)
			if record and record.lock and record.lock.server ~= SERVER_ID then
				return nil, nil -- we lost the lock; never overwrite another server's session
			end
			local newRecord: Record = {
				data = data,
				lock = if release then nil else { server = SERVER_ID, time = os.time() },
			}
			return newRecord, { player.UserId } -- user IDs link the key for right-to-be-forgotten
		end)
		return true
	end)
end

local function onPlayerAdded(player: Player)
	local data = nil
	for _ = 1, 3 do -- the previous server may still be releasing the lock after a teleport
		data = load(player)
		if data or player.Parent ~= Players then
			break
		end
		task.wait(5)
	end
	if player.Parent ~= Players then
		return
	end
	if not data then
		player:Kick("Your data is still in use on another server. Please rejoin shortly.")
		return
	end
	sessions[player] = data
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player, true)
	sessions[player] = nil
end)

task.spawn(function()
	task.wait(math.random() * AUTOSAVE_INTERVAL) -- stagger servers
	while true do
		for player in sessions do
			task.spawn(save, player, false)
		end
		task.wait(AUTOSAVE_INTERVAL)
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1) -- let PlayerRemoving saves start in Studio
	end
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			save(player, true)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
end)
```

## Notes

- `UpdateAsync`'s transform can run more than once (on conflicts); keep it side-effect free apart from
  capturing the result as above.
- `BindToClose` has about 30 seconds in total. Save all players in parallel, not sequentially.
- A kicked or crashed server leaves a stale lock; `LOCK_EXPIRY` recovers after 10 minutes. ProfileStore
  resolves conflicts faster by messaging the lock holder.
- In Studio, use a separate data store name (e.g. `PlayerData_Studio`) or a separate test universe.
- Log failures to analytics; if a save ultimately fails on leave, the next server loads the last
  good version — never write partial or default data over a failed load.
