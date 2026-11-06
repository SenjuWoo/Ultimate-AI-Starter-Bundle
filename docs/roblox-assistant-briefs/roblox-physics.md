---
name: roblox-physics
description: Physics and spatial queries - Raycast/Blockcast/Spherecast, overlap queries, collision groups, Touched pitfalls, collision summaries (impact point/normal/speed), assemblies and welds, mover constraints replacing BodyMovers, mechanical constraints, network ownership, CFrame math, vehicles/projectiles, and server authority (BindToSimulation, prediction, rollback). Use when moving parts, detecting hits, building vehicles or projectiles, or fixing jitter, flinging, or ownership bugs.
enabled: true
---
# Roblox physics and spatial queries

## Spatial queries (use these, not Touched, for gameplay decisions)

```luau
--!strict
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {} -- e.g. { character } of the shooter
params.IgnoreWater = true

local function castRay(origin: Vector3, direction: Vector3): RaycastResult?
	-- direction's length is the max distance
	return workspace:Raycast(origin, direction, params)
end

local result = castRay(Vector3.new(0, 50, 0), Vector3.new(0, -100, 0))
if result then
	print(result.Instance, result.Position, result.Normal, result.Material, result.Distance)
end

-- Swept volumes: thick bullets, melee arcs, ground checks with width.
local sphereHit = workspace:Spherecast(Vector3.new(0, 10, 0), 2, Vector3.new(0, 0, 50), params)
local boxHit = workspace:Blockcast(CFrame.new(0, 10, 0), Vector3.new(4, 4, 4), Vector3.new(0, 0, 50), params)

-- Volume overlap: explosions, hitboxes, zone checks.
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.MaxParts = 50
local partsInBox = workspace:GetPartBoundsInBox(CFrame.new(0, 5, 0), Vector3.new(10, 10, 10), overlap)
local partsInSphere = workspace:GetPartBoundsInRadius(Vector3.zero, 15, overlap)
print(sphereHit, boxHit, #partsInBox, #partsInSphere)
```

- **Reuse** params objects; update `FilterDescendantsInstances` (or `params:AddToFilter(instance)`) instead
  of allocating per call.
- Newer filters: `params.ExcludeInstances` / `IncludeInstances` (can be combined; exclude wins) supersede
  `FilterType` + `FilterDescendantsInstances` for new code.
- `RespectCanCollide = true` to ignore non-collidable parts; `CollisionGroup = "Name"` to query as a group.
- Shapecasts (October 2026): `params.Margin` inflates/rounds the cast shape (a `Raycast` with a margin acts
  as a spherecast — use a thin one where rays slip through seams); `params.SizeGradient` grows/shrinks it
  along the cast (`0.5` ends 50% larger, `-1` shrinks to nothing) for cones and funnels;
  `workspace:Shapecast(part, direction, params, cframeOverride?, sizeOverride?)` casts a part from any
  pose/size without moving it (placement previews). Debug: Studio Visualization Modes → Physics → Shapecasts.
- `GetPartsInPart(part, params)` does exact geometry overlap (costlier); `GetPartBoundsIn*` use bounding boxes.
- Deprecated: `FindPartOnRay*`, `Ray.new`, `FindPartsInRegion3*` → use the APIs above.
- Client queries only see streamed-in parts; authoritative checks run on the server.

## Touched: know its limits

`Touched` fires from the physics engine, only for parts that physically contact, is fired by whoever
simulates the part (clients can spoof or suppress it for parts they own), and can fire many times per
contact. Use it for triggers (pads, pickups) with a debounce and server-side validation; use spatial
queries for hit detection and zones.

```luau
--!strict
local Players = game:GetService("Players")

local pad = Instance.new("Part")
pad.Anchored = true
pad.Parent = workspace

local recently: { [Player]: boolean } = {}

pad.Touched:Connect(function(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or recently[player] then
		return
	end
	recently[player] = true
	print(`{player.Name} stepped on the pad`)
	task.delay(1, function()
		recently[player] = nil
	end)
end)
```

## Collision summaries (impact data)

For *how* parts hit (impact FX, impact audio, damage by impact speed), use
`BasePart:BindToCollisionSummaries(callback)` instead of `Touched`. Once per frame after the physics step,
the callback gets every contact of that part: `Part0` (the bound part), `Part1`, `Point`, `Normal` (points
away from `Part0`), `RelativeVelocity` (before the solver resolves the hit), `Area`, and `Time`.

- Fires only where the part is simulated (its network owner); nothing replicates. Send what others need
  through your own remote, validated on the server.
- No summaries for `CanCollide = false` parts or between two sleeping parts; non-convex parts can produce
  several summaries per pair. Cost scales with bound parts, not total collisions.

```luau
--!strict
local function bindImpacts(part: BasePart, onImpact: (point: Vector3, speed: number) -> ()): RBXScriptConnection
	return part:BindToCollisionSummaries(function(summaries: { any })
		for _, summary in summaries do
			local speed = math.abs(summary.RelativeVelocity:Dot(summary.Normal)) -- head-on impact speed
			if speed > 10 then
				onImpact(summary.Point, speed)
			end
		end
	end)
end

return bindImpacts
```

## Collision groups

```luau
--!strict
-- Collision group APIs now live on WorldRoot (workspace); the PhysicsService versions are superseded.
workspace:RegisterCollisionGroup("Players")
workspace:RegisterCollisionGroup("Ghosts")
workspace:CollisionGroupSetCollidable("Players", "Ghosts", false)

local ghost = Instance.new("Part")
ghost.CollisionGroup = "Ghosts" -- assign by name (CollisionGroupId/SetPartCollisionGroup are deprecated)
ghost.Parent = workspace
```

Register groups once at server start (max 32, see `workspace:GetMaxCollisionGroups()`). `CanCollide = false` removes all collisions;
`CanQuery = false` hides a part from raycasts; `CanTouch = false` disables `Touched` (saves CPU);
`NoCollisionConstraint` disables collision between two specific parts.

`MeshPart` collision shape: `CollisionFidelity` `Box`/`Hull` (cheap), `Default`, `PreciseConvexDecomposition`
(costly), or `Tunable` with a `CollisionPrecision` slider (set in Studio; scripts can't write it) to trade
precision for performance per mesh.

## Assemblies and joints

- An **assembly** = parts rigidly connected (welds, `WeldConstraint`, `Motor6D`, rigid constraints). It
  simulates as one body; the root part (`part.AssemblyRootPart`) determines network ownership.
- Anchor static geometry. Unanchored + welded to an anchored part = anchored assembly.
- Weld at edit time with `WeldConstraint` (keeps current offset); in code set `Part0`/`Part1` and parent.
- Move whole models with `model:PivotTo(cframe)`. Moving many parts at once: `workspace:BulkMoveTo`.
- Read/set physics via `AssemblyLinearVelocity`/`AssemblyAngularVelocity`, `part:ApplyImpulse()`,
  `ApplyAngularImpulse()`, `AssemblyMass`. `Velocity`/`RotVelocity` are deprecated.
- `CustomPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)`.
- Units: 1 stud ≈ 0.28 m, `workspace.Gravity` default 196.2 studs/s².

## Mover constraints (replace BodyMovers)

| Goal | Constraint | Replaces |
| --- | --- | --- |
| Hold/drive a velocity | `LinearVelocity` (`VelocityConstraintMode` Vector/Plane/Line) | `BodyVelocity` |
| Move toward a position | `AlignPosition` (`Mode = OneAttachment` + `Position`, `Responsiveness`, `MaxForce`) | `BodyPosition` |
| Rotate toward an orientation | `AlignOrientation` (`CFrame`/`LookAtPosition`) | `BodyGyro` |
| Constant force | `VectorForce` (`RelativeTo = World`) | `BodyForce`, `BodyThrust` |
| Spin | `AngularVelocity` | `BodyAngularVelocity` |
| Pull toward point | `LineForce` | `RocketPropulsion` |
| Torque | `Torque` | — |

All need an `Attachment` (`Attachment0`). Set `MaxForce`/`MaxTorque` realistically (not `math.huge`
unless intended) or objects fling. Mechanical constraints: `HingeConstraint` (Motor/Servo actuators for
wheels, doors), `PrismaticConstraint` (sliders, elevators), `SpringConstraint` (suspension),
`RopeConstraint`, `RodConstraint`, `BallSocketConstraint`, `CylindricalConstraint` (wheel + steering),
`UniversalConstraint`, `RigidConstraint`.

Vehicle and projectile recipes, CFrame cookbook: [references/recipes.md](#reference-references-recipes-md).

## Network ownership

- The server auto-assigns ownership of unanchored assemblies to a nearby client (smooth for that client,
  exploitable by it). Characters are owned by their player.
- `part:SetNetworkOwner(nil)` = server simulates (secure, laggier for players); `SetNetworkOwner(player)`
  for a vehicle driver; `SetNetworkOwnershipAuto()` to restore. Call on the root part, server-side, after
  the assembly is in `Workspace`. Anchored parts have no owner.
- Ownership changes cause hitches; don't flip it every frame. Visualize with the viewport's
  **Visualization options → Network owners** toggle.

## Server authority (competitive games)

Workspace `AuthorityMode = Server` makes the server simulate everything while clients **predict** a few
frames ahead and **roll back/resimulate** on mispredictions. Requirements: `NextGenerationReplication`,
`PlayerScriptsUseInputActionSystem`, `SignalBehavior = Deferred`, `UseFixedSimulation`, `StreamingEnabled`
(setting `AuthorityMode` sets these). Core rules:
- Game logic lives in functions bound with `RunService:BindToSimulation(fn)` inside a ModuleScript required
  by both server and client.
- Clients affect the game only through **Input Actions** (InputContexts parented under the `Player`),
  not `UserInputService` events.
- Sync custom state through **attributes** on predicted instances, written only inside simulation callbacks.
- Don't cache `AnimationTrack`s; query `Animator:GetTrackByAnimationId()` each step.
- Read a player's camera on the server with `player:GetCameraState()` (`CFrame`, `FieldOfView`,
  `ViewportSize`); the old camera `InputAction` replication no longer syncs.

Fully released (opt-in) since July 2026. Details and patterns: [references/server-authority.md](#reference-references-server-authority-md).

## Stability tips

- Jitter: conflicting ownership, constraints fighting, huge mass ratios (> 1:100), or setting CFrame on
  unanchored parts every frame (use constraints instead).
- Flinging: `MaxForce = math.huge` on light parts, overlapping collisions at spawn, NaN/huge velocities.
- Sleeping assemblies stop simulating until disturbed — wake with a small impulse if needed.
- Adaptive timestepping (`Workspace.PhysicsSteppingMethod = Adaptive`) saves CPU; use fixed for precise mechanisms.

## Related skills

`roblox-security` (ownership exploits), `roblox-characters-animation`, `roblox-networking`,
`roblox-performance`, `roblox-input`.

---

<a id="reference-references-recipes-md"></a>

## Appendix: references/recipes.md

### Physics recipes

## CFrame cookbook

```luau
--!strict
local origin = CFrame.new(0, 5, 0)

local lookAt = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(10, 5, 10)) -- position facing a target
local rotated = origin * CFrame.Angles(0, math.rad(90), 0) -- rotate in local space
local worldRotated = CFrame.Angles(0, math.rad(90), 0) * origin -- rotate around world origin
local offset = origin * CFrame.new(0, 0, -5) -- 5 studs "forward" (LookVector is -Z)
local relative = origin:ToObjectSpace(lookAt) -- lookAt expressed relative to origin
local back = origin:ToWorldSpace(relative) -- == lookAt
local halfway = origin:Lerp(lookAt, 0.5)
local rx, ry, rz = lookAt:ToOrientation() -- radians (Y-X-Z order like Orientation)
local flat = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.yAxis) -- from basis vectors

print(rotated, worldRotated, offset, back, halfway, rx, ry, rz, flat)
print(lookAt.LookVector, lookAt.RightVector, lookAt.UpVector, lookAt.Position)
```

- Compose right-to-left in world space, left-to-right in local space: `a * b` applies `b` in `a`'s space.
- Use `PivotTo`/`GetPivot` for models; `part.CFrame` for single parts.

## Projectiles

Pick by speed and precision:
1. **Hitscan** (instant): one server-validated `workspace:Raycast` — rifles, lasers.
2. **Simulated** (visible travel, drop): step a ray each frame; no physics parts needed.
3. **Physical** parts: only for slow, physics-interactive objects (grenades); set ownership deliberately.

```luau
--!strict
local RunService = game:GetService("RunService")

local GRAVITY = Vector3.new(0, -workspace.Gravity, 0)

local function fireProjectile(origin: Vector3, velocity: Vector3, params: RaycastParams, onHit: (RaycastResult) -> ())
	local position = origin
	local currentVelocity = velocity
	local travelled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		local step = currentVelocity * deltaTime + 0.5 * GRAVITY * deltaTime * deltaTime
		local result = workspace:Raycast(position, step, params)
		if result then
			connection:Disconnect()
			onHit(result)
			return
		end
		position += step
		currentVelocity += GRAVITY * deltaTime
		travelled += step.Magnitude
		if travelled > 1000 then
			connection:Disconnect() -- max range
		end
	end)
end

return fireProjectile
```

Clients render the bullet visuals locally (object pool of tracer parts or Beams); the server runs the
same stepping (or validates the client's reported hit — see `roblox-security`).

## Hover / follow with AlignPosition + AlignOrientation

```luau
--!strict
local function makeFollower(part: BasePart, target: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = part.AssemblyMass * workspace.Gravity * 4
	align.Responsiveness = 20
	align.Parent = part

	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.Responsiveness = 20
	orient.Parent = part

	return function()
		align.Position = target.Position + Vector3.new(0, 4, 0)
		orient.CFrame = target.CFrame
	end
end

return makeFollower
```

## Simple car (constraint-based)

- Chassis part (root) + 4 wheel parts (cylinders), each joined with a `CylindricalConstraint` (or
  `HingeConstraint` for non-steering wheels) whose `ActuatorType = Motor`; set `AngularVelocity` and
  `MotorMaxTorque` from the throttle. Steering: a `HingeConstraint` servo on the front wheel mounts
  (`ActuatorType = Servo`, `TargetAngle`).
- Suspension: `SpringConstraint` (`Stiffness`, `Damping`, `FreeLength`) or `CylindricalConstraint` limits.
- Read input from `VehicleSeat.ThrottleFloat`/`SteerFloat` (the integer `Throttle`/`Steer` are deprecated)
  or Input Actions; give the driver network ownership (`chassis:SetNetworkOwner(driver)`) for responsive
  handling, and validate speed on the server — or use server authority.

## Explosion without the Explosion instance's side effects

```luau
--!strict
local function blast(center: Vector3, radius: number, maxDamage: number)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(center, radius, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			local distance = (part.Position - center).Magnitude
			humanoid:TakeDamage(maxDamage * (1 - math.clamp(distance / radius, 0, 1)))
		elseif not part.Anchored then
			local direction = (part.Position - center).Unit
			part:ApplyImpulse(direction * part.AssemblyMass * 60)
		end
	end
end

return blast
```

---

<a id="reference-references-server-authority-md"></a>

## Appendix: references/server-authority.md

### Server authority model

Source: Roblox "Server authority model" and "Server authority techniques" docs (2026). Fully released for
all games in July 2026; it is opt-in per place.

## What it is

The server is the single source of truth; clients send only **inputs**. To hide latency, each client
**predicts** a few frames ahead of the last known server state, compares its prediction with the
authoritative state when it arrives, and on a **misprediction** rolls back to the server state and
resimulates forward, re-applying its inputs. Movement exploits (speed, fly, teleport) disappear because
clients never report positions.

## Setup (Workspace)

`AuthorityMode = Server` (automatically sets the rest): `NextGenerationReplication` on,
`PlayerScriptsUseInputActionSystem` on, `SignalBehavior = Deferred`, `UseFixedSimulation` on,
`StreamingEnabled` on.

## Rules for code

1. **Simulation sync**: put core logic in functions bound with `RunService:BindToSimulation(fn)` inside a
   ModuleScript that both a server Script and a client LocalScript require and initialize. These run on
   fixed steps and are re-run during resimulation.
2. **Only simulation-access APIs** (labelled "Simulation Access" in the API reference, e.g.
   `BasePart.CFrame`) can be used inside bound functions.
3. **Inputs**: clients influence the game only through Input Actions. `InputContext`s must be descendants
   of the `Player` (e.g. the server clones an `Inputs` folder into each player on join). Read
   `action:GetState()` for every player inside the simulation on both sides. Don't use
   `UserInputService` events in core simulation.
4. **State**: sync custom data via **attributes** on predicted instances, written only inside simulation
   callbacks. Replicated attributes: first 64 per instance, names ≤ 50 chars, string values ≤ 50 chars.
5. **Remote events** still work for discrete, non-simulation messages (score popups, purchases) but are
   not ordered relative to property/attribute replication.
6. **Prediction control**: Roblox predicts simulation-access properties near the local character by default;
   force it on/off with `RunService:SetPredictionMode(instance, mode)`.
7. **Camera**: read a player's camera on the server with `player:GetCameraState()` (table with `CFrame`,
   `FieldOfView`, `ViewportSize`). Camera `InputAction` replication (`CameraContext.CameraAction`) no longer
   syncs since the full release.

Known limits at full release: 8 playing animation tracks per `Animator`; Backpacks and Tools are supported.

```luau
--!strict
-- ReplicatedStorage/Simulation.luau — required by a server Script and a client LocalScript.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Simulation = {}

function Simulation.initialize()
	RunService:BindToSimulation(function(deltaTime: number)
		for _, player in Players:GetPlayers() do
			local inputs = player:FindFirstChild("Inputs")
			local dash = inputs and inputs:FindFirstChild("Dash", true)
			if dash and dash:IsA("InputAction") and dash:GetState() == true then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					root:ApplyImpulse(root.CFrame.LookVector * root.AssemblyMass * 50 * deltaTime)
				end
			end
		end
	end)
end

return Simulation
```

## Techniques

- **Instance stitching**: create instances (`Instance.new`, `Clone`, `Instance.fromExisting`) inside a
  simulation callback from a module required on both sides; client and server derive the same GUID and
  the client's predicted instance is merged with the server's copy. Parent them within the same frame.
- **Position smoothing**: simulate an invisible object and render a massless, non-collidable visual
  copy that follows it with `TweenService:SmoothDamp` to hide correction snaps.
- **Animations**: don't cache `AnimationTrack`s (rollback invalidates them); each step, get the live
  track with `Animator:GetTrackByAnimationId(id)` or load it, and mirror animation logic on both sides.
- **Sounds/VFX**: play effects from predicted state carefully — they may need to be cancelled if the
  prediction is rolled back; trigger irreversible effects from confirmed (server) state.
- **Other players' inputs** can't be known in advance; design mechanics tolerant of small corrections
  (wind-ups, telegraphed attacks) and use smoothing.
- Debug with the **server authority visualizer** and tune the simulation radius.

Official templates: Racing, Soccer, and Laser Tag "Server Authority Template" games on Roblox.
