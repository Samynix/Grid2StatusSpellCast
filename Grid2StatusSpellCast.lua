local StatusSpellCast = Grid2.statusPrototype:new("incoming-spell-damage", false) 
StatusSpellCast._eventFrame = CreateFrame("frame")
StatusSpellCast._isEnabled = false
StatusSpellCast.troll = "fisk"
StatusSpellCast._defaultDB = {
    interval = 0.1,
}

StatusSpellCast._active_indicators = {}
StatusSpellCast._cast_indicator_mappings = {}

StatusSpellCast.db = {}
StatusSpellCast.db.profile = StatusSpellCast._defaultDB

Grid2.setupFunc["incoming-spell-damage"] = function(baseKey, dbx)
	Grid2:RegisterStatus(StatusSpellCast, {"icon", "text"}, baseKey, dbx)
	return StatusSpellCast
end
Grid2:DbSetStatusDefaultValue("incoming-spell-damage", {type = "incoming-spell-damage", color1 = {r=0,g=.6,b=1,a=.6}})


function StatusSpellCast:OnEnable()
	if not self._timer then
		self._timer = Grid2:CreateTimer(self.OnUpdate, self.db.profile.interval)
	end

    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    
    self._eventFrame:SetScript("OnEvent", self.OnEvent)
	self._isEnabled = true
end

function StatusSpellCast:OnUpdate()
    self = StatusSpellCast

    currentTime = GetTime()
    self:DeactiveIndicatorsByTime(currentTime)
end

function StatusSpellCast:DeactiveIndicatorsByTime(currentTime)
    for unitId, indicatorData in pairs(self._active_indicators) do
        if (indicatorData.endTime <= currentTime) then
            self._active_indicators[unitId] = nil

            self:ResetVariablesForIndicator(indicatorData.unitInformation)
            self:UpdateIndicators(unitId)
        end
    end
end

function StatusSpellCast:OnEvent(event, ...) 
    self = StatusSpellCast

    if event == "UNIT_SPELLCAST_START" then
        self:HandleCastStart(UnitCastingInfo, ...)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        self:HandleCastStart(UnitChannelInfo, ...)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        self:HandleSpellCastAborted(...)
    end
end


function StatusSpellCast:HandleCastStart(castInfoFunction, unitId, castGuid, spellId)
    unitInformation = self:GetSpellEventUnitInformation(unitId)
    if not unitInformation then
        return
    end

    if self._active_indicators[unitInformation.destinationUnitId] then
        return
    end

    if not self:IsHostileNpcUnit(unitInformation.sourceGuid) then
        return
    end

    spell, text, icon, startTime, endTime = castInfoFunction(unitInformation.sourceUnitId)
    self._active_indicators[unitInformation.destinationUnitId] = {
        icon = icon,
        start = startTime/1000,
        duration = (endTime-startTime) / 1000 + (self.db.profile.interval/2),
        ICON_TEX_COORDS,
        text = text,
        unitInformation = unitInformation,
        endTime = endTime/1000 + (self.db.profile.interval/2)
    }

    self._cast_indicator_mappings[unitInformation.sourceGuid] = unitInformation
    self._cast_indicator_mappings[unitInformation.destinationGuid] = unitInformation

    self:UpdateIndicators(unitInformation.destinationUnitId)
end

function StatusSpellCast:GetSpellEventUnitInformation(sourceUnitId)
    local sourceTargetUnitId = sourceUnitId .. "target"
    
    local sourceGuid = UnitGUID(sourceUnitId)
    local destinationGuid = UnitGUID(sourceTargetUnitId)
    local destinationUnitId = Grid2:IsGUIDInRaid(destinationGuid)
    if (not destinationUnitId) then
        return nil
    end

    return {
        sourceGuid = sourceGuid,
        sourceUnitId = sourceUnitId,
        destinationUnitId = destinationUnitId,
        destinationGuid = destinationGuid,
    }
end

function StatusSpellCast:HandleSpellCastAborted(unitId, castGuid, spellId)
    unitGuid = UnitGUID(unitId)
    if not self:IsHostileNpcUnit(unitGuid) then
        return
    end

    unitInformation = self._cast_indicator_mappings[unitGuid]
    if not unitInformation then
        return
    end

    self:ResetVariablesForIndicator(unitInformation)
    self:UpdateIndicators(unitInformation.destinationUnitId)
end

function StatusSpellCast:IsHostileNpcUnit(guid)
    return not Grid2:IsGUIDInRaid(guid)
end

function StatusSpellCast:ResetVariablesForIndicator(unitInformation)
    self._active_indicators[unitInformation.destinationUnitId] = nil
    self._cast_indicator_mappings[unitInformation.sourceGuid] = nil
    self._cast_indicator_mappings[unitInformation.destinationGuid] = nil
end

function StatusSpellCast:OnDisable()
	self._isEnabled = false
    self._eventFrame:UnregisterAllEvents()
    self:ResetAllVariables()
end

function StatusSpellCast:ResetAllVariables()

end

--Grid status indicator getters
function StatusSpellCast:IsActive(unitId)
	return self._active_indicators[unitId] ~= nil
end

function StatusSpellCast:GetDuration(unitId)
	return self._active_indicators[unitId].duration
end

function StatusSpellCast:GetExpirationTime(unitId)
	return self._active_indicators[unitId].endTime
end

function StatusSpellCast:GetIcon(unitId)
	return self._active_indicators[unitId].icon
end

function StatusSpellCast:GetText(unitId)
	return self._active_indicators[unitId].text
end