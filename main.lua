local io = require("io")
local lfs = require("lfs")
MODULE_FOLDER = lfs.writedir()..[[Scripts\syr-miz\]]
package.path = MODULE_FOLDER .. "?.lua;" .. package.path

local ctld_config = require("ctld_config")
local logging = require("logging")
local utils = require("utils")
-- local ground = require("ground")
local log = logging.Logger:new("main", "info")
trigger.action.setUserFlag("SSB", 100)

local slotblock = require("slotblock")

local BASE_FILE = lfs.writedir() .. "Scripts\\syr-miz\\syr_state.json"
local _STATE = {}
_STATE["bases"] = {}
_STATE["slots"] = {}
_STATE["scenery"] = {}
_STATE["ctld_units"] = {}
_STATE["hawks"] = {}
_STATE["dead"] = {}
local INIT = true
local DEBUG_DISPATCH_AA = false
local DEBUG_DISPATCH_AG = false
local DEBUG_IADS = false
local A2G_ACTIVE = true

ATIS = {}


local ContestedBases = {
  "Ramat David",
  "Aleppo",
  "Abu al-Duhur",
  "Hatay",
  "Haifa",
  -- "An Nasiriyah",
  "Bassel Al-Assad",
  "Beirut-Rafic Hariri",
  "Damascus",
  "Al Qusayr",
  "Hama"
}


local AG_BASES = {
  "Damascus",
  "Bassel Al-Assad",
  -- "An Nasiriyah",
  -- "Al Qusayr",
}


local sceneryTargets = {"damascus-target-1", "damascus-target-2", "damascus-target-3"}

local _NumAirbaseDefenders = 1

if utils.file_exists(BASE_FILE) then
  _STATE = utils.readState(BASE_FILE)
  if _STATE ~= nil then
    MESSAGE:New("State file found... restoring...", 5):ToAll()
    INIT = false
  end
else
  utils.log("No state file exists..")
end

local function enumerateCTLD()
  local CTLDstate = {}
  utils.log("Enumerating CTLD")
  for _groupname, _groupdetails in pairs(ctld.completeAASystems) do
      local CTLDsite = {}
      for k,v in pairs(_groupdetails) do
          CTLDsite[v['unit']] = v['point']
      end
      CTLDstate[_groupname] = CTLDsite
  end
  _STATE["hawks"] = CTLDstate
  utils.log("Done Enumerating CTLD")
end

ctld.addCallback(function(_args)
  if _args.action and _args.action == "unpack" then
      local name
      local groupname = _args.spawnedGroup:getName()

    if string.match(groupname, "Soldier stinger") then
        name = "stinger"
      else
        name = groupname:lower()
      end

      local coord = GROUP:FindByName(groupname):GetCoordinate()
      table.insert(_STATE["ctld_units"], {
              name=name,
              pos={x=coord.x, y=coord.y, z=coord.z}
          })

      enumerateCTLD()
      utils.saveTable(_STATE, BASE_FILE)
  end
end)


local function prune_enemies(Site, name)
  local countTotal=Site:Count()
  local sitesKeep = UTILS.Round(countTotal/100*70, 0)
  local sitesDestroy = countTotal - sitesKeep
  utils.log("Pruning from site " .. name..": "..tostring(sitesDestroy))
    for i = 1, sitesDestroy do
      local grpObj = Site:GetRandom()
      grpObj:Destroy(true)
    end
  utils.log("Total after prune: "..name.." - "..tostring(Site:Count()))
end

local function removeUnit (unitName)
  utils.log("Removing previously destroyed unit: "..unitName)
  local grp = GROUP:FindByName(unitName)
  if grp ~= nil then
    grp:Destroy()
  else
    local unit = UNIT:FindByName(unitName)
    if unit then
      unit:Destroy()
    end
  end
end

local function setBaseRed(baseName)
  utils.log("Setting "..baseName.." as red...")
  local logUnitName = "logistic-"..baseName
  local logZone = 'logizone-'..baseName
  ctld.deactivatePickupZone(logZone)
  utils.destroyIfExists(logUnitName, true)

  slotblock.configureSlotsForBase(baseName, "red")

  MESSAGE:New( baseName.." was captured by Red!", 5):ToAll()
end


local function setBaseBlue(baseName, startup)
  utils.log("Setting "..baseName.." as blue...")
  local logUnitName = "logistic-"..baseName
  local logZone = 'logizone-'..baseName
  local logisticCoordZone = ZONE:FindByName(logZone, false)
  if logisticCoordZone ~= nil then
    logisticCoordZone = ZONE_RADIUS:New(logZone, AIRBASE:FindByName(baseName):GetVec2(),1000)

    local logisticCoord = logisticCoordZone:GetPointVec2()
    local logisticUnit = SPAWNSTATIC:NewFromStatic("logisticBase", country.id.USA)
    logisticUnit:SpawnFromCoordinate(logisticCoord, 10, logUnitName)
    table.insert(ctld.logisticUnits, logUnitName)
    ctld.activatePickupZone(logZone)
    if logisticUnit == nil then
      utils.log("Could not find base logistic unit")
    end

  else
    MESSAGE:New("Trigger zone does not exist for "..logZone.."!", 5):ToAll()
  end

  slotblock.configureSlotsForBase(baseName, "blue")
  MESSAGE:New( baseName.." was captured by Blue!", 5):ToAll()

end


local SAMS = {}
SAMS["SA6sam"] = SET_GROUP:New():FilterPrefixes("SAM-SA6"):FilterActive(true):FilterOnce()
SAMS["SA2sam"] = SET_GROUP:New():FilterPrefixes("SAM-SA2"):FilterActive(true):FilterOnce()
SAMS["SA3sam"] = SET_GROUP:New():FilterPrefixes("SAM-SA3"):FilterActive(true):FilterOnce()
SAMS["SA10sam"] = SET_GROUP:New():FilterPrefixes("SAM-SA10"):FilterActive(true):FilterOnce()
SAMS["EWR"] = SET_GROUP:New():FilterPrefixes("EWR"):FilterActive(true):FilterStart()

if INIT then

  for k, sam in pairs(SAMS) do
    pcall(function(_args) prune_enemies(sam, k) end)
  end
else
  for _, unit in pairs(_STATE["dead"]) do
    removeUnit(unit)
  end

  for _, obj in pairs(_STATE["scenery"]) do
    if obj then
      local unit = Unit.getByName(tostring(obj.id))
      if unit then
        env.info("Destrying object: "..obj.id)
        unit:destroy()
      end
    end
    local vec3 = COORDINATE:New(obj.x, obj.y, obj.z)
    local searchZone = ZONE_RADIUS:New(tostring(i), vec3:GetVec2(), 1)
    searchZone:Scan( Object.Category.SCENERY )

    for SceneryTypeName, SceneryData in pairs( searchZone:GetScannedScenery() ) do
      for SceneryName, SceneryObject in pairs( SceneryData ) do
        local SceneryObject = SceneryObject
        env.info( "Scenery Destroyed: " .. SceneryObject:GetTypeName())
        SceneryObject:GetDCSObject():destroy()
        vec3:Explosion(200)
      end
    end
  end
end


utils.log("START: Spawning CTLD units from state")
local ctld_unitIndex = ctld_config.unit_index
for idx, data in ipairs(_STATE["ctld_units"]) do

    local coords2D = { x = data.pos.x, y = data.pos.z}
    local country = 2   --USA

    if data.name == 'mlrs' then
        local key = "M270_Index"
        utils.init_ctld_units(ctld_config.unit_config["MLRS M270"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'M-109' then
        local key = "M109_Index"
        utils.init_ctld_units(ctld_config.unit_config["M109 Paladin"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'abrams' then
        local key = "M1A1_Index"
        utils.init_ctld_units(ctld_config.unit_config["M1A1 Abrams"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'jtac' then
        local key = "JTAC_Index"
        local _spawnedGroup = utils.init_ctld_units(ctld_config.unit_config["HMMWV JTAC"], coords2D, country, ctld_unitIndex, key)

        local _code = table.remove(ctld.jtacGeneratedLaserCodes, 1)
        table.insert(ctld.jtacGeneratedLaserCodes, _code)
        ctld.JTACAutoLase(_spawnedGroup:getName(), _code)
    end

    if data.name == 'ammo' then
        local key = "M818_Index"
        utils.init_ctld_units(ctld_config.unit_config["M818 Transport"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'stinger' then
      local key = "Stinger_Index"
      utils.init_ctld_units(ctld_config.unit_config["Stinger"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'gepard' then
        local key = "Gepard_Index"
        utils.init_ctld_units(ctld_config.unit_config["Flugabwehrkanonenpanzer Gepard"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'vulcan' then
        local key = "Vulcan_Index"
        utils.init_ctld_units(ctld_config.unit_config["M163 Vulcan"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'avenger' then
        local key = "Avenger_Index"
        utils.init_ctld_units(ctld_config.unit_config["M1097 Avenger"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'chaparral' then
        local key = "Chaparral_Index"
        utils.init_ctld_units(ctld_config.unit_config["M48 Chaparral"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'roland' then
        local key = "Roland_Index"
        utils.init_ctld_units(ctld_config.unit_config["Roland ADS"], coords2D, country, ctld_unitIndex, key)
    end

    if data.name == 'ipv' then
      local key = "IPV_Index"
      utils.init_ctld_units(ctld_config.unit_config["IPV LAV-25"], coords2D, country, ctld_unitIndex, key)
  end
end

if  _STATE["hawks"] ~= nil then
    for k,v in pairs( _STATE["hawks"]) do
        utils.respawnHAWKFromState(v)
    end
end


-- For reach numbered group, for each airbase,
-- Attempt to find the group, destroying it if the airbase is blue, and activating it
--  if the base is red.
for _, base in pairs(ContestedBases) do
  local base_obj = AIRBASE:FindByName(base)
  if base_obj == nil then
    MESSAGE:New("Invalid airbase name in main.lua: " .. base, 5):ToCoalition( coalition.side.BLUE )
  end

  if INIT or _STATE.bases[base] == nil then
    _STATE.bases[base] = base_obj:GetCoalition()
  end
  if _STATE.bases[base] == coalition.side.BLUE then
    setBaseBlue(base)
  else
    setBaseRed(base)
    for i=1,_NumAirbaseDefenders do
      local grp_name = "defenseBase-"..base.."-"..tostring(i)
      local zone_base = ZONE_AIRBASE:New(base, 150):GetRandomPointVec2()
      local baseDef = SPAWN:NewWithAlias( "defenseBase", grp_name )
      local is_valid = false
      local tries = 0
      local despawn = true
      while is_valid == false and tries < 5 do
        local units = baseDef:SpawnFromPointVec2(zone_base)
        if tries == 4 then
          despawn = false
        end
        if base_obj:CheckOnRunWay(units, 10, despawn) == false then
          is_valid = true
        end
        tries = tries + 1
      end
    end
  end
end


redIADS = SkynetIADS:create('SYRIA')
if DEBUG_IADS then
  local iadsDebug = redIADS:getDebugSettings()
  iadsDebug.IADSStatus = true
  iadsDebug.samWentDark = false
  iadsDebug.contacts = true
  iadsDebug.radarWentLive = true
  iadsDebug.noWorkingCommmandCenter = true
  iadsDebug.ewRadarNoConnection = true
  iadsDebug.addedEWRadar = true
  redIADS:addRadioMenu()
end


commandCenter1 = StaticObject.getByName('RED-HQ-2')
redIADS:addCommandCenter(commandCenter1)
redIADS:setUpdateInterval(15)
redIADS:addEarlyWarningRadarsByPrefix('EWR')
redIADS:addEarlyWarningRadarsByPrefix("redAWACS")
redIADS:addSAMSitesByPrefix('SAM')
redIADS:getSAMSites():setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(80)
redIADS:getSAMSitesByPrefix("SA-10"):setActAsEW(true)
redIADS:setupSAMSitesAndThenActivate()

DetectionSetGroup = SET_GROUP:New():FilterPrefixes({"EWR", "redAWACS", "defenseBase-"}):FilterCoalitions("red"):FilterActive(true):FilterStart()
Detection = DETECTION_AREAS:New( DetectionSetGroup, 30000 )
BorderZone = ZONE_POLYGON:New( "RED-BORDER", GROUP:FindByName( "red-border" ) )

redCommand = COMMANDCENTER:New( GROUP:FindByName( "REDHQ" ), "REDHQ" )

A2ADispatcher = AI_A2A_DISPATCHER:New( Detection )
A2ADispatcher:SetBorderZone( BorderZone )
A2ADispatcher:SetCommandCenter(redCommand)
A2ADispatcher:SetEngageRadius()
A2ADispatcher:SetGciRadius()
A2ADispatcher:SetIntercept( 10 )

if A2G_ACTIVE then
  DetectionSetGroup_G = SET_GROUP:New():FilterPrefixes({"redAWACS", "mark-redtank", "defenseBase-"}):FilterCoalitions("red"):FilterActive(true):FilterStart()
  Detection_G = DETECTION_AREAS:New( DetectionSetGroup_G, 1000 )
  A2GDispatcher = AI_A2G_DISPATCHER:New( Detection_G )
  A2GDispatcher:AddDefenseCoordinate( "ag-base", AIRBASE:FindByName( "Damascus" ):GetCoordinate() )
  A2GDispatcher:SetDefenseReactivityHigh()
  A2GDispatcher:SetDefenseRadius( 200000 )
  A2GDispatcher:SetCommandCenter(redCommand)
end


-- SetCargoInfantry = SET_CARGO:New():FilterTypes( "InfantryType" ):FilterStart()
-- SetAPC = SET_GROUP:New():FilterPrefixes( "red-apc-convoy" ):FilterStart()
-- SetHeli = SET_GROUP:New():FilterPrefixes( "red-helos" ):FilterStart()
-- SetDeployZones = SET_ZONE:New()
-- SetPickupZones = SET_ZONE:New():FilterPrefixes( "redpickup" ):FilterStart()

-- AICargoDispatcherAPC = AI_CARGO_DISPATCHER_APC:New( SetAPC, SetCargoInfantry, SetPickupZones, SetDeployZones)
-- AICargoDispatcherAPC:Start()

-- AICargoDispatcherHelicopter = AI_CARGO_DISPATCHER_HELICOPTER:New(SetHeli, SetCargoInfantry, SetPickupZones, SetDeployZones)
-- AICargoDispatcherHelicopter:Start()


for _, base in pairs(ContestedBases) do
  local base_obj = AIRBASE:FindByName(base)

  if _STATE.bases[base] == coalition.side.RED then
    local zone_name = base.."-capzone"
    local zone = ZONE:FindByName(zone_name)
    if zone == nil then
      zone = ZONE_AIRBASE:New(base, 150000)
      zone:SetName(zone_name)
    end

    local sqd = base.."-cap"
    local sqd_gci = base.."-gci"
    local sqdName = { "su-30-cap", "mig-31-cap", "jf-17-cap" }

    if GROUP:FindByName(sqd) ~= nil then
      utils.log("Creating a2a group: "..base)

      A2ADispatcher:SetSquadron( sqd, base, sqdName ) --, 10)
      A2ADispatcher:SetSquadronGrouping( sqd, 2 )
      A2ADispatcher:SetSquadronTakeoffFromParkingHot(sqd)
      A2ADispatcher:SetSquadronLandingNearAirbase( sqd )
      A2ADispatcher:SetSquadronCap( sqd, zone, 10000, 25000, 500, 800, 600, 1200, "BARO")
      A2ADispatcher:SetSquadronCapInterval( sqd, 1, 60*2, 60*10, 1)
      A2ADispatcher:SetSquadronCapRacetrack(sqd, 10000, 20000, 90, 180, 5*60, 10*60)

      A2ADispatcher:SetSquadron( sqd_gci, base, {"su-30-gci"} )
      A2ADispatcher:SetSquadronGrouping( sqd_gci, 1 )
      A2ADispatcher:SetSquadronTakeoffFromParkingCold(sqd_gci)
      A2ADispatcher:SetSquadronGci( sqd_gci, 600, 900 )

    else
      env.info("Could not spawn red a2a group: "..sqd.."!")
    end

    if A2G_ACTIVE then
      for _, agBase in pairs(AG_BASES) do
        if agBase == base then
          local cas_zone = ZONE_AIRBASE:New(base, 10000)

          -- local sqd_cas = base.."-cas"
          -- A2GDispatcher:SetSquadron(sqd_cas, base,  { "ka-50-cas" }, 4 )
          -- A2GDispatcher:SetSquadronGrouping( sqd_cas, 1 )
          -- A2GDispatcher:SetSquadronCasPatrol(sqd_cas, cas_zone) --,  300, 500, 50, 80, 250, 300 )
          -- A2GDispatcher:SetSquadronCasPatrolInterval( sqd_cas, 2, 120, 600, 1 )
          -- A2GDispatcher:SetSquadronOverhead(sqd_cas, 0.15)
          -- -- A2GDispatcher:SetDefaultPatrolTimeInterval(180)
          -- A2GDispatcher:SetDefaultTakeoffInAir( sqd_cas )
          -- A2GDispatcher:SetSquadronLandingNearAirbase( sqd_cas )

          local sqd_sead = base.."-sead"
          A2GDispatcher:SetSquadron(sqd_sead, base,  { "jf-17-sead" }, 4 )
          A2GDispatcher:SetSquadronGrouping( sqd_sead, 2 )
          A2GDispatcher:SetSquadronSead(sqd_sead, 400, 1200, 10000, 30000)
          A2GDispatcher:SetSquadronOverhead(sqd_sead, 0.15)
          A2GDispatcher:SetDefaultTakeoffFromParkingHot( sqd_sead )
          -- A2GDispatcher:SetDefaultTakeoffInAir( sqd_sead )
          -- A2GDispatcher:SetDefaultTakeoffInAirAltitude(5000)
          A2GDispatcher:SetSquadronLandingAtRunway( sqd_sead )

          local sqd_bai = base.."-bai"
          A2GDispatcher:SetSquadron(sqd_bai, base,  { "su-34-cas" }, 4 )
          A2GDispatcher:SetSquadronGrouping( sqd_bai, 2 )
          A2GDispatcher:SetSquadronSead(sqd_bai, 400, 1200, 5000, 30000)
          A2GDispatcher:SetSquadronOverhead(sqd_bai, 0.15)
          A2GDispatcher:SetDefaultTakeoffFromParkingHot( sqd_bai )
          -- A2GDispatcher:SetDefaultTakeoffInAir( sqd_bai )
          -- A2GDispatcher:SetDefaultTakeoffInAirAltitude(5000)
          A2GDispatcher:SetSquadronLandingAtRunway( sqd_bai )

        end
      end
    end
  end
  utils.saveTable(_STATE, BASE_FILE)
end

A2ADispatcher:Start()

if A2G_ACTIVE then
  A2GDispatcher:Start()
end

local function ShowStatus(  )
  for i, name in pairs(sceneryTargets) do
    local Zone = ZONE:New( name )
    Zone:Scan( Object.Category.SCENERY )
    for SceneryTypeName, SceneryData in pairs( Zone:GetScannedScenery() ) do
      for SceneryName, SceneryObject in pairs( SceneryData ) do
        local SceneryObject = SceneryObject
        MESSAGE:NewType( "Targets: " .. SceneryObject:GetTypeName() .. ", Coord LL DMS: " .. SceneryObject:GetCoordinate():ToStringLLDMS(),
          MESSAGE.Type.Information ):ToAll()
      end
    end
  end
end


local function ToggleDebugAA(  )
  if DEBUG_DISPATCH_AA then
    DEBUG_DISPATCH_AA = false
  else
    DEBUG_DISPATCH_AA = true
  end
  A2ADispatcher:SetTacticalDisplay(DEBUG_DISPATCH_AA)
end

local function ToggleDebugAG(  )
  if DEBUG_DISPATCH_AG then
    DEBUG_DISPATCH_AG = false
  else
    DEBUG_DISPATCH_AG = true
  end
  A2GDispatcher:SetTacticalDisplay(DEBUG_DISPATCH_AG)
end

local MenuCoalitionBlue = MENU_COALITION:New( coalition.side.BLUE, "Mission Data" )
MENU_COALITION_COMMAND:New( coalition.side.BLUE, "Show Objectives", MenuCoalitionBlue, ShowStatus )

local MenuCoalitionRed = MENU_COALITION:New( coalition.side.RED, "Mission Data" )
MENU_COALITION_COMMAND:New( coalition.side.RED, "Toggle AA Debug", MenuCoalitionRed, ToggleDebugAA )
MENU_COALITION_COMMAND:New( coalition.side.RED, "Toggle AG Debug", MenuCoalitionRed, ToggleDebugAG )

local num_tanks = 1
local num_sams = 1
local n_hawks = 1
local num_redtanks = 1
local n_apc_convoys = 1

EH1 = EVENTHANDLER:New()
EH1:HandleEvent(EVENTS.MarkRemoved)
function EH1:OnEventMarkRemoved(EventData)

  if EventData.text == "tgt" then
    EventData.MarkCoordinate:Explosion(1000)

  elseif EventData.text == 'blue-ground' then
    SPAWN:NewWithAlias("blue-ground", "blue-ground-"):SpawnFromCoordinate(EventData.MarkCoordinate)

  elseif EventData.text == 'tank' then
    SPAWN:NewWithAlias("tank-base", "mark-tank-"..tostring(num_tanks)):SpawnFromCoordinate(EventData.MarkCoordinate)
    num_tanks = num_tanks + 1

  elseif EventData.text == 'redtank' then
    SPAWN:NewWithAlias("redtank-base", "mark-redtank-"..tostring(num_redtanks)):SpawnFromCoordinate(EventData.MarkCoordinate)
    utils.info(DetectionSetGroup_G:Flush())
    num_redtanks = num_redtanks + 1

  elseif EventData.text == 'rapier' then
    SPAWN:NewWithAlias("rapier-base", "mark-rapier-"..tostring(num_sams)):SpawnFromCoordinate(EventData.MarkCoordinate)
    num_sams = num_sams + 1

  elseif EventData.text == 'hawk' then
    SPAWN:NewWithAlias("hawk-base", "mark-hawk-"..tostring(n_hawks)):SpawnFromCoordinate(EventData.MarkCoordinate)
    n_hawks = n_hawks + 1

  elseif EventData.text == 'farp' then
    SPAWNSTATIC:NewFromStatic("farp-static"):SpawnFromCoordinate(EventData.MarkCoordinate)

  elseif EventData.text == 'red-convoy' then
    SPAWN:NewWithAlias("red-apc-convoy", "red-apc-convoy-"..tostring(n_apc_convoys)):SpawnFromCoordinate(EventData.MarkCoordinate)
    n_apc_convoys = n_apc_convoys + 1
  end

end

EH1:HandleEvent(EVENTS.BaseCaptured)
function EH1:OnEventBaseCaptured(EventData)
  if _STATE.bases[EventData.PlaceName] == EventData.IniCoalition then
    return
  end
  _STATE.bases[EventData.PlaceName] = EventData.IniCoalition
  if EventData.IniCoalition == coalition.side.RED then
    setBaseRed(EventData.PlaceName)
  else
    setBaseBlue(EventData.PlaceName)
    ground.initRedGroundBaseAttack("Damascus",  EventData.PlaceName)
    utils.log(SetDeployZones:Flush())

  end
  utils.saveTable(_STATE, BASE_FILE)
end


EH1:HandleEvent(EVENTS.Dead)
function EH1:OnEventDead(EventData)
  if EventData.IniCoalition == coalition.side.RED then
    if EventData.IniGroupName ~= nil then
      utils.log("Marking object dead: "..EventData.IniGroupName.." - "..EventData.IniUnitName)
    end
    if _STATE["dead"] == nil then
      _STATE["dead"] = { EventData.IniUnitName }
    else
      table.insert(_STATE["dead"], EventData.IniUnitName)
    end
  end


  if EventData.IniUnit and EventData.IniObjectCategory==Object.Category.SCENERY then
    if EventData.IniUnitName ~= nil then
      local Scenery_Point = EventData.initiator:getPoint()
      local Scenery_Coordinate = COORDINATE:NewFromVec3(Scenery_Point)
      local insdata = { x=Scenery_Coordinate.x, y=Scenery_Coordinate.y, z=Scenery_Coordinate.z, id=EventData.IniDCSUnit }
      if _STATE["scenery"] then
        table.insert(_STATE["scenery"], insdata)
      else
        _STATE["scenery"] = insdata
      end
    end
    for id, name in pairs(sceneryTargets) do
      if EventData.IniUnitName ~= nil and EventData.IniUnitName == id then
        MESSAGE:New(name.." Destoyed!").ToAll()
        table.remove(sceneryTargets, id)
      end
    end
  end
  utils.saveTable(_STATE, BASE_FILE)
end
