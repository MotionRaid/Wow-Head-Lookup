local _, ns = ...
local button

local function UpdatePosition()
	local angle = math.rad(ns.db.minimap.angle or 200)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
	UpdatePosition()
end

local function Create()
	button = CreateFrame("Button", "WowheadLookupMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
	icon:SetPoint("TOPLEFT", 7, -6)

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			if ns.lastEntry or ns.db.history[1] then
				ns.ShowEntry(ns.lastEntry or ns.db.history[1])
			else
				ns.Print("No lookups yet.")
			end
		else
			WowheadLookup_ToggleWindow()
		end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Wowhead Lookup")
		GameTooltip:AddLine("Left-click: search window", 1, 1, 1)
		GameTooltip:AddLine("Right-click: last lookup again", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UpdatePosition()
end

local function Refresh()
	if ns.db.minimap.hide then
		if button then button:Hide() end
	else
		if not button then Create() end
		button:Show()
	end
end

ns.On("PLAYER_LOGIN", Refresh)

ns.AddCommand("minimap", "/wh minimap  - show or hide the minimap button", function()
	ns.db.minimap.hide = not ns.db.minimap.hide
	Refresh()
	ns.Print("Minimap button " .. ns.OnOff(not ns.db.minimap.hide) .. ".")
end)
