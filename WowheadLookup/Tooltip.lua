local _, ns = ...

local GREY = { 0.85, 0.85, 0.85 }

local function NPCName(id) return ns.NPCName(id) end

local DATA_COLORS = {
	["Source"] = { 0.85, 0.85, 0.85 }, ["Quest reward"] = { 1, 0.82, 0 },
	["Created by"] = { 0.6, 0.85, 1 }, ["Used to make"] = { 0.6, 0.85, 1 },
	["Part of set"] = { 1, 1, 0.6 },
}

local function Line(tt, text, color, r, g, b)
	color = color or GREY
	tt:AddLine(text, r or color[1], g or color[2], b or color[3], true)
end

local function DropList(map)
	local list = {}
	for npcID, n in pairs(map) do list[#list + 1] = { name = NPCName(npcID), n = n } end
	table.sort(list, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.name < b.name
	end)
	local out = {}
	for i, e in ipairs(list) do out[i] = e.name .. " (" .. e.n .. ")" end
	return out
end

local function NameSet(...)
	local seen, out = {}, {}
	for i = 1, select("#", ...) do
		local map = select(i, ...)
		if map then
			for npcID in pairs(map) do
				local n = NPCName(npcID)
				if not seen[n] then seen[n] = true; out[#out + 1] = n end
			end
		end
	end
	table.sort(out)
	return out
end

local function AddItemLines(tt, id)
	local db = ns.db
	if not (db and db.tooltip and id and tt and tt.AddLine) then return end
	if tt.whlHooked then
		if tt.whlAdded == id then return end
		tt.whlAdded = id
	end

	if db.tooltipNew and db.hadInit and not db.had[id] then
		Line(tt, "New: you've never had this item", nil, 0.25, 1, 0.25)
	end

	local name = ns.ItemName(id)
	local needs = name and ns.questNeeds[name:lower()]
	if needs then
		for _, n in ipairs(needs) do
			local progress = n.done and "|cff40ff40done|r" or (n.have .. "/" .. n.need)
			Line(tt, "Needed for: " .. n.quest .. " (" .. progress .. ")", nil, 1, 0.82, 0)
		end
	end

	local price = db.prices[id]
	if price then
		Line(tt, "AH: " .. ns.Coins(price.p) .. " each |cff888888(" .. ns.Ago(price.t) .. ")|r", nil, 1, 1, 1)
	end

	local dataLines = ns.DataItemLines and ns.DataItemLines(id)
	local dataHas = {}
	if dataLines then
		for _, text in ipairs(dataLines) do
			local label = text:match("^(.-):")
			dataHas[label or ""] = true
			Line(tt, text, DATA_COLORS[label])
		end
	end

	if db.drops[id] and next(db.drops[id]) then
		Line(tt, "You looted this from: " .. ns.ShortList(DropList(db.drops[id])))
	end
	if ns.QuestieDrops and db.questie and not (db.drops[id] or dataHas["Source"]) then
		local list = ns.QuestieDrops(id)
		if list and #list > 0 then Line(tt, "Drops from (Questie): " .. ns.ShortList(list)) end
	end
	local vendors = NameSet(db.vendors[id])
	if #vendors > 0 then Line(tt, "Sold by: " .. ns.ShortList(vendors)) end

	local uses = db.usedIn[id]
	if uses and not dataHas["Used to make"] then
		local list = {}
		for product, prof in pairs(uses) do list[#list + 1] = product .. " |cff888888(" .. prof .. ")|r" end
		table.sort(list)
		Line(tt, "Used to make: " .. ns.ShortList(list), nil, 0.6, 0.85, 1)
	end
	local crafters = db.crafters[id]
	if crafters then
		local list = {}
		for who, prof in pairs(crafters) do list[#list + 1] = who .. " (" .. prof .. ")" end
		table.sort(list)
		Line(tt, "Your characters who can make this: " .. ns.ShortList(list), nil, 0.6, 0.85, 1)
	end

	local hint = db.altClick and "Alt-click for Wowhead  " or "Wowhead  "
	tt:AddLine(hint .. "|cff888888(ID " .. id .. ")|r", 0.2, 0.73, 1)
	return true
end

ns.OnInit(function()
	local usesProcessor = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
		and Enum and Enum.TooltipDataType
	if usesProcessor then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
			local id = data and data.id
			if tt.GetItem then
				local _, link = tt:GetItem()
				id = ns.RememberItemLink(link) or id
			end
			AddItemLines(tt, id)
		end)
	end
	for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
		local tt = _G[name]
		if tt then
			tt.whlHooked = true
			tt:HookScript("OnTooltipCleared", function(self) self.whlAdded = nil end)
			if not usesProcessor and tt:HasScript("OnTooltipSetItem") then
				tt:HookScript("OnTooltipSetItem", function(self)
					local _, link = self:GetItem()
					if AddItemLines(self, ns.RememberItemLink(link)) then self:Show() end
				end)
			end
		end
	end
end)
