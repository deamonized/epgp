local mod = EPGP:NewModule("standings", "AceEvent-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

mod.dbDefaults = {
  profile = {
    enabled = true,
    sort_order = "PR",
    show_offline = true,
    show_raid_only = true,
  }
}

local standings

function mod:ShouldShow(i)
  local name = GetGuildRosterInfo(i)
  local online = select(8, GetGuildRosterInfo(i))
  if not self.db.profile.show_offline and not online then return false end
  if self.db.profile.show_raid_only and UnitInRaid("player") and not UnitInRaid(name) then return false end
  local info = EPGP:GetMemberInfo(name)
  if info and info.GetEP() then return true end
end

local function BuildStandings(self)
  standings = {}
  local totalMembers = GetNumGuildMembers()
  for i = 1, totalMembers do
    if self:ShouldShow(i) then
      local name = GetGuildRosterInfo(i)
      local info = EPGP:GetMemberInfo(name)
      -- Show all mains that have ep.
      table.insert(standings,
                   {info.GetClass(), info.GetName(),
                    info.GetEP(), info.GetGP(), info.GetPR()})
    end
  end
  EPGP:SortStandings(EPGP:StandingsSortOrder())
end
mod.GuildRosterUpdate = EPGP.Profile(
  BuildStandings, "Updating standings (GuildRosterUpdate)")
mod.BaseGPChanged = EPGP.Profile(
  BuildStandings, "Updating standings (BaseGPChanged)")

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
  "b[3] < EPGP:GetMinEP() and 0 or 1, a[3] < EPGP:GetMinEP() and 0 or 1"

local comparator = {
  NAME = BuildComparator(NAME_SEL),
  EP = BuildComparator(EP_SEL, NAME_SEL),
  GP = BuildComparator(GP_SEL, NAME_SEL),
  PR = BuildComparator(MIN_EP_SEL, PR_SEL, NAME_SEL),
}

function mod:OnModuleEnable()
  EPGP:GetModule("guild_notes").RegisterMessage(self, "GuildRosterUpdate")
  EPGP:GetModule("guild_info").RegisterMessage(self, "BaseGPChanged")
end

function mod:OnModuleDisable()
  EPGP:GetModule("guild_notes").UnregisterAllMessages(self)
  EPGP:GetModule("guild_info").UnregisterAllMessages(self)
end

--------------------------------------------------------------------------------
-- These functions change the core interface.

function EPGP:StandingsSortOrder()
  return mod.db.profile.sort_order
end

function EPGP:SortStandings(order)
  assert(comparator[order], "Unknown sort order")
  mod.db.profile.sort_order = order
  table.sort(standings, comparator[order])
  mod:SendMessage("StandingsUpdate")
end

function EPGP:GetNumStandingsMembers()
  return #standings
end

function EPGP:GetStandingsInfo(i)
  return unpack(standings[i])
end

function EPGP:GetStandingsShowOffline()
  return mod.db.profile.show_offline
end

function EPGP:SetStandingsShowOffline(v)
  mod.db.profile.show_offline = v
  BuildStandings(mod)
end

function EPGP:GetStandingsShowRaidOnly()
  return mod.db.profile.show_raid_only
end

function EPGP:SetStandingsShowRaidOnly(v)
  mod.db.profile.show_raid_only = v
  BuildStandings(mod)
end

function EPGP:CanAwardStandings(reason, delta_ep)
  return self:CanChangeEPGP(reason, delta_ep, 0)
end

function EPGP:AwardStandings(reason, delta_ep, raid_only, online_only)
  if raid_only == nil then raid_only = mod.db.profile.show_raid_only end
  if online_only == nil then online_only = not mod.db.profile.show_offline end
  local function ShouldAward(i)
    local name = GetGuildRosterInfo(i)
    local online = select(8, GetGuildRosterInfo(i))
    if raid_only and UnitInRaid("player") and not UnitInRaid(name) then return false end
    if online_only and offline then return false end
    if self:GetMemberInfo(name).GetMain() then return false end
    return true
  end
  local award_list = {}
  local totalMembers = GetNumGuildMembers()
  for i = 1, totalMembers do
    if ShouldAward(i) then
      local name = GetGuildRosterInfo(i)
      table.insert(award_list, name)
    end
  end
  self:ChangeEPGP(reason, delta_ep, 0, unpack(award_list))
end
