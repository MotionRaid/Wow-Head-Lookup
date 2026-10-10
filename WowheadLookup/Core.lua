local ADDON_NAME, ns = ...
WowheadLookup = ns

ns.BASE = "https://www.wowhead.com/"
ns.HISTORY_MAX = 20

ns.DEFAULTS = {
	site = "forever",
	altClick = true,
	tooltip = true,
	tooltipNew = true,
	announceNew = true,
	questie = true,
	minimap = { hide = false, angle = 200 },
	filters = { kind = "all", quality = 0, myLevel = false },
	hadInit = false,

	history = {},
	items = {},
	itemMeta = {},
	scan = { active = false, build = nil, total = 0 },
	quests = {},
	npcs = {},
	drops = {},
	vendors = {},
	prices = {},
	usedIn = {},
	crafters = {},
	had = {},
}
ns.DATA_KEYS = { "history", "items", "itemMeta", "scan", "quests", "npcs", "drops", "vendors", "prices",
	"usedIn", "crafters", "had" }

BINDING_HEADER_WOWHEADLOOKUP = "Wowhead Lookup"
BINDING_NAME_WOWHEADLOOKUP_HOVER = "Look up hovered item / spell / NPC"
BINDING_NAME_WOWHEADLOOKUP_TARGET = "Look up current target"
BINDING_NAME_WOWHEADLOOKUP_WINDOW = "Open search window"

ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
ns.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
ns.GetContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

function ns.NumQuestLogEntries()
	if GetNumQuestLogEntries then return (GetNumQuestLogEntries()) end
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
	return 0
end

function ns.QuestLogEntry(i)
	if GetQuestLogTitle then
		local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
		return title, isHeader, questID
	end
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(i)
		if info then return info.title, info.isHeader, info.questID end
	end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffWowhead Lookup:|r " .. msg)
end

local function SitePrefix()
	local site = ns.db and ns.db.site or ns.DEFAULTS.site
	return (site and site ~= "") and (site .. "/") or ""
end

function ns.BuildURL(kind, id)
	local k = ns.KINDS and ns.KINDS[kind]
	if k and k.build then return k.build(id) end
	return ns.BASE .. SitePrefix() .. (k and k.url or kind) .. "=" .. id
end

local function URLEncode(s)
	s = s:gsub("([^%w%-_%.~ ])", function(c) return string.format("%%%02X", c:byte()) end)
	return (s:gsub(" ", "+"))
end

function ns.SearchURL(text)
	return ns.BASE .. SitePrefix() .. "search?q=" .. URLEncode(text)
end

function ns.ItemIDFromLink(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function ns.NPCIDFromGUID(guid)
	if not guid then return end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then return tonumber(id) end
end

function ns.RememberItemLink(link)
	local db = ns.db
	if not (db and type(link) == "string") then return end
	local id = ns.ItemIDFromLink(link)
	local name = link:match("%[(.-)%]")
	if id and name and name ~= "" then db.items[id] = name end
	return id
end

function ns.RememberUnit(unit)
	local db = ns.db
	if not db then return end
	local id = ns.NPCIDFromGUID(UnitGUID(unit))
	if id then
		local name = UnitName(unit)
		if name and name ~= "" and name ~= UNKNOWNOBJECT then db.npcs[id] = name end
	end
	return id
end

function ns.ItemName(id)
	local name = ns.db and ns.db.items[id]
	if name then return name end
	name = ns.GetItemInfo(id)
	return name or (ns.DataName and ns.DataName("item", id))
end

function ns.NPCName(id)
	return (ns.db and ns.db.npcs[id]) or (ns.DataName and ns.DataName("npc", id)) or ("NPC #" .. id)
end

function ns.ItemQualityLevel(id)
	local info = ns.DataInfo and ns.DataInfo("item", id)
	if info then return tonumber(info[2]), tonumber(info[4]) end
	local meta = ns.db and ns.db.itemMeta[id]
	if meta then return math.floor(meta / 1000), meta % 1000 end
	local _, _, quality, _, minLevel = ns.GetItemInfo(id)
	return quality, minLevel
end

function ns.ItemColorHex(id)
	local quality = ns.ItemQualityLevel(id)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return c and c.hex or "|cffffffff"
end

function ns.Coins(copper)
	copper = math.floor(copper + 0.5)
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. c .. "c"
end

function ns.Ago(t)
	local d = time() - (t or 0)
	if d < 3600 then return math.max(1, math.floor(d / 60)) .. "m ago" end
	if d < 86400 then return math.floor(d / 3600) .. "h ago" end
	return math.floor(d / 86400) .. "d ago"
end

function ns.ShortList(list, max)
	max = max or 3
	local out = {}
	for i = 1, math.min(max, #list) do out[i] = list[i] end
	local s = table.concat(out, ", ")
	if #list > max then s = s .. " +" .. (#list - max) .. " more" end
	return s
end

function ns.AltOnly()
	return ns.db and ns.db.altClick and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()
end

local function GetPopupEditBox(dialog)
	return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

function ns.ShareInChat(entry)
	if not entry then return ns.Print("Nothing to share yet.") end
	local text = (entry.link or entry.name or "") .. " " .. entry.url
	local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	if eb then
		eb:Insert(text)
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat(text)
	end
end

StaticPopupDialogs["WOWHEADLOOKUP_URL"] = {
	text = "%s\n|cff999999Press Ctrl+C to copy, then paste into your browser.|r",
	button1 = "Share in chat",
	button2 = CLOSE or "Close",
	hasEditBox = true,
	editBoxWidth = 360,
	maxLetters = 1024,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(_, data) ns.ShareInChat(data) end,
	OnShow = function(self, data)
		local eb = GetPopupEditBox(self)
		if eb and data then
			eb:SetText(data.url)
			eb:HighlightText()
			eb:SetFocus()
		end
	end,

	EditBoxOnTextChanged = function(self, data)
		if data and self:GetText() ~= data.url then
			self:SetText(data.url)
			self:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function AddHistory(entry)
	local h = ns.db and ns.db.history
	if not h then return end
	for i = #h, 1, -1 do
		if h[i].url == entry.url then table.remove(h, i) end
	end
	table.insert(h, 1, { kind = entry.kind, id = entry.id, name = entry.name, url = entry.url })
	while #h > ns.HISTORY_MAX do table.remove(h) end
end

local lastURL, lastTime = nil, 0

function ns.Lookup(kind, id, name, link)
	local url = (kind == "search") and ns.SearchURL(id) or ns.BuildURL(kind, id)

	if url == lastURL and GetTime() - lastTime < 0.4 then return end
	lastURL, lastTime = url, GetTime()

	name = name or (kind == "search" and id) or (ns.DataName and ns.DataName(kind, id))
		or (kind:gsub("^%l", string.upper) .. " " .. id)
	local entry = { kind = kind, id = id, name = name, url = url, link = link }
	AddHistory(entry)
	ns.lastEntry = entry

	local title = link or name
	if kind == "search" then title = "Search: " .. name end
	StaticPopup_Hide("WOWHEADLOOKUP_URL")
	StaticPopup_Show("WOWHEADLOOKUP_URL", title, nil, entry)
	if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.ShowEntry(e)
	if not e then return end
	local link
	if e.kind == "item" then link = select(2, ns.GetItemInfo(e.id)) end
	lastURL = nil
	ns.Lookup(e.kind, e.id, e.name, link)
end

function ns.LookupQuestID(id, name)
	id = tonumber(id)
	if not id or id <= 0 then return false end
	if name and ns.db then ns.db.quests[id] = name end
	ns.Lookup("quest", id, name or (ns.db and ns.db.quests[id]))
	return true
end

function ns.LookupLink(link, skipItems)
	if type(link) ~= "string" then return false end
	local kind, id = link:match("|H(%a+):(%d+)")
	if not kind then kind, id = link:match("^(%a+):(%d+)") end
	if not kind then return false end
	local name = link:match("%[(.-)%]")
	local isLink = link:find("|H") and link or nil
	if kind == "item" then
		if skipItems then return false end
		ns.RememberItemLink(link)
		ns.Lookup("item", tonumber(id), name or ns.ItemName(tonumber(id)), isLink)
	elseif kind == "quest" then
		ns.LookupQuestID(id, name)
	elseif kind == "spell" or kind == "enchant" then
		ns.Lookup("spell", tonumber(id), name, isLink)
	elseif kind == "achievement" then
		ns.Lookup("achievement", tonumber(id), name, isLink)
	else
		return false
	end
	return true
end

local eventFrame = CreateFrame("Frame")
local handlers = {}
local initFns = {}

function ns.On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	list[#list + 1] = fn
end

function ns.OnInit(fn) initFns[#initFns + 1] = fn end

eventFrame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5, a6)
	if event ~= "ADDON_LOADED" and not ns.db then return end
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do

		xpcall(function() fn(a1, a2, a3, a4, a5, a6) end, geterrorhandler())
	end
end)

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME then return end
	WowheadLookupDB = WowheadLookupDB or {}
	CopyDefaults(ns.DEFAULTS, WowheadLookupDB)
	ns.db = WowheadLookupDB
	ns.player = UnitName("player")

	local h = ns.db.history
	for i = #h, 1, -1 do
		local k = h[i].kind
		if k == "armory" or k == "raiderio" or k == "logs" then table.remove(h, i) end
	end
	ns.db.profileURLs = nil
	ns.db.guild, ns.db.shared, ns.db.recent = nil, nil, nil
	for _, fn in ipairs(initFns) do xpcall(fn, geterrorhandler()) end
end)

local commands, commandOrder = {}, {}

function ns.AddCommand(name, usage, fn)
	commands[name] = fn
	commandOrder[#commandOrder + 1] = usage
end

function ns.OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

local function Toggle(key, label)
	return function()
		ns.db[key] = not ns.db[key]
		ns.Print(label .. " " .. ns.OnOff(ns.db[key]) .. ".")
	end
end

ns.AddCommand("help", "/wh help  - this list", function()
	ns.Print("Commands:")
	ns.Print("  /wh  - open the search window (recent lookups when empty)")
	ns.Print("  /wh <item link | item ID | name>  - look something up")
	for _, usage in ipairs(commandOrder) do ns.Print("  " .. usage) end
	ns.Print("Keybinds: Esc > Key Bindings > AddOns > Wowhead Lookup")
end)

ns.AddCommand("share", "/wh share  - put your last lookup's link in the chat box", function()
	ns.ShareInChat(ns.lastEntry or (ns.db.history[1]))
end)
ns.AddCommand("tooltip", "/wh tooltip  - toggle extra tooltip lines", Toggle("tooltip", "Tooltip lines"))
ns.AddCommand("new", "/wh new  - toggle \"New\" tooltip line and first-time loot message", function()
	ns.db.tooltipNew = not ns.db.tooltipNew
	ns.db.announceNew = ns.db.tooltipNew
	ns.Print("New-item notices " .. ns.OnOff(ns.db.tooltipNew) .. ".")
end)
ns.AddCommand("altclick", "/wh altclick  - toggle Alt-click lookups", Toggle("altClick", "Alt-click lookups"))
ns.AddCommand("site", "/wh site <forever|classic|retail>  - which Wowhead section to link", function(rest)
	local site = strtrim(rest or ""):lower()
	if site == "retail" then site = "" end
	ns.db.site = site
	ns.Print("Links now look like: " .. ns.BuildURL("item", "123"))
end)
ns.AddCommand("forget", "/wh forget  - clear history and everything recorded", function()
	for _, k in ipairs(ns.DATA_KEYS) do ns.db[k] = nil end
	ns.db.hadInit = false
	CopyDefaults(ns.DEFAULTS, ns.db)
	if ns.RefreshWindow then ns.RefreshWindow() end
	ns.Print("History and recorded data cleared.")
end)

SLASH_WOWHEADLOOKUP1 = "/wh"
SLASH_WOWHEADLOOKUP2 = "/wowhead"
SlashCmdList.WOWHEADLOOKUP = function(msg)
	if not ns.db then return end
	msg = strtrim(msg or "")
	if msg == "" then return WowheadLookup_ToggleWindow() end

	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	local fn = cmd and commands[cmd:lower()]
	if fn then return fn(rest) end

	if msg:find("|H") and ns.LookupLink(msg) then return end

	local id = tonumber(msg)
	if id then return ns.Lookup("item", id, ns.ItemName(id)) end

	local _, link = ns.GetItemInfo(msg)
	if link and ns.LookupLink(link) then return end
	WowheadLookup_ToggleWindow(msg)
end
