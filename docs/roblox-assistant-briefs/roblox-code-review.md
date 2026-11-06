---
name: roblox-code-review
description: Review Roblox/Luau code for exploits, data loss, memory leaks, performance problems, lifecycle bugs, policy issues, and deprecated or superseded APIs, using a severity-ranked checklist and the full 2026 deprecation map. Use when reviewing a PR or script, auditing a game before launch, modernizing legacy code, or asked what is wrong with some Roblox code.
enabled: true
---
# Roblox code review

Review in severity order. Report each finding with **file:line, severity, what breaks, and the fix**.
Verify claims against the code (and the engine reference when unsure) — don't pattern-match blindly.

## Severity guide

| Severity | Examples |
| --- | --- |
| **Critical** | Client-authoritative rewards/damage/currency; unvalidated remote args (NaN, instance spoofing); purchases granted outside `ProcessReceipt` or non-idempotent; data saved with `SetAsync` from multiple servers without session locking; secrets/API keys in replicated code; unfiltered player text shown to others. |
| **High** | Data loss paths (no `BindToClose`, saving default data after a failed load, no retry); memory leaks (connections, player-keyed tables); `InvokeClient`; per-frame remotes; infinite yields (`WaitForChild` without timeout on optional instances, `RemoteFunction` handlers that can yield forever); streaming-unsafe client indexing. |
| **Medium** | Deprecated/superseded APIs; `wait`/`spawn`/`delay`; polling loops; server-side tweens; missing `pcall` on network/yielding APIs; missing late-joiner handling; race conditions on `CharacterAdded`. |
| **Low** | Style, naming, missing types, magic numbers, dead code, minor inefficiencies. |

## Checklist

**Security** (`roblox-security`)
- Every `OnServerEvent`/`OnServerInvoke`: types checked with `typeof`, numbers `math.isfinite`, strings
  length/UTF-8 checked, instances `IsA` + `IsDescendantOf(trusted)`, rate limited, context checked.
- No server-only logic, admin lists, or secrets in `ReplicatedStorage`/`StarterPlayer`/`Workspace`.
- `ProximityPrompt`/`ClickDetector`/`Touched` handlers re-validate distance/state on the server.
- Gameplay-critical unanchored parts are server-owned.

**Data** (`roblox-data-stores`)
- Session locking (ProfileStore or equivalent); `UpdateAsync` for read-modify-write; retries with backoff.
- `BindToClose` flushes saves in parallel; no saves of `Instance`/`Vector3`/mixed tables.
- Failed loads never overwritten with defaults; player-keyed tables cleared on leave.
- Keys stable (`User_{UserId}`), Studio uses a separate store/universe.

**Monetization** (`roblox-monetization`)
- Single `ProcessReceipt`; idempotent by `PurchaseId`; returns `PurchaseGranted` only after persisting.
- Pass perks checked on join **and** after in-session purchase; prices not hardcoded; paid random items
  disclose odds and respect `PolicyService`.

**Correctness & lifecycle** (`roblox-architecture`)
- Handles players already in game (`for _, p in Players:GetPlayers()`) and characters already spawned.
- Per-character state rebuilt on respawn; per-player state cleaned on `PlayerRemoving`.
- No yields at module top level; no circular requires; one owner per piece of state.
- Deferred-event safe (doesn't rely on handlers running synchronously).
- Client code streaming-safe (`WaitForChild`/nil checks for `Workspace` content).

**Performance** (`roblox-performance`)
- No per-frame `FindFirstChild`/`GetDescendants`/`Instance.new`; params objects reused.
- Event-driven instead of polling; think loops throttled and staggered.
- Tweens and cosmetic effects on clients; remotes batched/throttled; payloads minimal.
- Connections disconnected / instances destroyed; no unbounded caches.

**Text & safety** (`roblox-text-chat`)
- All player-authored text shown to others filtered server-side (`FilterStringAsync`), fail closed.
- Chat uses `TextChatService`; public editable text rate-limited (≥ 1 minute).

**Modern API usage**
- `task.*`, `*Async` variants, `Raycast`, mover constraints, `PivotTo`, `Animator:LoadAnimation`,
  `TextChatService`, `UIDragDetector`, `workspace` collision-group APIs, `CreatePath`+`ComputeAsync`.
- Full map of deprecated and superseded members: [references/deprecated-apis.md](#reference-references-deprecated-apis-md).

**Code quality** (`roblox-luau`)
- `--!strict` with typed public APIs; services via `GetService`; no `_G`/`shared`.
- Clear module boundaries; config separated from logic; tests for pure logic (`roblox-testing`).

## Output format

```text
## Summary
<2–3 sentences: overall risk, the most important fixes>

## Findings
1. [Critical] src/server/Shop.server.luau:42 — Price read from client argument.
   Impact: exploiters buy anything for 0 coins. Fix: look up ITEMS[itemId].price on the server.
2. [High] ...

## Modernization (optional)
- Replace `wait()` → `task.wait()` (12 occurrences) ...
```

Offer to apply fixes; when fixing, keep behavior identical except for the bug, and re-run the relevant
checks (type check, tests, Studio playtest via `roblox-studio-mcp`).

---

<a id="reference-references-deprecated-apis-md"></a>

## Appendix: references/deprecated-apis.md

### Deprecated and superseded Roblox APIs (engine reference, Studio 0.740, September 2026)

"Superseded" members still work but have a documented replacement — treat them as deprecated in new
code. Search this file for the member you're looking at. Camel-case aliases (`:findFirstChild`,
`:remove`, `.className`, ...) are all deprecated in favor of their PascalCase versions.

## Globals and libraries

| Deprecated | Use |
| --- | --- |
| `wait()` / `spawn()` / `delay()` | `task.wait()` / `task.spawn()` / `task.delay()` |
| `ypcall`, `elapsedTime`, `version`, `printidentity`, `stats()` | `pcall`, `os.clock`/`time()`, — , — , `game:GetService("Stats")` |
| `getfenv` / `setfenv` | nothing (disables optimizations) |
| `table.getn`, `table.foreach`, `table.foreachi` | `#t`, `for k, v in t do` |
| `Ray.new` + `FindPartOnRay*` | `workspace:Raycast(origin, direction, RaycastParams)` |
| `Region3` + `FindPartsInRegion3*`, `IsRegion3Empty*` | `workspace:GetPartBoundsInBox(cframe, size, OverlapParams)` |

## Players and characters

| Deprecated | Use |
| --- | --- |
| `Player:LoadCharacter()` | `Player:LoadCharacterAsync()` |
| `Player:LoadCharacterWithHumanoidDescription()` | `LoadCharacterWithHumanoidDescriptionAsync()` |
| `Player:LoadCharacterAppearance()`, `Player.CharacterAppearance`, `Players:GetCharacterAppearanceAsync()` | `HumanoidDescription` APIs |
| `Player:GetRankInGroup(Async)`, `Player:GetRoleInGroup(Async)` | `GroupService:GetRolesInGroupAsync()` |
| `Player:IsInGroup()` | `Player:IsInGroupAsync()` |
| `Player:IsFriendsWith()`, `IsBestFriendsWith()` | `Player:IsFriendsWithAsync()` |
| `Player:GetFriendsOnline()` | `Player:GetFriendsOnlineAsync()` |
| `Player.MembershipType` | `Player.HasRobloxSubscription` |
| `Player:Save*/Load*`, `DataReady`, `WaitForDataReady`, `DataComplexity` | `DataStoreService` |
| `Players.NumPlayers` | `#Players:GetPlayers()` |
| `Players:GetHumanoidDescriptionFromUserId/OutfitId()` | `...Async()` variants |
| `Players:CreateHumanoidModelFromDescription/UserId()` | `...Async()` variants |
| `Humanoid:LoadAnimation()`, `AnimationController:LoadAnimation()` | `Animator:LoadAnimation()` |
| `Humanoid:ApplyDescription()` / `ApplyDescriptionReset()` / `PlayEmote()` | `...Async()` variants |
| `Humanoid:*Status*` (RbxStatus), `Humanoid.Torso/LeftLeg/RightLeg` (R6-only) | attributes/tags; R15 body parts |
| `AnimationTrack.KeyframeReached` | `AnimationTrack:GetMarkerReachedSignal(name)` |
| `KeyframeSequenceProvider:GetKeyframeSequence*`, `AnimationClipProvider:GetAnimationClip*` | `AnimationClipProvider:GetAnimationClipAsync()` |
| `PoseBase.Weight`, `Pose.MaskWeight` | `AnimationTrack:AdjustWeight()` |

## Physics and parts

| Deprecated | Use |
| --- | --- |
| `BodyVelocity`, `BodyPosition`, `BodyGyro`, `BodyForce`, `BodyThrust`, `BodyAngularVelocity`, `RocketPropulsion` | `LinearVelocity`, `AlignPosition`, `AlignOrientation`, `VectorForce`, `AngularVelocity`, `LineForce` |
| `BasePart.Velocity` / `RotVelocity` | `AssemblyLinearVelocity` / `AssemblyAngularVelocity` (or `ApplyImpulse`) |
| `BasePart.Friction/Elasticity/SpecificGravity` | `CustomPhysicalProperties` |
| `BasePart:MakeJoints/BreakJoints`, `Model:MakeJoints`, surface joints (`Glue`, `Snap`, `Rotate*`, `Motor`, `ManualWeld`), `JointsService` | `WeldConstraint`, `HingeConstraint`, `GetJoints()` + `Destroy()` |
| `BasePart:GetRenderCFrame()` | `BasePart.CFrame` |
| `BasePart.StoppedTouching`, `LocalSimulationTouched` | `TouchEnded`, `Touched` |
| `PhysicsService:CreateCollisionGroup/RemoveCollisionGroup/GetCollisionGroups` | `workspace:RegisterCollisionGroup/UnregisterCollisionGroup/GetRegisteredCollisionGroups` |
| `PhysicsService:RegisterCollisionGroup`, `CollisionGroupSetCollidable`, `CollisionGroupsAreCollidable`, `IsCollisionGroupRegistered`, `RenameCollisionGroup`, `UnregisterCollisionGroup`, `GetMaxCollisionGroups` (superseded) | same methods on `workspace` (WorldRoot) |
| `PhysicsService:SetPartCollisionGroup`, `GetCollisionGroupId/Name`, `CollisionGroupContainsPart`, `BasePart.CollisionGroupId` | `BasePart.CollisionGroup` (string) |
| `Model:SetPrimaryPartCFrame()` / `GetPrimaryPartCFrame()` | `Model:PivotTo()` / `Model:GetPivot()` |
| `Model:GetModelCFrame()` / `GetModelSize()` | `GetPivot()`/`GetBoundingBox()` / `GetExtentsSize()` |
| `AlignOrientation.PrimaryAxisOnly` | `AlignOrientation.AlignType` |
| `Attachment.Rotation/WorldRotation`, `Get/SetAxis`, `Get/SetSecondaryAxis` | `Orientation`/`WorldOrientation`, `Axis`/`SecondaryAxis` properties / `CFrame` |
| `TorsionSpringConstraint.LimitEnabled` | `LimitsEnabled` |
| `VehicleSeat.Steer` / `Throttle` | `SteerFloat` / `ThrottleFloat` |
| `SkateboardPlatform`, `Flag`, `FlagStand` | custom systems |
| `FormFactorPart.FormFactor` | `Size` directly |

## Workspace, world, rendering

| Deprecated | Use |
| --- | --- |
| `Workspace.FilteringEnabled` | nothing (always on) |
| `game.Workspace`, `game.lighting` | `workspace`, `game:GetService("Lighting")` |
| `Lighting.Technology` (superseded) | `Lighting.LightingStyle` + `PrioritizeLightingQuality` |
| `Lighting.Outlines`, `ShadowColor`, `GetMoonPhase` | nothing |
| `Decal.Texture`, `Decal.TextureContent` (superseded) | `Decal.ColorMapContent` |
| `Decal.Shiny/Specular` | `SurfaceAppearance` / materials |
| `Terrain:SetCell/GetCell/SetCells/AutowedgeCell(s)/GetWaterCell/SetWaterCell`, `ConvertToSmooth`, `IsSmooth` | `FillBlock/FillBall/ReadVoxels/WriteVoxels` |
| `Sparkles.Color`, `ParticleEmitter.VelocitySpread`, `SelectionBox/Sphere.SurfaceColor`, `GuiBase3d.Color` | `SparkleColor`, `SpreadAngle`, `SurfaceColor3`, `Color3` |
| `Camera.CoordinateFrame`, `Camera:Interpolate`, `InterpolationFinished`, `SetRoll/GetRoll`, `PanUnits/TiltUnits`, `SetCameraPanMode` | `Camera.CFrame`, `TweenService`, CFrame math |
| `Hint`, `Message` | `TextLabel` in a `ScreenGui` |
| `Hat` | `Accessory` |
| `Skin` | `BodyColors` |
| `HopperBin`, `Hopper` | `Tool`, `StarterPack` |
| `FloorWire`, `SelectionPartLasso`, `SelectionPointLasso` | `Beam` |
| `CustomEvent`, `CustomEventReceiver` | `BindableEvent` (or a Luau signal module) |
| `IntConstrainedValue`, `DoubleConstrainedValue` | `IntValue`/`NumberValue` + `math.clamp`, or attributes |
| `Debris.MaxItems` | nothing |
| `Instance:Remove()` | `Instance:Destroy()` / `Parent = nil` |
| `Instance.RobloxLocked` | nothing |
| `DataModel.OnClose` | `game:BindToClose()` |
| `DataModel.VIPServerId/VIPServerOwnerId` | `PrivateServerId` / `PrivateServerOwnerId` |
| `Workspace.AvatarUnificationMode` (deprecation planned Dec 1, 2026) | remove dependencies on it |
| `DataModel:GetRemoteBuildMode()` | `RunService:IsServer()` |
| `DataModel.ItemChanged` | `Instance.Changed` / `GetPropertyChangedSignal` |
| `BaseScript.LinkedSource`, `ModuleScript.LinkedSource` | Packages |
| `CollectionService.ItemAdded/ItemRemoved`, `GetCollection` | `GetInstanceAddedSignal/GetInstanceRemovedSignal`, `GetTagged` |

## UI and input

| Deprecated | Use |
| --- | --- |
| `GuiObject:TweenPosition/TweenSize/TweenSizeAndPosition` | `TweenService:Create()` |
| `GuiObject.Draggable`, `DragBegin`, `DragStopped` | `UIDragDetector` |
| `GuiObject.BackgroundColor/BorderColor/Transparency` | `BackgroundColor3`/`BorderColor3`/`BackgroundTransparency` |
| `TextLabel/TextButton/TextBox.FontSize`, `TextColor`, `TextWrap` | `TextSize`, `TextColor3`, `TextWrapped` |
| `StarterGui.ResetPlayerGuiOnSpawn` | `ScreenGui.ResetOnSpawn` |
| `GuiService:IsTenFootInterface()` (superseded) | `GuiService.ViewportDisplaySize` |
| `GuiService.IsModalDialog`, `IsWindows`, `AddSelectionParent/Tuple`, `RemoveSelectionGroup` | `SelectionGroup`, `UserInputService.PreferredInput` |
| `UIGridStyleLayout:SetCustomSortFunction` | `SortOrder = LayoutOrder`/`Name` |
| `Mouse.KeyDown/KeyUp` | `UserInputService` / Input Action System |
| `UserInputService.ModalEnabled` | `GuiService.TouchControlsEnabled` |
| `UserInputService.VREnabled`, `UserHeadCFrame`, `GetUserCFrame`, `UserCFrameChanged` | `VRService` equivalents |
| `ContextActionService:BindActionToInputTypes` | `BindAction` (or Input Action System) |
| `InputAction:Fire()` | `InputBinding:Fire()` |
| `UserGameSettings.ControlMode` | `UserInputService.MouseBehavior` for shift-lock style control |

## Services

| Deprecated | Use |
| --- | --- |
| `MarketplaceService:GetProductInfo()` | `GetProductInfoAsync()` |
| `MarketplaceService:PlayerOwnsAsset()` / `PlayerOwnsBundle()` | `...Async()` variants |
| `MarketplaceService:PromptPremiumPurchase()` | `PromptRobloxSubscriptionPurchase()` |
| `GamePassService:PlayerHasPass()` | `MarketplaceService:UserOwnsGamePassAsync()` |
| `BadgeService:AwardBadge()` / `UserHasBadge()` / `IsDisabled()` / `IsLegal()` | `AwardBadgeAsync()` / `UserHasBadgeAsync()` / `GetBadgeInfoAsync().IsEnabled` / — |
| `TeleportService:Teleport`, `TeleportToPlaceInstance`, `TeleportToPrivateServer`, `TeleportPartyAsync`, `TeleportToSpawnByName` | `TeleportService:TeleportAsync()` + `TeleportOptions` |
| `TeleportService:ReserveServer()` / `ReserveServerAsync()`, `TeleportOptions.ShouldReserveServer` / `ReservedServerAccessCode` | `TeleportOptions.ReservedServerId = HttpService:GenerateGUID(false)` |
| `AssetService:PromptCreateAssetAsync()` (removed) | `PromptCreatePlatformContentAsync()` |
| `TeleportService.CustomizedTeleportUI` | `SetTeleportGui` |
| `GlobalDataStore:OnUpdate()` | `MessagingService` |
| `DataStore:RemoveVersionAsync()` | versions expire automatically; `RemoveAsync` for keys |
| `PathfindingService:FindPathAsync()` (superseded), `ComputeRawPathAsync`, `ComputeSmoothPathAsync`, `Path:GetPointCoordinates`, `Path:CheckOcclusionAsync` | `CreatePath()` + `Path:ComputeAsync()`, `GetWaypoints()`, `Path.Blocked` |
| `AnalyticsService:FireEvent/FireCustomEvent/FireInGameEconomyEvent/FirePlayerProgressionEvent/FireLogEvent` | `LogCustomEvent`, `LogEconomyEvent`, `LogProgressionEvent` (+ Start/Complete/Fail), `LogFunnelStepEvent` |
| `Chat` service, `Chat:FilterStringForPlayerAsync`, legacy ChatService modules, `TextChatService.ChatVersion` | `TextChatService`; `TextService:FilterStringAsync` |
| `TextFilterResult:GetChatForUserAsync()` (returns empty string) | `TextChannel`s for chat; `GetNonChatStringForUserAsync/ForBroadcastAsync` for other text |
| `TextService:FilterAndTranslateStringAsync()` | `FilterStringAsync` |
| `LocalizationService:GetTranslatorForPlayer()` | `GetTranslatorForPlayerAsync()` |
| `LocalizationTable:GetString/GetContents/SetContents/SetEntry/RemoveKey`, `DevelopmentLanguage` | `GetTranslator`, `GetEntries/SetEntries`, `RemoveEntry`, `SourceLocaleId` |
| `InsertService:Insert/GetFreeModels/GetFreeDecals`, sets APIs | `LoadAsset`, `GetFreeModelsAsync`, `GetFreeDecalsAsync` |
| `AssetService:SearchAudio/GetAssetIdsForPackage` | `SearchAudioAsync`/`GetAssetIdsForPackageAsync` |
| `AudioPlayer.AssetId` | `AudioPlayer.Asset` |
| `Sound.Pitch`, `Sound.MinDistance/MaxDistance/EmitterSize` | `PlaybackSpeed`, `RollOffMinDistance/RollOffMaxDistance` |
| `SocialService:PromptLinkSharing()` | `PromptLinkSharingAsync()` |
| `OpenCloudService`, `OpenCloudApiV1` | `HttpService:RequestAsync` with an API key secret |
| `ContentProvider:Preload()` | `PreloadAsync()` |
| `Stats.HeartbeatTimeMs/PhysicsStepTimeMs` | `HeartbeatTime`/`PhysicsStepTime` |
| `TestService:Run()`, `FunctionalTest` | `TestService:RunAsync()` / a test framework (Jest Lua) |
| `Teams:RebalanceTeams()`, `Team.Score`, `Team.AutoColorCharacters` | custom logic |
| `PointsService` | badges / your own progression |
| `AdService:ShowVideoAd`, `AdGui.OnAdEvent` | Rewarded video via `AdService:ShowRewardedVideoAdAsync` |
| `GenerationService:GenerateMeshAsync` (scheduled for deprecation) | `GenerateModelAsync` |
