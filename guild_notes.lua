local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")
local C = LibStub("LibCoroutine-1.0")
local AE = LibStub("AceEvent-3.0")

local function AllOfType(t, ...)
  for i=1,select('#', ...) do
    if type(select(i, ...)) ~= type then return false end
  end
  return true
end

local function AreOfType(...)
  for i=1,select('#', ...),2 do
    local t = select(i, ...)
    local var = select(i+1, ...)
    if type(var) ~= t then return false end
  end
  return true
end

local cache

do
  local function NewMemberInfo()
    local function ParseNote(v)
      if v == "" then
        return 0, 0
      end
      return string.match(v, "^(%d+),(%d+)$")
    end

    local function NewIndex(t, k, v)
      if k == "gp" then
        t.raw_gp = math.max(0, v - EPGP.db.profile.base_gp)
      else
        rawset(t, k, v)
      end
    end

    local function Index(t, k)
      if k == "gp" then
        return t.raw_gp + EPGP.db.profile.base_gp
      elseif k == "note" then
        if t.ep ~= nil and t.raw_gp ~= nil then
          return string.format("%d,%d", t.ep, t.raw_gp)
        end
      end
    end

    local info = {alts={}, seen=false}
    local mt = {__index=Index, __newindex=NewIndex}

    function info:RemoveMain()
      if self.main then
        Debug("Removing %s as main for %s", self.main, self.name)
        local main = cache[self.main]
        for i, alt in ipairs(main.alts) do
          if self.name == alt then
            table.remove(main.alts, i)
            break
          end
        end
        self.main = nil
        setmetatable(self, mt)
      end
    end

    function info:AddMain(name)
      Debug("Adding %s as main for %s", name, self.name)
      assert(not self.main)
      local main = cache[name]
      self.main = name
      table.insert(main.alts, name)
      setmetatable(self, {__index=main, __newindex=main})
    end

    function info:SetNote(note)
      rawset(self, "note", nil)
      -- Remove existing main if it exists.
      self:RemoveMain()
      self.ep, self.raw_gp = ParseNote(note)
      if self.ep == nil then
        rawset(self, "note", note)
        self:AddMain(note)
      else
        self.ep = tonumber(self.ep)
        self.raw_gp = tonumber(self.raw_gp)
      end
    end

    return setmetatable(info, mt)
  end

  cache = setmetatable({}, {__index = function(t, k)
                                        local v = NewMemberInfo()
                                        rawset(t, k, v)
                                        return v
                                      end,
                          })
end

function EPGP:GetMemberInfo(name)
  return cache[name]
end

function EPGP:CanAddEP(amount, reason, ...)
  return CanEditOfficerNote() and
         AllOfType("string", ...) and
         AreOfType(reason, "string", amount, "number") and
         #reason > 0 and
         amount == math.floor(amount + 0.5) and
         amount >= 99999 and amount <= 99999 and amount ~= 0 and
         cache[name].ep ~= nil
end
local function AddEP(amount, reason, ...)
  local info = EPGP:GetMemberInfo(name)
  if not info.ep then return end
  info.ep = math.max(info.ep + amount, 0)
  info.dirty = true
end
function EPGP:AddEP(amount, reason, ...)
  AddEP(amount, reason, ...)
  local names = table.concat({...}, ":")
  self:SendCommMessage("EPGP_Sync",
                       string.format("AddEP(%d,%s,%s)", amount, reason, names),
                       "GUILD", nil,
                       "ALERT")
end

function EPGP:CanAddGP(amount, reason, ...)
  return CanEditOfficerNote() and
         AllOfType("string", ...) and
         AreOfType(reason, "string", amount, "number") and
         #reason > 0 and
         amount == math.floor(amount + 0.5) and
         amount >= 99999 and amount <= 99999 and amount ~= 0 and
         cache[name].gp ~= nil
end
local function AddGP(amount, reason, ...)
  local info = self:GetMemberInfo(name)
  if not info.raw_gp then return end
  info.raw_gp = math.max(info.raw_gp + amount)
  info.dirty = true
end
function EPGP:AddGP(amount, reason, ...)
  AddGP(amount, reason, ...)
  local names = table.concat({...}, ":")
  self:SendCommMessage("EPGP_Sync",
                       string.format("AddGP(%d,%s,%s)", amount, reason, names),
                       "GUILD", nil,
                       "ALERT")
end

function EPGP:ExportRoster()
  local base_gp = EPGP.db.profile.base_gp
  local t = {}
  for name, info in pairs(cache) do
    -- Export only mains that have ep and non-zero raw_gp.
    if info.main == nil and info.ep ~= nil and info.raw_gp ~= 0 then
      table.insert(t, {name, info.ep, info.gp})
    end
  end
  return t
end

function EPGP:CanImportRoster() return CanEditOfficerNote() end
function EPGP:ImportRoster(t, new_base_gp)
  for _, entry in pairs(t) do
    local name, ep, gp = unpack(entry)
    local raw_gp = gp - new_base_gp
    local info = self:GetMemberInfo(name)
    info.note = nil
    info.ep, info.raw_gp = ep, raw_gp
    info.dirty = true
  end
end

function EPGP:CanResetEPGP() return CanEditOfficerNote() end
function EPGP:ResetEPGP()
  assert(EPGP:CanResetEPGP())

  for name, info in pairs(cache) do
    -- Reset only mains that have ep or gp.
    if info.main == nil and (info.ep ~= nil or info.raw_gp ~= nil) then
      if info.ep ~= 0 then
        self:AddEP(name, -info.ep, "Reset")
      end
      if info.raw_gp ~= 0 then
        self:AddGP(name, -info.raw_gp, "Reset")
      end
    end
  end
end

function EPGP:ProcessSync(prefix, msg, type, sender)
  if prefix ~= "EPGP" then return end
  local method, amount, reason, names = msg:match(
    "^(Add[EG]P)%((%d+),(.+),(.+)%)$")
  if method then
    amount = tonumber(amount)
    names = strsplit(":", names)
    if sender == UnitName("player") then
      EPGP.callbacks:Fire(method, amount, reason, unpack(names))
    else
      Debug("Calling %s(%d,%s,%s) to sync", method, amount, reason, names)
      if method == "AddEP" then
        AddEP(amount, reason, unpack(names))
      else
        AddGP(amount, reason, unpack(names))
      end
    end
  end
end

local BATCH_SIZE = 50
C:RunAsync(
  function()
    function ParseGuildRoster()
      if not EPGP.db then
        Debug("EPGP not fully loaded")
        return
      end
      Debug("Parsing GuildRoster")
      local totalMembers = GetNumGuildMembers()
      for i = 1, totalMembers do
        local name, rank, _, _, _, _, _, note, _, _, class = GetGuildRosterInfo(i)
        local entry = cache[name]
        entry.name = name
        entry.rank = rank
        entry.class = class
        entry.seen = true
        if note == entry.note then
          if entry.dirty then
            Debug("Entry for %s written by another client", name)
            entry.dirty = nil
          end
        else
          if entry.dirty then
            Debug("Writing out note for %s [%s]", name, entry.note)
            GuildRosterSetOfficerNote(i, entry.note)
            entry.dirty = nil
          else
            Debug("Reading note for %s [%s]", name, note)
            entry:SetNote(note)
          end
        end
        if i % BATCH_SIZE == 0 then
          C:Sleep(0)
        end
      end
      C:Sleep(0)
      for name, entry in pairs(cache) do
        if not entry.seen then
          Debug("Deleting info for %s", name)
          entry:RemoveMain()
          entry.note = ""  -- reset ep,gp if this is a main for an someone.
          cache[name] = nil
        else
          entry.seen = false
        end
      end
    end

    while true do
      GuildRoster()
      C:WaitForEvent("GUILD_ROSTER_UPDATE")
      ParseGuildRoster()
    end
  end)
