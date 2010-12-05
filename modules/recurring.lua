local mod = EPGP:NewModule("recurring", "AceEvent-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

mod.dbDefaults = {
  profile = {
    enabled = true,
    period_mins = 1,
    next = {}
  }
}

local GetTimestamp = EPGP.GetTimestamp

local handle

--------------------------------------------------------------------------------
function mod:Tick()
  EPGP:AwardStandings(self.db.profile.reason,
                      self.db.profile.amount,
                      self.db.profile.raid_only,
                      self.db.profile.online_only)
  mod.db.profile.next.timestamp = GetTimestamp() + self:TimeLeft(handle)
end

--------------------------------------------------------------------------------
-- These functions change the core interface.

function EPGP:StartRecurringAward(reason, raid_only, online_only)
  local amount = mod.db.profile.period_mins  -- 1 EP per min.
  assert(self:CanAwardStandings(reason, amount))
  assert(not handle)

  if raid_only == nil then raid_only = self:GetStandingsShowRaidOnly() end
  if online_only == nil then online_only = not self:GetStandingsShowOffline() end
  mod.db.profile.next.reason = reason
  mod.db.profile.next.amount = amount
  mod.db.profile.next.raid_only = raid_only
  mod.db.profile.next.online_only = online_only
  mod.db.profile.next.period_secs = mod.db.profile.period_mins * 60

  local period_secs = mod.db.profile.next.period_secs
  handle = mod:ScheduleRepeatingTimer("Tick", period_secs)
  mod.db.profile.next.timestamp = GetTimestamp() + period_secs
end

function EPGP:StopRecurringAward()
  assert(handle)
  mod:CancelTimer(handle)
  handle = nil
  mod.db.profile.next = {}
end

function EPGP:IsRecurringAwardRunning()
  return not not handle
end

function EPGP:GetRecurringAwardPeriodMinutes()
  return mod.db.profile.period_mins
end

function EPGP:SetRecurringAwardPeriodMinutes(period_mins)
  mod.db.profile.period_mins = period_mins
end

function EPGP:GetRecurringAwardTimeLeft()
  return mod:TimeLeft(handle)
end
