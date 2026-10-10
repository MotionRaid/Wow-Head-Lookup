local _, ns = ...
local cache = {}

local function QuestieDB()
	if not QuestieLoader or not QuestieLoader.ImportModule then return end
	local ok, qdb = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
	if ok and qdb and qdb.QueryItemSingle and qdb.QueryNPCSingle then return qdb end
end

function ns.QuestieDrops(itemID)
	if cache[itemID] ~= nil then return cache[itemID] or nil end
	local qdb = QuestieDB()
	if not qdb then return end
	local ok, npcs = pcall(qdb.QueryItemSingle, itemID, "npcDrops")
	local list = {}
	if ok and type(npcs) == "table" then
		for _, npcID in ipairs(npcs) do
			local okName, name = pcall(qdb.QueryNPCSingle, npcID, "name")
			if okName and type(name) == "string" then list[#list + 1] = name end
		end
		table.sort(list)
	end
	cache[itemID] = #list > 0 and list or false
	return cache[itemID] or nil
end

ns.AddCommand("questie", "/wh questie  - toggle Questie drop info in tooltips", function()
	ns.db.questie = not ns.db.questie
	local status = QuestieDB() and "" or " |cff888888(Questie isn't loaded right now)|r"
	ns.Print("Questie tooltip info " .. ns.OnOff(ns.db.questie) .. "." .. status)
end)
