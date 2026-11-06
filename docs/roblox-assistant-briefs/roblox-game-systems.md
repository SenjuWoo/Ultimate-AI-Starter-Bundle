---
name: roblox-game-systems
description: Recipes for common systems built on server authority - currency service and leaderstats, XP/levels, round loops with intermission and teams, validated melee/ranged combat, inventory and tools, soft-currency shops, obby checkpoints, daily rewards, pets. Use when implementing or reviewing gameplay systems such as rounds, combat, weapons, inventories, shops, currencies, or progression.
enabled: true
---
# Game systems recipes

Every recipe follows the same contract:
1. **State lives on the server** in a service module; persistent parts go through the data layer
   (`roblox-data-stores`).
2. **Clients send intents** through validated, rate-limited remotes (`roblox-security`,
   `roblox-networking`) and render state they receive (attributes, snapshots/deltas).
3. **Config is data**: tunables in a shared/server config module (or live `ConfigService` configs).
4. **Lifecycle-safe**: handles late joiners, respawns, leaving mid-action, and server shutdown.

| System | Reference |
| --- | --- |
| Leaderstats, currency service, XP/levels, daily rewards, obby checkpoints | [references/progression.md](#reference-references-progression-md) |
| Round loop (intermission → match → results), teams, spawning | [references/round-system.md](#reference-references-round-system-md) |
| Melee and ranged combat with server validation, cooldowns, damage attribution | [references/combat.md](#reference-references-combat-md) |
| Inventory, equipping tools, shop purchases (soft currency), pets that follow | [references/inventory-shop.md](#reference-references-inventory-shop-md) |

## Currency service (the pattern every economy uses)

```luau
--!strict
-- ServerScriptService/Server/Services/CurrencyService.luau
local Players = game:GetService("Players")

type Balances = { [Player]: number }

local MAX_BALANCE = 1e12

local CurrencyService = {}
local balances: Balances = {}

local function publish(player: Player)
	player:SetAttribute("Coins", balances[player]) -- replicated to every client; UI listens
end

function CurrencyService.load(player: Player, saved: number?)
	balances[player] = math.clamp(saved or 0, 0, MAX_BALANCE)
	publish(player)
end

function CurrencyService.get(player: Player): number
	return balances[player] or 0
end

-- Positive amount only; returns the new balance.
function CurrencyService.add(player: Player, amount: number, _source: string): number?
	local balance = balances[player]
	if balance == nil or not math.isfinite(amount) or amount <= 0 then
		return nil
	end
	balances[player] = math.min(balance + math.floor(amount), MAX_BALANCE)
	publish(player)
	return balances[player]
end

-- Atomic check-and-spend; false if insufficient.
function CurrencyService.spend(player: Player, amount: number, _sink: string): boolean
	local balance = balances[player]
	if balance == nil or not math.isfinite(amount) or amount <= 0 or balance < amount then
		return false
	end
	balances[player] = balance - math.floor(amount)
	publish(player)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	balances[player] = nil -- after the data layer has saved it
end)

return CurrencyService
```

- One module owns each resource; nothing else writes it. Log sources/sinks to analytics
  (`roblox-analytics-liveops`).
- The in-memory balance is saved by the data layer (ProfileStore `profile.Data.coins`) — or make the
  profile table the balance store directly.
- For display, clients read `player:GetAttribute("Coins")` and `GetAttributeChangedSignal("Coins")`.
  `leaderstats` (a Folder with `IntValue`s under the player) shows values in the player list.

## Design checklist for any new system

- [ ] Where does authoritative state live, and how is it persisted?
- [ ] What can the client request, and how is each request validated and rate-limited?
- [ ] What happens on join mid-session, respawn, leave, teleport, and server shutdown?
- [ ] How is it tuned (config) and measured (analytics)?
- [ ] How does it behave with 1 player, full servers, and high latency?
- [ ] Is it streaming-safe on the client?

## Related skills

`roblox-architecture`, `roblox-security`, `roblox-data-stores`, `roblox-networking`,
`roblox-characters-animation`, `roblox-monetization`, `roblox-ui`.

---

<a id="reference-references-combat-md"></a>

## Appendix: references/combat.md

### Server-validated combat

Clients predict (play the swing/shot instantly) and send **intent**; the server owns cooldowns, hit
detection or hit validation, and damage.

## Weapon config (shared)

```luau
--!strict
-- ReplicatedStorage/Shared/WeaponConfig.luau
export type Weapon = {
	kind: "Melee" | "Ranged",
	damage: number,
	cooldown: number,
	range: number,
	hitboxSize: Vector3?, -- melee
}

return table.freeze({
	Sword = { kind = "Melee", damage = 25, cooldown = 0.6, range = 7, hitboxSize = Vector3.new(6, 5, 7) },
	Blaster = { kind = "Ranged", damage = 18, cooldown = 0.25, range = 300 },
} :: { [string]: Weapon })
```

## Server combat service

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local attackRemote = Instance.new("RemoteEvent")
attackRemote.Name = "Attack"
attackRemote.Parent = ReplicatedStorage

local lastAttack: { [Player]: number } = {}
local equipped: { [Player]: string } = {} -- set by the inventory/tool system, never by the client

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid.RootPart
end

local function damageModel(model: Model, attacker: Player, amount: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local victim = Players:GetPlayerFromCharacter(model)
	if not humanoid or humanoid.Health <= 0 or victim == attacker then
		return
	end
	if victim and victim.Team and victim.Team == attacker.Team and not victim.Neutral then
		return -- no friendly fire
	end
	humanoid:SetAttribute("LastAttacker", attacker.UserId)
	humanoid:TakeDamage(amount)
end

local function meleeAttack(player: Player, root: BasePart, damage: number, range: number, hitboxSize: Vector3)
	-- Server-side hitbox in front of the attacker (uses server positions: no client-reported targets).
	local boxCFrame = root.CFrame * CFrame.new(0, 0, -range / 2)
	overlap.FilterDescendantsInstances = { player.Character :: Model }
	local hitModels: { [Model]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, hitboxSize, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not hitModels[model] then
			hitModels[model] = true
			damageModel(model, player, damage)
		end
	end
end

local function rangedAttack(player: Player, root: BasePart, damage: number, range: number, direction: Vector3)
	-- Client sends only an aim direction; the server casts from its own muzzle position.
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local offset = direction.Unit * range
	rayParams.FilterDescendantsInstances = { player.Character :: Model }
	local result = workspace:Raycast(origin, offset, rayParams)
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model then
			damageModel(model, player, damage)
		end
	end
	attackRemote:FireAllClients(player, origin, if result then result.Position else origin + offset)
end

attackRemote.OnServerEvent:Connect(function(player: Player, direction: unknown)
	local weaponName = equipped[player]
	local weapon = weaponName and WeaponConfig[weaponName]
	local root = rootOf(player)
	if not weapon or not root then
		return
	end
	local now = os.clock()
	if now - (lastAttack[player] or 0) < weapon.cooldown * 0.9 then -- small tolerance for jitter
		return
	end
	lastAttack[player] = now

	if weapon.kind == "Melee" then
		meleeAttack(player, root, weapon.damage, weapon.range, weapon.hitboxSize or Vector3.one * 5)
	elseif
		typeof(direction) == "Vector3"
		and direction.Magnitude > 0.01
		and direction.Magnitude == direction.Magnitude
	then
		rangedAttack(player, root, weapon.damage, weapon.range, direction) -- Magnitude == Magnitude rejects NaN
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
	equipped[player] = nil
end)

return { equipped = equipped }
```

## Lag compensation (fast shooters)

Server-side raycasts against **current** server positions miss targets the shooter saw earlier.
Options:
- **Hit claims + validation**: client reports `(targetCharacter, hitPosition, clientTime)`; server checks
  the target was within tolerance of that position recently (keep a short position history per
  character, ~1 s, sampled on Heartbeat, rewound by `player:GetNetworkPing()`), line of sight against
  static geometry, range, and fire rate.
- **Server authority** mode handles prediction/rollback for you (`roblox-physics`).

## Client side

- On input: play the animation/sound/muzzle flash immediately, then `Attack:FireServer(aimDirection)`.
- On `Attack.OnClientEvent(shooter, from, to)`: draw tracers for other players' shots (skip your own if
  already predicted).
- Health bars read `Humanoid.Health`; damage numbers from a server event carrying `(target, amount)`.
- Use `GetMarkerReachedSignal` on swing animations to time client VFX; the server uses its own timing.

---

<a id="reference-references-inventory-shop-md"></a>

## Appendix: references/inventory-shop.md

### Inventory, equipment, shop, pets

## Item catalog (server-authoritative data)

```luau
--!strict
-- ReplicatedStorage/Shared/Items.luau — shared so clients can render names/icons/prices.
-- The server still re-reads prices from here; never from client messages.
export type Item = {
	id: string,
	name: string,
	price: number?, -- nil = not sold in the shop
	maxStack: number,
	toolTemplate: string?, -- name of a Tool in ServerStorage.Tools
}

local Items: { [string]: Item } = {
	Sword = { id = "Sword", name = "Iron Sword", price = 100, maxStack = 1, toolTemplate = "Sword" },
	Potion = { id = "Potion", name = "Health Potion", price = 25, maxStack = 20 },
}

return table.freeze(Items)
```

## Inventory service (server)

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Items = require(ReplicatedStorage.Shared.Items)

type Inventory = { [string]: number }

local inventories: { [Player]: Inventory } = {} -- point this at profile.Data.inventory on load
local changed = Instance.new("RemoteEvent")
changed.Name = "InventoryChanged"
changed.Parent = ReplicatedStorage

local InventoryService = {}

function InventoryService.load(player: Player, saved: Inventory)
	inventories[player] = saved
	changed:FireClient(player, "snapshot", saved)
end

function InventoryService.count(player: Player, itemId: string): number
	local inventory = inventories[player]
	return inventory and inventory[itemId] or 0
end

function InventoryService.add(player: Player, itemId: string, amount: number): boolean
	local inventory = inventories[player]
	local item = Items[itemId]
	if not inventory or not item or amount <= 0 then
		return false
	end
	local current = inventory[itemId] or 0
	if current + amount > item.maxStack then
		return false
	end
	inventory[itemId] = current + amount
	changed:FireClient(player, "delta", itemId, inventory[itemId])
	return true
end

function InventoryService.remove(player: Player, itemId: string, amount: number): boolean
	local inventory = inventories[player]
	local current = inventory and inventory[itemId] or 0
	if not inventory or amount <= 0 or current < amount then
		return false
	end
	local remaining = current - amount
	inventory[itemId] = if remaining > 0 then remaining else nil
	changed:FireClient(player, "delta", itemId, remaining)
	return true
end

-- Equip = clone the Tool template into the backpack; the tool's behavior lives in a tagged service.
function InventoryService.equip(player: Player, itemId: string): boolean
	local item = Items[itemId]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not item or not item.toolTemplate or not backpack or InventoryService.count(player, itemId) < 1 then
		return false
	end
	local template = ServerStorage:WaitForChild("Tools"):FindFirstChild(item.toolTemplate)
	if not template or backpack:FindFirstChild(template.Name) then
		return false
	end
	template:Clone().Parent = backpack
	return true
end

Players.PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)

return InventoryService
```

Tools in the backpack are lost on respawn unless re-granted: re-equip owned items on `CharacterAdded`
(or clone into `player.StarterGear` so Roblox restores them).

## Shop purchase with soft currency (server)

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Items = require(ReplicatedStorage.Shared.Items)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local InventoryService = require(ServerScriptService.Server.Services.InventoryService)

local buy = Instance.new("RemoteFunction")
buy.Name = "BuyItem"
buy.Parent = ReplicatedStorage

local lastBuy: { [Player]: number } = {}

buy.OnServerInvoke = function(player: Player, itemId: unknown): (boolean, string)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < 0.3 then
		return false, "Too fast"
	end
	lastBuy[player] = now

	if typeof(itemId) ~= "string" then
		return false, "Invalid item"
	end
	local item = Items[itemId]
	if not item or not item.price then
		return false, "Not for sale"
	end
	if InventoryService.count(player, itemId) >= item.maxStack then
		return false, "Inventory full"
	end
	if not CurrencyService.spend(player, item.price, `Shop:{itemId}`) then
		return false, "Not enough coins"
	end
	if not InventoryService.add(player, itemId, 1) then
		CurrencyService.add(player, item.price, "Refund") -- keep the operation atomic
		return false, "Could not add item"
	end
	return true, "Purchased"
end

Players.PlayerRemoving:Connect(function(player)
	lastBuy[player] = nil
end)
```

Robux purchases go through developer products and `ProcessReceipt` instead (`roblox-monetization`).

## Pets that follow the player

- Server spawns the pet model (cosmetic ownership is server-side data), sets
  `pet.PrimaryPart:SetNetworkOwner(player)` so the owner's client moves it smoothly, and replicates
  `PetOwner` as an attribute.
- The owner's client moves the pet each frame toward an offset behind the character with
  `AlignPosition`/`AlignOrientation` (see `roblox-physics` recipes) — or all clients animate every pet
  locally from the owner's position (no physics, cheapest for many pets).
- Hatching/random pets bought with Robux or Robux-bought currency are **paid random items**: disclose
  odds and respect `PolicyService` restrictions (`roblox-monetization`).

---

<a id="reference-references-progression-md"></a>

## Appendix: references/progression.md

### Progression recipes

## leaderstats (player list display)

```luau
--!strict
local Players = game:GetService("Players")

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats" -- exact lowercase name is required

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	local function sync()
		local value = player:GetAttribute("Coins")
		coins.Value = if typeof(value) == "number" then value else 0
	end
	sync()
	coins.Parent = leaderstats
	player:GetAttributeChangedSignal("Coins"):Connect(sync)

	leaderstats.Parent = player
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	task.spawn(setupLeaderstats, player)
end
```

`leaderstats` values are display only — the source of truth stays in the service/data layer.

## XP and levels

```luau
--!strict
local Levels = {}

-- XP needed to go from `level` to `level + 1`: gentle exponential curve.
function Levels.xpForLevel(level: number): number
	return math.floor(100 * level ^ 1.5)
end

-- Adds XP and returns the new (level, xp, levelsGained). Pure: easy to unit test.
function Levels.addXp(level: number, xp: number, amount: number, maxLevel: number): (number, number, number)
	local gained = 0
	xp += amount
	while level < maxLevel and xp >= Levels.xpForLevel(level) do
		xp -= Levels.xpForLevel(level)
		level += 1
		gained += 1
	end
	if level >= maxLevel then
		xp = 0
	end
	return level, xp, gained
end

print(Levels.addXp(1, 0, 450, 100))
return Levels
```

## Daily rewards with streaks (server)

```luau
--!strict
type RewardState = { lastClaimDay: number?, streak: number }

local REWARDS = { 50, 75, 100, 150, 200, 300, 500 } -- day 1..7, then repeat day 7

local function utcDay(): number
	return os.time() // 86400
end

-- Returns (granted amount or nil, reason). Mutates `state`.
local function claimDaily(state: RewardState): (number?, string)
	local today = utcDay()
	if state.lastClaimDay == today then
		return nil, "already claimed"
	end
	if state.lastClaimDay == today - 1 then
		state.streak += 1
	else
		state.streak = 1 -- missed a day (or first claim)
	end
	state.lastClaimDay = today
	return REWARDS[math.min(state.streak, #REWARDS)], "ok"
end

local state: RewardState = { streak = 0 }
print(claimDaily(state))
return claimDaily
```

Store `RewardState` in the player's profile; call from a rate-limited remote; save immediately after.
Show the next claim time using `(utcDay() + 1) * 86400` and `workspace:GetServerTimeNow()` on the client.

## Obby checkpoints (server-validated)

```luau
--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local stageOf: { [Player]: number } = {}

local function onCheckpoint(checkpoint: BasePart)
	local stage = checkpoint:GetAttribute("Stage")
	if typeof(stage) ~= "number" then
		return
	end
	checkpoint.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local current = stageOf[player] or 0
		if stage == current + 1 then -- only the next stage counts (no skipping ahead)
			stageOf[player] = stage
			player:SetAttribute("Stage", stage)
		end
	end)
end

for _, checkpoint in CollectionService:GetTagged("Checkpoint") do
	if checkpoint:IsA("BasePart") then
		onCheckpoint(checkpoint)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local stage = stageOf[player] or 0
		for _, checkpoint in CollectionService:GetTagged("Checkpoint") do
			if checkpoint:IsA("BasePart") and checkpoint:GetAttribute("Stage") == stage then
				task.defer(function()
					character:PivotTo(checkpoint.CFrame + Vector3.new(0, 4, 0))
				end)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	stageOf[player] = nil
end)
```

Add timing heuristics (minimum plausible time per stage) to flag teleport exploits (`roblox-security`).

---

<a id="reference-references-round-system-md"></a>

## Appendix: references/round-system.md

### Round-based game loop

State machine on the server; clients render from replicated attributes on a shared instance.
Timers use absolute end times so clients count down locally without per-second remotes.

```luau
--!strict
-- ServerScriptService/Server/Services/RoundService.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

type Phase = "Waiting" | "Intermission" | "Playing" | "Results"

local MIN_PLAYERS = 2
local INTERMISSION = 15
local ROUND_LENGTH = 180
local RESULTS = 8

-- Shared state instance: clients read attributes (Phase, PhaseEndsAt, Map, Winner).
local state = Instance.new("Folder")
state.Name = "RoundState"
state.Parent = ReplicatedStorage

local maps = ServerStorage:WaitForChild("Maps")
local lobbySpawn = workspace:WaitForChild("LobbySpawn") :: BasePart

local participants: { [Player]: boolean } = {}
local currentMap: Model? = nil

local function setPhase(phase: Phase, duration: number?)
	state:SetAttribute("Phase", phase)
	state:SetAttribute("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else nil)
end

local function aliveParticipants(): { Player }
	local alive = {}
	for player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player.Parent == Players and humanoid and humanoid.Health > 0 then
			table.insert(alive, player)
		end
	end
	return alive
end

local function loadMap(): Model
	local choices = maps:GetChildren()
	local template = choices[math.random(1, #choices)] :: Model
	local map = template:Clone()
	map.Parent = workspace
	state:SetAttribute("Map", template.Name)
	return map
end

local function teleportTo(player: Player, target: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(target + Vector3.new(0, 4, 0))
	end
end

local function startRound()
	currentMap = loadMap()
	local spawns = (currentMap :: Model):WaitForChild("Spawns"):GetChildren()
	local red, blue = Teams:FindFirstChild("Red") :: Team?, Teams:FindFirstChild("Blue") :: Team?
	for index, player in Players:GetPlayers() do
		participants[player] = true
		if red and blue then
			player.Team = if index % 2 == 0 then red else blue
		end
		local spawnPart = spawns[(index - 1) % #spawns + 1] :: BasePart
		teleportTo(player, spawnPart.CFrame)
	end
end

local function endRound(winner: string)
	state:SetAttribute("Winner", winner)
	for player in participants do
		teleportTo(player, lobbySpawn.CFrame)
		player.Neutral = true
	end
	table.clear(participants)
	if currentMap then
		currentMap:Destroy()
		currentMap = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	participants[player] = nil -- leaving mid-round must not break win checks
end)

local function run()
	while true do
		if #Players:GetPlayers() < MIN_PLAYERS then
			setPhase("Waiting")
			repeat
				task.wait(1)
			until #Players:GetPlayers() >= MIN_PLAYERS
		end

		setPhase("Intermission", INTERMISSION)
		task.wait(INTERMISSION)
		if #Players:GetPlayers() < MIN_PLAYERS then
			continue
		end

		startRound()
		setPhase("Playing", ROUND_LENGTH)
		local deadline = os.clock() + ROUND_LENGTH
		local winner = "Nobody"
		while os.clock() < deadline do
			local alive = aliveParticipants()
			if #alive <= 1 then
				winner = if alive[1] then alive[1].Name else "Nobody"
				break
			end
			task.wait(0.5)
		end

		setPhase("Results", RESULTS)
		endRound(winner)
		task.wait(RESULTS)
	end
end

task.spawn(run)
return {}
```

## Client countdown

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local state = ReplicatedStorage:WaitForChild("RoundState")

RunService.Heartbeat:Connect(function()
	local endsAt = state:GetAttribute("PhaseEndsAt")
	local phase = state:GetAttribute("Phase")
	if typeof(endsAt) == "number" then
		local remaining = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		-- update a TextLabel only when `remaining` changes
		local _text = `{phase}: {remaining}s`
	end
end)
```

## Variations

- **Teams**: create `Team` objects in `Teams` (`AutoAssignable = false` when you assign manually); set
  `player.Team`; team spawns via `SpawnLocation.TeamColor`.
- **Late joiners** during `Playing`: spectate (camera on a random alive player) until next round.
- **Rewards**: grant through the currency service at `Results` for participants still in the server.
- **Round per reserved server** (competitive): the lobby teleports a full match to a reserved server
  that runs exactly one round, then teleports everyone back (`roblox-teleport-matchmaking`).
