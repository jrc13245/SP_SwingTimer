
local version = "6.3.0"

local defaults = {
	x = 0,
	y = -150,
	w = 200,
	h = 10,
	b = 2,
	a = 1,
	s = 1,
	vo = -6,
	ho = 0,
	move = "off",
	icons = 1,
	bg = 1,
	border = 1,
	bga = 0.8,
	timers = 1,
	style = 2,
	colorBar = "1,1,1",
	colorTimer = "0,0,0",
	timerPostitionX = 0,
	show_oh = true,
	show_range = true,
	show_hs = true,
	show_dist = false,
	lag = 0,        -- manual latency offset in ms (0 = auto if available)
	autolag = true, -- auto-estimate latency using spell timing
}

local backdrop_with_border = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 8,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local backdrop_no_border = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	tile = true,
	tileSize = 16,
}

local settings = {
	x = "Bar X position",
	y = "Bar Y position",
	w = "Bar width",
	h = "Bar height",
	b = "Border height",
	a = "Alpha between 0 and 1",
	s = "Bar scale",
	vo = "Offhand bar vertical offset",
	ho = "Offhand bar horizontal offset",
	icons = "Show weapon icons (1 = show, 0 = hide)",
	bg = "Show background (1 = show, 0 = hide)",
	border = "Show border (1 = show, 0 = hide)",
	bga = "Background alpha (0-1)",
	timers = "Show weapon timers (1 = show, 0 = hide)",
	style = "Choose 1, 2, 3, 4, 5 or 6",
	move = "Enable bars movement",
	colorBar = "Bar color (R,G,B). Number range is 0-1.",
	colorTimer = "Bar color (R,G,B). Number range is 0-1.",
	timerPostitionX = "No idea"
}

local flurry = {
	WARRIOR = {10, 15, 20, 25, 30},
	SHAMAN  = { 8, 11, 14, 17, 20},
}

local armorDebuffs = {
	["Interface\\Icons\\Ability_Warrior_Sunder"] = 450, 
	["Interface\\Icons\\Spell_Shadow_Unholystrength"] = 640, 
	["Interface\\Icons\\Spell_Nature_Faeriefire"] = 505, 
	["Interface\\Icons\\Ability_Warrior_Riposte"] = 2550,
	["Interface\\Icons\\Inv_Axe_12"] = 200
}
local combatStrings = {
	SPELLLOGSELFOTHER,			-- Your %s hits %s for %d.
	SPELLLOGCRITSELFOTHER,		-- Your %s crits %s for %d.
	SPELLDODGEDSELFOTHER,		-- Your %s was dodged by %s.
	SPELLPARRIEDSELFOTHER,		-- Your %s is parried by %s.
	SPELLMISSSELFOTHER,			-- Your %s missed %s.
	SPELLBLOCKEDSELFOTHER,		-- Your %s was blocked by %s.
	SPELLDEFLECTEDSELFOTHER,	-- Your %s was deflected by %s.
	SPELLEVADEDSELFOTHER,		-- Your %s was evaded by %s.
	SPELLIMMUNESELFOTHER,		-- Your %s failed. %s is immune.
	SPELLLOGABSORBSELFOTHER,	-- Your %s is absorbed by %s.
	SPELLREFLECTSELFOTHER,		-- Your %s is reflected back by %s.
	SPELLRESISTSELFOTHER		-- Your %s was resisted by %s.
}
for index in combatStrings do
	for _, pattern in {"%%s", "%%d"} do
		combatStrings[index] = gsub(combatStrings[index], pattern, "(.*)")
	end
end
--------------------------------------------------------------------------------
-- Consolidate state into a table to avoid Lua 5.0 upvalue limit (32 max)
local S = {
	weapon = nil,
	offhand = nil,
	range = nil,
	combat = false,
	configmod = false,
	player_guid = nil,
	player_class = nil,
	flurry_mult = 1,
	range_fader = 0,
	ele_flurry_fresh = nil,
	flurry_fresh = nil,
	flurry_count = -1,
	wf_swings = 0,
	-- Nampower on-swing spell tracking
	queued_onswing_spell = nil,
	-- Latency estimation
	estimated_lag = 0,
	lag_samples = {},
	timer_zero_time = nil,
	timer_zero_timeOH = nil,
	-- Nampower spell cast timing
	pending_cast_time = nil,
	pending_cast_spell = nil,
}
local LAG_SAMPLE_COUNT = 5

-- Feature detection - deferred to avoid crashes during load
local has_nampower = false
local has_unitxp = false

local function DetectFeatures()
	-- Safely detect Nampower
	if GetCurrentCastingInfo then
		has_nampower = true
	end
	-- Safely detect UnitXP
	if UnitXP then
		local ok = pcall(UnitXP, "nop", "nop")
		has_unitxp = ok
	end
end

-- Timers need to be global for external access
st_timer = 0
st_timerMax = 1
st_timerOff = 0
st_timerOffMax = 1
st_timerRange = 0
st_timerRangeMax = 1

--------------------------------------------------------------------------------
local loc = {};
loc["enUS"] = {
	hit = "You hit",
	crit = "You crit",
	glancing = "glancing",
	block = "blocked",
	Warrior = "Warrior",
	combatSpells = {
		HS = "Heroic Strike",
		Cleave = "Cleave",
		-- Slam = "Slam",
		RS = "Raptor Strike",
		Maul = "Maul",
		-- HolyStrike = "Holy Strike", -- Turtle wow
		-- MongooseBite = "Mongoose Bite", -- Turtle wow
	}
}
loc["frFR"] = {
	hit = "Vous touchez",
	crit = "Vous infligez un coup critique",
	glancing = "érafle",
	block = "bloqué",
	Warrior = "Guerrier",
	combatSpells = {
		HS = "Frappe héroïque",
		Cleave = "Enchainement",
		-- Slam = "Heurtoir",
		RS = "Attaque du raptor",
		Maul = "Mutiler",
		-- HolyStrike = "Frappe sacrée" -- Tortue wow
	}
}
local L = loc[GetLocale()];
if (L == nil) then 
	L = loc['enUS']; 
end
--------------------------------------------------------------------------------
StaticPopupDialogs["SP_ST_Install"] = {
	text = TEXT("Thanks for installing SP_SwingTimer " ..version .. "! Use the chat command /st to change the settings."),
	button1 = TEXT(YES),
	timeout = 0,
	hideOnEscape = 1,
}
--------------------------------------------------------------------------------
function MakeMovable(frame)
    frame:SetMovable(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", function() this:StartMoving() end);
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end);
end
--------------------------------------------------------------------------------
local function print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5)
end
local function SplitString(s,t)
	local l = {n=0}
	local f = function (s)
		l.n = l.n + 1
		l[l.n] = s
	end
	local p = "%s*(.-)%s*"..t.."%s*"
	s = string.gsub(s,"^%s+","")
	s = string.gsub(s,"%s+$","")
	s = string.gsub(s,p,f)
	l.n = l.n + 1
	l[l.n] = string.gsub(s,"(%s%s*)$","")
	return l
end

-- This function is realy useful
local function has_value (tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    if (tab[val] ~= nil) then
        return true
    end

    return false
end

local function sp_round(number, decimals)
    local power = 10^decimals
    return math.floor(number * power) / power
end

-- Get current latency offset in seconds
local function GetLagOffset()
	-- Manual override takes priority
	if SP_ST_GS and SP_ST_GS["lag"] and SP_ST_GS["lag"] > 0 then
		return SP_ST_GS["lag"] / 1000
	end
	-- Use auto-estimated latency if enabled
	if SP_ST_GS and SP_ST_GS["autolag"] and S.estimated_lag > 0 then
		return S.estimated_lag
	end
	return 0
end

-- Add a latency sample and update the rolling average
local function AddLagSample(round_trip_time)
	-- One-way latency is roughly half of round-trip
	local one_way = round_trip_time / 2

	-- Add to samples
	table.insert(S.lag_samples, one_way)

	-- Keep only the last N samples
	while getn(S.lag_samples) > LAG_SAMPLE_COUNT do
		table.remove(S.lag_samples, 1)
	end

	-- Calculate average
	local sum = 0
	for _, sample in ipairs(S.lag_samples) do
		sum = sum + sample
	end
	S.estimated_lag = sum / getn(S.lag_samples)
end

--------------------------------------------------------------------------------

local function UpdateSettings()
	if not SP_ST_GS then SP_ST_GS = {} end
	for option, value in defaults do
		if SP_ST_GS[option] == nil then
			SP_ST_GS[option] = value
		end
	end
end

--------------------------------------------------------------------------------

local HeroicTrackedActionSlots = {}
local CleaveTrackedActionSlots = {}

local function UpdateHeroicStrike()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" or not SP_ST_GS["show_hs"] then
		return
	end
	HeroicTrackedActionSlots = {}
	local SPActionSlot = 0;
	for SPActionSlot = 1, 120 do
		local SPActionText = GetActionText(SPActionSlot);
		local SPActionTexture = GetActionTexture(SPActionSlot);
		
		if SPActionTexture then
			if (SPActionTexture == "Interface\\Icons\\Ability_Rogue_Ambush") then
				tinsert(HeroicTrackedActionSlots, SPActionSlot);
			elseif SPActionText then
				SPActionText = string.lower(SPActionText)
				if (SPActionText == "heroic strike" or SPActionText == "heroicstrike" or SPActionText == "hs") then
					tinsert(HeroicTrackedActionSlots, SPActionSlot);
				end
			end
		end
	end

end

----------------------------------------------------------------------------------

local function UpdateCleave()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" or not SP_ST_GS["show_hs"] then
		return
	end
	CleaveTrackedActionSlots = {}
	local SPActionSlot = 0;
	for SPActionSlot = 1, 120 do
		local SPActionText = GetActionText(SPActionSlot);
		local SPActionTexture = GetActionTexture(SPActionSlot);
		
		if SPActionTexture then
			if SPActionTexture == "Interface\\Icons\\Ability_Warrior_Cleave" then
				tinsert(CleaveTrackedActionSlots, SPActionSlot);
			elseif SPActionText then
				SPActionText = string.lower(SPActionText)
				if (SPActionText == "cleave") then
					tinsert(CleaveTrackedActionSlots, SPActionSlot);				
				end
			end
		end
	end

end

--------------------------------------------------------------------------------

local function HeroicStrikeQueued()
	-- Use Nampower's on-swing tracking if available
	if has_nampower and S.queued_onswing_spell then
		local name = SpellInfo(S.queued_onswing_spell)
		return name == "Heroic Strike" or name == L['combatSpells']['HS']
	end
	-- Fallback to action bar scanning
	if not HeroicTrackedActionSlots or getn(HeroicTrackedActionSlots) == 0 then
		return nil
	end
	for _, actionslotID in ipairs (HeroicTrackedActionSlots) do
		if IsCurrentAction(actionslotID) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------

local function CleaveQueued()
	-- Use Nampower's on-swing tracking if available
	if has_nampower and S.queued_onswing_spell then
		local name = SpellInfo(S.queued_onswing_spell)
		return name == "Cleave" or name == L['combatSpells']['Cleave']
	end
	-- Fallback to action bar scanning
	if not CleaveTrackedActionSlots or getn(CleaveTrackedActionSlots) == 0 then
		return nil
	end
	for _, actionslotID in ipairs (CleaveTrackedActionSlots) do
		if IsCurrentAction(actionslotID) then
			return true
		end
	end
	return false
end

-- Nampower SPELL_QUEUE_EVENT handler
local ON_SWING_QUEUED = 0
local ON_SWING_QUEUE_POPPED = 1

local function OnSpellQueueEvent(eventCode, spellId)
	if eventCode == ON_SWING_QUEUED then
		S.queued_onswing_spell = spellId
	elseif eventCode == ON_SWING_QUEUE_POPPED then
		S.queued_onswing_spell = nil
	end
end

--------------------------------------------------------------------------------

-- flurry check
local function CheckFlurry()
  local c = 0
  while GetPlayerBuff(c,"HELPFUL") ~= -1 do
    local id = GetPlayerBuffID(c)
		if SpellInfo(id) == "Flurry" then
			return GetPlayerBuffApplications(c)
		end
		c = c + 1
  end
	return -1
end

--------------------------------------------------------------------------------

local function UpdateAppearance()
	SP_ST_Frame:ClearAllPoints()
	SP_ST_FrameOFF:ClearAllPoints()
	SP_ST_FrameRange:ClearAllPoints()
	
	SP_ST_Frame:SetPoint("TOPLEFT", SP_ST_GS["x"], SP_ST_GS["y"])
	SP_ST_maintimer:SetPoint("RIGHT", "SP_ST_Frame", "CENTER", 7, 0)
	SP_ST_maintimer:SetFont("Fonts\\FRIZQT__.TTF", SP_ST_GS["h"])

	if SP_ST_GS["bg"] ~= 0 then
		local backdrop = SP_ST_GS["border"] ~= 0 and backdrop_with_border or backdrop_no_border
		local bga = SP_ST_GS["bga"] or 0.8
		SP_ST_Frame:SetBackdrop(backdrop)
		SP_ST_FrameOFF:SetBackdrop(backdrop)
		SP_ST_Frame:SetBackdropColor(0, 0, 0, bga)
		SP_ST_FrameOFF:SetBackdropColor(0, 0, 0, bga)
	else
		SP_ST_Frame:SetBackdrop(nil)
		SP_ST_FrameOFF:SetBackdrop(nil)
	end

	SP_ST_offtimer:SetFont("Fonts\\FRIZQT__.TTF", SP_ST_GS["h"])

-- Set timer text color from settings
	local _, _, r, g, b = string.find(SP_ST_GS["colorTimer"] or "0,0,0", "([%d%.]+),([%d%.]+),([%d%.]+)")
	r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
	SP_ST_maintimer:SetTextColor(r, g, b, 1)
	SP_ST_offtimer:SetTextColor(r, g, b, 1)

	SP_ST_FrameOFF:SetPoint("TOPLEFT", "SP_ST_Frame", "BOTTOMLEFT", SP_ST_GS["ho"], SP_ST_GS["vo"]);
	SP_ST_offtimer:SetPoint("RIGHT", "SP_ST_FrameOFF", "CENTER", 7, 0)
	SP_ST_FrameRange:SetPoint("TOPLEFT", "SP_ST_FrameOFF", "BOTTOMLEFT", SP_ST_GS["ho"], SP_ST_GS["vo"]);
	SP_ST_rangetimer:SetPoint("RIGHT", "SP_ST_FrameRange", "RIGHT", -2, 0)
	SP_ST_rangetimer:SetFont("Fonts\\FRIZQT__.TTF", SP_ST_GS["h"])
	SP_ST_rangetimer:SetTextColor(r, g, b, 1)

	if SP_ST_GS["bg"] ~= 0 then
		local backdrop = SP_ST_GS["border"] ~= 0 and backdrop_with_border or backdrop_no_border
		local bga = SP_ST_GS["bga"] or 0.8
		SP_ST_FrameRange:SetBackdrop(backdrop)
		SP_ST_FrameRange:SetBackdropColor(0, 0, 0, bga)
	else
		SP_ST_FrameRange:SetBackdrop(nil)
	end

	if (SP_ST_GS["icons"] ~= 0) then
		SP_ST_mainhand:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("MainHandSlot")));
		SP_ST_mainhand:SetHeight(SP_ST_GS["h"]+1);
		SP_ST_mainhand:SetWidth(SP_ST_GS["h"]+1);
		-- SP_ST_mainhand:SetDrawLayer("OVERLAY");
		SP_ST_offhand:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("SecondaryHandSlot")));
		SP_ST_offhand:SetHeight(SP_ST_GS["h"]+1);
		SP_ST_offhand:SetWidth(SP_ST_GS["h"]+1);
		-- SP_ST_offhand:SetDrawLayer("OVERLAY");
		SP_ST_range:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("RangedSlot")));
		SP_ST_range:SetHeight(SP_ST_GS["h"]+1);
		SP_ST_range:SetWidth(SP_ST_GS["h"]+1);
		-- SP_ST_offhand:SetDrawLayer("OVERLAY");
	else 
		SP_ST_mainhand:SetTexture(nil);
		SP_ST_mainhand:SetWidth(0);
		SP_ST_offhand:SetTexture(nil);
		SP_ST_offhand:SetWidth(0);
		SP_ST_range:SetTexture(nil);
		SP_ST_range:SetWidth(0);
	end

	if (SP_ST_GS["timers"] ~= 0) then
		SP_ST_maintimer:Show();
		SP_ST_offtimer:Show();
		SP_ST_rangetimer:Show();
	else
		SP_ST_maintimer:Hide();
		SP_ST_offtimer:Hide();
		SP_ST_rangetimer:Hide();
	end
	
	SP_ST_FrameTime:ClearAllPoints()
	SP_ST_FrameTime2:ClearAllPoints()
	SP_ST_FrameTime3:ClearAllPoints()

	local style = SP_ST_GS["style"]
	local icons_enabled = SP_ST_GS["icons"] ~= 0
	if style == 1 or style == 2 then
		SP_ST_mainhand:SetPoint("LEFT", "SP_ST_Frame", "LEFT");
		SP_ST_offhand:SetPoint("LEFT", "SP_ST_FrameOFF", "LEFT");
		SP_ST_range:SetPoint("LEFT", "SP_ST_FrameRange", "LEFT");
		if icons_enabled then
			SP_ST_FrameTime:SetPoint("LEFT", "SP_ST_mainhand", "RIGHT")
			SP_ST_FrameTime2:SetPoint("LEFT", "SP_ST_offhand", "RIGHT")
			SP_ST_FrameTime3:SetPoint("LEFT", "SP_ST_range", "RIGHT")
		else
			SP_ST_FrameTime:SetPoint("LEFT", "SP_ST_Frame", "LEFT")
			SP_ST_FrameTime2:SetPoint("LEFT", "SP_ST_FrameOFF", "LEFT")
			SP_ST_FrameTime3:SetPoint("LEFT", "SP_ST_FrameRange", "LEFT")
		end
	elseif style == 3 or style == 4 then
		SP_ST_mainhand:SetPoint("RIGHT", "SP_ST_Frame", "RIGHT");
		SP_ST_offhand:SetPoint("RIGHT", "SP_ST_FrameOFF", "RIGHT");
		SP_ST_range:SetPoint("RIGHT", "SP_ST_FrameRange", "RIGHT");
		if icons_enabled then
			SP_ST_FrameTime:SetPoint("RIGHT", "SP_ST_mainhand", "LEFT")
			SP_ST_FrameTime2:SetPoint("RIGHT", "SP_ST_offhand", "LEFT")
			SP_ST_FrameTime3:SetPoint("RIGHT", "SP_ST_range", "LEFT")
		else
			SP_ST_FrameTime:SetPoint("RIGHT", "SP_ST_Frame", "RIGHT")
			SP_ST_FrameTime2:SetPoint("RIGHT", "SP_ST_FrameOFF", "RIGHT")
			SP_ST_FrameTime3:SetPoint("RIGHT", "SP_ST_FrameRange", "RIGHT")
		end
	else
		SP_ST_mainhand:SetTexture(nil);
		SP_ST_mainhand:SetWidth(0);
		SP_ST_offhand:SetTexture(nil);
		SP_ST_offhand:SetWidth(0);
		SP_ST_range:SetTexture(nil);
		SP_ST_range:SetWidth(0);
		SP_ST_FrameTime:SetPoint("CENTER", "SP_ST_Frame", "CENTER")
		SP_ST_FrameTime2:SetPoint("CENTER", "SP_ST_FrameOFF", "CENTER")
		SP_ST_FrameTime3:SetPoint("CENTER", "SP_ST_FrameRange", "CENTER")
	end

	SP_ST_Frame:SetWidth(SP_ST_GS["w"])
	SP_ST_Frame:SetHeight(SP_ST_GS["h"])
	SP_ST_FrameOFF:SetWidth(SP_ST_GS["w"])
	SP_ST_FrameOFF:SetHeight(SP_ST_GS["h"])
	SP_ST_FrameRange:SetWidth(SP_ST_GS["w"])
	SP_ST_FrameRange:SetHeight(SP_ST_GS["h"])

	SP_ST_FrameTime:SetWidth(SP_ST_GS["w"] - SP_ST_mainhand:GetWidth())
	SP_ST_FrameTime:SetHeight(SP_ST_GS["h"] - SP_ST_GS["b"])
	SP_ST_FrameTime2:SetWidth(SP_ST_GS["w"] - SP_ST_offhand:GetWidth())
	SP_ST_FrameTime2:SetHeight(SP_ST_GS["h"] - SP_ST_GS["b"])
	SP_ST_FrameTime3:SetWidth(SP_ST_GS["w"] - SP_ST_range:GetWidth())
	SP_ST_FrameTime3:SetHeight(SP_ST_GS["h"] - SP_ST_GS["b"])

	SP_ST_Frame:SetAlpha(SP_ST_GS["a"])
	SP_ST_Frame:SetScale(SP_ST_GS["s"])
	SP_ST_FrameOFF:SetAlpha(SP_ST_GS["a"])
	SP_ST_FrameOFF:SetScale(SP_ST_GS["s"])
	SP_ST_FrameRange:SetAlpha(SP_ST_GS["a"])
	SP_ST_FrameRange:SetScale(SP_ST_GS["s"])
end

local function GetWeaponSpeed(off,ranged)
	local speedMH, speedOH = UnitAttackSpeed("player")
	if off and not ranged then
		return speedOH
	elseif not off and ranged then
		local rangedAttackSpeed, minDamage, maxDamage, physicalBonusPos, physicalBonusNeg, percent = UnitRangedDamage("player")
		return rangedAttackSpeed
	else
		return speedMH
	end
end

local function isDualWield()
	return (GetWeaponSpeed(true) ~= nil)
end

local function hasRanged()
	return (GetWeaponSpeed(nil,true) ~= nil)
end

local function ShouldResetTimer(off)
	if not st_timerMax then st_timerMax = GetWeaponSpeed(false) end
	if not st_timerOffMax and isDualWield() then st_timerOffMax = GetWeaponSpeed(true) end
	local percentTime
	if (off) then
		percentTime = st_timerOff / st_timerOffMax
	else 
		percentTime = st_timer / st_timerMax
	end
	
	return (percentTime < 0.025)
end

local function ClosestSwing()
	if not st_timerMax then st_timerMax = GetWeaponSpeed(false) end
	if not st_timerOffMax then st_timerOffMax = GetWeaponSpeed(true) end
	local percentLeftMH = st_timer / st_timerMax
	local percentLeftOH = st_timerOff / st_timerOffMax
	return (percentLeftMH > percentLeftOH)
end

local function UpdateWeapon()
	S.weapon = GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))
	if (SP_ST_GS["icons"] ~= 0) then
		SP_ST_mainhand:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("MainHandSlot")));
	end
	if (isDualWield()) then
		S.offhand = GetInventoryItemLink("player", GetInventorySlotInfo("SecondaryHandSlot"))
		if (SP_ST_GS["icons"] ~= 0) then
			SP_ST_offhand:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("SecondaryHandSlot")));
		end
	else
		SP_ST_FrameOFF:Hide()
	end
	if hasRanged() then
		S.range = GetInventoryItemLink("player", GetInventorySlotInfo("RangedSlot"))
		if (SP_ST_GS["icons"] ~= 0) then
			SP_ST_range:SetTexture(GetInventoryItemTexture("player", GetInventorySlotInfo("RangedSlot")))
		end
	else
		SP_ST_FrameRange:Hide()
	end
end

local function ResetTimer(off,ranged)
	-- Get latency offset to compensate for network delay
	-- The swing actually happened lag_offset seconds ago on the server
	local lag_offset = GetLagOffset()

	if not off and not ranged then
		st_timerMax = GetWeaponSpeed(off)
		st_timer = GetWeaponSpeed(off) - lag_offset
		if st_timer < 0 then st_timer = 0 end
	elseif off and not ranged then
		st_timerOffMax = GetWeaponSpeed(off)
		st_timerOff = GetWeaponSpeed(off) - lag_offset
		if st_timerOff < 0 then st_timerOff = 0 end
	else
		S.range_fader = GetTime()
		st_timerRangeMax = GetWeaponSpeed(false,true)
		st_timerRange = GetWeaponSpeed(false,true) - lag_offset
		if st_timerRange < 0 then st_timerRange = 0 end
	end

	if not off and not ranged then SP_ST_Frame:Show() end
	if (isDualWield() and SP_ST_GS["show_oh"]) then SP_ST_FrameOFF:Show() end
	if (hasRanged() and SP_ST_GS["show_range"]) then SP_ST_FrameRange:Show() end
end

local function TestShow()
	ResetTimer(false)
end


local function UpdateDisplay()
	local style = SP_ST_GS["style"]
	local show_oh = SP_ST_GS["show_oh"]
	local show_range = SP_ST_GS["show_range"]
	local show_hs = SP_ST_GS["show_hs"]
	local _, _, br, bg, bb = string.find(SP_ST_GS["colorBar"] or "1,1,1", "([%d%.]+),([%d%.]+),([%d%.]+)")
	br, bg, bb = tonumber(br) or 1, tonumber(bg) or 1, tonumber(bb) or 1
	if SP_ST_InRange() then
		if show_hs and CleaveQueued() then
			SP_ST_FrameTime:SetVertexColor(0.2, 0.9, 0.2); -- Green for Cleave
		elseif show_hs and HeroicStrikeQueued() then
			SP_ST_FrameTime:SetVertexColor(0.9, 0.9, 0.2); -- Yellow for Heroic Strike
		else
			SP_ST_FrameTime:SetVertexColor(br, bg, bb); -- User color for Auto
		end
		SP_ST_FrameTime2:SetVertexColor(br, bg, bb);
		if SP_ST_GS["bg"] ~= 0 then
			local bga = SP_ST_GS["bga"] or 0.8
			SP_ST_Frame:SetBackdropColor(0,0,0,bga);
			SP_ST_FrameOFF:SetBackdropColor(0,0,0,bga);
		end
	else
		SP_ST_FrameTime:SetVertexColor(1.0, 0, 0); -- Red if out of range
		SP_ST_FrameTime2:SetVertexColor(1.0, 0, 0);
		if SP_ST_GS["bg"] ~= 0 then
			local bga = SP_ST_GS["bga"] or 0.8
			SP_ST_Frame:SetBackdropColor(1,0,0,bga);
			SP_ST_FrameOFF:SetBackdropColor(1,0,0,bga);
		end
	end
	local rangeInRange = false
	if has_unitxp and UnitExists("target") then
		local dist = UnitXP("distanceBetween", "player", "target")
		rangeInRange = dist and dist <= 35 -- ranged attack range ~30-35 yards
	elseif UnitExists("target") then
		rangeInRange = CheckInteractDistance("target", 4) -- ~28 yard fallback
	else
		rangeInRange = true -- no target, don't show red
	end
	if rangeInRange then
		SP_ST_FrameTime3:SetVertexColor(br, bg, bb);
		if SP_ST_GS["bg"] ~= 0 then
			local bga = SP_ST_GS["bga"] or 0.8
			SP_ST_FrameRange:SetBackdropColor(0,0,0,bga);
		end
	else
		SP_ST_FrameTime3:SetVertexColor(1.0, 0, 0);
		if SP_ST_GS["bg"] ~= 0 then
			local bga = SP_ST_GS["bga"] or 0.8
			SP_ST_FrameRange:SetBackdropColor(1,0,0,bga);
		end
	end
	-- Hunters keep ranged bar visible during combat; other classes fade after 10s
	local isHunter = S.player_class == "HUNTER"
	if not isHunter and GetTime() - 10 > S.range_fader then
		SP_ST_FrameRange:Hide()
	end

	if (st_timer <= 0) then
		if style == 2 or style == 4 or style == 6 then
			--nothing
		else
			SP_ST_FrameTime:Hide()
		end

		if (not S.combat and not S.configmod) then
			SP_ST_Frame:Hide()
		end
	else
		SP_ST_FrameTime:Show()
		local width = SP_ST_GS["w"] - SP_ST_mainhand:GetWidth()
		local size = (st_timer / st_timerMax) * width
		if style == 2 or style == 4 or style == 6 then
			size = width - size
		end
		if (size > width) then
			size = width
			SP_ST_FrameTime:SetTexture(1, 0.8, 0.8, 1)
		else
			SP_ST_FrameTime:SetTexture(1, 1, 1, 1)
		end
		SP_ST_FrameTime:SetWidth(size)
		if (SP_ST_GS["timers"] ~= 0) then
			local showtmr = sp_round(st_timer, 1);
			if (math.floor(showtmr) == showtmr) then
				showtmr = showtmr..".0";
			end
			-- Optionally show distance using UnitXP
			if SP_ST_GS["show_dist"] and has_unitxp and UnitExists("target") then
				local dist = UnitXP("distanceBetween", "player", "target", "meleeAutoAttack")
				if dist then
					showtmr = showtmr .. " |cff888888" .. string.format("%.1fy", dist) .. "|r"
				end
			end
			SP_ST_maintimer:SetText(showtmr);
		end
	end

	if (hasRanged() and show_range) then
		if (st_timerRange <= 0) then
			if style == 2 or style == 4 or style == 6 then
				--nothing
			else
				SP_ST_FrameTime3:Hide()
			end

			if (not S.combat and not S.configmod) then
				SP_ST_FrameRange:Hide()
			end
		else
			SP_ST_FrameTime3:Show()
			local width = SP_ST_GS["w"] - SP_ST_range:GetWidth()
			local size2 = (st_timerRange / st_timerRangeMax) * width
			if style == 2 or style == 4 or style == 6 then
				size2 = width - size2
			end
			if (size2 > width) then
				size2 = width
				SP_ST_FrameTime3:SetTexture(1, 0.8, 0.8, 1)
			else
				SP_ST_FrameTime3:SetTexture(1, 1, 1, 1)
			end
			SP_ST_FrameTime3:SetWidth(size2)
			if (SP_ST_GS["timers"] ~= 0) then
				local showtmr = sp_round(st_timerRange, 1);
				if (math.floor(showtmr) == showtmr) then
					showtmr = showtmr..".0";
				end
				SP_ST_rangetimer:SetText(showtmr);
			end
		end
	else
		SP_ST_FrameRange:Hide()
	end

	if (isDualWield() and show_oh) then
		if (st_timerOff <= 0) then
			if style == 2 or style == 4 or style == 6 then
				--nothing
			else
				SP_ST_FrameTime2:Hide()
			end

			if (not S.combat and not S.configmod) then
				SP_ST_FrameOFF:Hide()
			end
		else
			SP_ST_FrameTime2:Show()
			local width = SP_ST_GS["w"] - SP_ST_offhand:GetWidth()
			local size2 = (st_timerOff / st_timerOffMax) * width
			if style == 2 or style == 4 or style == 6 then
				size2 = width - size2
			end
			if (size2 > width) then
				size2 = width
				SP_ST_FrameTime2:SetTexture(1, 0.8, 0.8, 1)
			else
				SP_ST_FrameTime2:SetTexture(1, 1, 1, 1)
			end
			SP_ST_FrameTime2:SetWidth(size2)
			if (SP_ST_GS["timers"] ~= 0) then
				local showtmr = sp_round(st_timerOff, 1);
				if (math.floor(showtmr) == showtmr) then
					showtmr = showtmr..".0";
				end
				SP_ST_offtimer:SetText(showtmr);
			end
		end
	else
		SP_ST_FrameOFF:Hide()
	end
end

--------------------------------------------------------------------------------

-- UnitXP provides accurate melee range detection without needing to scan action bars
function SP_ST_InRange()
	if not UnitExists("target") then
		return true -- no target, don't show red
	end

	if has_unitxp then
		-- UnitXP meleeAutoAttack distance is accurate for melee weapon swings
		local dist = UnitXP("distanceBetween", "player", "target", "meleeAutoAttack")
		return dist and dist <= 5 -- melee range is ~5 yards
	else
		-- Fallback: assume in range if no UnitXP
		return true
	end
end

function rangecheck()
	if has_unitxp then
		local dist = UnitXP("distanceBetween", "player", "target", "meleeAutoAttack")
		print(dist and string.format("%.1f yards", dist) or "no target")
	else
		print("UnitXP not available")
	end
end

function GetFlurry(class)
	-- default multiplier
	S.flurry_mult = 1.3

	-- Defensive check 1: Exit if the class isn't in our data table.
	if not flurry[class] then
		return
	end

	for page = 1, 3 do
		for talent = 1, 100 do
			local name, _, _, _, count = GetTalentInfo(page, talent)
			if not name then break end
			if name == "Flurry" then
				-- Defensive check 2: If count is nil or 0, there is no bonus.
				if not count or count == 0 then
					S.flurry_mult = 1
				else
					-- Only proceed if count is a valid number (1-5).
					-- Check if the value exists before using it.
					if flurry[class][count] then
						S.flurry_mult = 1 + (flurry[class][count] / 100)
					else
						-- Fallback if count is an unexpected number (e.g., > 5)
						S.flurry_mult = 1
					end
				end
				return
			end
		end
	end
end

-- Flag to prevent UnitXP calls during logout (crash prevention)
local SP_ST_IsLoggingOut = false

function SP_ST_OnLoad()
	this:RegisterEvent("ADDON_LOADED")
	this:RegisterEvent("PLAYER_REGEN_ENABLED")
	this:RegisterEvent("PLAYER_REGEN_DISABLED")
	this:RegisterEvent("UNIT_INVENTORY_CHANGED")
	this:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
	this:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
	this:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
	this:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
	this:RegisterEvent("CHARACTER_POINTS_CHANGED")
	this:RegisterEvent("UNIT_CASTEVENT")
	-- this:RegisterEvent("UNIT_AURA")
	-- this:RegisterEvent("PLAYER_AURAS_CHANGED")
	this:RegisterEvent("PLAYER_ENTERING_WORLD")
	this:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	-- SPELL_QUEUE_EVENT registered in ADDON_LOADED after feature detection
	-- Register logout events to prevent UnitXP crash during logout
	this:RegisterEvent("PLAYER_LOGOUT")
	this:RegisterEvent("PLAYER_LEAVING_WORLD")
end

function SP_ST_OnEvent()
	-- Handle logout to prevent UnitXP crashes during shutdown
	if (event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD") then
		SP_ST_IsLoggingOut = true
		return
	end
	if (event == "ADDON_LOADED" and arg1 == "SP_SwingTimer") then
		-- Detect SuperWoW extensions safely
		DetectFeatures()

		-- Register Nampower events if available
		if has_nampower then
			this:RegisterEvent("SPELL_QUEUE_EVENT")
			this:RegisterEvent("SPELL_CAST_EVENT")
		end

		if (SP_ST_GS == nil) then
			StaticPopup_Show("SP_ST_Install")
		end

		if (SP_ST_GS ~= nil) then
			for k,v in pairs(defaults) do
				if (SP_ST_GS[k] == nil) then
					SP_ST_GS[k] = defaults[k];
				end
			end
		end

		UpdateSettings()
		UpdateWeapon()
		UpdateAppearance()
		if not st_timerMax then st_timerMax = GetWeaponSpeed(false) end
		if not st_timerOffMax and isDualWield() then st_timerOffMax = GetWeaponSpeed(true) end
		if not st_timerRangeMax and hasRanged() then st_timerRangeMax = GetWeaponSpeed(nil,true) end
		print("SP_SwingTimer " .. version .. " loaded. Options: /st")
	elseif (event == "PLAYER_ENTERING_WORLD") then
		-- Reset the logout flag - we're back in the world
		SP_ST_IsLoggingOut = false
		_,S.player_guid = UnitExists("player")
		_,S.player_class = UnitClass("player")
		if UnitAffectingCombat('player') then S.combat = true else S.combat = false end
		GetFlurry(S.player_class)
		CheckFlurry()
		UpdateDisplay()
		UpdateHeroicStrike()
		UpdateCleave()
	elseif (event == "PLAYER_REGEN_ENABLED") then
		_,S.player_guid = UnitExists("player")
		_,S.player_class = UnitClass("player")
		if UnitAffectingCombat('player') then S.combat = true else S.combat = false end

		GetFlurry(S.player_class)
		CheckFlurry()
		UpdateDisplay()
	elseif (event == "PLAYER_REGEN_DISABLED") then
		S.combat = true
		S.wf_swings = 0
		CheckFlurry()
	elseif (event == "CHARACTER_POINTS_CHANGED") then
		GetFlurry(S.player_class)
	elseif (event == "ACTIONBAR_SLOT_CHANGED") then
		UpdateHeroicStrike()
		UpdateCleave()
	elseif (event == "SPELL_QUEUE_EVENT") then
		-- Nampower on-swing spell queue tracking (arg1 = eventCode, arg2 = spellId)
		OnSpellQueueEvent(arg1, arg2)
	elseif (event == "SPELL_CAST_EVENT") then
		-- Nampower latency measurement: arg1=success, arg2=spellId
		-- Measure time between cast start and server confirmation
		if S.pending_cast_spell and arg2 == S.pending_cast_spell and S.pending_cast_time then
			local round_trip = GetTime() - S.pending_cast_time
			-- Only use reasonable samples (10-500ms)
			if round_trip > 0.01 and round_trip < 0.5 and SP_ST_GS["autolag"] then
				AddLagSample(round_trip)
			end
			S.pending_cast_spell = nil
			S.pending_cast_time = nil
		end
	elseif (event == "UNIT_CASTEVENT" and arg1 == S.player_guid) then
		local spell = SpellInfo(arg4)

		-- Track spell cast start for Nampower latency measurement
		if arg3 == "START" and has_nampower then
			S.pending_cast_time = GetTime()
			S.pending_cast_spell = arg4
		end
		-- print(spell .. " "..arg4)

		-- wf proc happens first, then the normal hit, then the 1-2 wf hits
		-- if S.flurry_count > 0 then
		if (arg4 == 51368 or arg4 == 16361) then
			S.wf_swings = S.wf_swings + ((arg4 == 51368) and 1 or 2)
			return
		end

		if spell == "Flurry" then
			-- track a completely fresh flurry for timing
			S.flurry_fresh = S.flurry_count < 1
			S.flurry_count = 3
			return
		end

		if spell == "Elemental Flurry" then
			S.ele_flurry_fresh = true
		end

		-- Slam: timer keeps running during cast, but auto-attack is held until cast finishes
		-- We don't need to handle Slam specially - the held auto-attack fires naturally
		-- after Slam ends and will be detected by the normal auto-attack handler below

		if arg4 == 6603 then -- autoattack
			if arg3 == "MAINHAND" then
				-- Measure latency: time between timer hitting 0 and receiving swing event
				if S.timer_zero_time and SP_ST_GS["autolag"] then
					local lag_sample = GetTime() - S.timer_zero_time
					-- Only use reasonable samples (< 500ms)
					if lag_sample > 0 and lag_sample < 0.5 then
						AddLagSample(lag_sample * 2) -- multiply by 2 since this is one-way
					end
				end
				S.timer_zero_time = nil

				ResetTimer(false)

				if S.ele_flurry_fresh then
					st_timer = st_timer / 1.3
					st_timerMax = st_timerMax / 1.3
					S.ele_flurry_fresh = false
				end
				if not S.ele_flurry_fresh and S.ele_flurry_fresh ~= nil then
					st_timer = st_timer * 1.3
					st_timerMax = st_timerMax * 1.3
					S.ele_flurry_fresh = nil
				end

				if S.flurry_fresh then -- fresh flurry, decrease the swing cooldown of the next swing
					st_timer = st_timer / S.flurry_mult
					st_timerMax = st_timerMax / S.flurry_mult
					S.flurry_fresh = false
				end
				if S.flurry_count == 0 then -- used up last flurry
					st_timer = st_timer * S.flurry_mult
					st_timerMax = st_timerMax * S.flurry_mult
				end
			elseif arg3 == "OFFHAND" then
				-- Measure latency for offhand
				if S.timer_zero_timeOH and SP_ST_GS["autolag"] then
					local lag_sample = GetTime() - S.timer_zero_timeOH
					if lag_sample > 0 and lag_sample < 0.5 then
						AddLagSample(lag_sample * 2)
					end
				end
				S.timer_zero_timeOH = nil

				ResetTimer(true)

				if S.flurry_fresh then -- fresh flurry, decrease the swing cooldown of the next swing
					st_timerOff = st_timerOff / S.flurry_mult
					st_timerOffMax = st_timerOffMax / S.flurry_mult
					S.flurry_fresh = false
				end
				if S.flurry_count == 0 then -- used up last flurry
					st_timerOff = st_timerOff * S.flurry_mult
					st_timerOffMax = st_timerOffMax * S.flurry_mult
				end
			end
			-- print(GetTime() .. " normal swing "..S.flurry_count)
			-- print(GetTime() .. " wf_swing "..S.wf_swings)
			if S.wf_swings > 0 then
				S.wf_swings = S.wf_swings - 1
			else
				S.flurry_count = S.flurry_count - 1 -- normal swing occured, reduce flurry counter
			end
			return
		elseif arg3 == "CAST" and (arg4 == 5019 or arg4 == 75) then
			-- wand shoot (5019) or Auto Shot (75) for hunters
			ResetTimer(nil,true)
			return
		end

		-- check for attacks that take the place of autoattack
		for _,v in L['combatSpells'] do
			if spell == v and arg3 == "CAST" then
				-- print(spellname .. " " .. S.flurry_count)
				-- print(format("sp %.3f",GetWeaponSpeed(false)) .. " " .. S.flurry_count)
				ResetTimer(false)
				if S.flurry_fresh then
					st_timer = st_timer / S.flurry_mult
					st_timerMax = st_timerMax / S.flurry_mult
					S.flurry_fresh = false
				end
				if S.flurry_count == 0 then -- used up last flurry
					st_timer = st_timer * S.flurry_mult
					st_timerMax = st_timerMax * S.flurry_mult
				end
				S.flurry_count = S.flurry_count - 1 -- swing occured, reduce flurry counter
				return
			end
		end

	elseif (event == "UNIT_INVENTORY_CHANGED") then
		if (arg1 == "player") then
			local oldWep = S.weapon
			local oldOff = S.offhand
			local oldRange = S.range

			UpdateWeapon()
			if (S.combat and oldWep ~= S.weapon) then
				ResetTimer(false)
			end

			if S.offhand then
				-- don't forget OH timer just because you put on a shield, you might still care, especially for macros
				local _,_,itemId = string.find(S.offhand,"item:(%d+)")
				local _name,_link,_,_lvl,wep_type,_subtype,_ = GetItemInfo(itemId)
				if (S.combat and isDualWield() and ((oldOff ~= S.offhand) and (wep_type and wep_type == "Weapon"))) then
					ResetTimer(true)
				end
			end

			if (S.combat and oldRange ~= S.range) then
				ResetTimer(nil,true)
			end

		end

	elseif (event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES") or (event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE") or (event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES") or (event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE") then
		if (string.find(arg1, ".* attacks. You parry.")) or (string.find(arg1, ".* was parried.")) then
			-- Only the upcoming swing gets parry haste benefit
			if (isDualWield()) then
				if st_timerOff < st_timer then
					local minimum = GetWeaponSpeed(true) * 0.20
					local reduct = GetWeaponSpeed(true) * 0.40
					st_timerOff = st_timerOff - reduct
					if st_timerOff < minimum then
						st_timerOff = minimum
					end
					return -- offhand gets the parry haste benefit, return
				end
			end	

			local minimum = GetWeaponSpeed(false) * 0.20
			if (st_timer > minimum) then
				local reduct = GetWeaponSpeed(false) * 0.40
				local newTimer = st_timer - reduct
				if (newTimer < minimum) then
					st_timer = minimum
				else
					st_timer = newTimer
				end
			end
		end
	end
end

function SP_ST_OnUpdate(delta)
	-- Prevent UnitXP calls during logout (crash prevention)
	if SP_ST_IsLoggingOut then return end
	if (st_timer > 0) then
		st_timer = st_timer - delta
		if (st_timer <= 0) then
			st_timer = 0
			-- Record when timer hit zero for latency estimation
			if not S.timer_zero_time and S.combat then
				S.timer_zero_time = GetTime()
			end
		end
	end
	if (st_timerOff > 0) then
		st_timerOff = st_timerOff - delta
		if (st_timerOff <= 0) then
			st_timerOff = 0
			-- Record when timer hit zero for latency estimation
			if not S.timer_zero_timeOH and S.combat then
				S.timer_zero_timeOH = GetTime()
			end
		end
	end
	if (st_timerRange > 0) then
		st_timerRange = st_timerRange - delta
		if (st_timerRange < 0) then
			st_timerRange = 0
		end
	end
	UpdateDisplay()
end

--------------------------------------------------------------------------------

SLASH_SPSWINGTIMER1 = "/st"
SLASH_SPSWINGTIMER2 = "/swingtimer"

local function ChatHandler(msg)
	local vars = SplitString(msg, " ")
	for k,v in vars do
		if v == "" then
			v = nil
		end
	end
	local cmd, arg = vars[1], vars[2]
	if cmd == "reset" then
		SP_ST_GS = nil
		UpdateSettings()
		UpdateAppearance()
		print("Reset to defaults.")
	elseif cmd == "move" then
		if (arg == "on") then
			S.configmod = true;
			SP_ST_Frame:Show();
			SP_ST_FrameOFF:Show();
			MakeMovable(SP_ST_Frame);
		else
			SP_ST_Frame:SetMovable(false);
			_,_,_,SP_ST_GS["x"], SP_ST_GS["y"]= SP_ST_Frame:GetPoint()
			S.configmod = false;
			UpdateAppearance();
		end
	elseif cmd == "offhand" then
		SP_ST_GS["show_oh"] = not SP_ST_GS["show_oh"]
		print("toggled showing offhand: " .. (SP_ST_GS["show_oh"] and "on" or "off"))
	elseif cmd == "range" then
		SP_ST_GS["show_range"] = not SP_ST_GS["show_range"]
		print("toggled showing range weapon: " .. (SP_ST_GS["show_range"] and "on" or "off"))
	elseif cmd == "hs" then
		SP_ST_GS["show_hs"] = not SP_ST_GS["show_hs"]
		print("toggled showing HS/Cleave queue display: " .. (SP_ST_GS["show_hs"] and "on" or "off"))
	elseif cmd == "dist" then
		if has_unitxp then
			SP_ST_GS["show_dist"] = not SP_ST_GS["show_dist"]
			print("toggled showing distance: " .. (SP_ST_GS["show_dist"] and "on" or "off"))
		else
			print("Distance display requires UnitXP")
		end
	elseif cmd == "lag" then
		if arg then
			local ms = tonumber(arg)
			if ms and ms >= 0 then
				SP_ST_GS["lag"] = ms
				print("Latency offset set to " .. ms .. "ms" .. (ms == 0 and " (using auto)" or ""))
			else
				print("Usage: /st lag <milliseconds> (0 = auto)")
			end
		else
			local current = SP_ST_GS["lag"] or 0
			local auto = math.floor(S.estimated_lag * 1000 + 0.5)
			local source = has_nampower and "Nampower" or "swing timing"
			print("Latency: manual=" .. current .. "ms, auto=" .. auto .. "ms (" .. source .. "), using=" .. math.floor(GetLagOffset() * 1000 + 0.5) .. "ms")
		end
	elseif cmd == "autolag" then
		SP_ST_GS["autolag"] = not SP_ST_GS["autolag"]
		print("Auto latency detection: " .. (SP_ST_GS["autolag"] and "on" or "off"))
		if SP_ST_GS["autolag"] then
			S.lag_samples = {}
			S.estimated_lag = 0
			print("Latency samples reset. Attack a target to calibrate.")
		end
	elseif cmd == "colorbar" or cmd == "colortimer" then
		if arg == nil then
			print("Usage: /st colorbar R,G,B  or  /st colortimer R,G,B")
			return
		end
		local rgb = SplitString(arg, ",")
		local r = tonumber(rgb[1])
		local g = tonumber(rgb[2])
		local b = tonumber(rgb[3])
		if r and g and b and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
			if cmd == "colorbar" then
				SP_ST_GS["colorBar"] = r..","..g..","..b
			elseif cmd == "colortimer" then
				SP_ST_GS["colorTimer"] = r..","..g..","..b
			end
			UpdateAppearance()
		else
			print("Error: Invalid argument")
		end
	elseif settings[cmd] ~= nil then
		if arg ~= nil then
			local number = tonumber(arg)
			if number then
				SP_ST_GS[cmd] = number
				UpdateAppearance()
			else
				print("Error: Invalid argument")
			end
		end
		print(format("%s %s %s (%s)",
			SLASH_SPSWINGTIMER1, cmd, SP_ST_GS[cmd], settings[cmd]))
	else
		for k, v in settings do
			print(format("%s %s %s (%s)",
				SLASH_SPSWINGTIMER1, k, SP_ST_GS[k], v))
		end
		print("/st offhand (Toggle offhand display)")
		print("/st range (Toggle range wep display)")
		print("/st hs (Toggle HS/Cleave queue display)")
		print("/st dist (Toggle distance display - requires UnitXP)")
		print("/st lag [ms] (Set/show latency offset, 0=auto)")
		print("/st autolag (Toggle auto latency detection)")
	end
	TestShow()
end

SlashCmdList["SPSWINGTIMER"] = ChatHandler
