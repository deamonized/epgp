local mod = EPGP:NewModule("guild_notes",
                           "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

mod.dbDefaults = {
  profile = {
    enabled = true,
    data = {},
  }
}

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
local mt = {__index=function(t, k)
                      local main = t.GetMain()
                      return t and t[k] or nil
                    end}
local function NewMemberInfo(new_name)
  local info = {}

  local main
  local alts = {}
  local note
  local ep
  local raw_gp
  local seq = -1
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
      if new_note and CanEditOfficerNote() then
        Debug("Writing out note for %s: %s", name, new_note)
        GuildRosterSetOfficerNote(i, new_note)
        return true
      end
    end
  end

  function info.GetEP() return ep end
  function info.GetGP() return raw_gp and raw_gp + EPGP:GetBaseGP() or nil end
  function info.GetPR() return info.GetEP() / info.GetGP() end
  function info.GetRawGP() return raw_gp end
  function info.GetSeq() return seq end
  function info.GetNote()
    if note then return note end
    return EncodeNote(ep, raw_gp, seq)
  end
  function info.GetName() return name end
  function info.GetRank() return rank end
  function info.GetRankIndex() return rank_i end
  function info.GetClass() return class end
  function info.GetAlts() return alts end
  function info.GetMain() return main end
  -- Used for decay.
  function info.GetEPScaledBy(f)
    return math.max(0, math.floor(info.GetEP() * f))
  end
  function info.GetRawGPForGPScaledBy(f)
    local base_gp = EPGP:GetBaseGP()
    return math.max(base_gp, math.floor(info.GetGP() * f)) - base_gp
  end

  function info.SetEPGP(e, g, s)
    if s > seq then
      ep = math.max(0, e)
      raw_gp = math.max(0, g)
      seq = s
      GuildRoster()
    end
  end

  function info.SetNote(new_note)
    local new_ep, new_raw_gp, new_seq = ParseNote(new_note)
    if not new_ep or not new_raw_gp or not new_seq then
      note = new_note
      return
    end

    note = nil
    if new_seq > seq then
      ep = new_ep
      raw_gp = new_raw_gp
      seq = new_seq
    elseif seq > new_seq then
      return info.GetNote()
    end
  end

  local specials = {
    GetEP=info.GetEP,
    GetGP=info.GetGP,
    GetRawGP=info.GetRawGP,
    GetSeq=info.GetSeq,
    SetEPGP=info.SetEPGP,
  }

  function info.SetMain(m)
    Debug("Setting %s as main for %s", m.GetName(), name)
    main = m
    table.insert(main.GetAlts(), info)
    -- Delete all specials so that they are forwarded to main.
    for n,fn in ipairs(specials) do
      rawset(info, n, nil)
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
    for n,fn in ipairs(specials) do
      rawset(info, n, fn)
    end
    main = nil
  end

  return info
end

local function GUILD_ROSTER_UPDATE(self, event, loc)
  if loc then return end
  local totalMembers = GetNumGuildMembers()
  local seen = {}

  for i=1,totalMembers do
    local name, _, _, _, _, _, _, note, _, _, _  = GetGuildRosterInfo(i)
    local info = cache[name] or NewMemberInfo(name)
    cache[name] = info
    -- TODO(alkis): When this update happens on an offline member,
    -- we get a GUILD_ROSTER_UPDATE that does not contain the
    -- change. This happens until a real GUILD_ROSTER_UPDATE comes 15
    -- seconds later. This means for offline members we take about 15
    -- seconds per offline member to update their note. Obviously this
    -- needs to be fixed.
    if info.Update(i) then
      for name, info in pairs(cache) do
        info.seen = nil
      end
      return
    end
    info.seen = true
  end

  -- Remove seen marks, delete infos that are no longer valid and
  -- store a backup.
  for name, info in pairs(cache) do
    if info.seen then
      info.seen = nil
      -- Backup only mains that have epgp info.
      if not info.GetMain() and info.GetEP() then
        self.db.profile.data[name] = info.GetNote()
      end
    else
      for i, alt in ipairs(info.GetAlts()) do
        alt.RemoveMain(info)
      end
      cache[name] = nil
      self.db.profile.data[name] = nil
    end
  end
  self:ScheduleTimer(function() self:SendMessage("GuildRosterUpdate") end, 0)
end

local function GUILD_ROSTER_UPDATE_INIT(self, event, loc)
  if loc then return end
  local totalMembers = GetNumGuildMembers()
  for i=1,totalMembers do
    local name = GetGuildRosterInfo(i)
    local info = cache[name] or NewMemberInfo(name)
    cache[name] = info
  end

  for i=1, totalMembers do
    local name = GetGuildRosterInfo(i)
    local info = cache[name]
    info.Update(i)
  end
  self:ScheduleTimer(function() self:SendMessage("GuildRosterUpdate") end, 0)

  -- Switch to the post init function.
  self.GUILD_ROSTER_UPDATE = EPGP.Profile(GUILD_ROSTER_UPDATE,
                                          "Updating member infos")
end

function mod:OnModuleEnable()
  -- This module enables in multiple steps:
  -- 1) First pass of guild roster is done to find all toons.
  -- 2) Second pass of guild roster is done to parse notes and associate alts.
  -- 3...) All other passes update this state accordingly.
  self.GUILD_ROSTER_UPDATE = EPGP.Profile(GUILD_ROSTER_UPDATE_INIT,
                                          "Creating member infos")
  self:RegisterEvent("GUILD_ROSTER_UPDATE")
  -- Init the cache from backup.
  for name, note in pairs(self.db.profile.data) do
    local info = NewMemberInfo(name)
    info.SetNote(note)
  end

  -- We need to "show" offline members because when we change offline
  -- members' notes and GetGuildRosterShowOffline() returns nil a
  -- GUILD_ROSTER_UPDATE is fired but the data we just wrote is not
  -- reflected in the notes. As such we need to enable show offline
  -- while the guild roster is not shown and restore it's original
  -- value when it is.
  self:RawHook(
    "GuildFrame_LoadUI",
    function(...)
      SetGuildRosterShowOffline(self.db.profile.blizzard_show_offline)
      self.hooks.GuildFrame_LoadUI(...)
      self:RawHookScript(
        GuildRosterFrame, "OnShow",
        function(frame, ...)
          SetGuildRosterShowOffline(self.db.profile.blizzard_show_offline)
          self.hooks[frame].OnShow(frame, ...)
        end)
      self:RawHookScript(
        GuildRosterFrame, "OnHide",
        function(frame, ...)
          self.db.profile.blizzard_show_offline = GetGuildRosterShowOffline()
          self.hooks[frame].OnHide(frame, ...)
          SetGuildRosterShowOffline(true)
        end)
      self:Unhook("GuildFrame_LoadUI")

      SetGuildRosterShowOffline(true)
    end, true)
  SetGuildRosterShowOffline(true)
end

function mod:OnModuleDisable()
  cache = {}
  self.GUILD_ROSTER_UPDATE = nil
  EPGP:GetModule("guild_info").UnregisterAllMessages(self)
end

--------------------------------------------------------------------------------
-- These functions change the core interface.

function EPGP:GetMemberInfo(name)
  return cache[name]
end
