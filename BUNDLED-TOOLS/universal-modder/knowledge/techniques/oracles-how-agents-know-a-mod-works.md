---
kind: technique
title: "Oracles: how an agent knows a mod actually works"
tags: [verification, testing, trace-replay, round-trip, screenshots, measurement, circuit-breaker]
date: 2026-09-30
agents: ["Claude Code (Opus 5.5)"]
humans: ["@rehan_shei"]
links: []
---

# Oracles: how an agent knows a mod actually works

> Agents fail at modding by drifting: confidently building on a wrong guess about the engine. The cure is an
> **oracle**, something mechanical that says right or wrong, run after every change. Each project that
> worked had one; the viral September 2026 mashups did too.

## When to use it
Always. Pick the cheapest oracle that can catch the mistake you're most likely to make next.

## How
| Oracle | Catches | Example |
|---|---|---|
| **Round trip** | wrong file-format understanding | AoE2 SLD: decode → encode → decode a stock sprite, then compare (0.91/255 mean error) before writing new files |
| **Trace replay** | a port that differs from the game | Terraria EoC: feed real frame-t state + action into the sim, compare t+1 per variable (99.9% after fixes) |
| **Scripted scene + screenshot you actually look at** | scale, facing, pivot, layering, "does it show up at all" | a chat command or scenario that spawns the thing, `um win shot --scale 0.33` |
| **Game log** | load errors, exceptions, missing assets | tModLoader `client.log`, BepInEx `LogOutput.log`, UE4SS.log, Unity `Player.log`, Minecraft `latest.log` |
| **Synthetic host** | integration bugs before the real game is even installed | Minecraft × GTA: a fake host with known geometry, and a fake D3D11 "GTA" with reversed-Z depth running the real compositor |
| **Measurement scene** | timing and sync (latency, camera lag, audio offset) | Minecraft × GTA: a Minecraft-only gold wall against GTA's skyline showed the one-frame pose lead; Terraria: nuke flash vs boom measured the audio offset |
| **Byte-matching build** | decompilation errors | matching decomps compile back to the identical ROM, one function at a time |
| **Publish check** | shipping what you mustn't | `um publish check --game <install>` |

Rules that make oracles work for agents:
- **Automate the whole loop**, from launch through menus to scene, check and log, so one command answers
  "did it work".
- **A circuit breaker:** after about 3 identical failures, stop, write down what you know, and change
  approach.
- **Keep a journal (`MODLOG.md`):** every confirmed fact, and every dead end with why. It survives context
  compaction.
- **Be honest in the result:** write down what the oracle did *not* cover.

## Gotchas
1. **Screenshots nobody looks at.**
   - **Cause:** the agent saves them but never opens them.
   - **Fix:** view a scaled copy after every visual change. It's cheap, and it's the only way to catch
     "facing left instead of right".
2. **Oracles that test the wrong frame.**
   - **Cause:** off-by-one frame semantics: the action applied on frame t shows up at t+1, and a script
     reads the camera for the frame being prepared.
   - **Fix:** measure with a deliberate test before trusting the replay.
3. **"Works in the fake host" isn't "works in the game".**
   - **Cause:** the real game adds things the fake can't model (pause menus, idle cameras, window focus).
   - **Fix:** keep the fake for fast iteration, and run the real game before calling it done.

## Seen in
- [Minecraft inside GTA V](../games/gta-v/minecraft-passthrough.md)
- [Eye of Cthulhu RL agent](../games/terraria/eye-of-cthulhu-rl-agent.md)
- [San Franciscans civ](../games/age-of-empires-ii-de/san-franciscans-civ.md)
