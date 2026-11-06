---
name: roblox-luau
description: Modern, type-safe Luau for Roblox, covering --!strict and the new type solver, generics, string interpolation, if-expressions, task library, require-by-string, module/OOP patterns, error handling with retries, buffer/vector, and legacy APIs to avoid. Use when writing, refactoring, or explaining any Roblox script, fixing type errors, or modernizing old Lua code.
enabled: true
---
# Modern Luau for Roblox

Luau is Roblox's gradually-typed Lua 5.1 derivative. Engine and language move fast; many
patterns from older tutorials (and older training data) are deprecated. Apply these defaults
to **every** script you write unless the project clearly uses another convention.

## Defaults for all generated code

1. `--!strict` at the top of new ModuleScripts (and Scripts when practical). Type public functions.
2. Get services with `game:GetService("Name")` at the top of the file, never `game.Name`.
3. Use the `task` library: `task.wait`, `task.spawn`, `task.defer`, `task.delay`, `task.cancel`.
   Never `wait`, `spawn`, `delay` (deprecated, throttled, imprecise).
4. Yielding engine calls that can fail (DataStore, HTTP, Marketplace, Teleport, `*Async`) go inside `pcall`.
5. Prefer the `*Async` variants of APIs; Roblox renamed most yielding methods
   (`LoadCharacterAsync`, `GetProductInfoAsync`, `UserHasBadgeAsync`, ...). See the table below.
6. Disconnect connections / destroy instances you create (see "Cleanup" below).
7. Naming: `PascalCase` for services, modules, classes, types, and instance names;
   `camelCase` for locals and functions; `SCREAMING_SNAKE_CASE` for constants.
8. Tabs for indentation (StyLua default in the Roblox ecosystem), double quotes.

## Modern syntax cheat sheet

```luau
local Players = game:GetService("Players")

local count = 0
count += 1 -- compound assignment: += -= *= /= //= %= ^= ..=

local label = if count > 1 then "many" else "one" -- if-expression (no `and/or` pitfalls)
print(`Player count: {#Players:GetPlayers()} ({label})`) -- string interpolation

for index, player in Players:GetPlayers() do -- generalized iteration: no pairs/ipairs needed
	if player.AccountAge < 1 then
		continue -- continue is a keyword
	end
	print(index, player.Name)
end

local half = 7 // 2 -- floor division → 3
local frozen = table.freeze({ Speed = 16 }) -- read-only table; writes throw
local list = table.create(100, 0) -- preallocated array
local copy = table.clone(frozen) -- shallow copy (unfrozen)
local mid = math.lerp(0, 10, 0.5) -- also: math.map, math.clamp, math.round, math.sign
print(half, list[1], copy.Speed, mid)
```

- `pairs`/`ipairs` still work; generalized iteration is preferred and iterates arrays in order.
- `#t` is only defined for arrays without holes. Setting `t[i] = nil` in the middle creates holes.
- Numbers are doubles: integers are exact to 2^53. Use `math.floor`/`//` for integer math.
- `tick()` is discouraged: use `os.clock()` for benchmarks, `workspace:GetServerTimeNow()` for
  synced time across clients/server, `os.time()`/`DateTime.now()` for wall-clock UTC.

## Types (new type solver)

Roblox's **new type solver** is generally available (Nov 2025) and `Workspace.UseNewLuauTypeSolver`
controls it; `Workspace.LuauTypeCheckMode` sets the default mode. Write code that checks cleanly
under `--!strict`.

```luau
--!strict
export type Item = {
	id: string,
	name: string,
	stack: number,
	tags: { string }?, -- optional field
}

type Rarity = "Common" | "Rare" | "Legendary" -- singleton (literal) union

local function totalStack(items: { Item }, filter: ((Item) -> boolean)?): number
	local total = 0
	for _, item in items do
		if filter == nil or filter(item) then
			total += item.stack
		end
	end
	return total
end

local function first<T>(list: { T }): T? -- generics
	return list[1]
end

local rarity: Rarity = "Rare"
local part = workspace:FindFirstChild("Door") :: BasePart? -- cast with ::
print(totalStack({}, nil), first({ 1, 2 }), rarity, part)
```

- Refine before use: `if part then ... end`, `if typeof(x) == "Instance" and x:IsA("BasePart") then`.
- `typeof(v)` knows Roblox types (`"Vector3"`, `"Instance"`, ...); `type(v)` only knows Lua types.
- Instance types come from `IsA` refinement or `FindFirstChildOfClass`/`FindFirstChildWhichIsA`.
- Avoid `any` except at trust boundaries (remote payloads, decoded JSON) — validate there, then narrow.

Details: generics, type packs, `read`/`write` properties, user-defined type functions, typing
OOP classes, and migrating legacy code to strict: [references/type-system.md](#reference-references-type-system-md).

## Modules and require

ModuleScripts run once per environment (server or each client) and return one value, cached for every
later `require`. A module in `ReplicatedStorage` required by both sides runs twice, once per side, with
separate state.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal) -- instance path (always works)
local Config = require("./Config") -- require-by-string: sibling of this script (script.Parent)
local Utils = require("@self/Utils") -- child of this script
local Shared = require("@game/ReplicatedStorage/Shared") -- absolute from game
print(Signal, Config, Utils, Shared)
```

- String paths: `./` = `script.Parent`, `../` = `script.Parent.Parent`, `@self/` = `script`,
  `@game/` = `game`. They **do not wait** for instances to exist. Use instance paths with
  `WaitForChild` when the module may not have replicated yet.
- Never create circular requires; they deadlock/error. Break cycles with dependency injection or events.
- Don't yield at module top level (no `WaitForChild` chains on things that may never exist, no
  DataStore calls): every requirer blocks until the module returns.

### Module / class pattern

```luau
--!strict
local Counter = {}
Counter.__index = Counter

export type Counter = typeof(setmetatable({} :: { value: number, step: number }, Counter))

function Counter.new(step: number?): Counter
	return setmetatable({ value = 0, step = step or 1 }, Counter)
end

function Counter.increment(self: Counter): number
	self.value += self.step
	return self.value
end

return Counter
```

Prefer plain modules of functions + data tables over deep inheritance. Use composition.

## Errors and retries

```luau
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerData")

local function retry<T...>(attempts: number, fn: () -> T...): (boolean, T...)
	local delaySeconds = 1
	for attempt = 1, attempts do
		local result = table.pack(pcall(fn))
		if result[1] then
			return table.unpack(result, 1, result.n)
		end
		if attempt < attempts then
			warn(`attempt {attempt} failed: {result[2]}`)
			task.wait(delaySeconds)
			delaySeconds *= 2 -- exponential backoff
		end
	end
	return false
end

local ok, data = retry(3, function()
	return store:GetAsync("Player_1")
end)
print(ok, data)
```

- `error("message", 2)` blames the caller; `error({ code = "X" })` throws a table for structured errors.
- `xpcall(fn, debug.traceback)` keeps the stack trace.
- Don't wrap everything in `pcall` — only calls that can fail for reasons outside your code.

## Concurrency: the task library

| Call | Behavior |
| --- | --- |
| `task.spawn(fn, ...)` | Run now (until first yield) on a new thread. |
| `task.defer(fn, ...)` | Run at the end of the current resumption cycle. Good for "after this finishes". |
| `task.delay(t, fn, ...)` | Run after `t` seconds. Returns a thread you can `task.cancel`. |
| `task.wait(t?)` | Yield ≥ `t` seconds (one frame if omitted); returns elapsed time. |
| `task.cancel(thread)` | Stop a spawned/delayed thread. |
| `task.desynchronize()` / `task.synchronize()` | Parallel Luau (inside Actors) — see `roblox-performance`. |

- Per-frame work: `RunService.Heartbeat` (after physics), `RunService.PreSimulation`/`PostSimulation`,
  `RunService:BindToRenderStep` (client, before render, ordered). Don't `while true do task.wait() end` for
  per-frame logic; connect to an event and use its `deltaTime`.
- Write handlers that work under **deferred** signal behavior (`Workspace.SignalBehavior`): handlers run
  later in the frame, not inline. New template places use `Deferred`, `Default` will switch to it, and
  server authority requires it. Don't rely on handler side effects being visible right after `:Fire()`.
- Never yield inside metamethods or `Changed`-style callbacks that must be synchronous.

## Cleanup (memory leaks are the #1 Roblox bug)

```luau
local Players = game:GetService("Players")

local connections: { RBXScriptConnection } = {}

table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		print(`{player.Name} left`)
	end)
)

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

cleanup()
```

- `Instance:Destroy()` disconnects that instance's connections and locks `Parent`; it does **not**
  clear your Lua references — nil out tables that hold players/instances on `PlayerRemoving`.
- Use `:Once()` for one-shot connections. Use a Trove/Janitor/Maid-style helper for groups.
- Keys that are Player/Instance objects in long-lived tables leak unless removed on leave/destroy.

## Buffers and vectors (performance-sensitive data)

```luau
local packet = buffer.create(10)
buffer.writeu16(packet, 0, 513) -- item id
buffer.writef32(packet, 2, 12.5) -- amount
buffer.writei32(packet, 6, -4)
print(buffer.readu16(packet, 0), buffer.readf32(packet, 2), buffer.len(packet))

local v = vector.create(1, 2, 3) -- native 3-float vector (same type as Vector3 at runtime)
print(vector.magnitude(v), vector.normalize(v), vector.dot(v, vector.one))
```

`buffer` is the right tool for compact network payloads, large grids, and binary serialization.
Standard-library quick reference: [references/stdlib-cheatsheet.md](#reference-references-stdlib-cheatsheet-md).

## Legacy → current (most common mistakes)

| Don't write | Write instead |
| --- | --- |
| `wait()`, `spawn()`, `delay()` | `task.wait()`, `task.spawn()`, `task.delay()` |
| `game.Workspace`, `game.Players` | `workspace`, `game:GetService("Players")` |
| `Instance.new("Part", parent)` | create, set properties, **then** set `.Parent` last |
| `Humanoid:LoadAnimation()` | `Animator:LoadAnimation()` |
| `Model:SetPrimaryPartCFrame()` | `Model:PivotTo()` / `Model:GetPivot()` |
| `workspace:FindPartOnRay(Ray.new(...))` | `workspace:Raycast(origin, direction, params)` |
| `BodyVelocity`, `BodyPosition`, `BodyGyro` | `LinearVelocity`, `AlignPosition`, `AlignOrientation` |
| `player:LoadCharacter()` | `player:LoadCharacterAsync()` |
| `MarketplaceService:GetProductInfo()` | `:GetProductInfoAsync()` |
| `BadgeService:AwardBadge()` | `:AwardBadgeAsync()` |
| `player:GetRankInGroup()` | `GroupService:GetRolesInGroupAsync()` / `player:IsInGroupAsync()` |
| `TeleportService:Teleport*()` variants | `TeleportService:TeleportAsync()` |
| `Chat` service / `ChatService` modules | `TextChatService` |
| `GuiObject.Draggable` | `UIDragDetector` |
| `table.getn`, `table.foreach`, `getfenv` | `#t`, `for ... in`, nothing |

The full deprecation map lives in the `roblox-code-review` skill.

## Performance idioms (only where it matters)

- Measure first (`debug.profilebegin/profileend`, MicroProfiler, Script Profiler).
- `--!native` at the top of a script, or `@native` on a function, compiles hot numeric code natively.
  Use it on math-heavy modules, not everywhere (compile time + memory limits). Type annotations help it.
- Cache `Instance` lookups and service references outside loops; avoid `FindFirstChild` chains per frame.
- Build large strings with `table.concat` or `buffer`, not repeated `..` in loops.
- Reuse `RaycastParams`/`OverlapParams` objects instead of creating them per call.

## Related skills

`roblox-architecture` (project structure, client/server), `roblox-networking` (remotes),
`roblox-performance` (profiling, Parallel Luau), `roblox-code-review` (review checklist, full deprecation map).

---

<a id="reference-references-stdlib-cheatsheet-md"></a>

## Appendix: references/stdlib-cheatsheet.md

### Luau standard library on Roblox — cheat sheet

Only libraries and functions available in Roblox are listed. Deprecated: `table.getn`, `table.foreach`,
`table.foreachi`, `getfenv`, `setfenv`, globals `wait`, `spawn`, `delay`, `ypcall`, `version`, `elapsedTime`.

## task

`spawn(fnOrThread, ...)`, `defer(fnOrThread, ...)`, `delay(seconds, fnOrThread, ...)`, `wait(seconds?)`,
`cancel(thread)`, `desynchronize()`, `synchronize()` (Parallel Luau only).

## table

| Function | Notes |
| --- | --- |
| `table.create(n, value?)` | Preallocate an array of `n` slots. |
| `table.insert(t, v)` / `table.insert(t, i, v)` | Append / insert (shifts). |
| `table.remove(t, i?)` | Remove (shifts). For unordered removal: swap with last, then remove last. |
| `table.find(t, v, init?)` | Linear search in an array; returns index or nil. |
| `table.clear(t)` | Empties in place, keeps capacity (good for reused buffers). |
| `table.clone(t)` | Shallow copy. Deep copy must be written manually. |
| `table.freeze(t)` / `table.isfrozen(t)` | Shallow immutability. |
| `table.move(a, i, j, k, b?)` | Bulk copy ranges. |
| `table.concat(t, sep?)` | Join strings — use for building large strings. |
| `table.sort(t, lt?)` | In-place, not stable. Comparator must be a strict weak ordering (`<`, never `<=`). |
| `table.pack(...)` / `table.unpack(t, i?, j?)` | `pack` sets `n` (handles nils). |

## string

`split(s, sep)`, `format` (`%d %s %q %.2f %x`), `find/match/gmatch/gsub` (Lua patterns, not regex),
`sub`, `rep`, `lower/upper`, `byte/char`, `pack/unpack/packsize` (binary), `len`, `reverse`.
Interpolation: `` `Hi {name}` `` (use `\{` for a literal brace). `utf8` library for Unicode:
`utf8.len`, `utf8.codes`, `utf8.char`, `utf8.offset`, and Roblox additions `utf8.graphemes`,
`utf8.nfcnormalize`, `utf8.nfdnormalize` (use graphemes when counting/truncating user-visible text).

## math

`clamp`, `round`, `sign`, `floor`, `ceil`, `abs`, `min/max`, `lerp(a, b, t)`, `map(x, inMin, inMax, outMin, outMax)`,
`noise(x, y?, z?)` (Perlin, returns about -1..1), `random(m?, n?)`, `isnan`, `isinf`, `isfinite`,
`huge`, `pi`, `tau`. Prefer `Random.new(seed)` objects (`:NextInteger`, `:NextNumber`, `:Shuffle`) over
global `math.random` for reproducible or per-system RNG.

## buffer

Fixed-size mutable byte arrays. `create(size)`, `fromstring`, `tostring`, `len`, `copy`, `fill`,
`read/write` + `i8 u8 i16 u16 i32 u32 f32 f64`, `readstring/writestring(b, offset, str, count?)`,
`readbits/writebits(b, bitOffset, bitCount, value)`. Little-endian. Buffers can be sent through remotes
and stored in DataStores (serialized), and are the fastest way to pack network data.

## vector

`vector.create(x, y, z)`, `zero`, `one`, `magnitude`, `normalize`, `cross`, `dot`, `angle(a, b, axis?)`,
`floor`, `ceil`, `abs`, `sign`, `clamp`, `lerp`, `max`, `min`. Operates on the same immutable 3-component
value type as `Vector3`, with faster, native-codegen-friendly calls.

## bit32

`band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift`, `extract`, `replace`, `btest`, `countlz`, `countrz`, `byteswap`.

## coroutine

`create`, `resume`, `yield`, `wrap`, `status`, `running`, `isyieldable`, `close`. Use coroutines for
generators/state machines; use `task.spawn`/`task.defer` to run code concurrently (errors inside a
`coroutine.resume` are returned, not reported to Output, and are easy to lose).

## os / time

`os.clock()` (high-res CPU time, benchmarking), `os.time()` (UTC seconds), `os.date(fmt, t)`,
`os.difftime`. Roblox datatypes: `DateTime.now()`, `DateTime.fromUnixTimestamp`, `:ToIsoDate()`,
`:FormatLocalTime(fmt, locale)`. Synced server clock: `workspace:GetServerTimeNow()`.

## debug

`traceback(msg?, level?)`, `info(level|fn, "slnaf")`, `profilebegin(label)` / `profileend()` (MicroProfiler
labels), `setmemorycategory(name)` / `resetmemorycategory()` (Developer Console memory tags),
`dumpcodesize()` (native codegen size in Studio).

## Roblox globals

`game`, `workspace`, `script`, `plugin` (plugins only), `shared` (avoid: untyped global table — use
modules), `typeof`, `require`, `settings()`, `UserSettings()`, `warn`, `print`, `error`, `tick` (avoid).
Datatypes: `Vector3`, `Vector2`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Rect`, `NumberRange`,
`NumberSequence`, `ColorSequence`, `BrickColor`, `Enum`, `Instance`, `RaycastParams`, `OverlapParams`,
`TweenInfo`, `Random`, `DateTime`, `Font`, `Content`, `Path2DControlPoint`, `SharedTable`.

---

<a id="reference-references-type-system-md"></a>

## Appendix: references/type-system.md

### Luau type system (new solver) — reference

Authoritative spec: <https://luau.org/typecheck>. Everything here type-checks under the new solver in `--!strict`.

## Modes

| Hot comment | Behavior |
| --- | --- |
| `--!nocheck` | No type errors reported. |
| `--!nonstrict` | Infers types, reports only definite errors. Unannotated values are `any`-ish. |
| `--!strict` | Full inference and checking. Use for all new modules. |

`Workspace.LuauTypeCheckMode` sets the default for scripts without a hot comment;
`Workspace.UseNewLuauTypeSolver` (a `RolloutState`) selects the solver. With Rojo + luau-lsp, set
`"luau-lsp.fflags.enableNewSolver": true` (or the equivalent in your editor) so editor and Studio agree.

## Building blocks

```luau
--!strict
type Id = string
type Maybe<T> = T? -- same as T | nil
type Vec = { x: number, y: number } -- table (record) type
type List = { number } -- array
type Map = { [string]: number } -- dictionary
type Callback = (player: Player, amount: number) -> boolean
type Varargs = (...number) -> () -- variadic, returns nothing
type Pair<K, V = string> = { key: K, value: V } -- generic with a default
type Shape = { kind: "circle", radius: number } | { kind: "rect", w: number, h: number } -- tagged union

local function area(shape: Shape): number
	if shape.kind == "circle" then
		return math.pi * shape.radius ^ 2 -- refined to the circle variant
	else
		return shape.w * shape.h
	end
end

local lookup: Map = { a = 1 }
local pair: Pair<number> = { key = 1, value = "one" }
print(area({ kind = "rect", w = 2, h = 3 }), lookup, pair)
```

- Tagged unions + `if x.kind == ...` give exhaustive, refined handling — prefer them over loose optional fields.
- Intersections `A & B` combine table types; overloaded function types are intersections of function types.

## Generics and type packs

```luau
--!strict
local function map<T, U>(list: { T }, fn: (T) -> U): { U }
	local out = table.create(#list)
	for i, v in list do
		out[i] = fn(v)
	end
	return out
end

local function wrap<A..., R...>(fn: (A...) -> R...): (A...) -> R...
	return function(...: A...): R...
		return fn(...)
	end
end

local names = map({ 1, 2, 3 }, function(n)
	return `#{n}`
end)
print(names, wrap(math.max)(1, 5))
```

`T...` is a type pack (a list of types), used for varargs and multiple returns.

## Refinement

```luau
--!strict
local function describe(value: unknown): string
	if typeof(value) == "Instance" then
		if value:IsA("BasePart") then
			return `part at {value.Position}` -- refined to BasePart
		end
		return value:GetFullName()
	elseif type(value) == "number" then
		return string.format("%.2f", value)
	end
	return "unknown"
end
print(describe(workspace))
```

- Use `unknown` (not `any`) for values you haven't validated: the checker forces you to refine.
- `assert(x, "msg")` refines `x` to non-nil after the call.
- `FindFirstChild` returns `Instance?`; use `FindFirstChildOfClass("Humanoid")` or `FindFirstChildWhichIsA`
  to get a typed result, or refine with `IsA`.

## Casts

`expr :: T` asserts a type. It's only allowed when the types are related (e.g. `Instance` → `Part`).
To force an unrelated cast, go through `any`: `(x :: any) :: T` — a code smell; prefer refinement.

## Read-only / write-only properties

```luau
--!strict
type Settings = { read version: number, volume: number }

local settings: Settings = { version = 2, volume = 0.5 }
settings.volume = 1 -- ok
-- settings.version = 3 -- type error: property is read-only
print(settings.version)
```

Pair with `table.freeze` for runtime immutability.

## Built-in type functions

`keyof<T>` (union of a table's key literals), `index<T, K>` (type of a property), `typeof(expr)`,
plus `rawkeyof`, `rawget`, `getmetatable`, `setmetatable` type functions.

```luau
--!strict
local DEFAULTS = { walkSpeed = 16, jumpPower = 50 }
type SettingName = keyof<typeof(DEFAULTS)> -- "walkSpeed" | "jumpPower"

local function get(name: SettingName): number
	return DEFAULTS[name]
end
print(get("walkSpeed"))
```

## User-defined type functions

Type functions run at analysis time and build types programmatically with the `types` library.

```luau
--!strict
type function Partial(t)
	local result = types.newtable()
	for key, prop in t:properties() do
		result:setproperty(key, types.optional(prop.read))
	end
	return result
end

type Stats = { health: number, mana: number }
local patch: Partial<Stats> = { mana = 10 }
print(patch)
```

Use sparingly: they improve library APIs but make code harder for teammates to read.

## Typing classes (OOP)

Pattern A — infer from the constructor (least boilerplate):

```luau
--!strict
local Account = {}
Account.__index = Account

type AccountData = { owner: Player, balance: number }
export type Account = typeof(setmetatable({} :: AccountData, Account))

function Account.new(owner: Player): Account
	return setmetatable({ owner = owner, balance = 0 }, Account)
end

function Account.deposit(self: Account, amount: number)
	assert(amount > 0, "amount must be positive")
	self.balance += amount
end

return Account
```

Pattern B — explicit interface (best for public library APIs; decouples the shape from the metatable):

```luau
--!strict
export type Timer = {
	start: (self: Timer) -> (),
	elapsed: (self: Timer) -> number,
}

local function newTimer(): Timer
	local startedAt = os.clock()
	local timer = {}
	function timer.start(_self: Timer)
		startedAt = os.clock()
	end
	function timer.elapsed(_self: Timer): number
		return os.clock() - startedAt
	end
	return timer
end

return newTimer
```

Inheritance: prefer composition (a field holding another object). If you must inherit, set the child
metatable's `__index` to the parent class and type the child as an intersection of both shapes.

## Common errors → fixes

| Error | Fix |
| --- | --- |
| `Value of type 'Instance?' could be nil` | Refine: `local x = parent:FindFirstChild("X"); if not x then return end`. |
| `Key 'Foo' not found in external type 'Instance'` | Refine with `IsA`, cast (`:: Folder`), or use a Rojo sourcemap so luau-lsp knows children. |
| `Type 'string' could not be converted into 'number'` | Convert explicitly (`tonumber(s)`) and handle `nil`. |
| `Unknown type used in + operation` | Annotate the parameter (`function f(a: number)`). |
| `Cannot add property 'x' to table` | Declare the field in the table type or constructor literal. |
| Types from a required module are `any` | The require path isn't resolvable statically: use instance paths or string requires, and a sourcemap with Rojo. |

## Migrating a codebase to strict

1. Enable the new solver; add `--!strict` file by file, starting with leaf modules (utilities, data).
2. Add `export type` for every module's public data shape; annotate function parameters and returns.
3. Replace `FindFirstChild` chains with typed accessors or validated lookups.
4. Treat remote payloads and DataStore data as `unknown` and write validators that return typed values.
5. Keep `any` only at explicit boundaries, with a comment explaining why.
