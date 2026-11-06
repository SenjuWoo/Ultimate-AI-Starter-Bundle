---
name: roblox-monetization
description: Robux monetization - developer products with idempotent ProcessReceipt, passes, subscriptions, rewarded video ads, personalized shops, regional pricing and trade arbitrage, paid random item policy (PolicyService), commerce products, private servers, Roblox Plus, refunds, age checks and the US 18+ rate. Use when adding purchases, shops, game passes, subscriptions, ads, or loot boxes, or debugging lost/duplicated purchases.
enabled: true
---
# Roblox monetization

## Product types

| Type | Buy | Use for | Grant via |
| --- | --- | --- | --- |
| Developer product | Repeatedly | Currency, consumables, boosts, revives | `MarketplaceService.ProcessReceipt` (server) |
| Pass | Once, permanent | VIP, permanent perks, extra slots | `UserOwnsGamePassAsync` check on join + purchase-finished event |
| Subscription | Monthly, revocable | Recurring perks (daily currency, VIP) | `GetUserSubscriptionStatusAsync` + `UserSubscriptionStatusChanged` |
| Rewarded video ad | Free (watch ad) | Small rewards (≈3–10 Robux value) | Developer product granted through `ProcessReceipt` |
| Commerce product | Real money (physical goods) | Merch with bundled digital benefits | `CommerceService`; digital benefits via `ProcessReceipt` |
| Private server | Monthly | Paid private servers | Configured in Creator Dashboard |

All granting happens on the **server**. Never grant from client events like
`PromptProductPurchaseFinished` — clients can fake them.

## Developer products: ProcessReceipt

Rules:
- Exactly **one** server script sets `MarketplaceService.ProcessReceipt`.
- Return `PurchaseGranted` only after the grant is **persisted**. Otherwise return `NotProcessedYet`;
  Roblox retries later (including on the player's next join) with the same `PurchaseId`.
- Handlers must be **idempotent**: record handled `PurchaseId`s in the player's saved data so a retry
  never grants twice.
- Receipts arrive for players who may not be loaded yet or may have left: wait for their data, or
  return `NotProcessedYet`.

```luau
--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

type PlayerData = { coins: number, purchaseIds: { string } }
type ReceiptInfo = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
	PlaceIdWherePurchased: number,
}

local MAX_REMEMBERED_PURCHASES = 100

-- Provided by your data layer (ProfileStore profile.Data, etc.).
local function getLoadedData(_player: Player): PlayerData?
	return nil
end
local function saveNow(_player: Player): boolean
	return true
end

local PRODUCTS: { [number]: (Player, PlayerData) -> () } = {
	[1234567] = function(_player, data) -- 100 coins
		data.coins += 100
	end,
}

local function processReceipt(receipt: ReceiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted on their next visit
	end

	local data = getLoadedData(player)
	local deadline = os.clock() + 20
	while not data and player.Parent == Players and os.clock() < deadline do
		task.wait(0.5)
		data = getLoadedData(player)
	end
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if table.find(data.purchaseIds, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end

	local handler = PRODUCTS[receipt.ProductId]
	if not handler then
		warn(`No handler for product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(handler, player, data)
	if not ok then
		warn(`Grant failed for {receipt.PurchaseId}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(data.purchaseIds, receipt.PurchaseId)
	while #data.purchaseIds > MAX_REMEMBERED_PURCHASES do
		table.remove(data.purchaseIds, 1)
	end

	if not saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- the idempotency list prevents a double grant
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt :: any
```

With ProfileStore, "persisted" means waiting until the `PurchaseId` appears in `profile.LastSavedData`
(or calling `profile:Save()` and waiting); see ProfileStore's developer products guide.

Prompt from the client (UI) — the server still grants:
`MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)`.

## Passes

```luau
--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local VIP_PASS_ID = 987654

local function grantVip(player: Player)
	player:SetAttribute("VIP", true) -- apply perks from one place
end

local function checkPass(player: Player)
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, VIP_PASS_ID)
	if ok and owns then
		grantVip(player)
	end
end

Players.PlayerAdded:Connect(checkPass)
for _, player in Players:GetPlayers() do
	task.spawn(checkPass, player)
end

-- Fires on the server too; re-verify ownership rather than trusting `purchased` alone.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passId == VIP_PASS_ID then
		checkPass(player)
	end
end)
```

`UserOwnsGamePassAsync` results are cached per server; the purchase-finished handler covers in-session buys.

## Subscriptions

- Check with `MarketplaceService:GetUserSubscriptionStatusAsync(player, "EXP-...")` → `{ IsSubscribed, IsRenewing }`
  on join and on `Players.UserSubscriptionStatusChanged(player, subscriptionId)`.
- Benefits must be **revocable**: when `IsSubscribed` is false, remove perks you persisted.
- Prompt with `MarketplaceService:PromptSubscriptionPurchase(player, subscriptionId)`.
- Replacing a pass with a subscription: keep honoring existing pass owners, take the pass off sale.

## Shops that sell

- Personalize order with `MarketplaceService:RankProductsAsync(identifiers)` (call once on join —
  strict rate limit) and "Top picks" with `RecommendTopProductsAsync({ Enum.InfoType.Product, Enum.InfoType.GamePass })`
  (needs a sale in the last 28 days; call in `task.spawn`).
- Show live prices from `GetProductInfoAsync(id, Enum.InfoType.Product)` / `GetDeveloperProductsAsync()` — never
  hardcode Robux prices: **managed pricing** (regional pricing + price optimization) shows different
  users different prices. `receipt.CurrencySpent` has what the user actually paid.
- Contextual offers (revive on death, boost when stuck) outperform static menus. Also list items in
  the game's **Shop** tab in Creator Hub.
- Open the Roblox Shop overlay from your own buttons, NPCs, or zones with `MarketplaceService:OpenShop(player)`.
- **Listed** passes and developer products can also be sold outside the game (Home, search, after Robux
  purchases); the player joins with the item already bought. Developer products qualify only with a correct
  `ProcessReceipt` — Creator Hub → Monetization → Shop flags products that need a fix.

## Refunds and chargebacks

Refunded passes (and avatar items) lose ownership automatically — re-check ownership instead of caching it
forever. Developer product grants live in your data, so revoke them yourself: subscribe to the
**Transaction Refunded** webhook (covers developer products, passes, private servers, Paid Access) and
match it by the transaction/receipt ID in the payload (see `roblox-open-cloud`). Keep handled `PurchaseId`s
with what each granted so a refund can be reversed.

## Compliance

- **Paid random items** (loot boxes, gacha, spins bought with Robux or Robux-bought currency): disclose
  odds before purchase, and check `PolicyService:GetPolicyInfoForPlayerAsync(player)`:
  - `ArePaidRandomItemsRestricted` → offer a free earnable path, a disclosed fixed sequence, or direct purchase.
  - `IsPaidItemTradingAllowed` → disable trading of paid items when false.
- **Regional pricing arbitrage**: gate gifting/trading of purchased items using
  `MarketplaceService:GetUsersPriceLevelsAsync(userIds)` (1–1000, % of global price); fetch at join,
  don't cache across sessions.
- Rewarded video rewards must be developer products, not random, and must not harm the player's
  character while the ad plays.
- Respect age/region restrictions returned by `PolicyService` for ads, social links, and trading.

Rewarded video ads, commerce products, Premium/Roblox Plus hooks, US 18+ DevEx rate and age checks:
[references/ads-and-extras.md](#reference-references-ads-and-extras-md).

## Related skills

`roblox-data-stores` (persisting grants), `roblox-security` (economy exploits), `roblox-ui` (shop UI),
`roblox-analytics-liveops` (economy events, funnels, experiments).

---

<a id="reference-references-ads-and-extras-md"></a>

## Appendix: references/ads-and-extras.md

### Rewarded video ads, commerce products, Premium and Roblox Plus, 18+ rate

## Rewarded video ads (AdService)

Requirements: creator 13+ and ID-verified, public game with ≥ 2k monthly unique visitors, serving
enabled in **Creator Hub → Monetization → Ads → Settings**, and a developer product as the reward.

Client — show the button only when an ad is available (check right before showing):

```luau
--!strict
local AdService = game:GetService("AdService")

local function isAdAvailable(): boolean
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	return ok and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

print(isAdAvailable())
```

Server — play the ad; the reward arrives through `ProcessReceipt` like any developer product:

```luau
--!strict
local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REWARD_PRODUCT_ID = 1919753834 -- developer product in this universe
local requestAd = Instance.new("RemoteEvent")
requestAd.Name = "RequestRewardedAd"
requestAd.Parent = ReplicatedStorage

local watching: { [Player]: boolean } = {}

requestAd.OnServerEvent:Connect(function(player)
	if watching[player] then
		return
	end
	watching[player] = true
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(REWARD_PRODUCT_ID)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	watching[player] = nil
	requestAd:FireClient(player, ok, result) -- Enum.ShowAdResult.ShowCompleted on success
end)
```

- Protect the character during the ad (lobby/safe zone or pause damage).
- Clearly label "Watch an ad to get X"; rewards can't be random.

## Commerce products (real-world goods)

Eligible creators can sell physical products (e.g. imported from Shopify) with bundled digital
benefits. Prompt with `MarketplaceService:PromptCommerceProductPurchase(player, commerceProductId)`
(a string ID); bundled developer-product benefits are granted through `ProcessReceipt`, avatar items
are granted by Roblox. Check eligibility requirements in the Commerce products docs before building.

## Premium and Roblox Plus

- `player.HasRobloxSubscription` is `true` for players with an active Roblox subscription (use it for
  subscriber perks; `Player.MembershipType` is deprecated). Engagement-based payouts reward subscriber
  playtime automatically — make perks cosmetic/convenience, never pay-to-win.
- **Roblox Plus** subscribers get 10–20% off eligible purchases (Roblox covers the discount; your
  earnings don't drop), free paid private servers (you're still compensated), and free Robux transfers.
- `MarketplaceService:PromptRobloxSubscriptionPurchase(player)` prompts a Roblox Plus sign-up and
  earns a referral payout. `PromptPremiumPurchase` is deprecated.

## US 18+ DevEx rate and age checks

Spend from age-checked 18+ US players in eligible games cashes out at $0.54 per 100 earned Robux instead
of $0.38 (passes, developer products, in-game subscriptions, private servers, and Paid Access in Robux).
Check eligibility in Creator Dashboard; nothing to switch on.

- `player.AgeChecked` (`Enum.AgeCheckStatus.Checked` / `Unchecked`, read-only, replicated) shows whether
  the player completed an age check.
- `player:PromptAgeCheck()` opens the age-check flow (non-yielding). Max one prompt per player per 15
  minutes per session; extra calls are dropped silently, so prompt on a deliberate player action, not on spawn.
- Console and VR can't complete it, and some players can't (parental consent, cooldown). Treat `Unchecked`
  as normal: gate optional rewards behind it, never core gameplay.

```luau
--!strict
local function offerAgeCheck(player: Player)
	if player.AgeChecked == Enum.AgeCheckStatus.Unchecked then
		player:PromptAgeCheck()
	end
end

return offerAgeCheck
```

## Private servers

Enable and price in Creator Dashboard. Detect with `game.PrivateServerId ~= ""` and
`game.PrivateServerOwnerId` (`VIPServerId`/`VIPServerOwnerId` are deprecated). Reserved servers
(`TeleportOptions.ReservedServerId`) also have a non-empty `PrivateServerId` but owner id `0`.
VIP servers now work in every place of the experience: keep the group together by teleporting with
`TeleportOptions.VipServerId = game.PrivateServerId` (see `roblox-teleport-matchmaking`).

## Analytics for monetization

Log currency sources/sinks with `AnalyticsService:LogEconomyEvent` and purchase funnels with
`LogFunnelStepEvent` (see `roblox-analytics-liveops`) so you can see which offers convert.
