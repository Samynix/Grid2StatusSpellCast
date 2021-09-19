local CastTypeSpell = 'spell'
local CastTypeChannel = 'channel'

local TIMEOUT = 40 --Max time an indicator can be shown is 40 sec.

local StatusSpellCast = Grid2.statusPrototype:new("spell-cast", false) 
StatusSpellCast._eventFrame = CreateFrame("frame")
StatusSpellCast._isEnabled = false
StatusSpellCast._defaultDB = {
    interval = 0.1,
    special_spells = {
        -- [30128] = { extra_duration = 2 },
        -- [32938] = { extra_duration = 2 }
    },
    mode = "all",
    ignoredSpellList = {},
    selectedSpellList = {}
}

StatusSpellCast._active_indicators = {}
StatusSpellCast._player_guids_incoming_spells = {}
StatusSpellCast._npc_guids_outgoing_spells = {}

if (not StatusSpellCastDB) then
    StatusSpellCastDB = StatusSpellCast._defaultDB
end

StatusSpellCast.unit_ids = {
    "target", 
    "focus",
    "boss1", "boss2","boss3", "boss4","boss5", "boss6","boss7", "boss8","boss9", "boss10",
    "arena1", "arena2","arena3", "arena4","arena5", "arena6","arena7", "arena8","arena9", "arena10",
}

Grid2.setupFunc["spell-cast"] = function(baseKey, dbx)
	Grid2:RegisterStatus(StatusSpellCast, {"icon", "text"}, baseKey, dbx)
	return status
end
Grid2:DbSetStatusDefaultValue("spell-cast", {type = "spell-cast", color1 = {r=0,g=.6,b=1,a=.6}})

local prev_LoadOptions = Grid2.LoadOptions
function Grid2:LoadOptions()
    Grid2Options:RegisterStatusOptions("spell-cast", "combat", function(self, status, options)
        options.general = {
                type = "group",
                name = "General Settings",
                order = 1,
                args = {
                    {
                        type = "select",
                        name = "Mode",
                        order = 1,
                        values = {
                            ["all"] = "All spells",
                            ["all-but"] = "All spells but ignored",
                            ["none-but"] = "Only selected spells",
                        },
                        set = function(info, value)
                            StatusSpellCastDB["mode"] = value
                        end,
                        get = function()
                            return StatusSpellCastDB["mode"]
                        end,

                    },
                }
            }

        options.ignoredSpells = {
            type = "group",
            name = "Ignored spells",
            order = 2,
            args = {
                {
                    type = "input",
                    order = 50,
                    width = "full",
                    name = "Spells",
                    desc = "Spell names",
                    multiline= 20,
                    get = function()
                            local spells = {}
                            for _,spell in pairs(StatusSpellCastDB.ignoredSpellList) do
                                if spell then
                                    spells[#spells+1] = spell
                                end
                            end
                            return table.concat( spells, "\n" )
                    end,
                    set = function(_, v)
                        wipe(StatusSpellCastDB.ignoredSpellList)
                        local spells = { strsplit("\n,", v) }
                        for i,v in pairs(spells) do
                            local spell = strtrim(v)
                            if #spell>0 then
                                if spell then
                                    table.insert(StatusSpellCastDB.ignoredSpellList, spell)
                                end
                            end
                        end
                    end,
                }
            }
        }

        options.selectedSpells = {
            type = "group",
            name = "Selected spells",
            order = 3,
            args = {
                {
                    type = "input",
                    order = 50,
                    width = "full",
                    name = "Spells",
                    desc = "Spell names",
                    multiline= 20,
                    get = function()
                            local spells = {}
                            for _,spell in pairs(StatusSpellCastDB.selectedSpellList) do
                                if spell then
                                    spells[#spells+1] = spell
                                end
                            end
                            return table.concat( spells, "\n" )
                    end,
                    set = function(_, v)
                        wipe(StatusSpellCastDB.selectedSpellList)
                        local spells = { strsplit("\n,", v) }
                        for i,v in pairs(spells) do
                            local spell = strtrim(v)
                            if #spell>0 then
                                if spell then
                                    table.insert(StatusSpellCastDB.selectedSpellList, spell)
                                end
                            end
                        end
                    end,
                }
            }
        }
    end, 
    {
        hideTitle    = false,
        childGroups  = "tab",
        groupOrder   = 1,
        -- titleIcon    = Grid2.isClassic and "Interface\\Icons\\Ability_Creature_Cursed_05" or "Interface\\Icons\\Spell_Shadow_Skull",
    })


    prev_LoadOptions(self)
end


function StatusSpellCast:OnEnable()
	if not self._timer then
		self._timer = Grid2:CreateTimer(self.OnUpdate, StatusSpellCastDB.interval)
	end

    -- self._eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    -- self._eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    -- self._eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    self._eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self._eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self._eventFrame:RegisterEvent("PLAYER_DEAD")
    self._eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    
    self._eventFrame:SetScript("OnEvent", self.OnEvent)
	self._isEnabled = true
end

function StatusSpellCast:OnEvent(event, ...) 
    self = StatusSpellCast
    if event == "UNIT_SPELLCAST_START" then
        -- self:HandleCastStart(UnitCastingInfo, ...)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- self:HandleCastStart(UnitChannelInfo, ...)
    -- elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    --     self:HandleSpellCastAborted(...)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        self:HandleSpellCastAborted(...)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_DEAD" then
        self.ResetAllVariables()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        StatusSpellCast:CombatLogEvent(CombatLogGetCurrentEventInfo())
    end
end

function StatusSpellCast:CombatLogEvent(self, ...)
    -- print(...)
end

function StatusSpellCast:OnUpdate()
    self = StatusSpellCast

    currentTime = GetTime()
    self:DeactiveIndicatorsByTime(currentTime)

    --Nameplates
    for i=1, 40 do
        nameplate = "nameplate" .. tostring(i)
        if UnitExists(nameplate) then
            StatusSpellCast:HandleEnemeyUnit(nameplate)
        end
    end

    for i, unitId in pairs(StatusSpellCast.unit_ids) do
        if UnitExists(unitId) then
            StatusSpellCast:HandleEnemeyUnit(nameplate)
        end
    end
end

local function IsSpellRelevant(spellName)
    if (StatusSpellCastDB.mode == "all-but") then
        for _, spell in pairs(StatusSpellCastDB.ignoredSpellList) do
            if (spellName == spell) then
                return false
            end
        end

        return true
    elseif (StatusSpellCastDB.mode == "none-but") then
        for _, spell in pairs(StatusSpellCastDB.selectedSpellList) do
            if (spellName == spell) then
                return true
            end
        end

        return false
    end

    return true
end

function StatusSpellCast:HandleEnemeyUnit(unitId)
    unitInformation = self:GetSpellEventUnitInformation(unitId)
    if not unitInformation then
        return
    end

    if not UnitIsEnemy("player", unitId) then
        return false
    end

    castType = nil
    spell, text, icon, startTime, endTime, spellId = nil
    unitCastingInfo = {UnitCastingInfo(unitInformation.sourceUnitId)}
    if table.getn(unitCastingInfo) > 0 then
        spell, text, icon, startTime, endTime = unpack(unitCastingInfo)
        spellId = unitCastingInfo[8]
        castType = CastTypeSpell
    end

    if spell == nil then 
        unitChannelInfo = {UnitChannelInfo(unitInformation.sourceUnitId)}
        if table.getn(unitChannelInfo) > 0 then
            spell, text, icon, startTime, endTime = unpack(unitChannelInfo)
            spellId = unitChannelInfo[7]
            castType = CastTypeChannel
        end
    end
    
    if not spell or not IsSpellRelevant(spell) then
        return false
    end

    special_spell = StatusSpellCastDB.special_spells[spellId]
    extra_duration = special_spell and special_spell.extra_duration or 0

    self._active_indicators[unitInformation.destinationGuid] = {
        icon = icon,
        start = startTime/1000,
        duration = (endTime-startTime) / 1000 + (StatusSpellCastDB.interval/2) + extra_duration,
        ICON_TEX_COORDS,
        text = text,
        unitInformation = unitInformation,
        endTime = endTime/1000 + (StatusSpellCastDB.interval/2) + extra_duration,
        castType = castType,
        timeout = GetTime() + TIMEOUT
    }

    self._npc_guids_outgoing_spells[unitInformation.sourceGuid] = unitInformation
    self._player_guids_incoming_spells[unitInformation.destinationGuid] = unitInformation

    self:UpdateIndicators(unitInformation.getDestinationUnitId())
    return true
end

function StatusSpellCast:DeactiveIndicatorsByTime(currentTime)
    for unitGuid, indicatorData in pairs(self._active_indicators) do
        if (indicatorData.endTime <= currentTime or indicatorData.timeout <= currentTime) then
            self:ResetVariablesForIndicator(indicatorData.unitInformation)
        end
    end
end

function StatusSpellCast:GetSpellEventUnitInformation(sourceUnitId)
    local sourceTargetUnitId = sourceUnitId .. "target"
    
    local sourceGuid = UnitGUID(sourceUnitId)
    local destinationGuid = UnitGUID(sourceTargetUnitId)
    if (not Grid2:IsGUIDInRaid(destinationGuid)) then
        return nil
    end

    return {
        sourceGuid = sourceGuid,
        sourceUnitId = sourceUnitId, --Should not be used at a later timer, only on this tick, may change
        getDestinationUnitId = function() 
            local id = Grid2:IsGUIDInRaid(destinationGuid)
            return id
        end,
        destinationGuid = destinationGuid,
    }
end

function StatusSpellCast:HandleSpellCastAborted(unitId, castGuid, spellId)
    unitGuid = UnitGUID(unitId)
    if not self:IsHostileNpcUnit(unitGuid) then
        return
    end

    unitInformation = self._npc_guids_outgoing_spells[unitGuid]
    if not unitInformation then
        return
    end

    self:ResetVariablesForIndicator(unitInformation, true)
end

function StatusSpellCast:IsHostileNpcUnit(guid)
    return not Grid2:IsGUIDInRaid(guid)
end

function StatusSpellCast:ResetVariablesForIndicator(unitInformation)
    self._active_indicators[unitInformation.destinationGuid] = nil
    self._npc_guids_outgoing_spells[unitInformation.sourceGuid] = nil
    self._player_guids_incoming_spells[unitInformation.destinationGuid] = nil
    self:UpdateIndicators(unitInformation.getDestinationUnitId())
end

function StatusSpellCast:OnDisable()
	self._isEnabled = false
    self._eventFrame:UnregisterAllEvents()
    self:ResetAllVariables()
end

function StatusSpellCast:ResetAllVariables()
    StatusSpellCast._active_indicators = {}
    StatusSpellCast._player_guids_incoming_spells = {}
    StatusSpellCast._npc_guids_outgoing_spells = {}

    for guid, unitid in Grid2:IterateRosterUnits() do
        StatusSpellCast:UpdateIndicators(unitid)
    end
end

--Grid status indicator getters
function StatusSpellCast:IsActive(unitId)
    local guid = UnitGUID(unitId)
    if (not guid) then
        return nil
    end

	return self._active_indicators[guid] ~= nil
end

function StatusSpellCast:GetDuration(unitId)
    local guid = UnitGUID(unitId)
    if (not guid) then
        return nil
    end

	return self._active_indicators[guid].duration
end

function StatusSpellCast:GetExpirationTime(unitId)
    local guid = UnitGUID(unitId)
    if (not guid) then
        return nil
    end

	return self._active_indicators[guid].endTime
end

function StatusSpellCast:GetIcon(unitId)
    local guid = UnitGUID(unitId)
    if (not guid) then
        return nil
    end

	return self._active_indicators[guid].icon
end

function StatusSpellCast:GetText(unitId)
    local guid = UnitGUID(unitId)
    if (not guid) then
        return nil
    end

	return self._active_indicators[guid].text
end