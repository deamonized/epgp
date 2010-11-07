local Debug = LibStub("LibDebug-1.0")

local MASTER_ELE = "EPGP_MaEle"
local MASTER_VIC = "EPGP_MaVic"

local function InfoLess(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  return a.name < b.name
end

function EPGP:RegisterMasterElectionComms()
  self:RegisterComm(MASTER_ELE, "ProcessMasterElection")
  self:RegisterComm(MASTER_VIC, "ProcessMasterVictory")
end

function EPGP:StartElectionLoop()
  local function DoElection()
    if CanEditOfficerNote() then
      self:StartElection()
    end
  end

  self:ScheduleRepeatingTimer(DoElection, 30)
  DoElection()
end

function EPGP:StartElection()
  self:SendCommMessage(MASTER_ELE, "", GUILD, nil, "ALERT")
  self.election_end_handle = self:ScheduleTimer(
    function()
      self:SendCommMessage(MASTER_VIC, "", GUILD, nil, "ALERT")
      self.db.profile.master = UnitName("player")
      -- TODO(alkis): Enable master mode.
      Debug("Starting master mode")
    end,
    15)
  Debug("Started master election")
end

function EPGP:StopElection(new_master)
  if self:CancelTimer(self.election_end_handle, true) then
    Debug("Stopped master election")
  end
end

function EPGP:ProcessMasterElection(prefix, msg, type, sender)
  Debug("Received election request for %s to become master", sender)
  local me = UnitName("player")
  if EPGP.db.profile.master == me then
    local info = self:GetMemberInfo(sender)
    local my_info = self:GetMemberInfo(me)
    if InfoLess(info, my_info) then
      Debug("Stopping master mode")
      -- TODO(alkis): Disable master mode.
    else
      self:SendCommMessage(MASTER_VIC, "", GUILD, nil, "ALERT")
      Debug("I am the master and requestor is no good")
    end
  end
end

function EPGP:ProcessMasterVictory(prefix, msg, type, sender)
  local me = UnitName("player")
  Debug("Received election victory from %s", sender)
  local info = self:GetMemberInfo(sender)
  local my_info = self:GetMemberInfo(me)
  if InfoLess(my_info, info) then
    self:StartElection()
  else
    self:StopElection()
    if self.db.profile.master ~= sender then
      self.db.profile.master = sender
      Debug("New master is %s", sender)
    end
  end
end
