local _, ns = ...
local DATA_ADDON = "WowheadLookup_Data"

local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
local GetAddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local tried = false

ns.KINDS = {
	item     = { url = "item",     names = "itemNames",    info = "itemInfo",    label = "Item" },
	quest    = { url = "quest",    names = "questNames",   info = "questInfo",   label = "Quest" },
	npc      = { url = "npc",      names = "npcNames",     info = "npcInfo",     label = "NPC" },
	object   = { url = "object",   names = "objectNames",  info = "objectInfo",  label = "Object" },
	spell    = { url = "spell",    names = "spellNames",   info = "spellInfo",   label = "Spell" },
	zone     = { url = "zone",     names = "zoneNames",    info = "zoneInfo",    label = "Zone" },
	faction  = { url = "faction",  names = "factionNames", info = "factionInfo", label = "Faction" },
	itemset  = { url = "item-set", names = "setNames",     info = "setInfo",     label = "Item set" },
	achievement = { url = "achievement", label = "Achievement" },
	search   = { url = "search",   label = "" },
}

function ns.Data()
	if WowheadLookupData then return WowheadLookupData end
	if tried or not LoadAddOn then return nil end
	tried = true
	local ok, loaded = pcall(LoadAddOn, DATA_ADDON)
	if ok and loaded and WowheadLookupData then
		if ns.RefreshWindow then ns.RefreshWindow() end
		return WowheadLookupData
	end
	return nil
end

function ns.HasDataAddon()
	if WowheadLookupData then return true end
	if not GetAddOnInfo then return false end
	local name, _, _, _, reason = GetAddOnInfo(DATA_ADDON)
	return name ~= nil and reason ~= "MISSING"
end

local infoCache = {}
function ns.DataInfo(kind, id)
	local D, k = ns.Data(), ns.KINDS[kind]
	if not (D and k and k.info and D[k.info]) then return nil end
	local s = D[k.info][id]
	if not s then return nil end
	local key = kind .. id
	local t = infoCache[key]
	if not t then
		t = { strsplit("\t", s) }
		infoCache[key] = t
	end
	return t
end

function ns.DataName(kind, id)
	local D, k = ns.Data(), ns.KINDS[kind]
	return D and k and k.names and D[k.names] and D[k.names][id] or nil
end

function ns.Popularity(kind, id)
	local t = ns.DataInfo(kind, id)
	return t and tonumber(t[1]) or 0
end

function ns.DataDetail(kind, id)
	local t = ns.DataInfo(kind, id)
	if not t then return nil end
	if kind == "item" then
		local ilvl, slot = tonumber(t[3]) or 0, t[5] or ""
		return (slot ~= "" and (slot .. "  ") or "") .. (ilvl > 0 and ("ilvl " .. ilvl) or "")
	elseif kind == "quest" then
		local lvl = tonumber(t[2]) or 0
		return (lvl > 0 and ("lvl " .. lvl .. "  ") or "") .. (t[5] or "")
	elseif kind == "npc" then
		local lo, hi = tonumber(t[2]) or 0, tonumber(t[3]) or 0
		local lvl = lo > 0 and ("lvl " .. (lo == hi and lo or (lo .. "-" .. hi))) or ""
		local class = (t[4] and t[4] ~= "Normal") and (" " .. t[4]) or ""
		return lvl .. class
	elseif kind == "object" then
		return t[2]
	elseif kind == "spell" then
		return t[2]
	elseif kind == "zone" then
		local lo, hi = tonumber(t[2]) or 0, tonumber(t[3]) or 0
		return (lo > 0 and ("lvl " .. lo .. "-" .. hi .. "  ") or "") .. (t[4] or "")
	elseif kind == "faction" then
		return t[2]
	end
end

function ns.DataItemLines(id)
	local D = ns.Data()
	local s = D and D.itemLines and D.itemLines[id]
	if not s then return nil end
	local out = {}
	for line in s:gmatch("[^\n]+") do out[#out + 1] = line end
	return out
end

ns.On("PLAYER_LOGIN", function()

	C_Timer.After(5, function() ns.Data() end)
end)

ns.AddCommand("data", "/wh data  - show what the Data addon has loaded", function()
	local D = ns.Data()
	if not D then
		return ns.Print("The WowheadLookup_Data addon isn't installed or enabled.")
	end
	local parts = {}
	for _, kind in ipairs({ "item", "quest", "npc", "object", "spell", "zone", "faction", "itemset" }) do
		local t = D[ns.KINDS[kind].names]
		local n = 0
		if t then for _ in pairs(t) do n = n + 1 end end
		parts[#parts + 1] = n .. " " .. ns.KINDS[kind].label:lower() .. "s"
	end
	ns.Print("Data loaded: " .. table.concat(parts, ", ") .. ".")
end)
