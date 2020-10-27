local SHARDINDEX_VERSION = 2

ShardIndex = Class(function(self)
    self.ismaster = false
    self.slot = nil
    self.shard = nil
    self.version = SHARDINDEX_VERSION

    self.world = {options = {}}
    self.server = {}
    self.session_id = nil
    self.enabled_mods = {}
end)

function ShardIndex:GetShardIndexName()
    return "shardindex"
end

function ShardIndex:Save(callback)
    if not self.invalid and (self.isdirty or TheNet:GetIsServer()) then
        local data = DataDumper({
            world = self.world,
            server = self.server,
            session_id = self.session_id,
            enabled_mods = self.enabled_mods,
            version = self.version,
        }, nil, false)

        local filename = self:GetShardIndexName()
        if self.slot and self.shard then
            TheSim:SetPersistentStringInClusterSlot(self.slot, self.shard, filename, data, false, callback)
        else
            TheSim:SetPersistentString(filename, data, false, callback)
        end
        self.isdirty = false
        return
    end
    if callback then
        callback()
    end
end

function ShardIndex:WriteTimeFile(callback)
    local data = DataDumper(os.time(), nil, false)
    local filename = self:GetShardIndexName().."_time"
    if self.slot and self.shard then
        TheSim:SetPersistentStringInClusterSlot(self.slot, self.shard, filename, data, false, callback)
    else
        TheSim:SetPersistentString(filename, data, false, callback)
    end
end

local function UpgradeShardIndexData(self)
    local savefileupgrades = require "savefileupgrades"
    local upgraded = false
    
    if self.version == nil or self.version == 1 then
        savefileupgrades.utilities.UpgradeShardIndexFromV1toV2(self)
        upgraded = true
    end
    
    return upgraded
end

local function OnLoad(self, slot, shard, callback, str)
    local success, savedata = RunInSandbox(str)

    -- If we are on steam cloud this will stop a corrupt saveindex file from
    -- ruining everyone's day..
    if success and string.len(str) > 0 and type(savedata) == "table" then
        self.slot = slot
        self.shard = shard
        self.ismaster = shard == "Master"
        self.valid = true
        self.isdirty = false

        self.world = savedata.world
        self.server = savedata.server
        self.session_id = savedata.session_id
        self.enabled_mods = savedata.enabled_mods
        self.version = savedata.version

        local was_upgraded = false
        if self.version ~= SHARDINDEX_VERSION then
            was_upgraded = UpgradeShardIndexData(self)
        end

        local filename = self:GetShardIndexName()
        if was_upgraded then
            print("Saving upgraded "..filename)
            self:Save()
        end
    elseif TheNet:IsDedicated() then
        self.slot = slot
        self.shard = shard
        self.ismaster = false
        self.valid = true
        self.isdirty = true

        if SaveGameIndex and SaveGameIndex.loaded_from_file then
            local savefileupgrades = require "savefileupgrades"
            savefileupgrades.utilities.ConvertSaveSlotToShardIndex(SaveGameIndex, SaveGameIndex.current_slot, self)

            self:Save()
        else
            self.world = {options = {}}
            self.server = {}
            self.session_id = nil
            self.enabled_mods = {}
        end
    else
        self.ismaster = false
        self.slot = nil
        self.shard = nil
        self.valid = false
        self.isdirty = false
    
        self.world = {options = {}}
        self.server = {}
        self.session_id = nil
        self.enabled_mods = {}
    end

    if callback ~= nil then
        callback()
    end
end

function ShardIndex:Load(callback)
    --dedicated servers are never invalid
    --non servers are always invalid
    --client hosted servers must define the Settings.save_slot to be valid
    
    if TheNet:IsDedicated() then
        TheSim:GetPersistentString(self:GetShardIndexName(),
            function(load_success, str)
                --slot 0 isn't inside a Cluster_XX folder, instead its the (client_)save/ folder
                OnLoad(self, 0, nil, callback, str)
            end)
        return
    elseif TheNet:GetServerIsClientHosted() and Settings.save_slot then
        self:LoadShardInSlot(Settings.save_slot, "Master", callback)
        return
    end

    self.invalid = true
    if callback ~= nil then
        callback()
    end
end

function ShardIndex:LoadShardInSlot(slot, shard, callback)
    TheSim:GetPersistentStringInClusterSlot(slot, shard, self:GetShardIndexName(),
        function(load_success, str)
            OnLoad(self, slot, shard, callback, str)
        end)
end

local function OnLoadSaveDataFile(file, cb, load_success, str)
    if not load_success then
        if TheNet:GetIsClient() then
            assert(load_success, "ShardIndex:GetSaveData: Load failed for file ["..file.."] Please try joining again.")
        else
            assert(load_success, "ShardIndex:GetSaveData: Load failed for file ["..file.."] please consider deleting this save slot and trying again.")
        end
    end
    assert(str, "ShardIndex:GetSaveData: Encoded Savedata is NIL on load ["..file.."]")
    assert(#str > 0, "ShardIndex:GetSaveData: Encoded Savedata is empty on load ["..file.."]")

    print("Loading world: "..file)
    local success, savedata = RunInSandbox(str)

    assert(success, "Corrupt Save file ["..file.."]")
    assert(savedata, "ShardIndex:GetSaveData: Savedata is NIL on load ["..file.."]")
    assert(GetTableSize(savedata) > 0, "ShardIndex:GetSaveData: Savedata is empty on load ["..file.."]")

    cb(savedata)
end

function ShardIndex:GetSaveDataFile(file, cb)
    TheSim:GetPersistentString(file, function(load_success, str)
        OnLoadSaveDataFile(file, cb, load_success, str)
    end)
end

function ShardIndex:GetSaveData(cb)
    local session_id = self:GetSession()

    if not TheNet:IsDedicated() and not self:GetServerData().use_legacy_session_path then
        local slot = self:GetSlot()
        local file = TheNet:GetWorldSessionFileInClusterSlot(slot, "Master", session_id)
        if file ~= nil then
            TheSim:GetPersistentStringInClusterSlot(slot, "Master", file, function(load_success, str)
                OnLoadSaveDataFile(file, cb, load_success, str)
            end)
        elseif cb ~= nil then
            cb()
        end
    else
        local file = TheNet:GetWorldSessionFile(session_id)
        if file ~= nil then
            self:GetSaveDataFile(file, cb)
        elseif cb ~= nil then
            cb()
        end
    end
end

function ShardIndex:IsMasterShardIndex()
    return self.ismaster
end

function ShardIndex:GetSlot()
    return self.slot
end

function ShardIndex:GetShard()
    return self.shard
end

function ShardIndex:NewShardInSlot(slot, shard)
    self.slot = slot
    self.shard = shard
    self.ismaster = shard == "Master"
    self.valid = true
    self.isdirty = true

    self.world = {options = {}}
    self.server = {}
    self.session_id = nil
    self.enabled_mods = {}
end

local function ResetSlotData(self)
    self.world = {options = {}}
    self.server = {}
    self.session_id = nil
    self.enabled_mods = {}
end

function ShardIndex:Delete(cb, save_options)
    local server = self:GetServerData()
    local options = self:GetGenOptions()
    local enabled_mods = self:GetEnabledServerMods()

    local session_id = self:GetSession()
    if session_id ~= nil and session_id ~= "" then
        TheNet:DeleteSession(session_id)
    end

    ResetSlotData(self)

    if save_options then
        self.server = server
        self.world.options = options
        self.enabled_mods = enabled_mods
        self:Save(cb)
        return
    else
        self.invalid = true
    end

    if cb ~= nil then
        cb()
    end
end

--isshutdown means players have been cleaned up by OnDespawn()
--and the sim will shutdown after saving
function ShardIndex:SaveCurrent(onsavedcb, isshutdown)
    -- Only servers save games in DST
    if TheNet:GetIsClient() then
        return
    end

    known_assert(TheSim:HasEnoughFreeDiskSpace(), "CONFIG_DIR_DISK_SPACE")

    assert(TheWorld ~= nil, "missing world?")

    self.session_id = TheNet:GetSessionIdentifier()

    SaveGame(isshutdown, onsavedcb)
end

function ShardIndex:OnGenerateNewWorld(savedata, metadataStr, session_identifier, cb)
    local function onsavedatasaved()
        self.session_id = session_identifier
        self.server.encode_user_path = TheNet:TryDefaultEncodeUserPath()

        self:Save(cb)
    end

    SerializeWorldSession(savedata, session_identifier, onsavedatasaved, metadataStr)
end

local function GetLevelDataOverride(slot, shard, cb)
    local filename = "../leveldataoverride.lua"

    local function onload(load_success, str)
        if load_success == true then
            local success, savedata = RunInSandboxSafe(str)
            if success and string.len(str) > 0 then
                print("Found a level data override file with these contents:")
                dumptable(savedata)
                if savedata ~= nil then
                    print("Loaded and applied level data override from "..filename)
                    assert(savedata.id ~= nil
                        and savedata.name ~= nil
                        and savedata.desc ~= nil
                        and savedata.location ~= nil
                        and savedata.overrides ~= nil, "Level data override is invalid!")

                    cb(savedata)
                    return
                end
            else
                print("ERROR: Failed to load "..filename)
            end
        end
        print("Not applying level data overrides.")
        cb(nil, nil)
    end

    if shard ~= nil then
        TheSim:GetPersistentStringInClusterSlot(slot, shard, filename, onload)
    else
        TheSim:GetPersistentString(filename, onload)
    end
end

local function SanityCheckWorldGenOverride(wgo)
    print("  sanity-checking worldgenoverride.lua...")
    local validfields = {
        overrides = true,
        preset = true,
        override_enabled = true,
    }
    for k,v in pairs(wgo) do
        if validfields[k] == nil then
            print(string.format("    WARNING! Found entry '%s' in worldgenoverride.lua, but this isn't a valid entry.", k))
        end
    end

    local optionlookup = {}
    local Customise = require("map/customise")
    for i,option in ipairs(Customise.GetOptions(nil, true)) do
        optionlookup[option.name] = {}
        for i,value in ipairs(option.options) do
            table.insert(optionlookup[option.name], value.data)
        end
    end

    if wgo.overrides ~= nil then
        for k,v in pairs(wgo.overrides) do
            if optionlookup[k] == nil then
                print(string.format("    WARNING! Found override '%s', but this doesn't match any known option. Did you make a typo?", k))
            else
                if not table.contains(optionlookup[k], v) then
                    print(string.format("    WARNING! Found value '%s' for setting '%s', but this is not a valid value. Use one of {%s}.", v, k, table.concat(optionlookup[k], ", ")))
                end
            end
        end
    end
end

local function GetWorldgenOverride(slot, shard, cb)
    local filename = "../worldgenoverride.lua"

    local function onload(load_success, str)
        if load_success == true then
            local success, savedata = RunInSandboxSafe(str)
            if success and string.len(str) > 0 then
                print("Found a worldgen override file with these contents:")
                dumptable(savedata)

                if savedata ~= nil then

                    -- gjans: Added upgrade path 28/03/2016. Because this is softer and user editable, will probably have to leave this one in longer than the other upgrades from this same change set.
                    local savefileupgrades = require("savefileupgrades")
                    savedata = savefileupgrades.utilities.UpgradeWorldgenoverrideFromV1toV2(savedata)

                    SanityCheckWorldGenOverride(savedata)

                    if savedata.override_enabled then
                        print("Loaded and applied world gen overrides from "..filename)
                        savedata.override_enabled = nil -- Only part of worldgenoverride, not standard level definition.

                        local presetdata = nil
                        local frompreset = false
                        if savedata.preset ~= nil then
                            print("  contained preset "..savedata.preset..", loading...")
                            local Levels = require("map/levels")
                            presetdata = Levels.GetDataForLevelID(savedata.preset)
                            if presetdata ~= nil then
                                if GetTableSize(savedata) > 0 then
                                    print("  applying overrides to preset...")
                                    presetdata = MergeMapsDeep(presetdata, savedata)
                                end
                                frompreset = true
                            else
                                print("Worldgenoverride specified a nonexistent preset: "..savedata.preset..". If this is a custom preset, it may not exist in this save location. Ignoring it and applying overrides.")
                                presetdata = savedata
                            end
                            savedata.preset = nil -- Only part of worldgenoverride, not standard level definition.
                        else
                            presetdata = savedata
                        end

                        presetdata.override_enabled = nil
                        presetdata.preset = nil

                        cb( presetdata, frompreset )
                        return
                    else
                        print("Found world gen overrides but not enabled.")
                    end
                end
            else
                print("ERROR: Failed to load "..filename)
            end
        end
        print("Not applying world gen overrides.")
        cb(nil, nil)
    end

    if shard ~= nil then
        TheSim:GetPersistentStringInClusterSlot(slot, shard, filename, onload)
    else
        TheSim:GetPersistentString(filename, onload)
    end
end

local function GetDefaultWorldOptions(level_type)
    local Levels = require "map/levels"
    return Levels.GetDefaultLevelData(level_type, nil)
end

function ShardIndex:SetServerShardData(customoptions, serverdata, onsavedcb)
    local session_identifier = TheNet:GetSessionIdentifier()
    self.session_id = session_identifier ~= "" and session_identifier or self.session_id
    self.server = serverdata
    self.enabled_mods = KnownModIndex:LoadModOverides(self)

    self:MarkDirty()
    -- gjans:
    -- leveldataoverride is for GAME USE. It contains a _complete level definition_ and is used by the clusters to transfer level settings reliably from the client to the cluster servers. It completely overrides existing saved world data.
    -- worldgenoverride is for USER USE. It contains optionally:
    --   a) a preset name. If present, this preset will be loaded and completely override existing save data, including the above. (Note, this is not reliable between client and cluster, but users can do this if they please.)
    --   b) a partial list of overrides that are layered on top of whatever savedata we have at this point now.
    local slot = self:GetSlot()
    local shard = self:GetShard()
    GetLevelDataOverride(slot, shard, function(leveldata)
        if leveldata ~= nil then
            print("Overwriting savedata with level data file.")
            self.world.options = leveldata
        else
            local defaultoptions = GetDefaultWorldOptions(GetLevelType(serverdata.game_mode or DEFAULT_GAME_MODE))
            self.world.options = (customoptions ~= nil and not IsTableEmpty(customoptions) and customoptions) or defaultoptions
            if self.world.options.overrides == nil or IsTableEmpty(self.world.options.overrides) then
                self.world.options.overrides = defaultoptions.overrides
            end
        end

        GetWorldgenOverride(slot, shard, function(overridedata, frompreset)
            if overridedata ~= nil then
                if frompreset == true then
                    print("Overwriting savedata with override file.")
                    self.world.options = overridedata
                else
                    print("Merging override file into savedata.")
                    self.world.options = MergeMapsDeep(self.world.options, overridedata)
                end
            end

            self:Save(onsavedcb)
        end)
    end)
end

function ShardIndex:CheckWorldFile()
    local session_id = self:GetSession()
    return session_id ~= nil and TheNet:GetWorldSessionFile(session_id) ~= nil
end

function ShardIndex:MarkDirty()
    self.isdirty = true
end

function ShardIndex:IsValid()
    return self.valid
end

function ShardIndex:IsEmpty()
    return self.session_id == nil or self.session_id == ""
end

function ShardIndex:GetServerData()
    return self.server or {}
end

function ShardIndex:GetGenOptions()
    return self.world.options
end

function ShardIndex:GetSession()
    return self.session_id
end

function ShardIndex:GetGameMode()
    return self.server.game_mode or DEFAULT_GAME_MODE
end

function ShardIndex:GetEnabledServerMods()
    return self.ismaster and self.enabled_mods or {}
end

function ShardIndex:LoadEnabledServerMods()
    if not self.ismaster then return end
    
    ModManager:DisableAllServerMods()
    for modname, mod_data in pairs(self.enabled_mods) do
        if mod_data.enabled then
            KnownModIndex:Enable(modname)
        end

        local config_options = mod_data.config_data or mod_data.configuration_options or {} --config_data is the legacy format
        for option_name,value in pairs(config_options) do
            KnownModIndex:SetConfigurationOption(modname, option_name, value)
        end
        KnownModIndex:SaveHostConfiguration(modname)
    end
end

--Used in FE only, used so that we can save changes made to the server creation screen without having to save the world
function ShardIndex:SetEnabledServerMods(enabled_mods)
    if not self.ismaster then return end
    self.enabled_mods = enabled_mods
    self:MarkDirty()
end

function ShardIndex:SetServerData(serverdata)
    if not self.ismaster then return end
    self.server = serverdata
    self:MarkDirty()
end

function ShardIndex:SetGenOptions(options)
    if not self.ismaster then return end
    self.world.options = options
    self:MarkDirty()
end