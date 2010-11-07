-- This is the core addon.

local Debug = LibStub("LibDebug-1.0")
Debug:EnableDebugging()
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")
local GP = LibStub("LibGearPoints-1.0")

local EPGP = LibStub("AceAddon-3.0"):NewAddon(
  "EPGP", "AceComm-3.0", "AceEvent-3.0", "AceConsole-3.0")
-- The callbacks.
-- TODO(alkis): Use AceEvent:Messages instead.
EPGP.callbacks = LibStub("CallbackHandler-1.0"):New(EPGP)

_G.EPGP = EPGP

-- The module prototype.
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
EPGP:SetDefaultModulePrototype(moduleProto)

-- Addon and modules start disabled.
EPGP:SetEnabledState(false)
EPGP:SetDefaultModuleState(false)

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

  -- Display any notes if this is a new version.
  if self.db.global.last_version ~= self.version then
    self.db.global.last_version = self.version
    StaticPopup_Show("EPGP_NEW_VERSION")
  end

  -- This is a different GUILD_ROSTER_UPDATE handler. This handles
  -- enabling/disabling the addon and gathering basic information the
  -- whole addon depends on.
  local function GuildRosterUpdate()
    if not IsInGuild() then
      if self:IsEnabled() then
        for name, module in EPGP:IterateModules() do
          if module:Disable() then
            Debug("Disabled module (NotInGuild): %s", name)
          end
        end
        if self:Disable() then
          Debug("Disabled EPGP (NotInGuild)")
        end
      end
    else
      if not self:IsEnabled() then
        -- If we are not enabled this means we haven't finished
        -- initializing for this guild yet. Set profile and enable modules.
        local guild = GetGuildInfo("player") or ""
        if #guild == 0 then
          Debug("Got empty guild. Running GuildRoster() again")
          GuildRoster()
          return
        else
          if self.db:GetCurrentProfile() ~= guild then
            Debug("Setting DB profile to: %s", guild)
            self.db:SetProfile(guild)
          end
          if self:Enable() then
            Debug("Enabled EPGP (OnInit)")
          end
          -- Enable modules that are supposed to be enabled.
          for name, module in self:IterateModules() do
            if module.db.profile.enabled and module:Enable() then
              Debug("Enabled module (OnInit): %s", name)
            end
          end
        end
      end
      -- It is possible that we just got enabled.
      if self:IsEnabled() then
        -- TODO(alkis): More initialization goes here.
      end
    end
  end
  LibStub("AceEvent-3.0"):RegisterEvent("GUILD_ROSTER_UPDATE",
                                        GuildRosterUpdate)
end

function EPGP:OnEnable()
  EPGP:RegisterChatCommand("epgp", "ProcessChatCommand")
end

function EPGP:ProcessChatCommand(str)
  str = str:gsub("%%t", UnitName("target") or "notarget")
  local command, nextpos = self:GetArgs(str, 1)
  if command == "config" then
    InterfaceOptionsFrame_OpenToCategory("EPGP")
  elseif command == "debug" then
    Debug:Toggle()
  elseif command == "massep" then
    local reason, amount = self:GetArgs(str, 2, nextpos)
    amount = tonumber(amount)
    if self:CanIncEPBy(reason, amount) then
      self:IncMassEPBy(reason, amount)
    end
  elseif command == "ep" then
    local member, reason, amount = self:GetArgs(str, 3, nextpos)
    amount = tonumber(amount)
    if self:CanIncEPBy(reason, amount) then
      self:IncEPBy(member, reason, amount)
    end
  elseif command == "gp" then
    local member, itemlink, amount = self:GetArgs(str, 3, nextpos)
    self:Print(member, itemlink, amount)
    if amount then
      amount = tonumber(amount)
    else
      local gp1, gp2 = GP:GetValue(itemlink)
      self:Print(gp1, gp2)
      -- Only automatically fill amount if we have a single GP value.
      if gp1 and not gp2 then
        amount = gp1
      end
    end

    if self:CanIncGPBy(itemlink, amount) then
      self:IncGPBy(member, itemlink, amount)
    end
  elseif command == "decay" then
    if EPGP:CanDecayEPGP() then
      StaticPopup_Show("EPGP_DECAY_EPGP", EPGP:GetDecayPercent())
    end
  elseif command == "help" then
    local help = {
      self.version,
      "   config - "..L["Open the configuration options"],
      "   debug - "..L["Open the debug window"],
      "   massep <reason> <amount> - "..L["Mass EP Award"],
      "   ep <name> <reason> <amount> - "..L["Award EP"],
      "   gp <name> <itemlink> [<amount>] - "..L["Credit GP"],
      "   decay - "..L["Decay of EP/GP by %d%%"]:format(EPGP:GetDecayPercent()),
    }
    EPGP:Print(table.concat(help, "\n"))
  else
    EPGP:ToggleUI()
  end
end

function EPGP:ToggleUI()
  if EPGPFrame and IsInGuild() then
    if EPGPFrame:IsShown() then
      HideUIPanel(EPGPFrame)
    else
      ShowUIPanel(EPGPFrame)
    end
  end
end
