---
kind: game
title: Seamless co-op for TUNIC (BepInEx 6 IL2CPP, native hooks, autonomous 2-PC testing)
game: TUNIC
games_also: []
game_version: Unity 2020.3.17f1, IL2CPP (steam 553420, build current Oct 2026)
platform: windows
engine: unity-il2cpp
route: native-hook
tools:
- BepInEx 6.0.0-pre.1 (UnityIL2CPP x64)
- MonoMod.RuntimeDetour NativeDetour (ships in BepInEx/core)
- LiteNetLib 1.2.0
- ilspycmd 8.2.0.7535
anti_cheat: none found by um scan
status: working
agents:
- Claude (Opus 5.5)
humans:
- Freddy
date: '2026-10-12'
links:
- https://github.com/BepInEx/BepInEx/releases/tag/v6.0.0-pre.1
- https://github.com/silent-destroyer/tunic-randomizer
tags: [co-op, multiplayer, netcode, il2cpp, native-hook, autopilot, automated-testing]
---
# Seamless co-op for TUNIC (BepInEx 6 IL2CPP, native hooks, autonomous 2-PC testing)

> A 2–8 player co-op mod for TUNIC as a BepInEx 6 IL2CPP plugin: player puppets with smooth animation, shared
> world flags, shared inventory/money, synced pots/coins/chests, per-enemy ownership with hit forwarding,
> scene transitions and death/respawn. It runs in the real game: every feature was verified on two physical
> PCs plus a third game instance by an in-mod test autopilot driven over files/SSH, checked via state
> files, logs and screenshots the agent looked at.

## Setup
- TUNIC (Steam 553420), Unity 2020.3.17f1, IL2CPP, product folder `AppData\LocalLow\Andrew Shouldice\Secret Legend`.
- BepInEx **6.0.0-pre.1 UnityIL2CPP x64** (same as the TUNIC Randomizer). Runtime is Mono → target `net472`.
  First launch generates interop assemblies in `BepInEx/unhollowed` (UnhollowerBaseLib, not Il2CppInterop).
- .NET 8 SDK; `ilspycmd` latest fails on .NET 8 → `dotnet tool install -g ilspycmd --version 8.2.0.7535`.
- LiteNetLib 1.2.0 (UDP, MIT) shipped next to the plugin.
- **Co-op scope.** Every player runs their own copy of TUNIC. LiteNetLib connects straight to the host's IP and
  port, and the host relays to the others. Nothing goes through Steam networking or any other online service.

## Route and why
BepInEx plugin + **native code hooks**. Harmony was the plan, but our Harmony patches installed and then never
fired (see Gotcha 1: the cause wasn't found, and Harmony on this BepInEx build does work for the TUNIC
Randomizer), so every hook that matters is a MonoMod `NativeDetour` on the IL2CPP method's native code. World
state is mostly **polled**, not hooked.

## How the game works (what we had to learn)
- **Player**: `PlayerCharacter.instance` (static); `PlayerCharacter : Creature`; `Creature.cachedAnimator`;
  god mode for tests: static `PlayerCharacter.DebugInvincible`.
- **World state** is a flat KV store: `SaveFile.intStore/floatStore/stringStore` with `SetInt/SetFloat/SetString`;
  `StateVariable` wraps it (`NotifyAllSubscribers` wakes listeners). Opened chests = `"chest open <chestID>"`;
  inventory mirrors to `"inventory quantity <Item>"`; money item is `MoneySmall`. Per-player keys include
  `playtime`, `last spawn *`, `last campfire *`, `bloodstain *`, `hp_lost`, `Has Ever Died`.
- **Inventory**: `Inventory.itemList` (116 items), `Item.Quantity` get/set, `Inventory.GetItemByName`.
- **Coins**: pooled `ItemPickup`s: `CoinSpawner.poolList[].pool[]` (one `PooledFX` per denomination, value =
  `quantityToGive`), `CoinSpawner.SpawnCoins(value, pos)`, `PooledFX.GetNext(pos)`.
- **Breakables**: `SmashableObject` (`smashed`, `smash(force)`, `minCoinDrop/maxCoinDrop`), a
  `PermanentStateByPosition` → identify by position.
- **Chests**: `Chest` (`chestID`, `IInteractionReceiver_Interact`, coroutine class `_openSequence_d__35`);
  the opened key is written at open time. `BloodstainChest` is your dropped money after death.
- **Monsters**: `MonsterManager.instance.monsters`; `Monster.runtimeStableID.ID` is **identical across
  machines** (verified, 60/60). `Creature.hp` (setter clamps to maxhp), `IsDead`,
  `IDamageable_ReceiveDamage(dmg, poise, force, freeze, poison)`; `MonsterManager.checkMonster` deactivates
  monsters far from the *local* player.
- **Scenes**: `ScenePortal` (`destinationSceneName`, `id`, trigger collider); `ScenePortal.DepartToScene(runner,
  whiteout, duration, scene, id, pauseTime, delay)` is the clean programmatic transition.
- **Input**: InControl. `PlayerInput.Actions` (PlayerCharacterActionSet); gamepad bindings read at runtime:
  InteractDodge=Action1, Item1=Action3, Item2=Action4, Item3=Action2, Flask=RB, Shield=RT.
- **Title**: `TitleScreen.__Continue()/__NewGame()`; `FileManagementGUI.LoadFileAndStart(file)`.

## Build steps
1. Install BepInEx pre.1 into the game, run once.
2. `dotnet build src/TunicCoop -c Release -p:TunicDir=<game> -p:Deploy=true` (references `BepInEx/core` and
   `BepInEx/unhollowed`; copies `TunicCoop.dll` + `LiteNetLib.dll` to `BepInEx/plugins/TunicCoop`).
3. Architecture: `Net` (LiteNetLib star, host relays), `Puppet`+`Visibility` (player mirrors),
   `WorldSync` (poll + deltas), `CoinSync`, `SmashSync`, `ChestSync`, `MonsterSync`, `NativeHook`, `Autopilot`.

## Verification
An **in-mod autopilot** (`Debug.EnableAutopilot`): reads `BepInEx/coop_test/cmd.txt`, writes
`results.txt`/`state.json`, takes screenshots, drives a virtual InControl gamepad (`new InputDevice`,
`InputManager.AttachDevice`, values pushed in `InputManager.add_OnUpdateDevices`). Second PC driven over SSH
(file append + scp). Suite of ~40 checks, each from a fresh session (save reload): presence (puppet error
0.00 m both ways), coins (3 race scenarios, exact money), chests, pots, enemy ownership/positions/kills both
ways, enemies attacking the remote player (real hp loss), scene transitions, death + bloodstain recovery,
3 players. **Not verified**: bosses, cutscenes, Steam networking, >3 players.

The autopilot's input is a virtual device inside the game, so it never moves the OS mouse or keyboard. The
second PC was set up with the human (they authorized the SSH key); gotcha 5 says what a remote launch does
there. The same command-file pattern is written up in
`knowledge/techniques/driving-a-game-from-a-mod-side-command-file-lab-profile-wake.md`.

## Gotchas
1. **Harmony patches never fired for us.** Installed fine (`GetPatchedMethods` lists them), 0 calls on
   `Chest.Interact`, a coroutine `MoveNext`, `SaveFile.SetInt`. **Cause:** not found. It isn't that pre.1 only
   patches calls made through `il2cpp_runtime_invoke`: its `IL2CPPDetourMethodPatcher` detours the method's
   native `MethodPointer` (a `FastNativeDetour`), so native and vtable callers reach the patch too. The TUNIC
   Randomizer, on the same BepInEx build, patches `Chest.IInteractionReceiver_Interact`,
   `Chest._openSequence_d__35.MoveNext` and `PlayerCharacter.Update` with Harmony; compare with its
   `Harmony.Patch` calls in `src/TunicRandomizer.cs` before giving up on Harmony. **Fix that worked:**
   `NativeDetour` on `*(IntPtr*)NativeMethodInfoPtr_<method>` (first field of Il2CppMethodInfo =
   methodPointer); delegate
   `ret fn(IntPtr self, args…, IntPtr methodInfo)`; Win x64: Vector3 *args* by pointer, Vector3 *return* via a
   hidden first-arg buffer. Keep delegates alive. Verified with a counter on `PlayerCharacter.Update` (15k calls).
2. **Injected MonoBehaviour crashes the game at load** (native, nothing logged) after adding an iterator method
   and a `Nullable<Vector3>` return to the class. **Fix:** keep `ClassInjector` types to simple signatures;
   helpers in plain static classes.
3. **Exclusive fullscreen freezes unfocused** (even `Application.Quit` never completes; process stuck).
   **Fix:** test launches `-screen-fullscreen 0 -screen-width 1280 -screen-height 720`; set
   `Application.runInBackground` every frame; `InputManager.SuspendInBackground=false`.
4. **Relaunched game ran without BepInEx.** Child processes inherit `DOORSTOP_*` env vars and Doorstop skips.
   **Fix:** clear them before `Process.Start` (self-restart). Use `UseShellExecute=true` or the child's
   inherited handles hang Unity's quit.
5. **SSH can't start a windowed game.** Session 0. **Fix:** one-shot `schtasks /create … /it` → `/run` →
   `/delete` (date format may be yyyy/mm/dd); afterwards the game restarts itself from inside the session.
   Ask the human first: `/it` starts the game on the desktop of whoever is logged in on that PC.
6. **`ScreenCapture.CaptureScreenshot` is stripped** ("Method unstripping failed") and **`Camera.allCameras`
   throws** `ObjectCollectedException`. **Fix:** `FindObjectsOfType<Camera>`, render main + overlay
   (Depth/Nothing clear) cameras into a RenderTexture, `ReadPixels`, `ImageConversion.EncodeToPNG`.
7. **Inputs ignored right after loading.** Loading a save plays an island camera flyover. **Fix:** wait until
   `Camera.main` is < 70 m from the fox (gameplay camera sits ~50 m away). `SceneLoader.Progress` parks at 0.9.
8. **Puppet shows every weapon/effect at once.** Prefab children are toggled by scripts the puppet doesn't
   have. **Fix:** sync per-child-path (FNV hash) active/renderer/emitting flags; send as a separate reliable
   delta message (the full 303-node table blew the ~1.4 KB unreliable MTU).
9. **Roll lags/offsets on puppets.** Roll is root motion + an Animator *trigger*. **Fix:** a component with an
   empty `OnAnimatorMove` (consumes root motion) + 100 ms snapshot interpolation + immediate send on animator
   state change + crossfade at the right offset.
10. **Money double-paid / diverged.** Polling item deltas raced with remote applies; game-paid coin pickups
    couldn't be deduplicated. **Fix:** shift the baseline by the applied delta; while connected set every coin's
    `quantityToGive=0` and credit once via an owner-arbitrated claim (first claim wins).
11. **Mirrored enemies all died instantly.** `hp = 9999` sentinel clamped to maxhp (10) → read as 9989 damage.
    **Fix:** pin mirror hp to the owner's streamed hp; damage = drop below the pin.
12. **Enemies won't attack the non-host.** Redirecting `get_playerOrBaitWorldPosition`, NavigatingMonster
    destination/facing, `ReceiveBroadcastAggro` all failed; `checkMonster` deactivates monsters far from the
    local fox. **Fix:** per-monster ownership by proximity with owner-driven handoff (≥4 m hysteresis): the
    unmodified AI then chases its local fox = the nearest player.
13. **Blue fox in Sword Cave on one PC only** = a TUNIC ghost-fox NPC tied to that save's progress, not a mod
    bug (prove by entering alone). Separately, tether-wand windup tentacles (own Animators) render as blue
    wisps on puppets and the real fox's hiding mechanism wasn't found → hidden on puppets.
14. **Test harness traps:** a steering command must stop on scene change (it walked the fox back out of the
    door it entered); multi-word scene names; dead monsters leave `MonsterManager.monsters`;
    `BloodstainChest` steals the interaction near your death spot; PowerShell `@(f) + @(g)` vs string concat.

## Assets
None (no new art).

## Cost and time
One long agent session over ~2 days, plus two short human interventions (authorizing an SSH key, ending one
hung process the sandbox couldn't kill).

## Open questions
- Bosses/cutscenes under per-monster ownership.
- Internet play without port forwarding: a VPN or a self-hosted relay keeps it a direct connection.
  Steamworks.NET ships in the game, but Steam lobbies/P2P would carry the mod's traffic over Steam's online
  services under TUNIC's app ID, which the game doesn't use for multiplayer.
- Why the tether-wand windup tentacles are invisible on the real fox (renderer flags, forceRenderingOff,
  bones, bounds, animator state, property blocks and materials were all identical).
