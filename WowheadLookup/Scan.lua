local _, ns = ...

local MAX_ID = 300000
local IDS_PER_TICK = 4000
local TICK = 0.1
local REQUESTS_PER_TICK = 3
local MAX_IN_FLIGHT = 30
local TIMEOUT = 15

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestItem = C_Item and C_Item.RequestLoadItemDataByID

local state
local ticker

local function Build()
	local _, build = GetBuildInfo()
	return build
end

local function Store(id)
	local name, _, quality, _, minLevel = ns.GetItemInfo(id)
	if not name then return false end
	ns.db.items[id] = name
	ns.db.itemMeta[id] = (quality or 0) * 1000 + math.min(minLevel or 0, 999)
	return true
end

local function Finish()
	local db = ns.db
	db.scan.active = false
	db.scan.build = Build()
	db.scan.total = #state.ids
	ns.Print(("Item scan done: %d items. %s"):format(#state.ids,
		state.failed > 0 and ("|cff888888(" .. state.failed .. " didn't load; /wh scan again later to retry)|r") or ""))
	ticker:Cancel()
	ticker, state = nil, nil
	if ns.RefreshWindow then ns.RefreshWindow() end
end

local function Tick()
	if not state then return end
	if InCombatLockdown() then
		state.paused = true
		if ns.UpdateFooter then ns.UpdateFooter() end
		return
	end
	state.paused = false

	if state.step == 1 then
		local stop = math.min(state.pos + IDS_PER_TICK, MAX_ID)
		for id = state.pos + 1, stop do
			if GetItemInfoInstant(id) then state.ids[#state.ids + 1] = id end
		end
		state.pos = stop
		if stop >= MAX_ID then state.step, state.pos = 2, 0 end
	else
		local now = GetTime()
		for id, t in pairs(state.pending) do
			if now - t > TIMEOUT then
				state.pending[id] = nil
				state.inFlight = state.inFlight - 1
				state.failed = state.failed + 1
			end
		end
		local sent, skipped = 0, 0
		while sent < REQUESTS_PER_TICK and state.inFlight < MAX_IN_FLIGHT and skipped < 5000
			and state.pos < #state.ids do
			state.pos = state.pos + 1
			local id = state.ids[state.pos]
			if ns.db.items[id] and ns.db.itemMeta[id] then
				skipped = skipped + 1
			elseif Store(id) then
				skipped = skipped + 1
			else
				state.pending[id] = now
				state.inFlight = state.inFlight + 1
				sent = sent + 1
				if RequestItem then RequestItem(id) end
			end
		end
		if state.pos >= #state.ids and state.inFlight == 0 then return Finish() end
	end
	if ns.UpdateFooter then ns.UpdateFooter() end
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id, success)
	if not (state and state.pending[id]) then return end
	state.pending[id] = nil
	state.inFlight = state.inFlight - 1
	if not (success and Store(id)) then state.failed = state.failed + 1 end
end)

local function Start()
	if state then return end
	if not GetItemInfoInstant then
		return ns.Print("This game version can't list items, so the scan isn't available.")
	end
	ns.db.scan.active = true
	state = { step = 1, pos = 0, ids = {}, pending = {}, inFlight = 0, failed = 0 }
	ticker = C_Timer.NewTicker(TICK, Tick)
end

local function Stop()
	if not state then return end
	ns.db.scan.active = false
	ticker:Cancel()
	ticker, state = nil, nil
	if ns.UpdateFooter then ns.UpdateFooter() end
end

function ns.ScanStatus()
	if not state then return nil end
	if state.paused then return "Item scan paused while you're in combat" end
	if state.step == 1 then
		return ("Item scan: finding items... %d%%"):format(state.pos / MAX_ID * 100)
	end
	return ("Item scan: %d / %d items"):format(state.pos - state.inFlight, #state.ids)
end

ns.AddCommand("scan", "/wh scan  - load every item in the game into search (/wh scan stop to pause)", function(rest)
	if strtrim(rest or ""):lower() == "stop" then
		if state then Stop(); ns.Print("Item scan paused. /wh scan to continue.") end
		return
	end
	if state then return ns.Print(ns.ScanStatus()) end
	Start()
	ns.Print("Item scan started. It runs in the background (about 15-30 minutes the first time) and pauses in combat. Open /wh to watch progress.")
end)

ns.On("PLAYER_LOGIN", function()
	local scan = ns.db.scan
	if scan.active then
		Start()
	elseif scan.build and scan.build ~= Build() then
		ns.Print("The game was patched since your last item scan. /wh scan to pick up new items.")
	end
end)
