---
name: roblox-architecture
description: Roblox project structure and client/server model - replication, where code and assets belong (ServerScriptService, ReplicatedStorage, StarterPlayer), RunContext, service/controller bootstrapping, player/character lifecycle, CollectionService components, attributes, streaming-safe client code, library choices. Use when starting a project, deciding where code goes, or fixing replication/streaming bugs.
enabled: true
---
# Roblox game architecture

## The model in one paragraph

Every Roblox game is a **server** (authoritative, runs `Script`s, sees everything, owns DataStores)
plus one **client** per player (runs `LocalScript`s / client `Script`s, renders, reads input).
The server's DataModel **replicates** to clients automatically. Client changes do **not** replicate
back, except: physics of parts the client has network ownership of (its character by default),
its own `Humanoid` state/animations, and remote calls. Assume every client is compromised
(see `roblox-security`). Design every feature as: *client requests → server validates and
decides → state replicates → clients render*.

## Where things go

| Container | Runs/visible on | Put here |
| --- | --- | --- |
| `ServerScriptService` | Server only | Server `Script`s and server-only ModuleScripts (game logic, data, anti-cheat). |
| `ServerStorage` | Server only | Server-only assets: maps, NPC templates, tools to clone, secrets-adjacent config. |
| `ReplicatedStorage` | Both | Shared modules (types, config, pure utils), `RemoteEvent`s, assets clients clone. |
| `ReplicatedFirst` | Client, first | Loading screen only. Replicates before everything else. |
| `StarterPlayer.StarterPlayerScripts` | Client (copied once to `PlayerScripts`) | Client entry point and controllers. |
| `StarterPlayer.StarterCharacterScripts` | Client (copied per spawn into character) | Per-character client scripts (rarely needed). |
| `StarterGui` | Client (copied to `PlayerGui`) | `ScreenGui`s. Set `ResetOnSpawn = false` unless you want reset on death. |
| `Workspace` | Both (streamed to clients) | The 3D world only. Not a place for code or templates. |
| `Lighting`, `SoundService`, `Teams`, `TextChatService` | Both | Their respective config objects. |

Rules:
- Code in `ReplicatedStorage` is **downloadable by exploiters**. Never put server logic, secrets,
  admin lists, or anti-cheat thresholds there.
- `Script.RunContext`: `Legacy` (default: behavior depends on the container), `Server`, `Client`, or
  `Plugin`. A non-Legacy RunContext makes a `Script` run **regardless of container** (e.g. a `Client`
  Script in `ReplicatedStorage` runs on every client) — so templates you clone must not contain such
  scripts unintentionally. Legacy `Script`s don't run in `ReplicatedStorage`/`ServerStorage`.

## Project layout (Rojo-style, recommended)

```text
src/
  server/            -> ServerScriptService.Server   (init.server.luau = entry point)
    Services/        -> one ModuleScript per system (DataService, CombatService, ...)
  client/            -> StarterPlayer.StarterPlayerScripts.Client (init.client.luau)
    Controllers/     -> one ModuleScript per client system (InputController, UIController, ...)
  shared/            -> ReplicatedStorage.Shared (types, config, pure logic, network definitions)
Packages/            -> ReplicatedStorage.Packages (Wally/pesde dependencies)
ServerPackages/      -> ServerScriptService.ServerPackages
```

One entry script per side, everything else is a ModuleScript. This gives deterministic load order,
testable modules, and a single place to wire dependencies. Roblox's own recommendation is equivalent:
one `Script` (`RunContext = Server`) in `ServerScriptService` and one `Script` (`RunContext = Client`) in
`ReplicatedStorage`, each requiring modules and calling their `start()`. Tooling setup: `roblox-tooling`.

## Bootstrapping services (no framework needed)

```luau
--!strict
-- ServerScriptService/Server/init.server.luau
type Service = {
	init: ((self: Service) -> ())?, -- sync setup; may reference other services; must not yield
	start: ((self: Service) -> ())?, -- runs after every init; may yield / connect events
}

local servicesFolder = script:WaitForChild("Services")
local services: { [string]: Service } = {}

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		services[module.Name] = (require :: any)(module)
	end
end

for name, service in services do
	if service.init then
		debug.setmemorycategory(name)
		service:init()
		debug.resetmemorycategory()
	end
end

for name, service in services do
	if service.start then
		task.spawn(function()
			debug.setmemorycategory(name)
			service:start()
		end)
	end
end
```

- Services reference each other with plain `require` (no cycles) or receive dependencies in `init`.
- The client mirrors this with `Controllers`. Keep names symmetrical (`ShopService` / `ShopController`).
- Frameworks like Knit are unnecessary for this; if a project already uses one, follow its conventions.

## Player and character lifecycle

```luau
--!strict
local Players = game:GetService("Players")

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		print(`{player.Name} died`)
	end)
end

local function onPlayerAdded(player: Player)
	-- Load data first (see roblox-data-stores), then set up character handling.
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

local function onPlayerRemoving(player: Player)
	-- Save data, release session locks, clear every table keyed by this player.
	print(`{player.Name} left`)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do -- players who joined before this script connected
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	-- Server shutdown: flush saves for remaining players (max ~30 s total).
end)
```

- Always handle players/characters that already exist when your code starts.
- Characters respawn: anything bound to a character must be re-created on `CharacterAdded`.
- On the client, character descendants may not exist yet (streaming): `WaitForChild` them.

## Components with CollectionService tags

Tag instances (Studio **Tags** section or `CollectionService:AddTag`) and attach behavior in code.
This scales better than copying scripts into every model and works with streaming because the
added/removed signals fire as instances stream in and out.

```luau
--!strict
local CollectionService = game:GetService("CollectionService")

local TAG = "KillBrick"
local cleanups: { [Instance]: () -> () } = {}

local function onAdded(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local connection = instance.Touched:Connect(function(hit)
		local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end)
	cleanups[instance] = function()
		connection:Disconnect()
	end
end

local function onRemoved(instance: Instance)
	local cleanup = cleanups[instance]
	if cleanup then
		cleanup()
		cleanups[instance] = nil
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(onRemoved)
for _, instance in CollectionService:GetTagged(TAG) do
	task.spawn(onAdded, instance)
end
```

Configure components with **attributes** (`instance:GetAttribute("Damage")`,
`GetAttributeChangedSignal`) instead of `IntValue`/`StringValue` children. Attributes replicate
server → client, are cheaper, and show in the Properties panel.

## Sharing state

| Need | Use |
| --- | --- |
| Small per-instance/per-player values visible to clients | Attributes on the instance / `Player` (server sets). |
| Events and requests | `RemoteEvent` / `UnreliableRemoteEvent` (see `roblox-networking`). |
| Large or per-player private state (inventory, quests) | Server-owned tables + remotes that send snapshots/diffs to that player only. |
| Same-side communication | Module function calls or a typed Signal module — not `BindableEvent`, `_G`, or `shared`. |
| Persistent data | `roblox-data-stores`. Cross-server: MessagingService / MemoryStore. |

## Streaming (on by default for new places)

With `Workspace.StreamingEnabled`, clients only have nearby parts. Client code must:
- `WaitForChild` (with a timeout when it may never arrive) or nil-check anything in `Workspace`.
- Use `ModelStreamingMode = Atomic` for models whose parts scripts need together;
  `Persistent` only when a model must always be present (costs memory).
- Treat `GetChildren`, raycasts, and property reads of streamed-out parts as partial/stale; do full-world
  queries on the server.
- Pre-stream destinations on the server with `player:RequestStreamAroundAsync(position)` before teleporting a character.
- Scopes, racing, free cameras: `player.FrustumStreaming = Enum.FrustumStreamingMode.Automatic` streams what
  the camera sees instead of raising the radius.

Full pattern catalog and recommended Workspace settings: [references/streaming.md](#reference-references-streaming-md).

## Anti-patterns

- Dozens of loose `Script`s inside parts/models (use tags + one service).
- Polling loops (`while task.wait(0.1) do check() end`) instead of events or `Heartbeat` with `deltaTime`.
- Trusting the client for game state, or firing remotes every frame.
- `_G`/`shared` globals, circular requires, yielding at module top level.
- Cloning maps into `Workspace` from the client (client-only copies never get server updates).
- Storing per-player data in the character (it's destroyed on death).

Library ecosystem (signals, cleanup, networking, UI, ECS, data): [references/ecosystem.md](#reference-references-ecosystem-md).

## Related skills

`roblox-networking`, `roblox-security`, `roblox-data-stores`, `roblox-tooling`, `roblox-performance`, `roblox-game-systems`.

---

<a id="reference-references-ecosystem-md"></a>

## Appendix: references/ecosystem.md

### Roblox open-source ecosystem (2026)

Guidance, not endorsements. **Always check the project's repository for its current status and API
before adding it** — several popular libraries were archived or rewritten recently. If a project already
uses a library, follow it instead of introducing an alternative. Install with Wally or pesde (see
`roblox-tooling`).

## Frameworks

- **None (recommended)** — a single entry script per side that requires service/controller modules
  (see SKILL.md). Fully typed, no magic.
- **Knit** — archived by its author in July 2024. Don't start new projects on it; maintain existing ones.
- **Flamework** — decorator-based framework for roblox-ts projects.

## Utilities

| Need | Libraries |
| --- | --- |
| Signals | `sleitnick/signal`, GoodSignal, LemonSignal |
| Cleanup | Trove (`sleitnick/trove`), Janitor, Maid |
| Promises | `evaera/promise` (Promise-based async; optional — plain `task` + `pcall` is fine) |
| Tables/functional | Sift, Dash |

## Networking (buffer-packed, schema-driven)

- **Zap** and **Blink** — IDL compilers: you write a schema, they generate typed, validated,
  buffer-serialized remote code for client and server. Both have had rewrites/forks; check which
  branch/fork is maintained.
- **ByteNet**, **Packet** — runtime (non-codegen) buffer networking libraries.
- Plain `RemoteEvent`s are fine for most games; adopt these when bandwidth or remote CPU shows up in profiling.

## Data

- **ProfileStore** (loleris) — session-locked player data, successor to ProfileService; uses
  MessagingService to resolve lock conflicts quickly. The default choice for player data.
- **Lapis** — alternative DataStore wrapper with session locking and migrations.
- **Replica** (loleris) — replicate server state tables to clients.
- DataStore2 — legacy; don't use for new work.

## UI

- **React** (`jsdotlua/react` + `jsdotlua/react-roblox`, the Roblox port of React 17) — hooks, large apps.
- **Fusion** — reactive state + declarative instances.
- **Vide** — lightweight reactive UI library.
- Plain instances + Studio's UI editor + StyleSheets for simple UIs.

## ECS

- **jecs** — fast archetype ECS with relationships and a typed Luau API.
- **Matter** — earlier ECS with a debugger; less active.

## Testing / tooling libs

- **Jest Lua** (`jsdotlua/jest`) — Jest port; the modern test framework. TestEZ is legacy.
- See `roblox-testing` and `roblox-tooling`.

## roblox-ts

TypeScript → Luau compiler (`roblox-ts`, npm `@rbxts/*` packages). If a project has `tsconfig.json` and
`@rbxts/types`, write TypeScript, not Luau, and use `@rbxts/services` imports.

---

<a id="reference-references-streaming-md"></a>

## Appendix: references/streaming.md

### Instance streaming — settings and client patterns

Source: Roblox "Instance streaming" and "Techniques and conversion" docs (2026).

## Recommended Workspace settings

| Property | Value |
| --- | --- |
| `StreamingEnabled` | `true` (default for new places; required by server authority) |
| `ModelStreamingBehavior` | `Improved` |
| `StreamingIntegrityMode` | `PauseOutsideLoadedArea` |
| `StreamingMinRadius` | `64` (default) |
| `StreamingTargetRadius` | `1024` (default) |
| `StreamOutBehavior` | `Opportunistic` (lowers client memory, prevents OOM crashes) |
| `EnableSLIMAvatars` | `Enabled` (lightweight stand-ins for distant R15 avatars) |

## Model settings

- `Model.ModelStreamingMode`:
  - `Default`/`Nonatomic` — parts stream individually.
  - `Atomic` — all **initial** descendants arrive together; scripts can index children directly once the
    model exists. Instances added later are not atomic.
  - `Persistent` — always present on every client, never streams out. Use sparingly (memory).
  - `PersistentPerPlayer` — persistent only for players added via `Model:AddPersistentPlayer(player)`.
- `Model.LevelOfDetail = SLIM` for static models: distant models render as optimized composite meshes.
  Not for animated or runtime-modified models.
- Keep models spatially compact (≈64 studs extents); split huge "container" models; flatten nesting
  (a persistent model inside an atomic one forces the parent persistent).

## Client script patterns

| Pattern | Problem under streaming | Fix |
| --- | --- | --- |
| `workspace.House1.Door` | Errors if not streamed in. | `WaitForChild` (with timeout if optional), nil-check, or make `House1` Atomic. |
| `character.Humanoid` in `CharacterAdded` | Character is parented before descendants replicate. | `character:WaitForChild("Humanoid")`. |
| Remote carries an `Instance` | Signal can arrive before (or without) the instance. | `WaitForChild` with timeout, pre-stream with `RequestStreamAroundAsync`, or tolerate `nil`. |
| Reading `part.Position` of a far part | Returns the last replicated (stale) value. | Do distance logic on the server, or check `part:IsDescendantOf(workspace)`. |
| `folder:GetChildren()` / `GetDescendants()` | Only streamed-in subset. | Enumerate on the server, or `PersistentPerPlayer`, or document that partial is fine. |
| Client raycasts / `GetPartBoundsInBox` | Only streamed-in geometry. | Full-world queries on the server; local-radius queries are fine. |
| `ChildAdded` / tag added signals | Fire again on every stream-in. | Mark first-time effects with an attribute; treat add/remove as stream in/out. |
| Cloning map from ReplicatedStorage on client | Client copy never receives server updates; can stream out. | Build the world on the server. |
| Loading screen waits for a map part | Hangs: no replication focus before spawn. | Wait for character + surroundings, or `player:AddReplicationFocus(part)` before spawn. |
| `Sound`/`AudioPlayer` in a far part | Stops when the part streams out. | Parent ambient audio to a persistent model or `SoundService`. |
| `Touched`, `ProximityPrompt`, `ClickDetector` | Don't work for clients without the part. | Expected; keep interactions local to the player. |
| Client pathfinding | Sees only streamed geometry. | Compute paths on the server. |

```luau
--!strict
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		warn("Humanoid did not replicate in time")
		return
	end
	print("walk speed", humanoid.WalkSpeed)
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
```

## Proactive streaming (server)

```luau
--!strict
local function teleportCharacter(player: Player, target: CFrame)
	local ok, err = pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5) -- optional timeout in seconds
	end)
	if not ok then
		warn(err)
	end
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(target)
	end
end

return teleportCharacter
```

`Player:AddReplicationFocus(part)` / `RemoveReplicationFocus(part)` keep an extra area loaded for a player
(e.g. a camera cutscene location). Keep the number of extra foci small.

## Frustum streaming (camera view)

`Player.FrustumStreaming` also streams what the camera looks at (out to the render distance, max 100,000
studs) without raising the radius in every direction — scopes, racing, free cameras. Opt-in per player:

- `Enum.FrustumStreamingMode.Automatic` — the engine turns it on for narrow FOV, fast movement in the
  looking direction, or a camera far from the avatar. Best default.
- `Enabled` / `Disabled` — manual control, e.g. force it on when a scope starts equipping. Set it on the server.
- No occlusion culling; wider FOV streams more. With `Opportunistic` stream-out, things leave shortly after
  they exit the view (and the normal radius). Usual streaming-safe client code still applies.

```luau
--!strict
local function setScoped(player: Player, scoped: boolean)
	player.FrustumStreaming = if scoped then Enum.FrustumStreamingMode.Enabled else Enum.FrustumStreamingMode.Automatic
end

return setScoped
```

## Testing

- Test with `StreamingTargetRadius = 64` to surface bugs.
- Traverse the whole map, teleport between distant areas, revisit areas.
- Watch Output/Developer Console for `attempt to index nil with ...`.
- Roblox publishes an official AI **streaming conversion skill** (`/rbx-convert-to-streaming`) that runs
  through the Studio MCP server; see the `roblox-studio-mcp` skill.
