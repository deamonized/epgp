local mod = EPGP:NewModule("slave", "AceComm-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")

mod.dbDefaults = {
  profile = {
    enabled = true,
    next_id = 0,
    req_queue = {},
  }
}

local master

local function map(f, t)
  local r = {}
  for i,v in ipairs(t) do
    r[i] = f(v)
  end
  return r
end

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  local requestor, id, reason, rest = msg:match("([^,]+),(%d+),([^,]+)(.+)")
  id = tonumber(id)

  Debug("Received announce for request %s:%d", requestor, id)
  local req = {requestor, id, reason}

  -- Remove request from the queue if it exists.
  for i,r in ipairs(self.db.profile.req_queue) do
    if r[1] == requestor and r[2] == id then
      tremove(self.db.profile.req_queue, i)
      break
    end
  end
end

function mod:ProcessRequest(i)
  if not master then return end
  local req = self.db.profile.req_queue[i]

  local str = table.concat(map(tostring, req), ",")

  Debug("Requesting change: %s", str)
  self:SendCommMessage(EPGP.CHANGE_REQUEST, str, "WHISPER", master, "BULK")
end

function mod:ProcessRequestQueue()
  for i=1,#self.db.profile.req_queue do
    self:ProcessRequest(i)
  end
end

--------------------------------------------------------------------------------

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:ScheduleRepeatingTimer("ProcessRequestQueue", 15)
  EPGP:GetModule("election").RegisterMessage(
    self, "MasterChanged", function(_, new_master) master = new_master end)
end

--------------------------------------------------------------------------------
-- These functions change the core interface.

local Map = EPGP.Map
local All = EPGP.All
local Not = EPGP.Not
local IsString = EPGP.IsString
local IsInteger = EPGP.IsInteger
local Between = EPGP.Between
local EqualTo = EPGP.EqualTo

function EPGP:CanChangeEPGP(reason, delta_ep, delta_gp, ...)
  return CanEditOfficerNote() and
         All(Map(IsString, reason, ...)) and
         #reason > 0 and
         All(Map(IsInteger, delta_ep, delta_gp)) and
         All(Map(Between(-99999, 99999), delta_ep, delta_gp)) and
         All(Map(Not(EqualTo(0)), delta_ep, delta_gp))
end

function EPGP:ChangeEPGP(reason, delta_ep, delta_gp, ...)
  tinsert(mod.db.profile.req_queue, {
            mod.db.profile.next_id,
            reason,
            delta_ep,
            delta_gp,
            ...
          })
  mod.db.profile.next_id = mod.db.profile.next_id + 1
  mod:ProcessRequest(#mod.db.profile.req_queue)
end
