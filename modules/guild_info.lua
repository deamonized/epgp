local mod = EPGP:NewModule("guild_info", "AceEvent-3.0")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

-- Parse options. Options are inside GuildInfo and are inside a -EPGP-
-- block. Possible options are:
--
-- @DECAY_P:<number>
-- @EXTRAS_P:<number>
-- @MIN_EP:<number>
-- @BASE_GP:<number>
local global_config_defs = {
  decay_p = {
    pattern = "@DECAY_P:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 and v <= 100 end,
    error = L["Decay Percent should be a number between 0 and 100"],
    default = 0,
    change_message = "DecayPercentChanged",
  },
  extras_p = {
    pattern = "@EXTRAS_P:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 and v <= 100 end,
    error = L["Extras Percent should be a number between 0 and 100"],
    default = 100,
    change_message = "ExtrasPercentChanged",
  },
  min_ep = {
    pattern = "@MIN_EP:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 end,
    error = L["Min EP should be a positive number"],
    default = 0,
    change_message = "MinEPChanged",
  },
  base_gp = {
    pattern = "@BASE_GP:(%d+)",
    parser = tonumber,
    validator = function(v) return v >= 0 end,
    error = L["Base GP should be a positive number"],
    default = 1,
    change_message = "BaseGPChanged",
  },
}

function mod:GUILD_ROSTER_UPDATE()
  assert(self:IsEnabled())

  local info = GetGuildInfoText()
  if not info or #info == 0 then
    Debug("GuildInfoText empty or nil, ignoring")
    GuildRoster()
    return
  end
  Debug("Parsing GuildInfoText")

  local lines = {string.split("\n", info)}
  local in_block = false

  local new_config = {}

  for _,line in pairs(lines) do
    if line == "-EPGP-" then
      in_block = not in_block
    elseif in_block then
      for var, def in pairs(global_config_defs) do
        local v = line:match(def.pattern)
        if v then
          Debug("Matched [%s]", line)
          v = def.parser(v)
          if v == nil or not def.validator(v) then
            Debug(def.error)
          else
            new_config[var] = v
          end
        end
      end
    end
  end
  for var, def in pairs(global_config_defs) do
    local old_value = EPGP.db.profile[var]
    self.db.profile[var] = new_config[var] or def.default
    if old_value ~= EPGP.db.profile[var] then
      Debug("%s changed from %s to %s", var, old_value, self.db.profile[var])
      self:SendMessage(def.change_message, self.db.profile[var])
    end
  end
end

function mod:OnEnable()
  self:RegisterEvent("GUILD_ROSTER_UPDATE")
end