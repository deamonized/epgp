local mod = EPGP:NewModule("guild_notes", "AceEvent-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

local function BaseGP()
  return EPGP:GetModule("guild_info").db.profile.base_gp
end
local cache = {}

local function ParseNote(note)
  if note == "" then return 0, 0, 0 end
  local ep, gp, v
  v = 0
  ep, gp = note:match("^(%d+),(%d+)$")
  if not ep or not gp then
    ep, gp, v = note:match("^(%d+),(%d+),(%d+)$")
  end
  if ep and gp then
    return tonumber(ep), tonumber(gp), tonumber(v)
  end
end

local function EncodeNote(ep, gp, v)
  return string.format("%d,%d,%d", ep, gp, v)
end

-- The metatable for the infos. It forwards methods that do not exist
-- to the main toon's info.
local mt = {__index=function(t, k) return t.GetMain()[k] end}
local function NewMemberInfo(new_name)
  local info = {}

  local main
  local alts = {}
  local note
  local ep
  local raw_gp
  local version = -1
  local name = new_name
  local rank
  local rank_i
  local class

  setmetatable(info, mt)

  function info.Update(i)
    local note
    name, rank, rank_i, _, _, _, _, note, _, _, class = GetGuildRosterInfo(i)
    local new_main = cache[note]
    if new_main then
      if main ~= new_main then
        info.SetMain(new_main)
      end
    else
      if main then
        info.RemoveMain()
      end
      local new_note = info.SetNote(note)
      if new_note then
        Debug("Writing out note for %s: %s", name, new_note)
        GuildRosterSetOfficerNote(i, new_note)
      end
    end
  end

  function info.GetEP() return ep end
  function info.GetGP() return raw_gp and raw_gp + BaseGP() or nil end
  function info.GetRawGP() return raw_gp end
  function info.GetVersion() return version end
  function info.GetNote()
    if note then return note end
    return EncodeNote(ep, raw_gp, version)
  end
  function info.GetName() return name end
  function info.GetRank() return rank end
  function info.GetRankIndex() return rank_i end
  function info.GetClass() return class end
  function info.GetAlts() return alts end
  function info.GetMain() return main end

  function info.SetEP(n) ep = math.max(0, n) end
  function info.SetGP(n) info.SetRawGP(n - BaseGP()) end
  function info.SetRawGP(n) raw_gp = math.max(0, n) end
  function info.SetVersion(n) version = n end -- TODO(alkis): Rollover.
  function info.SetNote(new_note)
    local ep, raw_gp, n = ParseNote(new_note)
    if not ep or not raw_gp or not n then
      note = new_note
      return
    end

    note = nil
    if n > version then
      info.SetEP(ep)
      info.SetRawGP(raw_gp)
      info.SetVersion(n)
    elseif version > n then
      return info.GetNote()
    end
  end

  local specials = {
    "GetEP", "GetGP", "GetRawGP", "GetVersion",
    "SetEP", "SetGP", "SetRawGP", "SetVersion",
  }
  -- Make _FunName copies of specials for use when moving methods around.
  for i,fn in ipairs(specials) do
    rawset(info, "_"..fn, rawget(info, fn))
  end

  function info.SetMain(m)
    Debug("Setting %s as main for %s", m.GetName(), name)
    main = m
    table.insert(main.GetAlts(), info)
    -- Delete all specials so that they are forwarded to main.
    for i, fn in ipairs(specials) do
      rawset(info, fn, nil)
    end
  end

  function info.RemoveMain()
    Debug("Removing %s as main for %s", main.GetName(), name)
    for i, alt in ipairs(main.GetAlts()) do
      if name == alt then
        table.remove(main.GetAlts(), i)
        break
      end
    end
    -- Copy specials back.
    for i, fn in ipairs(specials) do
      rawset(info, fn, rawget(info, "_"..fn))
    end
    main = nil
  end

  return info
end

-- This function changes the core interface.
function EPGP:GetMemberInfo(name)
  return cache[name]
end

local function GUILD_ROSTER_UPDATE(self, event, loc)
  if loc then return end
  local totalMembers = GetNumGuildMembers()
  local seen = {}

  for i=1,totalMembers do
    local name, _, _, _, _, _, _, note, _, _, _  = GetGuildRosterInfo(i)
    local info = cache[name]
    if not info then
      info = NewMemberInfo(name)
    end
    info.Update(i)
    info.seen = true
  end

  -- Remove seen marks and delete infos that are no longer valid.
  for name, info in pairs(cache) do
    if info.seen then
      info.seen = nil
    else
      for i, alt in ipairs(info.GetAlts()) do
        alt.RemoveMain(info)
      end
      cache[name] = nil
    end
  end
end

local function GUILD_ROSTER_UPDATE_INIT(self, event, loc)
  if loc then return end
  local totalMembers = GetNumGuildMembers()
  for i=1,totalMembers do
    local name = GetGuildRosterInfo(i)
    cache[name] = NewMemberInfo(name)
  end

  -- Switch to the post init function.
  self.GUILD_ROSTER_UPDATE = EPGP.Profile(GUILD_ROSTER_UPDATE,
                                          "Updating member infos")
  -- And run it now.
  self.GUILD_ROSTER_UPDATE(self, event, loc)
end

function mod:BaseGPChanged(new_base_gp)
  base_gp = new_base_gp
end

function mod:OnModuleEnable()
  -- This module enables in multiple steps:
  -- 1) First pass of guild roster is done to find all toons.
  -- 2) Second pass of guild roster is done to parse notes and associate alts.
  -- 3...) All other passes update this state accordingly.
  EPGP:GetModule("guild_info").RegisterMessage(self, "BaseGPChanged")

  self.GUILD_ROSTER_UPDATE = EPGP.Profile(GUILD_ROSTER_UPDATE_INIT,
                                          "Creating member infos")
  self:RegisterEvent("GUILD_ROSTER_UPDATE")
end

function mod:OnModuleDisable()
  base_gp = nil
  cache = {}
  self.GUILD_ROSTER_UPDATE = nil
  EPGP:GetModule("guild_info").UnregisterAllMessages(self)
end
