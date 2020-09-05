
local module_folder = lfs.writedir()..[[Scripts\syr-miz\]]
package.path = module_folder .. "?.lua;" .. package.path
local io = require("io")
local lfs = require("lfs")
local utils = dofile(lfs.writedir() .. "Scripts\\syr-miz\\utils.lua")

local BASE_FILE = lfs.writedir() .. "Scripts\\syr-miz\\state.json"
local _BASES = {}
local INIT = true
local ContestedBases = { "Aleppo", "Taftanaz", "Abu al-Duhur",
                         "Hatay", "Haifa", "Ramat David",
                         "Bassel Al-Assad", "Beirut-Rafic Hariri",
                         "Damascus" }
local _NumAirbaseDefenders = 1

if utils.file_exists(BASE_FILE) then
  _BASES = utils.readState(BASE_FILE)
  if _BASES ~= nil then
      INIT = false
  end
else
  env.info("No base file exists..")
end


local function prune_enemies(Site, name)
  local countTotal=Site:Count()
  local sitesKeep = UTILS.Round(countTotal/100*50, 0)
  local sitesDestroy = countTotal - sitesKeep
  env.info("Pruning from site " .. name..": "..tostring(sitesDestroy))
    for i = 1, sitesDestroy do
      local grpObj = Site:GetRandom()
      grpObj:Destroy(true)
    end
  env.info("Total after prune: "..name.." - "..tostring(Site:Count()))
end



local function destroyIfExists(grp_name, is_static)
  if is_static then
    local grp = STATIC:FindByName(grp_name, false)
  else
    local grp = GROUP:FindByName(grp_name, false)
  end
  if grp ~= nil then
    env.info('Destroying Object ' .. grp_name)
    grp:Destroy()
  else
    env.info("Object does not exist: " .. grp_name)
  end
end



local function setBaseRed(baseName)
  env.info("Setting "..baseName.." as red...")
  local logUnitName = "logistic-"..baseName
  local logZone = 'logizone-'..baseName
  destroyIfExists(logUnitName, true)
  MESSAGE:NewType( baseName.." was captured by Red!",
                   MESSAGE.Type.Information ):ToAll()
end


local function setBaseBlue(baseName, startup)
  env.info("Setting "..baseName.." as blue...")
  local logUnitName = "logistic-"..baseName
  local logZone = 'logizone-'..baseName
  local logisticCoordZone = ZONE:FindByName(logZone, false)
  if logisticCoordZone == nil then
    env.info("Zone does not exist for "..logZone..". Creating one...")
    logisticCoordZone = ZONE_RADIUS:New(logZone, AIRBASE:FindByName(baseName):GetVec2(),1000)
    -- logisticCoordZone = ZONE:FindByName(logZone)
  end
  local logisticCoord = logisticCoordZone:GetPointVec2()
  local logisticUnit = SPAWNSTATIC:NewFromStatic("logisticBase", country.id.USA)
  if logisticUnit == nil then
    env.info("Could not find base logistic unit")
  end
  logisticUnit:SpawnFromCoordinate(logisticCoord, 10, logUnitName)
  table.insert(ctld.logisticUnits, logUnitName)
  -- table.insert(ctld.dropOffZones, {logZone, "blue", 2})
  -- table.insert(ctld.pickupZones, { logZone, "blue", -1, "yes", 2 })
  ctld.activatePickupZone(logZone)
  MESSAGE:NewType( baseName.." was captured by Blue!",
                    MESSAGE.Type.Information ):ToAll()
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
end

-- For reach numbered group, for each airbase,
-- Attempt to find the group, destroying it if the airbase is blue, and activating it
--  if the base is red.

for _, base in pairs(ContestedBases) do
  local base_obj = AIRBASE:FindByName(base)
  _BASES[base] = base_obj:GetCoalition()
  if base_obj == nil then
    MESSAGE:New("Invalid airbase name in main.lua: " .. base, 25):ToCoalition( coalition.side.BLUE )
  end

  if base_obj:GetCoalition() == coalition.side.BLUE then
    setBaseBlue(base)
  else
    setBaseRed(base)
    for i=1,_NumAirbaseDefenders do
      local grp_name = base.."-"..tostring(i)
      env.info("Initializing group " .. grp_name)
      local zone_base = ZONE_AIRBASE:New(base, 150):GetRandomPointVec2()
      local baseDef = SPAWN:NewWithAlias( "defenseBase", grp_name )
      baseDef:SpawnFromPointVec2(zone_base)
    end
  end

  base_obj:HandleEvent(EVENTS.BaseCaptured)
  function base_obj:OnEventBaseCaptured(EventData)
    _BASES[EventData.PlaceName] = EventData.IniCoalition
    if EventData.IniCoalition == coalition.side.RED then
      setBaseRed(EventData.PlaceName)
    else
      setBaseBlue(EventData.PlaceName)
    end
    utils.saveTable(_BASES, BASE_FILE)
  end
  utils.saveTable(_BASES, BASE_FILE)
end


redIADS = SkynetIADS:create('SYRIA')
redIADS:setUpdateInterval(15)
redIADS:addEarlyWarningRadarsByPrefix('EWR')
redIADS:addSAMSitesByPrefix('SAM')
redIADS:getSAMSitesByNatoName('SA-2'):setGoLiveRangeInPercent(70)
redIADS:getSAMSitesByNatoName('SA-3'):setGoLiveRangeInPercent(70)
redIADS:getSAMSitesByNatoName('SA-10'):setGoLiveRangeInPercent(70)
redIADS:activate()

-- Define a SET_GROUP object that builds a collection of groups that define the EWR network.
DetectionSetGroup = SET_GROUP:New()
DetectionSetGroup:FilterPrefixes("EWR")
DetectionSetGroup:FilterStart()
-- Setup the detection and group targets to a 30km range!
Detection = DETECTION_AREAS:New( DetectionSetGroup, 10000 )
A2ADispatcher = AI_A2A_DISPATCHER:New( Detection )
A2ADispatcher:SetEngageRadius(180000) -- 100000 is the default value.
A2ADispatcher:SetGciRadius(100000) -- 200000 is the default value.
A2ADispatcher:SetDefaultTakeoffFromParkingCold()
A2ADispatcher:SetDefaultLandingAtEngineShutdown()
BorderZone = ZONE_POLYGON:New( "RED-BORDER", GROUP:FindByName( "SyAF-GCI" ) )
A2ADispatcher:SetBorderZone( BorderZone )
--SQNs
A2ADispatcher:SetSquadron( "54 Squadron", "Marj Ruhayyil", { "54 Squadron" }, 2 ) --mig23
A2ADispatcher:SetSquadronGrouping( "54 Squadron", 2 )
A2ADispatcher:SetSquadronGci( "54 Squadron", 900, 1200 )

A2ADispatcher:SetSquadron( "698 Squadron", "Al-Dumayr", { "698 Squadron" }, 2 ) --mig29a
A2ADispatcher:SetSquadronGrouping( "698 Squadron", 2 )
A2ADispatcher:SetSquadronGci( "698 Squadron", 900, 1200 )

A2ADispatcher:SetSquadron( "695 Squadron", "An Nasiriyah", { "695 Squadron" }, 2 ) --mig23
A2ADispatcher:SetSquadronGrouping( "695 Squadron", 2 )
A2ADispatcher:SetSquadronGci( "695 Squadron", 900, 1200 )

-- A2ADispatcher:SetSquadron( "Beirut-Squadron", "Beirut-Rafic Hariri", { "Beirut-Squadron" }, 2 ) --Su-30
-- A2ADispatcher:SetSquadronGrouping( "Beirut-Squadron", 2 )
-- A2ADispatcher:SetSquadronGci( "Beirut-Squadron", 900, 1200 )

A2ADispatcher:SetSquadron( "Russia GCI", "Bassel Al-Assad", { "Russia GCI" }, 2 ) --su30
A2ADispatcher:SetSquadronGrouping( "Russia GCI", 2 )
A2ADispatcher:SetSquadronGci( "Russia GCI", 900, 1200 )

--A2ADispatcher:SetTacticalDisplay(true)
A2ADispatcher:Start()

-- add the MOOSE SET_GROUP to the IADS
--redIADS:addMooseSetGroup(DetectionSetGroup)

local Zone={}
Zone.Alpha   = ZONE:New("Aleppo")
Zone.Bravo   = ZONE:New("Golan")
local AllZones=SET_ZONE:New():FilterOnce()

SCHEDULER:New( nil, function()
  local mission=AUFTRAG:NewCAS(Zone.Alpha)
  local fg=FLIGHTGROUP:New("2 Squadron-4")
  fg:AddMission(mission)

  local mission=AUFTRAG:NewCAS(Zone.Alpha)
  local fg=FLIGHTGROUP:New("turkishCAS")
  fg:AddMission(mission)

  local mission=AUFTRAG:NewCAS(Zone.Bravo)
  local fg=FLIGHTGROUP:New("976 Squadron AI")
  fg:AddMission(mission)
end, {},4, 900, .8)

SCHEDULER:New( nil, function()
  local mission=AUFTRAG:NewCAS(Zone.Alpha)
  local fg=FLIGHTGROUP:New("825 Squadron-7")
  fg:AddMission(mission)

  local mission=AUFTRAG:NewCAS(Zone.Alpha)
  local fg=FLIGHTGROUP:New("Warthog-6")
  fg:AddMission(mission)

  local mission=AUFTRAG:NewCAS(Zone.Bravo)
  local fg=FLIGHTGROUP:New("767 Squadron")
  fg:AddMission(mission)
end, {},300, 900, .8)



-- env.info("Configuring markpoint destroyer...")
EH1 = EVENTHANDLER:New()
EH1:HandleEvent(EVENTS.MarkRemoved)

function EH1:OnEventMarkRemoved(EventData)
  env.info("Mark removed...")
  if EventData.text == "tgt" then
    EventData.MarkCoordinate:Explosion(5400)
  else
    env.info("Not a target mark...")
  end
end
