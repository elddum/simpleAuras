-- Perf: cache globals
local floor, format = math.floor, string.format
local getn = table.getn
local unpack = unpack

-- Parent frame
local sAParent = CreateFrame("Frame", "sAParentFrame", UIParent)
sAParent:SetFrameStrata("BACKGROUND")
sAParent:SetAllPoints(UIParent)

-------------------------------------------------
-- Cooldown info by spell name
-------------------------------------------------
function sA:GetCooldownInfo(spellName)
  local i = 1
  while true do
    local name = GetSpellName(i, "spell")
    if not name then break end

    if name == spellName then
      local start, duration, enabled = GetSpellCooldown(i, "spell")
      local texture = GetSpellTexture(i, "spell")

      local remaining
      if enabled == 1 and duration and duration > 1.5 then
        remaining = (start + duration) - GetTime()
        if remaining <= 0 then remaining = nil end
      end

      return texture, remaining, 0
    end
    i = i + 1
  end
end

-------------------------------------------------
-- SuperWoW-aware aura search
-------------------------------------------------
local function find_aura(name, unit, auratype)
  local function search(is_debuff)
    local i = (unit == "Player") and 0 or 1
    while true do
      local tex, stacks, sid, rem
      if unit == "Player" then
        local buffType = is_debuff and "HARMFUL" or "HELPFUL"
        local bid = GetPlayerBuff(i, buffType)
        tex, stacks, sid, rem = GetPlayerBuffTexture(bid), GetPlayerBuffApplications(bid), GetPlayerBuffID(bid), GetPlayerBuffTimeLeft(bid)
      else
        if is_debuff then
          tex, stacks, _, sid, rem = UnitDebuff(unit, i)
        else
          tex, stacks, sid, rem = UnitBuff(unit, i)
        end
      end

      if not tex then break end
      if sid and name == SpellInfo(sid) then
        return true, stacks, sid, rem, tex
      end
      i = i + 1
    end
    return false
  end

  local was_found, s, sid, rem, tex
  if auratype == "Buff" then
	was_found, s, sid, rem, tex = search(false)
  else
	was_found, s, sid, rem, tex = search(true)
	if not was_found then
		was_found, s, sid, rem, tex = search(false)
	end
  end
  
  return was_found, s, sid, rem, tex
end

-------------------------------------------------
-- Get Icon / Duration / Stacks (SuperWoW)
-------------------------------------------------
function sA:GetSuperAuraInfos(name, unit, auratype)
  if auratype == "Cooldown" then
    local texture, remaining_time = self:GetCooldownInfo(name)
    return texture, remaining_time, 1
  end

  local found, stacks, spellID, remaining_time, texture = find_aura(name, unit, auratype)
  if not found then return end

  -- Fallback for missing remaining_time
  if (not remaining_time or remaining_time == 0) and spellID and sA.auraTimers then
    local _, unitGUID = UnitExists(unit)
    if unitGUID then
      unitGUID = gsub(unitGUID, "^0x", "")
      local timers = sA.auraTimers[unitGUID]
      if timers and timers[spellID] then
        local expiry = timers[spellID]
        remaining_time = (expiry > GetTime()) and (expiry - GetTime()) or 0
      end
    end
  end
  return texture, remaining_time, stacks
end

-------------------------------------------------
-- Tooltip-based aura info (no SuperWoW)
-------------------------------------------------
function sA:GetAuraInfos(auraname, unit, auratype)
  if auratype == "Cooldown" then
    local texture, remaining_time = self:GetCooldownInfo(auraname)
    return texture, remaining_time, 1
  end

  if not sAScanner then
    sAScanner = CreateFrame("GameTooltip", "sAScanner", sAParent, "GameTooltipTemplate")
    sAScanner:SetOwner(sAParent, "ANCHOR_NONE")
  end

  local function AuraInfo(unit, index, kind)
    sAScanner:ClearLines()

    local name, icon, duration, stacks
    if unit == "Player" then
      local buffindex = GetPlayerBuff(index - 1, (kind == "Buff") and "HELPFUL" or "HARMFUL")
      sAScanner:SetPlayerBuff(buffindex)
      icon, duration, stacks = GetPlayerBuffTexture(buffindex), GetPlayerBuffTimeLeft(buffindex), GetPlayerBuffApplications(buffindex)
    else
      if kind == "Buff" then
        sAScanner:SetUnitBuff(unit, index)
        icon = UnitBuff(unit, index)
      else
        sAScanner:SetUnitDebuff(unit, index)
        icon = UnitDebuff(unit, index)
      end
      duration = 0
    end
    name = sAScannerTextLeft1:GetText()
    return name, icon, duration, stacks
  end

  local i = 1
  while true do
    local name, icon, duration, stacks = AuraInfo(unit, i, auratype)
    if not name then break end
    if name == auraname then
      return icon, duration, stacks
    end
    i = i + 1
  end
end

-------------------------------------------------
-- Frame creation helpers
-------------------------------------------------
local FONT = "Fonts\\FRIZQT__.TTF"

local function CreateAuraFrame(id)
  local f = CreateFrame("Frame", "sAAura" .. id, UIParent)
  f:SetFrameStrata("BACKGROUND")

  f.texture = f:CreateTexture(nil, "BACKGROUND")
  f.texture:SetAllPoints(f)

  f.durationtext = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.durationtext:SetFont(FONT, 12, "OUTLINE")
  f.durationtext:SetPoint("CENTER", f, "CENTER", 0, 0)

  f.stackstext = f:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  f.stackstext:SetFont(FONT, 10, "OUTLINE")
  f.stackstext:SetPoint("TOPLEFT", f.durationtext, "CENTER", 1, -6)

  return f
end

local function CreateDualFrame(id)
  local f = CreateAuraFrame(id)
  f.texture:SetTexCoord(1, 0, 0, 1)
  f.stackstext:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  return f
end

-------------------------------------------------
-- Update aura display
-------------------------------------------------
function sA:UpdateAuras()
  -- hide test/editor when not editing
  if not (gui and gui.editor and gui.editor:IsVisible()) then
    if sA.TestAura     then sA.TestAura:Hide() end
    if sA.TestAuraDual then sA.TestAuraDual:Hide() end
    if gui and gui.editor then gui.editor:Hide(); gui.editor = nil end
  end

  for id, aura in ipairs(simpleAuras.auras) do
    local show, icon, duration, stacks
    local currentDuration, currentStacks, currentDurationtext = 600, 20, ""

    -- only process if aura is enabled
    if aura.name ~= "" and ((aura.inCombat == 1 and sAinCombat) or (aura.outCombat == 1 and not sAinCombat)) then
      if sA.SuperWoW then
        icon, duration, stacks = self:GetSuperAuraInfos(aura.name, aura.unit, aura.type)
      else
        icon, duration, stacks = self:GetAuraInfos(aura.name, aura.unit, aura.type)
      end       

      if icon then
        show, currentDuration, currentStacks = 1, duration, stacks
        if aura.autodetect == 1 and aura.texture ~= icon then
          aura.texture, simpleAuras.auras[id].texture = icon, icon
        end
      end

      if aura.type == "Cooldown" then
        show = ((aura.invert == 1 and not currentDuration) or (aura.dual == 1 and currentDuration)) and 1 or 0
      elseif aura.invert == 1 then
        show = 1 - (show or 0)
      end
    end

    local frame     = self.frames[id]     or CreateAuraFrame(id)
    local dualframe = self.dualframes[id] or (aura.dual == 1 and CreateDualFrame(id))
    self.frames[id] = frame
    if aura.dual == 1 and aura.type ~= "Cooldown" then self.dualframes[id] = dualframe end

    if (show == 1 or (gui and gui:IsVisible())) and not (gui and gui.editor and gui.editor:IsVisible()) then
      -------------------------------------------------
      -- Duration text
      -------------------------------------------------
      if aura.duration == 1 and currentDuration then
        if currentDuration > 100 then
          currentDurationtext = floor(currentDuration / 60 + 0.5) .. "m"
        elseif currentDuration <= (aura.lowdurationvalue or 5) then
          currentDurationtext = format("%.1f", floor(currentDuration * 10 + 0.5) / 10)
        else
          currentDurationtext = floor(currentDuration + 0.5)
        end
      end

      if currentDurationtext == "0.0" then
        currentDurationtext = 0
      elseif currentDurationtext == "0" then
        currentDurationtext = "learning..."
      end

      -------------------------------------------------
      -- Apply visuals
      -------------------------------------------------
      local scale = aura.scale or 1
      frame:SetPoint("CENTER", UIParent, "CENTER", aura.xpos or 0, aura.ypos or 0)
      frame:SetFrameLevel(128 - id)
      frame:SetWidth(48 * scale)
	  frame:SetHeight(48 * scale)
      frame.texture:SetTexture(aura.texture)
      frame.durationtext:SetText((aura.duration == 1 and (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown")) and currentDurationtext or "")
      frame.stackstext:SetText((aura.stacks == 1) and currentStacks or "")
      if aura.duration == 1 then frame.durationtext:SetFont(FONT, 20 * scale, "OUTLINE") end
      if aura.stacks   == 1 then frame.stackstext:SetFont(FONT, 14 * scale, "OUTLINE") end

      local color = (aura.lowduration == 1 and currentDuration and currentDuration <= aura.lowdurationvalue)
        and (aura.lowdurationcolor or {1, 0, 0, 1})
        or  (aura.auracolor or {1, 1, 1, 1})

      local r, g, b, alpha = unpack(color)
      if aura.type == "Cooldown" and currentDuration then
        frame.texture:SetVertexColor(r * 0.5, g * 0.5, b * 0.5, alpha)
      else
        frame.texture:SetVertexColor(r, g, b, alpha)
      end

      local durationcolor = {1.0, 0.82, 0.0, alpha}
      local stackcolor    = {1, 1, 1, alpha}
      if (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown") and (currentDuration and currentDuration <= (aura.lowdurationvalue or 5)) then
        durationcolor = {1, 0, 0, alpha}
      end
      frame.durationtext:SetTextColor(unpack(durationcolor))
      frame.stackstext:SetTextColor(unpack(stackcolor))

      if aura.type == "Cooldown" and not icon then 
        frame:Hide()
      else
        frame:Show()
      end

      -------------------------------------------------
      -- Dual frame
      -------------------------------------------------
      if aura.dual == 1 and aura.type ~= "Cooldown" and dualframe then
        dualframe:SetPoint("CENTER", UIParent, "CENTER", -(aura.xpos or 0), aura.ypos or 0)
        dualframe:SetFrameLevel(128 - id)
        dualframe:SetWidth(48 * scale)
		dualframe:SetHeight(48 * scale)
        dualframe.texture:SetTexture(aura.texture)
        if aura.type == "Cooldown" and currentDuration then
          dualframe.texture:SetVertexColor(r * 0.5, g * 0.5, b * 0.5, alpha)
        else
          dualframe.texture:SetVertexColor(r, g, b, alpha)
        end
        dualframe.durationtext:SetText((aura.duration == 1 and (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown")) and currentDurationtext or "")
        dualframe.stackstext:SetText((aura.stacks == 1) and currentStacks or "")
        if aura.duration == 1 then dualframe.durationtext:SetFont(FONT, 20 * scale, "OUTLINE") end
        if aura.stacks   == 1 then dualframe.stackstext:SetFont(FONT, 14 * scale, "OUTLINE") end
        dualframe.durationtext:SetTextColor(unpack(durationcolor))
        dualframe:Show()
        if aura.type == "Cooldown" and not icon then 
          dualframe:Hide()
        else 
          dualframe:Show()
        end
      elseif dualframe then
        dualframe:Hide()
      end
    else
      if frame     then frame:Hide()     end
      if dualframe then dualframe:Hide() end
    end
  end
  
end
