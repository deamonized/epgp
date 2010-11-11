local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")
local AE = LibStub("AceEvent-3.0")

local standings

local function BuildStandings()
  debugprofilestart()
  if not EPGP.db then
    Debug("EPGP not fully loaded")
    return
  end

  standings = {}
  local totalMembers = GetNumGuildMembers()
  for i = 1, totalMembers do
    local name = GetGuildRosterInfo(i)
    local info = EPGP:GetMemberInfo(name)
    -- Show all mains that have ep.
    if info and info.GetMain() == nil and info.GetEP() ~= nil then
      table.insert(standings,
                   {info.GetClass(), info.GetName(),
                    info.GetEP(), info.GetGP(), info.GetEP() / info.GetGP()})
    end
  end
  Debug(tostring(debugprofilestop()).."ms for BuildStandings()")
  EPGP:SortStandings(EPGP:SortOrder())
end

function EPGP:GetNumStandingsMembers()
  return #standings
end

function EPGP:GetStandingsInfo(i)
  return unpack(standings[i])
end

-- TODO(alkis): Remove after testing.
function EPGP:GetStandings() return standings end

local function BuildComparator(...)
  local chunks = {}
  table.insert(chunks, "return function(a, b) local x, y")
  for i = 1, select('#', ...) do
    local chunk = [[
        x, y = ]] .. select(i, ...) .. [[
        if x ~= y then
          return x < y
        end
    ]]
    table.insert(chunks, chunk)
  end
  table.insert(chunks, "end")
  local code = table.concat(chunks, "\n")
  return assert(loadstring(code))()
end

local NAME_SEL = "a[2], b[2]"
local EP_SEL = "b[3], a[3]"
local GP_SEL = "b[4], a[4]"
local PR_SEL = "b[5], a[5]"
local MIN_EP_SEL =
  "b[3] < EPGP.db.profile.min_ep, a[3] < EPGP.db.profile.min_ep"

local comparator = {
  NAME = BuildComparator(NAME_SEL),
  EP = BuildComparator(EP_SEL, NAME_SEL),
  GP = BuildComparator(GP_SEL, NAME_SEL),
  PR = BuildComparator(MIN_EP_SEL, PR_SEL, NAME_SEL),
}

function EPGP:SortStandings(order)
  assert(comparator[order], "Unknown sort order")
  self.db.profile.sort_order = order
  table.sort(standings, comparator[order])
  self.callbacks:Fire("StandingsUpdate")
end

function EPGP:SortOrder()
  return self.db.profile.sort_order
end

AE:RegisterEvent("GUILD_ROSTER_UPDATE", BuildStandings)
EPGP:RegisterCallback("BaseGPChanged", BuildStandings)
