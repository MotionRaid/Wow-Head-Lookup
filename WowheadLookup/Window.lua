local _, ns = ...
local MAX_ROWS = 12
local ROW_TOP = -112

local Window

local ICONS = {
	quest = "Interface\\GossipFrame\\AvailableQuestIcon",
	npc = "Interface\\Icons\\INV_Misc_Head_Human_01",
	object = "Interface\\Icons\\INV_Box_01",
	spell = "Interface\\Icons\\INV_Misc_Book_09",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
	faction = "Interface\\Icons\\INV_BannerPVP_02",
	itemset = "Interface\\Icons\\INV_Chest_Chain_05",
	achievement = "Interface\\Icons\\INV_Misc_Book_09",
	search = "Interface\\Icons\\INV_Misc_Spyglass_03",
}
local TABS = { { "all", "All" }, { "item", "Items" }, { "quest", "Quests" }, { "npc", "NPCs" },
	{ "spell", "Spells" }, { "other", "Other" } }
local OTHER = { object = true, zone = true, faction = true, itemset = true, achievement = true }

local POOLS = {
	{ kind = "item", seen = "items" }, { kind = "quest", seen = "quests" }, { kind = "npc", seen = "npcs" },
	{ kind = "object" }, { kind = "spell" }, { kind = "zone" }, { kind = "faction" }, { kind = "itemset" },
}
local QUALITY_STEPS = {
	{ 0, "Any quality" },
	{ 2, "|cff1eff00Uncommon+|r" },
	{ 3, "|cff0070ddRare+|r" },
	{ 4, "|cffa335eeEpic+|r" },
}
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

local function EntryIcon(e)
	if e.kind == "item" then
		return (ns.GetItemIcon and ns.GetItemIcon(e.id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
	elseif e.kind == "spell" and GetSpellTexture then
		local tex = GetSpellTexture(e.id)
		if tex then return tex end
	end
	return ICONS[e.kind] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function EntryText(e)
	if e.kind == "item" then return ns.ItemColorHex(e.id) .. (e.name or ("Item " .. e.id)) .. "|r" end
	if e.kind == "quest" then return "|cffffd100" .. (e.name or "") .. "|r" end
	if e.kind == "search" then return "|cff33bbffSearch Wowhead for \"" .. e.name .. "\"|r" end
	return e.name or ""
end

local function KindLabel(kind)
	local k = ns.KINDS and ns.KINDS[kind]
	return k and k.label or kind
end

local function KindAllowed(kind)
	local f = ns.db.filters.kind
	if f == "all" or kind == "search" then return true end
	if f == "other" then return OTHER[kind] or false end
	return kind == f
end

local function Passes(e)
	local f = ns.db.filters
	if not KindAllowed(e.kind) then return false end
	if e.kind == "item" and (f.quality > 0 or f.myLevel) then
		local quality, minLevel = ns.ItemQualityLevel(e.id)

		if quality and quality < f.quality then return false end
		if f.myLevel and minLevel and minLevel > UnitLevel("player") then return false end
	elseif f.quality > 0 and e.kind ~= "item" and e.kind ~= "search" then
		return false
	end
	return true
end

local lowerCache = {}
local function Lower(name)
	local l = lowerCache[name]
	if not l then l = name:lower(); lowerCache[name] = l end
	return l
end

local function PopOf(D, kind, id)
	local k = ns.KINDS[kind]
	local s = D and k.info and D[k.info] and D[k.info][id]
	return s and tonumber(s:match("^%d+")) or 0
end

local function Search(text)
	local db, q = ns.db, text:lower()
	local D = ns.Data and ns.Data()
	local found = {}

	local function Consider(kind, id, name, fromData)
		local s = Lower(name):find(q, 1, true)
		if not s then return end

		local pop = fromData and PopOf(D, kind, id) or 0
		found[#found + 1] = { kind = kind, id = id, name = name,
			key = (s == 1 and 0 or 1e9) - pop * 1000 + #name }
	end

	for _, pool in ipairs(POOLS) do
		local kind = pool.kind
		if KindAllowed(kind) then
			local k = ns.KINDS[kind]
			local data = D and #q >= 2 and k.names and D[k.names] or nil
			if data then
				for id, name in pairs(data) do Consider(kind, id, name, true) end
			end
			local seen = pool.seen and db[pool.seen]
			if seen then
				for id, name in pairs(seen) do
					if not (data and data[id]) then Consider(kind, id, name, false) end
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.key < b.key end)

	local results, used = {}, {}
	for _, e in ipairs(found) do

		local base = e.kind == "spell" and Lower(e.name):gsub(" %(rank %d+%)$", "") or Lower(e.name)
		local dedupe = e.kind .. ":" .. base
		if not used[dedupe] and Passes(e) then
			used[dedupe] = true
			results[#results + 1] = e
			if #results >= MAX_ROWS - 1 then break end
		end
	end
	results[#results + 1] = { kind = "search", id = text, name = text }
	return results
end

local function ActivateEntry(e)
	if not e then return end
	if e.kind == "item" and IsShiftKeyDown() then
		local _, link = ns.GetItemInfo(e.id)
		if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
		return
	end
	ns.ShowEntry(e)
end

local function SmallButton(parent, width, text)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	local fs = b:GetFontString()
	if fs then fs:SetFontObject("GameFontHighlightSmall") end
	return b
end

local function UpdateFilterButtons()
	local f = ns.db.filters
	for _, tab in ipairs(Window.tabs) do
		if tab.kind == f.kind then tab:LockHighlight() else tab:UnlockHighlight() end
	end
	for _, step in ipairs(QUALITY_STEPS) do
		if step[1] == f.quality then Window.quality:SetText(step[2]) end
	end
	Window.myLevel:SetChecked(f.myLevel)
end

local function CreateWindow()
	local f = CreateFrame("Frame", "WowheadLookupFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(380, -ROW_TOP + MAX_ROWS * 22 + 30)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "WowheadLookupFrame")

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Wowhead Lookup")

	local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	eb:SetSize(334, 22)
	eb:SetPoint("TOPLEFT", 24, -32)
	eb:SetAutoFocus(false)
	f.editBox = eb

	local placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	placeholder:SetPoint("LEFT", 2, 0)
	placeholder:SetText("Item, quest or NPC name...")

	f.tabs = {}
	for i, t in ipairs(TABS) do
		local b = SmallButton(f, 56, t[2])
		b:SetPoint("TOPLEFT", 14 + (i - 1) * 59, -58)
		b.kind = t[1]
		b:SetScript("OnClick", function(self)
			ns.db.filters.kind = self.kind
			UpdateFilterButtons()
			ns.RefreshWindow()
		end)
		f.tabs[i] = b
	end

	local quality = SmallButton(f, 110, "Any quality")
	quality:SetPoint("TOPLEFT", 16, -80)
	quality:SetScript("OnClick", function()
		local fl = ns.db.filters
		for i, step in ipairs(QUALITY_STEPS) do
			if step[1] == fl.quality then
				fl.quality = QUALITY_STEPS[(i % #QUALITY_STEPS) + 1][1]
				break
			end
		end
		UpdateFilterButtons()
		ns.RefreshWindow()
	end)
	f.quality = quality

	local myLevel = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	myLevel:SetSize(22, 22)
	myLevel:SetPoint("LEFT", quality, "RIGHT", 10, 0)
	myLevel:SetScript("OnClick", function(self)
		ns.db.filters.myLevel = self:GetChecked() and true or false
		ns.RefreshWindow()
	end)
	local myLevelText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	myLevelText:SetPoint("LEFT", myLevel, "RIGHT", 2, 0)
	myLevelText:SetText("Usable at my level")
	f.myLevel = myLevel

	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 18, ROW_TOP + 10)
	f.header = header

	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", 22, ROW_TOP - 4)
	empty:SetWidth(330)
	empty:SetJustifyH("LEFT")
	f.empty = empty

	local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOM", 0, 10)
	f.footer = footer

	f.rows = {}
	for i = 1, MAX_ROWS do
		local r = CreateFrame("Button", nil, f)
		r:SetSize(340, 20)
		r:SetPoint("TOPLEFT", 18, ROW_TOP - 4 - (i - 1) * 22)
		r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 2, 0)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.text:SetWidth(200)
		r.text:SetWordWrap(false)
		r.kind = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.kind:SetPoint("RIGHT", -4, 0)
		r.kind:SetWidth(112)
		r.kind:SetJustifyH("RIGHT")
		r.kind:SetWordWrap(false)
		r:SetScript("OnClick", function(self) ActivateEntry(self.entry) end)
		r:SetScript("OnEnter", function(self)
			local e = self.entry
			if not e or e.kind == "search" then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if e.kind == "item" then
				GameTooltip:SetHyperlink("item:" .. e.id)
			else
				GameTooltip:AddLine(e.name)
				GameTooltip:AddLine(KindLabel(e.kind) .. "  |cff888888#" .. e.id .. "|r", 0.6, 0.6, 0.6)
				local detail = ns.DataDetail and ns.DataDetail(e.kind, e.id)
				if detail and detail ~= "" then GameTooltip:AddLine(detail, 1, 1, 1, true) end
			end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = r
	end

	local pending = 0
	eb:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		pending = pending + 1
		local mine = pending
		C_Timer.After(0.15, function() if mine == pending then ns.RefreshWindow() end end)
	end)
	eb:SetScript("OnEnterPressed", function()
		local first = f.rows[1]
		if first:IsShown() then ActivateEntry(first.entry) end
	end)
	eb:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else f:Hide() end
	end)
	f:SetScript("OnShow", function()
		UpdateFilterButtons()
		ns.RefreshWindow()
	end)

	return f
end

local HINT = "Click: Wowhead link   Shift-click item: link in chat"

function ns.UpdateFooter()
	if not (Window and Window:IsShown()) then return end
	Window.footer:SetText(ns.ScanStatus and ns.ScanStatus() or HINT)
end

function ns.RefreshWindow()
	if not (Window and Window:IsShown() and ns.db) then return end
	ns.UpdateFooter()
	local text = strtrim(Window.editBox:GetText() or "")
	local list
	if text == "" then
		Window.header:SetText("Recent lookups")
		list = {}
		for _, e in ipairs(ns.db.history) do
			if Passes(e) then list[#list + 1] = e end
		end
		Window.empty:SetText(#list == 0 and "Nothing here yet. Alt-click an item, or type a name above." or "")
	else
		local full = WowheadLookupData or ns.db.scan.build
		Window.header:SetText(full and "Matches" or "Matches from things you've seen  |cff888888(/wh scan for all items)|r")
		list = Search(text)
		Window.empty:SetText("")
	end
	for i, r in ipairs(Window.rows) do
		local e = list[i]
		r.entry = e
		if e then
			r.icon:SetTexture(EntryIcon(e))
			r.text:SetText(EntryText(e))
			local detail = ns.DataDetail and ns.DataDetail(e.kind, e.id)
			r.kind:SetText(e.kind == "search" and "" or ((detail and detail ~= "") and detail or KindLabel(e.kind)))
			r:Show()
		else
			r:Hide()
		end
	end
end

function WowheadLookup_ToggleWindow(text)
	if not ns.db then return end
	Window = Window or CreateWindow()
	if text then
		Window:Show()
		Window.editBox:SetText(text)
		Window.editBox:SetFocus()
		return
	end
	if Window:IsShown() then
		Window:Hide()
	else
		Window:Show()
		Window.editBox:SetFocus()
	end
end

ns.AddCommand("history", "/wh history  - recent lookups", function() WowheadLookup_ToggleWindow("") end)
