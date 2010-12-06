local mod = EPGP:NewModule("version", "AceComm-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

local MapT = EPGP.MapT

local function ParseVersion(v)
  local x, y, z = v:match("(%d+)%.(%d+)%.(%d+)")
  if x then return MapT(tonumber, {x, y, z}) end
  x, y = v:match("(%d+)%.(%d+)")
  if x then return MapT(tonumber, {x, y, 0}) end
  return {0, 0, 0}
end

local function CompareVersions(v1, v2)
  for i,v in ipairs(v1) do
    if v < v2[i] then return -1 end
    if v > v2[i] then return 1 end
  end
  return 0
end

function mod:ProcessVersionCheck(prefix, msg, type, sender)
  Debug("Received version check for version %s (%s)", msg, sender)

  local version = ParseVersion(msg)
  local my_version = ParseVersion(EPGP.version)
  local comp = CompareVersions(my_version, version)
  if comp == -1 then
    Debug("Our version is outdated %s (%s)", EPGP.version, msg)
    EPGP:Disable()
    StaticPopup_Show("EPGP_OLD_VERSION", EPGP.version, msg)
  elseif comp == 1 then
    Debug("%s's version is outdated %s (%s)", sender, msg, EPGP.version)
    -- TODO(alkis): Might want to add some jitter to avoid flooding
    -- the remote (outdated) client.
    self:SendCommMessage(EPGP.VERSION_CHECK, EPGP.version,
                         "WHISPER", sender, "BULK")
  end
end

--------------------------------------------------------------------------------

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.VERSION_CHECK, "ProcessVersionCheck")
  self:SendCommMessage(EPGP.VERSION_CHECK, EPGP.version, "GUILD", nil, "BULK")
end

--------------------------------------------------------------------------------
