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

local function FindRequest(sender, id)
  for i,r in ipairs(mod.db.profile.req_queue) do
    if sender == r[2] and id == r[3] then
      return i, r
    end
  end
end

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  local ann = EPGP.ParseChangeAnnounce(msg)
  Debug("Received change announce %s (%s)", msg, ann[1])

  -- Find the request that was announced, call callbacks with info
  -- from request and then remove it.
  local idx, req = FindRequest(ann[1], ann[2])
  if req then
    self:SendMessage(unpack(req))
    Debug("Removing request %s:%d from our queue", ann[1], ann[2])
    tremove(self.db.profile.req_queue, idx)
  end
end

function mod:ProcessChangeRequest(prefix, msg, type, sender)
  Debug("Received change request %s (%s)", msg, sender)

  -- If we are the sender we have this request in our queue already.
  if sender == UnitName("player") then return end

  local req = EPGP.ParseChangeRequest(msg)
  if not FindRequest(sender, req[1]) then
    table.insert(self.db.profile.req_queue,
                 {EPGP.CHANGE_REQUEST, sender, unpack(req)})
  end
end

function mod:ProcessDecayRequest(prefix, msg, type, sender)
  Debug("Received decay request %s (%s)", msg, sender)

  -- If we are the sender we have this request in our queue already.
  if sender == UnitName("player") then return end

  local req = EPGP.ParseDecayRequest(msg)
  if not FindRequest(sender, req[1]) then
    table.insert(self.db.profile.req_queue,
                 {EPGP.DECAY_REQUEST, sender})
  end
end

function mod:ProcessRequest(i)
  local req = self.db.profile.req_queue[i]
  if not req[1] == UnitName("player") then return end

  local req_type = req[1]
  local sender = req[2]

  -- TODO(alkis): Change this to retry other sender's requests.
  if sender ~= UnitName("player") then return end

  -- Ignore the first (type) and second (sender) argument.
  local str = table.concat({Map(tostring, unpack(req, 2))}, ",")

  Debug("Requesting change: %s: %s", req_type, str)
  self:SendCommMessage(req_type, str, "GUILD", nil, "BULK")
end

function mod:ProcessRequestQueue()
  for i=1,#self.db.profile.req_queue do
    self:ProcessRequest(i)
  end
end

--------------------------------------------------------------------------------

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:RegisterComm(EPGP.CHANGE_REQUEST, "ProcessChangeRequest")
  self:RegisterComm(EPGP.DECAY_REQUEST, "ProcessDecayRequest")

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
                 EPGP.CHANGE_REQUEST,
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
  return CanEditOfficerNote() and #mod.db.profile.req_queue == 0
end

function EPGP:DecayEPGP()
  assert(self:CanDecayEPGP())
  table.insert(mod.db.profile.req_queue, {
                 EPGP.DECAY_REQUEST,
                 UnitName("player"),
                 mod.db.profile.next_id
               })
  mod.db.profile.next_id = mod.db.profile.next_id + 1
  mod:ProcessRequest(#mod.db.profile.req_queue)
end
