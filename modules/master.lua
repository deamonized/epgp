local mod = EPGP:NewModule("master", "AceComm-3.0")

local Debug = LibStub("LibDebug-1.0")
local Map = EPGP.Map
local MapT = EPGP.MapT
local TableInsert = EPGP.TableInsert

mod.dbDefaults = {
  profile = {
    enabled = true,
    journal = {},
  }
}

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  local requestor, id, reason, rest = msg:match("([^,]+),(%d+),([^,]+),(.+)")
  Debug("Received change announce %s (%s)", msg, requestor)

  -- If we are the sender everything is done already.
  if sender == UnitName("player") then return end

  id = tonumber(id)
  local ann = {requestor, id, reason}
  for name, sn, ep, raw_gp in rest:gmatch("([^,]+),(%d+),(%d+),(%d+)") do
    seq, ep, raw_gp = Map(tonumber, sn, ep, raw_gp)
    TableInsert(ann, name, seq, ep, raw_gp)
    local info = EPGP:GetMemberInfo(name)
    info.SetEP(ep)
    info.SetRawGP(raw_gp)
    info.SetSeq(seq)
  end
  Debug("Adding announce %s (%s) to journal", msg, requestor)
  tinsert(self.db.profile.journal, ann)
  -- TODO(alkis): Journal application and cleanup.
end

function mod:ProcessChangeRequest(prefix, msg, type, sender)
  Debug("Received change request %s (%s)", msg, sender)
  if EPGP:GetMaster() ~= UnitName("player") then return end

  local id, reason, delta_ep, delta_gp, rest = msg:match(
    "(%d+),([^,]+),(%d+),(%d+)(.+)")
  id, delta_ep, delta_gp = Map(tonumber, id, delta_ep, delta_gp)

  local ann = {sender, id, reason}
  for target in rest:gmatch(",([^,]+)") do
    local info = EPGP:GetMemberInfo(target)
    local ep = info.GetEP() + delta_ep
    local raw_gp = info.GetRawGP() + delta_gp
    local seq = info.GetSeq() + 1
    TableInsert(ann, target, ep, raw_gp, v)
    info.SetEP(ep)
    info.SetRawGP(raw_gp)
    info.SetSeq(seq)
  end
  table.insert(self.db.profile.journal, ann)
  self:SendCommMessage(EPGP.CHANGE_ANNOUNCE,
                       table.concat(MapT(tostring, ann), ","),
                       "GUILD", nil, "ALERT")
end

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:RegisterComm(EPGP.CHANGE_REQUEST, "ProcessChangeRequest")
end
