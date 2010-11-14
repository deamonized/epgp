local mod = EPGP:NewModule("slave",
                           "AceComm-3.0", "AceEvent-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")

local PERIOD = 15

mod.dbDefaults = {
  profile = {
    enabled = true,
    next_id = 0,
    req_queue = {},
  }
}

local Map = EPGP.Map

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  local ann = EPGP.ParseChangeAnnounce(msg)
  Debug("Received change announce %s (%s)", msg, ann[1])

  -- Find the request that was announced, call callbacks with info
  -- from request and then remove it.
  for i,r in ipairs(self.db.profile.req_queue) do
    if r[1] == ann[1] and r[2] == ann[2] then
      self:SendMessage("ChangeAnnounced", unpack(r))
      Debug("Removing request %s:%d from our queue", r[1], r[2])
      tremove(self.db.profile.req_queue, i)
      break
    end
  end
end

function mod:ProcessChangeRequest(prefix, msg, type, sender)
  Debug("Received change request %s (%s)", msg, sender)

  -- If we are the sender we have this request in our queue.
  if sender == UnitName("player") then return end

  local req = EPGP.ParseChangeRequest(msg)
  table.insert(self.db.profile.req_queue, {sender, unpack(req)})
end

function mod:ProcessRequest(i)
  local req = self.db.profile.req_queue[i]
  if not req[1] == UnitName("player") then return end

  -- Ignore the first argument since that's us.
  local str = table.concat({Map(tostring, unpack(req, 2))}, ",")

  Debug("Requesting change: %s", str)
  self:SendCommMessage(EPGP.CHANGE_REQUEST, str, "GUILD", nil, "BULK")
end

function mod:ProcessRequestQueue()
  for i=1,#self.db.profile.req_queue do
    self:ProcessRequest(i)
  end
end

--------------------------------------------------------------------------------

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:ScheduleRepeatingTimer("ProcessRequestQueue", PERIOD)
end

--------------------------------------------------------------------------------
-- These functions change the core interface.

local All = EPGP.All
local Any = EPGP.Any
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
         Any(Map(Not(EqualTo(0)), delta_ep, delta_gp))
end

function EPGP:ChangeEPGP(reason, delta_ep, delta_gp, ...)
  assert(self:CanChangeEPGP(reason, delta_ep, delta_gp, ...))
  table.insert(mod.db.profile.req_queue, {
                 UnitName("player"),
                 mod.db.profile.next_id,
                 reason,
                 delta_ep,
                 delta_gp,
                 ...
               })
  mod.db.profile.next_id = mod.db.profile.next_id + 1
  mod:ProcessRequest(#mod.db.profile.req_queue)
end

function EPGP:CanDecayEPGP()
  return CanEditOfficerNote()
end
