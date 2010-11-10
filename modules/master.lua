local mod = EPGP:NewModule("master", "AceComm-3.0")

local Debug = LibStub("LibDebug-1.0")

local master

mod.dbDefaults = {
  profile = {
    enabled = true,
    req_queue = {},
    journal = {},
  }
}

local function map(f, t)
  local r = {}
  for i,v in ipairs(t) do
    r[i] = f(v)
  end
  return r
end

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  -- If we are not the sender we need to store this in the journal for backup.
  local requestor, id, reason, rest = msg:match("([^,]+),(%d+),([^,]+)(.+)")
  id = tonumber(id)

  Debug("Received announce for request %s:%d", requestor, id)
  if sender ~= UnitName("player") then
    local req = {requestor, id, reason}
    for name, cn, ep, raw_gp in rest:gmatch(",([^,]+),(%d+),(%d+),(%d+)") do
      cn, ep, raw_gp = unpack(map(tonumber, {cn, ep, raw_gp}))

      tinsert(req, name)
      tinsert(req, cn)
      tinsert(req, ep)
      tinsert(req, raw_gp)
    end

    tinsert(self.db.profile.journal, req)
  end
end

function mod:ProcessChangeRequest(prefix, msg, type, sender)
  Debug("Received request %s (%s)", msg, sender)
  if master ~= UnitName("player") then return end

  local id, reason, delta_ep, delta_gp, rest = msg:match(
    "(%d+),([^,]+),(%d+),(%d+)(.+)")
  id, delta_ep, delta_gp = unpack(map(tonumber, {id, delta_ep, delta_gp}))

  local req = {sender, id, reason, delta_ep, delta_gp}
  for target in rest:gmatch(",([^,]+)") do
    table.insert(req, target)
  end
  tinsert(self.db.profile.req_queue, req)
end

function mod:OnEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:RegisterComm(EPGP.CHANGE_REQUEST, "ProcessChangeRequest")
  EPGP:GetModule("election").RegisterMessage(
    self, "MasterChanged", function(_, new_master) master = new_master end)
end

-- TODO(alkis): Journal cleanup.
-- TODO(alkis): Apply change requests and send out the change announcement.
