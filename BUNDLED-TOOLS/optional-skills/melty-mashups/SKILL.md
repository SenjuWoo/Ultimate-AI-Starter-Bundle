---
name: melty-mashups
description: Use when building, packaging, remixing or publishing a game mashup or mod on Melty (melty.gg), or when melty MCP tools are present in the session.
metadata:
  service: https://melty.gg/api/mcp
  verified: 2026-10-10 (server 1.0.0, protocol 2025-06-18; 21 public tools, 23 when signed in)
  optional: install with INSTALL-AIO.ps1 -OptionalSkills melty-mashups
---

# Melty mashups

Optional skill: the bundle never installs or routes to Melty by default.

## When Melty applies

Only when the user explicitly asks to fuse two games or publish a mashup on
Melty. An ordinary mod (a Skyrim plugin, a RimWorld def, a texture pack) stays
in its own project folder; nothing is copied, packaged or published to Melty
unless that request is on the table. The server stays parked like every other
task tool, so a Melty request can start it on demand.
Melty's own app and instructions are the authority; this skill only keeps an
agent inside them.

Melty is a Windows launcher that installs and starts mods and "mashups" that
join games the player already owns (SkyCraft = Skyrim SE + Minecraft). Its MCP
server at `https://melty.gg/api/mcp` (streamable HTTP) lets an agent research
games, check packages and publish. Standalone games, browser games, mockups and
demos do not qualify; a mashup must really integrate with its host games.

## Connection

The Melty app registers the server in each AI client with that client's own
bearer token. Never write, copy or print that token or move it between
providers. Check what the session has: Claude shows `mcp__melty__*` tools
(Tool Search may defer them); Codex has `[mcp_servers.melty]`.

Not registered: ask the user to connect their agent from the Melty app. Read-only
research works without a token; never invent one. A slow call ending in
"couldn't check your token" (HTTP 503) means the app or session is offline:
start/re-link Melty and keep building and testing locally meanwhile.

`consult_melty` is the creator's progress log: it sends Melty the creator's
last message and your full reply. Call it only on turns that are Melty work,
as the server instructs, and never put unrelated conversation, credentials or
private paths in it.

## Flow

1. Prior art: `search_games` (only slugs it returns are valid), `game_info`
   (mod folders, loaders, base files you must not ship, sell policy, what is
   unsafe for players), `search_mashups` / `mashup_info`. Remixing may beat a
   rebuild: `remix_mashup` creates a credited draft with the current files.
2. Build and test locally first through the normal engine route (`game-modding`,
   `universal-modder` mashup guide, `skyrim-tool-router` for Skyrim) with
   BUILD HYGIENE: semantic version, changelog, last-known-good copy, toggleable
   debug log (`observability-first`).
3. Before any upload: `inspect_package` on the exact archive or folder you
   built, then `validate_recipe` and `one_click_check`. A release that is not
   one click is blocked. Multiplayer: `setup_multiplayer` before
   `submit_release`, then again with the host/join logs from two copies on one PC.
4. Draft: `create_mod` (private until published), `start_upload` with the local
   size and SHA-256, PUT the bytes to the signed URL (multipart:
   `upload_part_urls`), `finish_upload` (pass `listing` for 7z/rar).
5. Media: `add_screenshot` then `finish_screenshot` with real gameplay capture.
   Never use mockups, generated stand-ins or footage of another build.
6. `submit_release` with semver `version`, `changelogMd` and the reviewed
   recipe. If issues remain, `report_fix_attempt` stating exactly what players
   still have to do.
7. `publish` makes it public: get the user's explicit go-ahead first. A release
   awaiting review is not live; confirm with `mod_status`.
8. After launch: `install_outcomes` lists real install/launch failures per game
   version. Fix the top reason and ship a new version.

## Do not

- Ship base-game files, others' assets without permission, or leaked/pirated material.
- Treat `inspect_package` or `one_click_check` as a gameplay test.
- Claim a multiplayer setup the recipe does not configure.
- Delegate building or testing to the user when tools on this machine can do it.
- Fill missing items (required games/versions, playable build, credits/license/
  remix choice, real media) with inventions: keep the draft and ask one focused
  question at a time.
