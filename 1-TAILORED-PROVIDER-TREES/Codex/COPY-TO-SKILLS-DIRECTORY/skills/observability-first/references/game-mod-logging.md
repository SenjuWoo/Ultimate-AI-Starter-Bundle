# Debug logging for games and mods

Ship the log with the first build, not after the first bug report. One switch
turns verbose output on (INI/JSON key, MCM toggle, launch flag or env var);
releases stay quiet except for warnings and errors. Prefix every line with the
mod/game id so it can be filtered out of a shared log.

Every build logs, once at startup: name, version, build/commit, the host
version it detected and the resolved settings. After that: each state
transition, each external dependency that is missing or rejected, and each
failure with its cause and the action taken. Never log per-frame chatter,
credentials, save contents or whole payloads.

Check the actual install before quoting a path: users relocate Documents,
OneDrive redirects it, and loaders change their layout between major versions.

| Platform | API | Default log location |
|---|---|---|
| Skyrim SE/AE Papyrus | `Debug.Trace(msg)`; own file: `Debug.OpenUserLog("Mod")` then `Debug.TraceUser("Mod", msg)` | `Documents\My Games\Skyrim Special Edition\Logs\Script\Papyrus.0.log` and `...\Logs\Script\User\Mod.0.log`. Needs `[Papyrus] bEnableLogging=1` and `bEnableTrace=1` in the user's Skyrim INI |
| Skyrim SKSE (CommonLibSSE-NG) | spdlog via `SKSE::log` | `Documents\My Games\Skyrim Special Edition\SKSE\<Plugin>.log` (`SKSE::log::log_directory()`) |
| Fallout 4 / Starfield | Papyrus `Debug.Trace`, F4SE/SFSE spdlog | `Documents\My Games\Fallout4\Logs\Script\`, `...\Fallout4\F4SE\`; Starfield under `Documents\My Games\Starfield\` |
| Unity (BepInEx) | plugin `Logger.LogInfo/LogWarning/LogError` | `BepInEx\LogOutput.log` in the game folder |
| Unity (MelonLoader) | `LoggerInstance.Msg/Warning/Error` | `MelonLoader\Latest.log` in the game folder |
| Unity (own game) | `Debug.Log/LogWarning/LogError` | `%USERPROFILE%\AppData\LocalLow\<Company>\<Product>\Player.log` |
| Unreal | `DECLARE_LOG_CATEGORY_EXTERN` + `UE_LOG(LogMyMod, Verbose, ...)`; `-LogCmds` to raise verbosity | `<Project>\Saved\Logs\<Project>.log` |
| Godot | `print`, `push_warning`, `push_error` | `user://logs/godot.log` (`debug/file_logging/enable_file_logging`) |
| Minecraft (Fabric/Forge/NeoForge) | SLF4J `LoggerFactory.getLogger(MOD_ID)` | `<instance>\logs\latest.log`; Forge/NeoForge also write debug level to `logs\debug.log` |
| RimWorld | `Log.Message/Warning/Error` | `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log` |
| Roblox | `print`, `warn`, `error` | Studio Output window; live servers via the Developer Console |
| Browser games | a `debug` flag gating `console.debug`; keep `console.error` for failures | DevTools console; persist a ring buffer if players must send it |
| Python/Node tools | `logging` with a rotating file handler / a leveled logger | next to the app's config or `%LOCALAPPDATA%\<App>\logs\` |

Tell the user how to enable the verbose switch and where the file lands. When
a crash report or load-order log is the evidence, route to the engine's crash
skill (`skyrim-crash-diagnostics`, `skyrim-runtime-log-forensics`, `game-modding`).
