---
name: roblox-text-chat
description: Chat and text safety - TextChatService (channels, SendAsync, ShouldDeliverCallback, OnIncomingMessage, commands, bubbles, custom UI, platform-integrated chat and TextChannelWindow migration due May 2027), mandatory TextService filtering of any player-authored text, rate limits, privacy checks, PolicyService restrictions, legacy Chat migration. Use when adding chat features or commands, or any feature that shows one player's text to others (names, signs, notes).
enabled: true
---
# Chat and text safety

## Non-negotiable rules (Roblox Community Standards)

1. Player-to-player conversation must go through **TextChatService** `TextChannel`s (handles filtering,
   privacy/parental settings, and abuse reporting). The legacy `Chat` service/`ChatService` Lua modules
   are gone — `TextChatService` is the only chat system.
2. **Any text authored by one player and shown to another** (pet names, signs, guild names, trade notes,
   custom UI) must be filtered with `TextService:FilterStringAsync` on the server before display — and
   re-filtered when loaded from a DataStore later.
3. Editable text others can see (signs, bulletin boards) needs a rate limit of at least 1 minute.
4. Respect privacy settings with `CanUserChatAsync`/`CanUsersChatAsync`/`CanUsersDirectChatAsync` and mark
   direct-message channels with `TextChannel:SetDirectChatRequester()`.

Not chat (no filtering needed): your own UI text, game status messages, admin announcements you write.

## Filtering player-authored text

```luau
--!strict
local TextService = game:GetService("TextService")

-- Broadcast (e.g. a sign everyone sees). Returns nil if filtering failed: then show nothing.
local function filterForEveryone(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

-- Per-recipient (respects each viewer's age/settings; e.g. a private note).
local function filterForUser(text: string, fromUserId: number, toUserId: number): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PrivateChat)
		return filterResult:GetNonChatStringForUserAsync(toUserId)
	end)
	return if ok then result else nil
end

return { forEveryone = filterForEveryone, forUser = filterForUser }
```

- Filter on the **server**, after the player submits (not per keystroke); rate-limit and length-cap first.
- On failure, **fail closed** (show nothing / a placeholder), never the raw text.
- Store the raw text if you must, but always filter at display time (filters and viewer settings change).
- Numbers-only or short strings can still be filtered (hashtags `###`); design UI for that.

## TextChatService essentials

- Defaults: `CreateDefaultTextChannels` creates `RBXGeneral` and `RBXSystem`; `CreateDefaultCommands`
  adds built-ins (`/whisper`, `/team`, `/mute`, ...). Configure look via `ChatWindowConfiguration`,
  `ChatInputBarConfiguration`, `BubbleChatConfiguration` (or disable and build your own UI with
  `TextChannel:SendAsync` and `TextChatService.MessageReceived`).
- Flow: client `TextChannel:SendAsync(text)` → server `TextChannel.ShouldDeliverCallback(message, textSource)`
  per recipient → filtering → clients' `OnIncomingMessage` callbacks → display.
- Callbacks must **not yield**. `ShouldDeliverCallback` is server-only; `TextChatService.OnIncomingMessage`
  and `TextChannel.OnIncomingMessage` are client-only (formatting).
- System messages: `channel:DisplaySystemMessage(text)` on the client (local only).
- Custom channels (team, party, proximity): create `TextChannel`s under `TextChatService` on the server,
  `channel:AddUserAsync(userId)` to add members; check the returned `TextSource`'s `CanSend`.

```luau
--!strict
-- Client: chat tags and colors via OnIncomingMessage (formatting only; never yields).
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source then
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute("VIP") then
			properties.PrefixText = `<font color="#F5CD30">[VIP]</font> {message.PrefixText}`
		end
	end
	return properties
end
```

```luau
--!strict
-- Server: a /spawn command, restricted to admins.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ADMINS: { [number]: boolean } = { [123456] = true }

local command = Instance.new("TextChatCommand")
command.Name = "SpawnCommand"
command.PrimaryAlias = "/spawn"
command.Parent = TextChatService

command.Triggered:Connect(function(source: TextSource, unfilteredText: string)
	if not ADMINS[source.UserId] then
		return
	end
	local player = Players:GetPlayerByUserId(source.UserId)
	print(`{player and player.Name} ran: {unfilteredText}`)
end)
```

## Platform-integrated chat (required May 2027)

Roblox is making chat native. Opt in to test now: select `TextChatService` in Studio and set
`PlatformIntegratedChat = Enabled` (Studio only, not scriptable). When enabled:
- Roblox renders all chat, in the default window or `TextChannelWindow`s you place in UI (one per
  `TextChannel` via `Target`; works in `SurfaceGui`s). Custom chat UIs can no longer render messages.
- Message text is hidden from code: `TextChatMessage.Text`/`Translation`/`PrefixText`, `OnIncomingMessage`,
  `Player.Chatted`, and `TextChannel:SendAsync` stop working (return `""` + warning). No chat logging.
- Commands must be `TextChatCommand`s; preset phrases → Quick Words; chat tags/prefixes → role badges
  (planned Feb 2027 — don't opt in yet if you rely on prefixes). `DisplaySystemMessage` and
  `BubbleChatConfiguration`/`OnBubbleAdded` styling still work.
- **New code**: build on `TextChatCommand`, `TextChannelWindow`, and system messages; avoid reading message
  text. The `OnIncomingMessage` tag example above only works until migration.

More: proximity chat, team channels, custom UI, and migrating from legacy chat:
[references/chat-recipes.md](#reference-references-chat-recipes-md).

**Quick Words** (preset safe phrases for all ages, for coordinating where free chat is limited): add game-specific
ones in Creator Hub → game → Configure → Chat → Quick Words — up to 3 categories of 3–10 phrases, in English
(auto-translated), reviewed before going live. They replace the default categories; General stays.

## PolicyService (per-user restrictions)

`PolicyService:GetPolicyInfoForPlayerAsync(player)` (server, `pcall`) returns flags such as
`ArePaidRandomItemsRestricted`, `IsPaidItemTradingAllowed`, `AreAdsAllowed`, `AllowedExternalLinkReferences`,
`IsSubjectToChinaPolicies`, `IsContentSharingAllowed`. Gate loot boxes, trading, ads, and links to
social media (only show platforms listed in `AllowedExternalLinkReferences`) per player.

## Related skills

`roblox-security` (rate limits, validation), `roblox-ui` (text input UI), `roblox-monetization`
(paid random items), `roblox-data-stores` (storing user text).

---

<a id="reference-references-chat-recipes-md"></a>

## Appendix: references/chat-recipes.md

### Chat recipes

## Proximity chat (server)

```luau
--!strict
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local RANGE = 50
local channels = TextChatService:WaitForChild("TextChannels")
local general = channels:WaitForChild("RBXGeneral") :: TextChannel

local function positionOf(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	return character and character:GetPivot().Position
end

general.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
	local source = message.TextSource
	if not source or source.UserId == target.UserId then
		return true -- always show senders their own message
	end
	local from, to = positionOf(source.UserId), positionOf(target.UserId)
	return from ~= nil and to ~= nil and (from - to).Magnitude <= RANGE
end
```

## Team or party channel (server)

```luau
--!strict
local TextChatService = game:GetService("TextChatService")

local function createPartyChannel(partyId: string, members: { Player }): TextChannel
	local channel = Instance.new("TextChannel")
	channel.Name = `Party_{partyId}`
	channel.Parent = TextChatService:WaitForChild("TextChannels")
	for _, member in members do
		local ok, source = pcall(function()
			return channel:AddUserAsync(member.UserId)
		end)
		if not ok or not source then
			warn(`could not add {member.Name}`)
		end
	end
	return channel -- clients send with channel:SendAsync(text); Destroy() when the party ends
end

return createPartyChannel
```

Teams: the built-in `/team` command and team channels exist when `CreateDefaultCommands`/
`CreateDefaultTextChannels` are on and `Teams` are set up.

## Rate-limited bulletin board (server)

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local COOLDOWN = 60 -- at least 1 minute for player-editable public text
local MAX_LENGTH = 140

local postNote = Instance.new("RemoteEvent")
postNote.Name = "PostNote"
postNote.Parent = ReplicatedStorage

local lastPost: { [Player]: number } = {}

postNote.OnServerEvent:Connect(function(player, text: unknown)
	if typeof(text) ~= "string" or #text == 0 or #text > MAX_LENGTH or utf8.len(text) == nil then
		return
	end
	local now = os.clock()
	if lastPost[player] and now - lastPost[player] < COOLDOWN then
		return
	end
	lastPost[player] = now
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		postNote:FireAllClients(player.UserId, filtered)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastPost[player] = nil
end)
```

## Custom chat UI

Set `ChatWindowConfiguration.Enabled = false` and `ChatInputBarConfiguration.Enabled = false`, then:
- Send: `(TextChatService.TextChannels.RBXGeneral :: TextChannel):SendAsync(textBox.Text)`.
- Receive: `TextChatService.MessageReceived:Connect(function(message) ... end)`; render
  `message.PrefixText` and `message.Text` (already filtered). Use `message.MessageId` to replace the
  sender's local pending message when the server-processed version arrives.
- Keep bubble chat via `BubbleChatConfiguration` or `TextChatService.OnBubbleAdded`.

## Migrating from legacy Chat

| Legacy | TextChatService |
| --- | --- |
| `Chat:Chat(part, text)` bubbles | `TextChatService:DisplayBubble(part, text)` (client) |
| ChatService speakers/channels | `TextChannel` + `AddUserAsync`; permissions via `TextSource.CanSend` |
| Extra data (tags, colors) on speakers | `OnIncomingMessage` returning `TextChatMessageProperties` (`PrefixText`, `Text`) with rich text |
| `Chat:FilterStringAsync` | `TextService:FilterStringAsync` |
| Custom commands via message hooks | `TextChatCommand` instances (`PrimaryAlias`, `SecondaryAlias`, `Triggered`) |
