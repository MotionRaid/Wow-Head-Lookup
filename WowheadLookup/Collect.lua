local _, ns = ...

function ns.RecordDrop(itemID, npcID)
	local d = ns.db.drops
	d[itemID] = d[itemID] or {}
	d[itemID][npcID] = (d[itemID][npcID] or 0) + 1
end

function ns.RecordVendor(itemID, npcID)
	local v = ns.db.vendors
	v[itemID] = v[itemID] or {}
	v[itemID][npcID] = true
end

function ns.RecordPrice(itemID, unit, t)
	if not (itemID and unit and unit > 0) then return end
	t = t or time()
	local p = ns.db.prices
	local e = p[itemID]
	if e and e.t > t + 3600 then return end
	if not e or t > e.t + 3600 then
		p[itemID] = { p = unit, t = t }
	elseif unit < e.p then
		e.p, e.t = unit, math.max(e.t, t)
	end
end

local function MarkHad(link, announce)
	local id = ns.RememberItemLink(link)
	if not id then return end
	local db = ns.db
	if announce and db.hadInit and db.announceNew and not db.had[id] then
		ns.Print("New item: " .. link .. " |cff888888(Alt-click it for Wowhead)|r")
	end
	db.had[id] = true
end

local function ScanBag(bag, announce)
	local slots = ns.GetContainerNumSlots and ns.GetContainerNumSlots(bag) or 0
	for slot = 1, slots do MarkHad(ns.GetContainerItemLink(bag, slot), announce) end
end

local function ScanBags()
	for bag = 0, (NUM_BAG_SLOTS or 4) do ScanBag(bag, true) end
	for slot = 1, 19 do MarkHad(GetInventoryItemLink("player", slot), false) end
	ns.db.hadInit = true
end

local function ScanBank()
	ScanBag(BANK_CONTAINER or -1, false)
	local first = (NUM_BAG_SLOTS or 4) + 1
	for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do ScanBag(bag, false) end
end

ns.On("PLAYER_LOGIN", ScanBags)
ns.On("BAG_UPDATE_DELAYED", ScanBags)
ns.On("BANKFRAME_OPENED", ScanBank)

ns.questNeeds = {}

local function AddNeed(questTitle, text, finished)
	if type(text) ~= "string" then return end
	local item, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
	if not item then return end
	local key = item:lower()
	ns.questNeeds[key] = ns.questNeeds[key] or {}
	table.insert(ns.questNeeds[key], {
		quest = questTitle, have = tonumber(have), need = tonumber(need), done = finished,
	})
end

local function ScanQuestLog()
	wipe(ns.questNeeds)
	for i = 1, ns.NumQuestLogEntries() do
		local title, isHeader, questID = ns.QuestLogEntry(i)
		if title and not isHeader then
			if questID and questID > 0 then ns.db.quests[questID] = title end
			if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
				for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
					local text, kind, finished = GetQuestLogLeaderBoard(j, i)
					if kind == "item" then AddNeed(title, text, finished) end
				end
			elseif C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
				for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
					if o.type == "item" then AddNeed(title, o.text, o.finished) end
				end
			end
		end
	end
end

ns.On("PLAYER_LOGIN", ScanQuestLog)
ns.On("QUEST_LOG_UPDATE", ScanQuestLog)

ns.On("PLAYER_TARGET_CHANGED", function() ns.RememberUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.RememberUnit("mouseover") end)

local lootCounted = {}
ns.On("LOOT_OPENED", function()
	local targetGUID = UnitGUID("target")
	ns.RememberUnit("target")
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local id = ns.RememberItemLink(GetLootSlotLink(slot))
		if id then
			local sources = {}
			if GetLootSourceInfo then
				local info = { GetLootSourceInfo(slot) }
				for i = 1, #info, 2 do sources[#sources + 1] = info[i] end
			end
			if #sources == 0 and targetGUID then sources[1] = targetGUID end
			for _, guid in ipairs(sources) do
				local npcID = ns.NPCIDFromGUID(guid)
				local key = guid .. ":" .. id
				if npcID and not lootCounted[key] then
					lootCounted[key] = true
					ns.RecordDrop(id, npcID)
				end
			end
		end
	end
end)

local function ScanMerchant()
	local npcID = ns.RememberUnit("npc")
	if not npcID or not GetMerchantNumItems then return end
	for i = 1, GetMerchantNumItems() do
		local id = ns.RememberItemLink(GetMerchantItemLink(i))
		if id then ns.RecordVendor(id, npcID) end
	end
end
ns.On("MERCHANT_SHOW", ScanMerchant)
ns.On("MERCHANT_UPDATE", ScanMerchant)

local function ScanChat(msg)
	if type(msg) ~= "string" then return end
	pcall(function()
		for link in msg:gmatch("|Hitem:[^|]+|h%[.-%]|h") do ns.RememberItemLink(link) end
		for id, name in msg:gmatch("|Hquest:(%d+)[^|]*|h%[(.-)%]|h") do ns.db.quests[tonumber(id)] = name end
	end)
end
for _, e in ipairs({
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS",
}) do ns.On(e, ScanChat) end

local function AddUse(reagentLink, productName, prof)
	local rid = ns.RememberItemLink(reagentLink)
	if not (rid and productName) then return end
	local u = ns.db.usedIn
	u[rid] = u[rid] or {}
	u[rid][productName] = prof
end

local function AddCrafter(productLink, prof)
	local pid = ns.RememberItemLink(productLink)
	if not (pid and ns.player) then return end
	local c = ns.db.crafters
	c[pid] = c[pid] or {}
	c[pid][ns.player] = prof
end

local function ScanTradeSkill()
	if not (GetNumTradeSkills and GetTradeSkillInfo) then return end
	local prof = GetTradeSkillLine and GetTradeSkillLine()
	if not prof or prof == "UNKNOWN" then return end
	for i = 1, GetNumTradeSkills() do
		local name, kind = GetTradeSkillInfo(i)
		if name and kind ~= "header" and kind ~= "subheader" then
			AddCrafter(GetTradeSkillItemLink(i), prof)
			for r = 1, (GetTradeSkillNumReagents(i) or 0) do
				AddUse(GetTradeSkillReagentItemLink(i, r), name, prof)
			end
		end
	end
end

local function ScanCraft()
	if not (GetNumCrafts and GetCraftInfo) then return end
	local prof = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or "Enchanting"
	for i = 1, GetNumCrafts() do
		local name, _, kind = GetCraftInfo(i)
		if name and kind ~= "header" then
			for r = 1, (GetCraftNumReagents(i) or 0) do
				AddUse(GetCraftReagentItemLink(i, r), name, prof)
			end
		end
	end
end

local pending = {}
local function Debounced(fn)
	return function()
		if pending[fn] then return end
		pending[fn] = true
		C_Timer.After(0.5, function() pending[fn] = nil; fn() end)
	end
end
ns.On("TRADE_SKILL_SHOW", Debounced(ScanTradeSkill))
ns.On("TRADE_SKILL_UPDATE", Debounced(ScanTradeSkill))
ns.On("CRAFT_SHOW", Debounced(ScanCraft))
ns.On("CRAFT_UPDATE", Debounced(ScanCraft))

ns.On("AUCTION_ITEM_LIST_UPDATE", function()
	if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
	local now, mins = time(), {}
	for i = 1, (GetNumAuctionItems("list") or 0) do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
		local link = GetAuctionItemLink and GetAuctionItemLink("list", i)
		itemID = itemID or ns.ItemIDFromLink(link)
		ns.RememberItemLink(link)
		if itemID and buyout and buyout > 0 and count and count > 0 then
			local unit = buyout / count
			if not mins[itemID] or unit < mins[itemID] then mins[itemID] = unit end
		end
	end
	for id, unit in pairs(mins) do ns.RecordPrice(id, unit, now) end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
	for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		if r.itemKey and r.minPrice then ns.RecordPrice(r.itemKey.itemID, r.minPrice) end
	end
end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	local r = C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultInfo
		and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
	if r and r.unitPrice then ns.RecordPrice(itemID, r.unitPrice) end
end)
