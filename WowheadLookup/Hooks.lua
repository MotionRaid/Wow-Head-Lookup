local _, ns = ...

local function LookupUnit(unit)
	local id = ns.RememberUnit(unit)
	if not id then return false end
	ns.Lookup("npc", id, UnitName(unit))
	return true
end

function WowheadLookup_LookupHovered()
	local tt = GameTooltip
	if tt and tt:IsShown() then
		if tt.GetItem then
			local _, link = tt:GetItem()
			if link and ns.LookupLink(link) then return end
		end
		if tt.GetSpell then
			local name, spellID = tt:GetSpell()
			if spellID then return ns.Lookup("spell", spellID, name) end
		end
	end
	if LookupUnit("mouseover") then return end
	ns.Print("Hover an item, spell or NPC first.")
end

function WowheadLookup_LookupTarget()
	if not UnitExists("target") then return ns.Print("You have no target.") end
	if not LookupUnit("target") then ns.Print("Your target isn't an NPC.") end
end

ns.AddCommand("target", "/wh target  - look up your current target", WowheadLookup_LookupTarget)

hooksecurefunc("HandleModifiedItemClick", function(link)
	if type(link) ~= "string" then return end
	ns.RememberItemLink(link)
	if ns.AltOnly() then ns.LookupLink(link) end
end)

hooksecurefunc("SetItemRef", function(link, text)
	if not ns.AltOnly() or type(link) ~= "string" then return end

	ns.LookupLink(type(text) == "string" and text:find("|H") and text or link, true)
end)

local function LookupSelectedQuest()
	local idx = GetQuestLogSelection and GetQuestLogSelection()
	if idx and idx > 0 then
		local title, isHeader, questID = ns.QuestLogEntry(idx)
		if questID and not isHeader then return ns.LookupQuestID(questID, title) end
	end
	if C_QuestLog and C_QuestLog.GetSelectedQuest then
		local questID = C_QuestLog.GetSelectedQuest()
		if questID and questID > 0 then return ns.LookupQuestID(questID) end
	end
	return false
end

ns.AddCommand("quest", "/wh quest  - look up the quest selected in your quest log", function()
	if not LookupSelectedQuest() then ns.Print("Select a quest in your quest log first.") end
end)

local lastQuestClick = 0
local function OnQuestAltClick()
	if not ns.AltOnly() then return end
	if QuestLogFrame and QuestLogFrame.IsMouseOver and not QuestLogFrame:IsMouseOver() then return end
	if GetTime() - lastQuestClick < 0.3 then return end
	lastQuestClick = GetTime()
	C_Timer.After(0, LookupSelectedQuest)
end

local lateHooks = {
	QuestLog_SetSelection = OnQuestAltClick,

	QuestMapLogTitleButton_OnClick = function(self)
		if ns.AltOnly() and self and self.questID then ns.LookupQuestID(self.questID) end
	end,

	TradeSkillSkillButton_OnClick = function(self)
		if not ns.AltOnly() or not self or not GetTradeSkillItemLink then return end
		local link = GetTradeSkillItemLink(self:GetID())
		if link then ns.LookupLink(link) end
	end,

	CraftButton_OnClick = function(self)
		if not ns.AltOnly() or not self or not GetCraftItemLink then return end
		local link = GetCraftItemLink(self:GetID())
		if link then ns.LookupLink(link) end
	end,

	BrowseButton_OnClick = function(button)
		if not ns.AltOnly() or not button or not GetAuctionItemLink then return end
		local offset = (BrowseScrollFrame and FauxScrollFrame_GetOffset) and FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
		local link = GetAuctionItemLink("list", button:GetID() + offset)
		if link then ns.LookupLink(link) end
	end,
}
local hooked = {}

local function TryLateHooks()
	for name, fn in pairs(lateHooks) do
		if not hooked[name] and type(_G[name]) == "function" then
			hooksecurefunc(name, fn)
			hooked[name] = true
		end
	end
end

ns.On("ADDON_LOADED", TryLateHooks)
ns.On("PLAYER_LOGIN", function()
	ns.player = UnitName("player")
	TryLateHooks()
end)

local function AddUnitMenuButton(_, rootDescription, contextData)
	local unit = contextData and contextData.unit
	if not unit then return end
	local npcID = ns.NPCIDFromGUID(UnitGUID(unit))
	if not npcID then return end
	local name = UnitName(unit)
	rootDescription:CreateDivider()
	rootDescription:CreateButton("|cff33bbffWowhead|r", function()
		ns.Lookup("npc", npcID, name)
	end)
end

if Menu and Menu.ModifyMenu then
	for _, tag in ipairs({ "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_BOSS" }) do
		pcall(Menu.ModifyMenu, tag, AddUnitMenuButton)
	end
end
