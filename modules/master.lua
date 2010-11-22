local mod = EPGP:NewModule("master", "AceComm-3.0")

local Debug = LibStub("LibDebug-1.0")
local MapT = EPGP.MapT
local TableInsert = EPGP.TableInsert

mod.dbDefaults = {
  profile = {
    enabled = true,
    journal = {},
  }
}

local function ApplyAnnounce(ann)
  for i=4,#ann,4 do
    local name, ep, raw_gp, seq = unpack(ann, i)
    local info = EPGP:GetMemberInfo(name)
    info.SetEPGP(ep, raw_gp, seq)
  end
end

local function FindAnnounce(sender, id)
  for i,a in ipairs(mod.db.profile.journal) do
    if sender == a[1] and id == a[2] then
      return a
    end
  end
end

function mod:ProcessChangeAnnounce(prefix, msg, type, sender)
  local ann = EPGP.ParseChangeAnnounce(msg)
  Debug("Received change announce %s (%s)", msg, ann[1])

  -- If we are the sender everything is done already.
  if sender == UnitName("player") then return end

  -- If we have the announce we can also return safely.
  if FindAnnounce(ann[1], ann[2]) then return end

  ApplyAnnounce(ann)
  Debug("Adding announce %s (%s) to journal", msg, sender)
  tinsert(self.db.profile.journal, ann)
  -- TODO(alkis): Journal application and cleanup.
end

function mod:ProcessChangeRequest(prefix, msg, type, sender)
  Debug("Received change request %s (%s)", msg, sender)
  if EPGP:GetMaster() ~= UnitName("player") then return end

  local req = EPGP.ParseChangeRequest(msg)
  local id, reason, delta_ep, delta_gp = unpack(req)

  local ann = FindAnnounce(sender, id)
  -- We haven't processed this request before. Process it now.
  if not ann then
    ann = {sender, id, reason}
    for i=5,#req do
      local name = req[i]
      local info = EPGP:GetMemberInfo(name)
      local ep = info.GetEP() + delta_ep
      local raw_gp = info.GetRawGP() + delta_gp
      local seq = info.GetSeq() + 1
      TableInsert(ann, name, ep, raw_gp, seq)
    end
    ApplyAnnounce(ann)
    table.insert(self.db.profile.journal, ann)
  end
  self:SendCommMessage(EPGP.CHANGE_ANNOUNCE,
                       table.concat(MapT(tostring, ann), ","),
                       "GUILD", nil, "ALERT")
end

function mod:ProcessDecayRequest(prefix, msg, type, sender)
  Debug("Received decay request %s (%s)", msg, sender)
  if EPGP:GetMaster() ~= UnitName("player") then return end

  local req = EPGP.ParseDecayRequest(msg)

  -- Build the announcement.
  local id = unpack(req)
  local reason = ("Decay (%d%%)"):format(EPGP:GetDecayPercent())

  local ann = {sender, id, reason}
  local totalMembers = GetNumGuildMembers()
  local decay_factor = 1 - 0.01 * EPGP:GetDecayPercent()

  for i=1,totalMembers do
    local name = GetGuildRosterInfo(i)
    local info = EPGP:GetMemberInfo(name)

    -- Only decay mains.
    if not info.GetMain() then
      local ep = info.GetEPScaledBy(decay_factor)
      local raw_gp = info.GetRawGPForGPScaledBy(decay_factor)
      local seq = info.GetSeq() + 1
      if ep ~= info.GetEP() or raw_gp ~= info.GetRawGP() then
        TableInsert(ann, name, ep, raw_gp, seq)
      end
    end
    ApplyAnnounce(ann)
    table.insert(self.db.profile.journal, ann)
  end
  self:SendCommMessage(EPGP.CHANGE_ANNOUNCE,
                       table.concat(MapT(tostring, ann), ","),
                       "GUILD", nil, "ALERT")
end

function mod:OnModuleEnable()
  self:RegisterComm(EPGP.CHANGE_ANNOUNCE, "ProcessChangeAnnounce")
  self:RegisterComm(EPGP.CHANGE_REQUEST, "ProcessChangeRequest")
  self:RegisterComm(EPGP.DECAY_REQUEST, "ProcessDecayRequest")
end

-- TODO(alkis): Validate change requests.
-- TODO(alkis): Keep a list of applied change requests so that we know what to ignore.
