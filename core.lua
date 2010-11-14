-- This is the core addon.

local Debug = LibStub("LibDebug-1.0")
Debug:EnableDebugging()
Debug:Toggle()
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

local EPGP = LibStub("AceAddon-3.0"):NewAddon(
  "EPGP", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- The callbacks.
local callbacks = LibStub("CallbackHandler-1.0"):New(EPGP)
EPGP.callbacks = callbacks

_G.EPGP = EPGP

-- Comm strings.
-- no args
EPGP.MASTER_ELECTION = "EPGP_MaEle"
-- no args
EPGP.MASTER_VICTORY = "EPGP_MaVic"
-- REQUESTOR,ID,REASON(,NAME,CN,EP,RAW_GP)+
EPGP.CHANGE_ANNOUNCE = "EPGP_ChAnn"
-- ID,REASON,DELTA_EP,DELTA_GP(,NAME)+
EPGP.CHANGE_REQUEST = "EPGP_ChReq"

-- The module prototype.

-- Addon and modules start disabled. See GUILD_ROSTER_UPDATE for why.
EPGP:SetEnabledState(false)
EPGP:SetDefaultModuleState(false)


-- EPGP modules are special. They already have OnInitialize, OnEnable
-- and OnDisable functions defined. Developers should override
-- OnModuleInitialize, OnModuleEnable and OnModuleDisable instead.

local moduleProto = {}
function moduleProto:IsDisabled(self, i)
  return not self:IsEnabled()
end
function moduleProto:SetEnabled (self, i, v)
  if v then
    Debug("Enabling module: %s", self:GetName())
    self:Enable()
  else
    Debug("Disabling module: %s", self:GetName())
    self:Disable()
  end
  self.db.profile.enabled = v
end
function moduleProto:GetDBVar(self, i)
  return self.db.profile[i[#i]]
end
function moduleProto:SetDBVar(self, i, v)
  self.db.profile[i[#i]] = v
end
function moduleProto:OnEnable()
  -- If we are about to be enabled but the config says we should not,
  -- disable now.
  if not self.db.profile.enabled then
    self:Disable()
    return
  end

  if self.OnModuleEnable then self:OnModuleEnable() end
  Debug("Enabled module: %s", self:GetName())
end
function moduleProto:OnDisable()
  if self.OnModuleDisable then self:OnModuleDisable() end
  Debug("Disabled module: %s", self:GetName())
end
function moduleProto:OnInitialize()
  if self.OnModuleInitialize then self:OnModuleInitialize() end
end

EPGP:SetDefaultModulePrototype(moduleProto)

function EPGP:OnInitialize()
  -- The db.
  self.db = LibStub("AceDB-3.0"):New("EPGP_DB")

  -- Grab the version.
  self.version = GetAddOnMetadata('EPGP', 'Version')
  if not self.version or #self.version == 0 then
    self.version = "(development)"
  end

  -- Set the global defaults.
  local defaults = {
    profile = {
      last_awards = {},
      show_everyone = false,
      sort_order = "PR",
      recurring_ep_period_mins = 15,
      decay_p = 0,
      extras_p = 100,
      min_ep = 0,
      base_gp = 1,
    }
  }
  self.db:RegisterDefaults(defaults)

  -- Each module gets its own namespace. If a module needs to set
  -- defaults, module.dbDefaults needs to be a table with
  -- defaults. Otherwise we initialize it to be enabled by default.
  for name, module in self:IterateModules() do
    if not module.dbDefaults then
      module.dbDefaults = {
        profile = {
          enabled = true
        }
      }
    end
    module.db = self.db:RegisterNamespace(name, module.dbDefaults)
  end

  -- After the database objects are created, we setup the options.
  local options = {
    name = "EPGP",
    type = "group",
    childGroups = "tab",
    handler = self,
    args = {
      help = {
        order = 1,
        type = "description",
        name = L["EPGP is an in game, relational loot distribution system"],
      },
      hint = {
        order = 2,
        type = "description",
        name = L["Hint: You can open these options by typing /epgp config"],
      },
      list_errors = {
        order = 1000,
        type = "execute",
        name = L["List errors"],
        desc = L["Lists errors during officer note parsing to the default chat frame. Examples are members with an invalid officer note."],
        func = function()
                 outputFunc = function(s) DEFAULT_CHAT_FRAME:AddMessage(s) end
                 EPGP:ReportErrors(outputFunc)
               end,
      },
      reset = {
        order = 1001,
        type = "execute",
        name = L["Reset EPGP"],
        desc = L["Resets EP and GP of all members of the guild. This will set all main toons' EP and GP to 0. Use with care!"],
        func = function() StaticPopup_Show("EPGP_RESET_EPGP") end,
      },
    },
  }

  local registry = LibStub("AceConfigRegistry-3.0")
  registry:RegisterOptionsTable("EPGP Options", options)

  local dialog = LibStub("AceConfigDialog-3.0")
  dialog:AddToBlizOptions("EPGP Options", "EPGP")

  -- Each module can inject its own options by defining:
  -- * module.optionsName: The name of the options group for this module
  -- * module.optionsDesc: The description for this options group [short]
  -- * module.optionsArgs: The definition of this option group
  --
  -- In addition to the above EPGP will add an Enable checkbox for
  -- this module. It is also guaranteed that the name of the node this
  -- group will be in, is the same as the name of the module. This
  -- means you can get the name of the module from the info table
  -- passed to the callback functions by doing info[#info-1].
  for name, m in self:IterateModules() do
    if m.optionsArgs then
      -- Set all options under this module as disabled when the module
      -- is disabled.
      for n, o in pairs(m.optionsArgs) do
        if o.disabled then
          local old_disabled = o.disabled
          o.disabled = function(i)
                         return old_disabled(i) or m:IsDisabled()
                       end
        else
          o.disabled = "IsDisabled"
        end
      end
      -- Add the enable/disable option.
      m.optionsArgs.enabled = {
        order = 0,
        type = "toggle",
        width = "full",
        name = ENABLE,
        get = "IsEnabled",
        set = "SetEnabled",
      }
    end
    if m.optionsName then
      registry:RegisterOptionsTable("EPGP " .. name, {
                                      handler = m,
                                      order = 100,
                                      type = "group",
                                      name = m.optionsName,
                                      desc = m.optionsDesc,
                                      args = m.optionsArgs,
                                      get = "GetDBVar",
                                      set = "SetDBVar",
                                    })
      dialog:AddToBlizOptions("EPGP " .. name, m.optionsName, "EPGP")
    end
  end

  -- We register this event before we are even enabled because this
  -- event controls initialization.
  self:RegisterEvent("GUILD_ROSTER_UPDATE")
end

function EPGP:OnEnable()
  -- Display any notes if this is a new version.
  if self.db.global.last_version ~= self.version then
    self.db.global.last_version = self.version
    StaticPopup_Show("EPGP_NEW_VERSION")
  end

  -- Set enabled state on all modules otherwise they won't be enabled
  -- after this call returns.
  for name, module in self:IterateModules() do
    module:SetEnabledState(true)
  end

  Debug("Enabled EPGP")
end

function EPGP:OnDisable()
  -- OnEmbedDisable is called after OnDisable. This means AceEvent's
  -- OnEmbedDisable will unregister all handlers. So after this is
  -- done, we need to register again for GUILD_ROSTER_UPDATE so that
  -- we are enabled again when we join a guild. To do this we schedule
  -- a timer to grab the event. Yuck indeed :-p
  self:ScheduleTimer("RegisterEvent", 0, "GUILD_ROSTER_UPDATE")
  Debug("Disabled EPGP")
end

function EPGP:GUILD_ROSTER_UPDATE()
  -- This is a special GUILD_ROSTER_UPDATE handler. This handles
  -- enabling/disabling the addon and gathering basic information the
  -- addon and its modules depend on.
  if not IsInGuild() then
    self:Disable()
  else
    if not self:IsEnabled() then
      -- If we are not enabled this means we haven't finished
      -- initializing for this guild yet. Set profile and enable modules.
      local guild = GetGuildInfo("player")
      if not guild or #guild == 0 then
        Debug("Got empty guild. Running GuildRoster() again")
        GuildRoster()
        return
      else
        if self.db:GetCurrentProfile() ~= guild then
          Debug("Setting DB profile to: %s", guild)
          self.db:SetProfile(guild)
        end
        self:Enable()
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Utitily functions.
function EPGP.Profile(fn, msg)
  return function(...)
           Debug(msg)
           debugprofilestart()
           local ret = {fn(...)}
           local time_ms = debugprofilestop()
           Debug("%s (%.2fms)", msg, time_ms)
           return unpack(ret)
         end
end

function EPGP.Map(fn, ...)
  local r = {}
  for i=1,select('#', ...) do
    local item = select(i, ...)
    r[i] = fn(item)
  end
  return unpack(r)
end

function EPGP.MapT(fn, t)
  local r = {}
  for i,v in ipairs(t) do
    r[i] = fn(v)
  end
  return r
end

function EPGP.All(...)
  for i=1,select('#', ...) do
    local item = select(i, ...)
    if not item then
      return false
    end
  end
  return true
end

function EPGP.Any(...)
  for i=1,select('#', ...) do
    local item = select(i, ...)
    if item then
      return true
    end
  end
  return false
end

function EPGP.Not(pred)
  return function(...) return not pred(...) end
end

function EPGP.IsString(v)
  return type(v) == "string"
end

function EPGP.IsNumber(v)
  return type(v) == "number"
end

function EPGP.IsInteger(v)
  return EPGP.IsNumber(v) and math.floor(v + 0.5) == v
end

function EPGP.Between(a, b)
  return function(v) return v > a and v < b end
end

function EPGP.EqualTo(a)
  return function(v) return a == v end
end

function EPGP.TableInsert(t, ...)
  for i=1,select('#', ...) do
    local item = select(i, ...)
    table.insert(t, item)
  end
end

local Map = EPGP.Map
local TableInsert = EPGP.TableInsert

function EPGP.ParseChangeAnnounce(msg)
  local requestor, id, reason, rest = msg:match("([^,]+),(%d+),([^,]+),(.+)")
  id = tonumber(id)
  local ann = {requestor, id, reason}
  for name, seq, ep, raw_gp in rest:gmatch("([^,]+),(%d+),(%d+),(%d+)") do
    seq, ep, raw_gp = Map(tonumber, seq, ep, raw_gp)
    TableInsert(ann, name, seq, ep, raw_gp)
  end
  return ann
end

function EPGP.ParseChangeRequest(msg)
  local id, reason, delta_ep, delta_gp, rest = msg:match(
    "(%d+),([^,]+),(%d+),(%d+)(.+)")
  id, delta_ep, delta_gp = Map(tonumber, id, delta_ep, delta_gp)
  local req = {id, reason, delta_ep, delta_gp}
  for target in rest:gmatch(",([^,]+)") do
    table.insert(req, target)
  end
  return req
end
