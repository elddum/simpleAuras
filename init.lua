-- SavedVariables root
simpleAuras = simpleAuras or {}

-- runtime only
sA = sA or { auraTimers = {}, frames = {}, dualframes = {} }
sAinCombat = nil

-- perf: cache globals we use a lot (Lua 5.0-safe)
local gsub   = string.gsub
local find   = string.find
local lower  = string.lower
local floor  = math.floor
local tinsert = table.insert
local getn   = table.getn
local GetTime = GetTime

-- message helper
sA.PREFIX = "|c194b7dccsimple|cffffffffAuras: "
function sA:Msg(msg)
  DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. msg)
end

-- SuperWoW detected? 
sA.SuperWoW = SetAutoloot and true or false
if not sA.SuperWoW then
    sA:Msg("No SuperWoW detected!")
else
    sA:Msg("SuperWoW detected!")
end

-- Track temporary casts for updating durations
local ActiveCasts = {} -- ActiveCasts[targetGUID][spellID] = time of cast

---------------------------------------------------
-- SavedVariables Initialization
---------------------------------------------------

-- Ensure tables exist
if not simpleAuras then simpleAuras = {} end
simpleAuras.auras   = simpleAuras.auras   or {}
simpleAuras.refresh = simpleAuras.refresh or 5
if sA.SuperWoW then
  simpleAuras.auradurations = simpleAuras.auradurations or {}
  simpleAuras.updating      = simpleAuras.updating or 0
end

---------------------------------------------------
-- Helper Functions
---------------------------------------------------

local function GetAuraDurationBySpellID(spellID)
  if not spellID then return nil end
  return simpleAuras.auradurations[spellID]
end

-- SuperWoW: learn and track aura durations
if sA.SuperWoW then
  local sADuration = CreateFrame("Frame")
  sADuration:RegisterEvent("RAW_COMBATLOG")
  sADuration:RegisterEvent("UNIT_CASTEVENT")
  sADuration:SetScript("OnEvent", function()
    local timestamp = GetTime()

    if event == "RAW_COMBATLOG" and simpleAuras.auradurations then
      local raw = arg2
      if not raw or not find(raw, "fades from") then return end

      local _, _, spellName  = string.find(raw, "^(.-) fades from ")
      local _, _, targetGUID = string.find(raw, "from (.-).$")

      if lower(targetGUID or "") == "you" then _, targetGUID = UnitExists("player") end
      targetGUID = gsub(targetGUID or "", "^0x", "")
      if not spellName or targetGUID == "" then return end
      if not sA.auraTimers[targetGUID] then return end

      for spellID in pairs(sA.auraTimers[targetGUID]) do
        local n = SpellInfo(spellID)
        if n then
          n = gsub(n, "%s*%(%s*Rank%s+%d+%s*%)", "")
          if n == spellName then
            -- if we were learning this duration, compute actual
            if ActiveCasts[targetGUID] and ActiveCasts[targetGUID][spellID] then
              local castTime = ActiveCasts[targetGUID][spellID]
              local actual   = timestamp - castTime
              simpleAuras.auradurations[spellID] = floor(actual + 0.5)
              if simpleAuras.updating == 1 then
                sA:Msg("Updated duration for " .. spellName .. " ("..spellID..") to: " .. floor(actual + 0.5) .. "s")
              end
              ActiveCasts[targetGUID][spellID] = nil
            end

            sA.auraTimers[spellID] = nil
            if not next(sA.auraTimers[targetGUID]) then
              sA.auraTimers[targetGUID] = nil
            end
            break
          end
        end
      end

    elseif event == "UNIT_CASTEVENT" and simpleAuras.auradurations then
      local casterGUID, targetGUID, evType, spellID = arg1, arg2, arg3, arg4
      if evType ~= "CAST" or not spellID then return end

      local dur       = GetAuraDurationBySpellID(spellID)
      local spellName = SpellInfo(spellID)

      local _, playerGUID = UnitExists("player")
      playerGUID = gsub(playerGUID, "^0x", "")
      casterGUID = gsub(casterGUID or "", "^0x", "")
      if targetGUID then targetGUID = gsub(targetGUID, "^0x", "") end

      if dur and dur > 0 and simpleAuras.updating == 0 then
        sA.auraTimers[targetGUID] = sA.auraTimers[targetGUID] or {}
        sA.auraTimers[targetGUID][spellID] = timestamp + dur
      elseif casterGUID == playerGUID then
        if not targetGUID or targetGUID == "" then targetGUID = playerGUID end
        ActiveCasts[targetGUID] = ActiveCasts[targetGUID] or {}
        ActiveCasts[targetGUID][spellID] = timestamp
        sA.auraTimers[targetGUID] = sA.auraTimers[targetGUID] or {}
        sA.auraTimers[targetGUID][spellID] = 0
        if simpleAuras.updating == 1 then
          sA:Msg("Updating duration for " .. (spellName or spellID) .. " ("..spellID..") - wait for it to fade.")
        end
      end
    end
  end)
end

-- Timed updates
local sAEvent = CreateFrame("Frame", "sAEvent", UIParent)
sAEvent:SetScript("OnUpdate", function()
  local time = GetTime()
  local refreshRate = 1 / (simpleAuras.refresh or 5)
  if (time - (sAEvent.lastUpdate or 0)) < refreshRate then return end
  sAEvent.lastUpdate = time
  sA:UpdateAuras()
end)

-- Combat state
local sACombat = CreateFrame("Frame")
sACombat:RegisterEvent("PLAYER_REGEN_DISABLED")
sACombat:RegisterEvent("PLAYER_REGEN_ENABLED")
sACombat:SetScript("OnEvent", function()
  if event == "PLAYER_REGEN_DISABLED" then
    sAinCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    sAinCombat = nil
  end
end)

---------------------------------------------------
-- Slash Commands
---------------------------------------------------
SLASH_sA1 = "/sa"
SLASH_sA2 = "/simpleauras"
SlashCmdList["sA"] = function(msg)

	-- Get Command
	if type(msg) ~= "string" then
		msg = ""
	end

	-- Get Command Arguments
	local cmd, val
	local s, e, a, b, c = string.find(msg, "^(%S+)%s*(%S*)%s*(%S*)$")
	if a then cmd = a else cmd = "" end
	if b then val = b else val = "" end
	if c then fad = c else fad = "" end
	
	-- hide / show or no command
	if cmd == "" or cmd == "show" or cmd == "hide" then
		if cmd == "show" then
			if not gui:IsVisible() then gui:Show() end
		elseif cmd == "hide" then
			if gui:IsVisible() then gui:Hide() sA.TestAura:Hide() sA.TestAuraDual:Hide() end
		else 
			if gui:IsVisible() then gui:Hide() sA.TestAura:Hide() sA.TestAuraDual:Hide() else gui:Show() end
		end
		sA:RefreshAuraList()
		return
	end
	
	-- refresh command
	if cmd == "refresh" then
		local num = tonumber(val)
		if num and num >= 1 and num <= 10 then
			simpleAuras.refresh = num
			sA:Msg("Refresh set to " .. num .. " times per second")
		else
			sA:Msg("Usage: /sa refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)")
			sA:Msg("Current refresh = " .. tostring(simpleAuras.refresh) .. " times per second")
		end
		return
	end
	
	-- refresh command
	if cmd == "update" then
		local num = tonumber(val)
		if num and num >= 0 and num <= 1 then
			simpleAuras.updating = num
			sA:Msg("Aura durations update status set to " .. num)
		else
			sA:Msg("/sa update X - force aura durations updates (1 = learn aura durations. Default: 0)")
			sA:Msg("Current update status = " .. tostring(simpleAuras.updating))
		end
		return
	end
	
	-- manual learning of durations
	if cmd == "learn" then
		if sA.SuperWoW then
			local spell = tonumber(val)
			local fade = tonumber(fad)
			if spell and fade then
				simpleAuras.auradurations[spell] = fade
				sA:Msg("Set Duration of "..SpellInfo(spell).."("..spell..") to " .. fade .. " seconds.")
			else
				sA:Msg("/sa learn spellID Duration - manually set duration of spell.")
			end
		else
			sA:Msg("/sa learn needs SuperWoW to be installed!")
		end
		return
	end
	

	-- help or unknown command fallback
	sA:Msg("Usage:")
	sA:Msg("/sa or /sa show or /sa hide - Show/hide simpleAuras Settings")
	sA:Msg("/sa refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)")
	sA:Msg("/sa update X - force aura durations updates (1 = learn aura durations. Default: 0)")
	sA:Msg("/sa learn X Y - manually set duration Y for aura with ID X.")

end
