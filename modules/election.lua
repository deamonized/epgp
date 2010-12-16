local mod = EPGP:NewModule("election",
                           "AceComm-3.0", "AceEvent-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")

local PERIOD = 30
local TIMEOUT = 10

local master = nil
local timeout_handle = nil

mod.dbDefaults = {
  profile = {
    enabled = true,
  }
}

local function InfoLess(a, b)
  if a.GetRankIndex() ~= b.GetRankIndex() then
    return a.GetRankIndex() < b.GetRankIndex()
  end
  return a.GetName() < b.GetName()
end

function mod:DoElection()
  if not CanEditOfficerNote() then return end

  self:SendCommMessage(EPGP.MASTER_ELECTION, "", GUILD, nil, "ALERT")
  timeout_handle = self:ScheduleTimer(
    function()
      self:SendCommMessage(EPGP.MASTER_VICTORY, "", GUILD, nil, "ALERT")
    end,
    TIMEOUT)
  Debug("Election started")
end

function mod:ProcessMasterElection(prefix, msg, type, sender)
  Debug("Received election request for %s to become master", sender)
  local me = UnitName("player")
  if master == me then
    local info = EPGP:GetMemberInfo(sender)
    local my_info = EPGP:GetMemberInfo(me)
    if InfoLess(info, my_info) then
      master = nil
      self:SendMessage("MasterChanged", master)
    else
      self:SendCommMessage(EPGP.MASTER_VICTORY, "", GUILD, nil, "ALERT")
    end
  end
end

function mod:ProcessMasterVictory(prefix, msg, type, sender)
  Debug("Received election victory from %s", sender)
  local me = UnitName("player")
  local info = EPGP:GetMemberInfo(sender)
  local my_info = EPGP:GetMemberInfo(me)
  if InfoLess(my_info, info) then
    self:DoElection()
  else
    self:CancelTimer(timeout_handle, true)
    Debug("Election ended")
    if master ~= sender then
      master = sender
      Debug("New master is %s", sender)
      self:SendMessage("MasterChanged", master)
    end
  end
end

function mod:OnModuleEnable()
  -- Reset the master when we are enabled (say after a Disable/Enable pair).
  master = nil
  self:RegisterComm(EPGP.MASTER_ELECTION, "ProcessMasterElection")
  self:RegisterComm(EPGP.MASTER_VICTORY, "ProcessMasterVictory")

  self:ScheduleRepeatingTimer("DoElection", PERIOD)
end

-- TODO(alkis): Test properly with multiple clients.
-- TODO(alkis): Algorithm might neeed modification to reduce addon traffic spam.

--------------------------------------------------------------------------------
-- These functions change the core interface

function EPGP:GetMaster()
  return master
end
