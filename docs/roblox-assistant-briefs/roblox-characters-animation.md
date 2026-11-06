---
name: roblox-characters-animation
description: Characters and animation - Humanoid properties/states, spawning (LoadCharacterAsync), health and damage, HumanoidDescription appearance, Animator/AnimationTrack playback, priorities and markers, default animation replacement, Tools, TweenService, IKControl, Character Controller Library (beta). Use when changing movement, abilities, damage, respawn, avatars, animations, tweens, or tools/weapons.
enabled: true
---
# Characters and animation

## Character basics

- A player character is a `Model` with a `Humanoid`, `HumanoidRootPart` (the root; move the character
  with `character:PivotTo(cframe)`), R15 body parts, and an `Animate` LocalScript.
- Defaults (walk speed, jump, health, R6/R15, collisions, body scaling) are configured in Studio's
  **Avatar Settings** window and `StarterPlayer` (`CharacterWalkSpeed`, `CharacterJumpHeight` or
  `CharacterUseJumpPower` + `CharacterJumpPower`).
- Custom character: put a `Model` named `StarterCharacter` in `StarterPlayer`. Custom per-player
  spawns: `Players.CharacterAutoLoads = false`, then `player:LoadCharacterAsync()` when ready
  (e.g. after data loads). `LoadCharacter` (non-Async) is deprecated.
- Characters are destroyed and recreated on death/respawn: bind per-character logic in `CharacterAdded`.
- Client-set `WalkSpeed`/`JumpHeight` are trivially exploitable; enforce limits on the server or use
  server authority (`roblox-security`, `roblox-physics`).

## Health and damage (server)

```luau
--!strict
local Players = game:GetService("Players")

local function damage(target: Model, amount: number, source: Player?)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid:SetAttribute("LastDamagedBy", if source then source.UserId else 0)
	humanoid:TakeDamage(amount) -- respects ForceField; use Health -= amount to bypass
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.MaxHealth = 150
		humanoid.Health = 150
		humanoid.Died:Once(function()
			local killerId = humanoid:GetAttribute("LastDamagedBy")
			print(`{player.Name} died (killer {killerId})`)
		end)
	end)
end)

return damage
```

- Disable default regen by deleting/replacing the `Health` script via `StarterCharacterScripts`.
- `Humanoid.BreakJointsOnDeath = false` + ragdoll constraints for ragdolls.
- States: `humanoid:ChangeState(Enum.HumanoidStateType.Jumping)`, `SetStateEnabled(state, false)`,
  `StateChanged`. `MoveDirection`, `FloorMaterial`, `RootPart`, `SeatPart` are read-only helpers.
- `humanoid:MoveTo(position)` walks NPCs (times out after 8 s; re-issue for long paths — see `roblox-npc-ai`).

## Appearance

```luau
--!strict
local Players = game:GetService("Players")

local function applyUniform(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	if not ok then
		return
	end
	description.Shirt = 123456 -- asset ids
	description.Pants = 654321
	description.HeightScale = 1.05
	pcall(function()
		humanoid:ApplyDescriptionAsync(description) -- server-side; replicates
	end)
end

return applyUniform
```

`Player:LoadCharacterWithHumanoidDescriptionAsync(description)` spawns directly with an outfit.
All the non-Async variants (`ApplyDescription`, `GetHumanoidDescriptionFromUserId`, ...) are deprecated.

## Animation playback

```luau
--!strict
local function playAttack(character: Model, animation: Animation): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local track = animator:LoadAnimation(animation) -- Humanoid:LoadAnimation is deprecated
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:GetMarkerReachedSignal("Hit"):Connect(function(param)
		print("hit frame reached", param) -- apply damage window, play sound, etc.
	end)
	track:Play(0.1) -- fade time
	return track
end

return playAttack
```

- **Where to play**: the local player's own character → play on the client (replicates automatically via
  its Animator); NPCs → play on the server (or on clients for purely cosmetic, high-count NPCs).
- Load each `Animation` once per Animator and reuse the track; don't call `LoadAnimation` every time an
  action happens (there's a per-Animator track limit). Exception: server authority (query live tracks).
- Priorities: `Core < Idle < Movement < Action < Action2 < Action3 < Action4`. Blend with `AdjustWeight`,
  change speed with `AdjustSpeed`, stop with `Stop(fadeTime)`.
- Events: `track.Stopped`, `track.Ended`, markers via `GetMarkerReachedSignal` (`KeyframeReached` is superseded).
- Animation assets must be owned by (or shared with, via asset permissions) the experience's owner —
  otherwise they silently fail to play in live servers.
- Replace defaults by editing the `Animate` script's `StringValue`/`Animation` children
  (`animate.run.RunAnim.AnimationId`) on `CharacterAdded`, or ship a custom `Animate` in
  `StarterCharacterScripts`.
- Procedural: `IKControl` (look-at, foot planting, reaching) instead of hand-written joint math.

## Tweening

```luau
--!strict
local TweenService = game:GetService("TweenService")

local door = Instance.new("Part")
door.Anchored = true
door.Parent = workspace

local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local open = TweenService:Create(door, info, { CFrame = door.CFrame * CFrame.new(0, 8, 0) })
open.Completed:Once(function(state)
	print("door tween finished:", state)
end)
open:Play()
```

- Tween **anchored** parts or UI. For unanchored/physics objects use constraints.
- Tweening on the server replicates every frame and stutters: for visual-only motion, tween on each client
  (the server sets the final state or an attribute clients react to).
- Models: tween a `CFrameValue` and call `model:PivotTo(value)` in its `Changed` handler, or tween the
  primary part with the rest welded to it.
- `TweenService:GetValue(alpha, style, direction)` for custom interpolation; `SmoothDamp` for follow motion.

## Tools

`Tool` in `StarterPack`/`Backpack` with a `Handle` part (or `RequiresHandle = false`). `Equipped`,
`Unequipped`, `Activated` fire on both client and server (`Activated` comes from the client: validate
rate and state on the server). Keep weapon logic in modules and use tags rather than scripts inside
every tool clone.

## Character Controller Library (beta)

Roblox's CCL (`require("@rbx/AvatarAbilities")`) replaces the fixed Humanoid state machine with
composable **abilities** (Running, Jumping, Climbing, custom Dash...) coordinated by labels, sensors,
conditions (`StartsWhen`/`RunsWhile` with `All`/`Any`/`Not`), conflicts (`Blocks`/`Stops`/`Suspends`),
and lifecycle callbacks. Enable it via **File → Beta Features** and **Avatar Settings → Movement →
Abilities**. Only use it when the project has opted in; APIs may change while in beta.
Sketch: [references/character-controller-library.md](#reference-references-character-controller-library-md).

## Related skills

`roblox-npc-ai` (NPC movement), `roblox-physics` (ragdolls, knockback), `roblox-input` (ability inputs),
`roblox-security` (movement/damage validation), `roblox-game-systems` (combat).

---

<a id="reference-references-character-controller-library-md"></a>

## Appendix: references/character-controller-library.md

### Character Controller Library (CCL) — beta

Source: Roblox "Character Controller Library" and "Custom abilities" docs (2026). Beta: enable
**File → Beta Features → AvatarAbilities Character Controller Library**, then **Avatar Settings →
Movement → Abilities → Character Controller Library**. APIs may change; re-check the docs.

## Concepts

- **Ability**: a table (`AvatarAbilities.AbilityDefinition`) in a ModuleScript shared by server and client.
- **Labels**: named bits in a 64-bit world mask. Active abilities broadcast `Labels`; `TimedLabels`
  (`OnStart`, `OnStop` with durations in seconds, `Consumes` list) broadcast or remove labels temporarily.
- **Sensors**: engine facts such as `Identifiers.Sensor.Ground`.
- **Conditions**: `StartsWhen` / `RunsWhile` built from labels, sensors, and `Rule.All`, `Rule.Any`, `Rule.Not`
  (`Not` takes a single label). They compile to bitmask math.
- **Conflicts**: `Blocks`, `Stops`, `Suspends`, `ExclusiveGroup`.
- **Input**: `{ InputName = "Dash", Mode = "Press", ActionSlot = 5 }` — injected into `StartsWhen`.
- **Callbacks**: `OnSetup`, `OnStart`, `OnUpdate`, `OnStop`, `OnTeardown` with
  `(managerCtx: AvatarAbilities.ManagerContext, abilityCtx: AvatarAbilities.AbilityContext)`.
  `managerCtx.AbilityOwner` is the character; `abilityCtx.Config` / `abilityCtx.State` hold per-ability config and replicated state.

## Custom dash ability

```luau
-- ReplicatedStorage/CustomAbilities/Dash (ModuleScript)
local AvatarAbilities = require("@rbx/AvatarAbilities")
local Identifiers = AvatarAbilities.Identifiers
local Rule = AvatarAbilities.Rule
local Sensor = Identifiers.Sensor
local All, Not = Rule.All, Rule.Not

local Dash: AvatarAbilities.AbilityDefinition = {
	Name = "Dash",
	Labels = { "Dashing" },
	StartsWhen = All(Sensor.Ground, Not("DashCooldown")),
	RunsWhile = "DashWindow",
	Input = { InputName = "Dash", Mode = "Press", ActionSlot = 5 },
	TimedLabels = {
		OnStart = { DashWindow = 0.2 }, -- active for 0.2 s
		OnStop = { DashCooldown = 1.0 }, -- then 1 s cooldown
	},
}

function Dash.OnStart(managerCtx: AvatarAbilities.ManagerContext, _abilityCtx: AvatarAbilities.AbilityContext)
	local rootPart = managerCtx.AbilityOwner.PrimaryPart
	if rootPart then
		rootPart:ApplyImpulse(managerCtx.RootLookVector * 80 * rootPart.AssemblyMass)
	end
end

return Dash
```

## Registering abilities (server)

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarAbilities = require("@rbx/AvatarAbilities")

local CUSTOM_ABILITIES = {
	ReplicatedStorage.CustomAbilities.Dash,
}

local function onCharacterAdded(character: Model)
	local actor = character:WaitForChild("AbilityManagerActor", 10)
	if not actor then
		return
	end
	while not actor:IsDescendantOf(game) do
		actor.AncestryChanged:Wait()
	end
	for _, abilityModule in CUSTOM_ABILITIES do
		AvatarAbilities.addAbilityForCharacter(character, abilityModule) -- pass the module, don't require it
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
```

Callbacks run in both the predicted client simulation and the authoritative server simulation: keep
them deterministic (no `math.random` without shared seeds, no client-only state).
