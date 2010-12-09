local mod = EPGP:NewModule("announce")

local Debug = LibStub("LibDebug-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

local SendChatMessage = _G.SendChatMessage
if ChatThrottleLib then
  SendChatMessage = function(...)
                      ChatThrottleLib:SendChatMessage("NORMAL", "EPGP", ...)
                    end
end

function mod:Announce(msg)
  local medium = self.db.profile.medium
  if not medium then return end

  local channel = GetChannelName(self.db.profile.channel or 0)

  -- Override raid and party if we are not grouped
  if (medium == "RAID" or medium == "GUILD") and not UnitInRaid("player") then
    medium = "GUILD"
  end

  local str = "EPGP:"
  for _,s in pairs({strsplit(" ", msg)}) do
    if #str + #s >= 250 then
      SendChatMessage(str, medium, nil, channel)
      str = "EPGP:"
    end
    str = str .. " " .. s
  end

  SendChatMessage(str, medium, nil, channel)
end

local function Wrapper(handler)
  return function(self, kind, changer, ...)
           if changer ~= UnitName("player") then return end
           return handler(self, kind, changer, ...)
         end
end

mod[EPGP.CHANGE_REQUEST] = Wrapper(
  function(self, kind, ...) self:Announce(EPGP.FormatChangeRequest(...)) end)

mod[EPGP.DECAY_REQUEST] = Wrapper(
  function(self, kind, ...) self:Announce(EPGP.FormatDecayRequest(...)) end)

function mod:StartRecurringAward(event_name, reason, amount, mins)
  local fmt, val = SecondsToTimeAbbrev(mins * 60)
  mod:Announce(L["Start recurring award (%s) %d EP/%s"], reason, amount, fmt:format(val))
end

function mod:ResumeRecurringAward(event_name, reason, amount, mins)
  local fmt, val = SecondsToTimeAbbrev(mins * 60)
  mod:Announce(L["Resume recurring award (%s) %d EP/%s"], reason, amount, fmt:format(val))
end

function mod:StopRecurringAward(event_name)
  mod:Announce(L["Stop recurring award"])
end

function mod:EPGPReset(event_name)
  mod:Announce(L["EP/GP are reset"])
end

mod.dbDefaults = {
  profile = {
    enabled = true,
    medium = "GUILD",
    events = {
      ['*'] = true,
    },
  }
}

mod.optionsName = L["Announce"]
mod.optionsDesc = L["Announcement of EPGP actions"]
mod.optionsArgs = {
  help = {
    order = 1,
    type = "description",
    name = L["Announces EPGP actions to the specified medium."],
  },
  medium = {
    order = 10,
    type = "select",
    name = L["Announce medium"],
    desc = L["Sets the announce medium EPGP will use to announce EPGP actions."],
    values = {
      ["GUILD"] = CHAT_MSG_GUILD,
      ["OFFICER"] = CHAT_MSG_OFFICER,
      ["RAID"] = CHAT_MSG_RAID,
      ["PARTY"] = CHAT_MSG_PARTY,
      ["CHANNEL"] = CUSTOM,
    },
  },
  channel = {
    order = 11,
    type = "input",
    name = L["Custom announce channel name"],
    desc = L["Sets the custom announce channel name used to announce EPGP actions."],
    disabled = function(i) return mod.db.profile.medium ~= "CHANNEL" end,
  },
  events = {
    order = 12,
    type = "multiselect",
    name = L["Announce on:"],
    values = {
      [EPGP.CHANGE_REQUEST] = L["EP and/or GP awards"],
      [EPGP.DECAY_REQUEST] = L["EPGP decay"],
      --StartRecurringAward = L["Recurring awards start"],
      --StopRecurringAward = L["Recurring awards stop"],
      --ResumeRecurringAward = L["Recurring awards resume"],
      --EPGPReset = L["EPGP reset"],
    },
    width = "full",
    get = "GetEvent",
    set = "SetEvent",
  },
}

function mod:GetEvent(i, e)
  return self.db.profile.events[e]
end

function mod:SetEvent(i, e, v)
  if v then
    Debug("Enabling announce of: %s", e)
    EPGP:GetModule("slave").RegisterMessage(self, e)
  else
    Debug("Disabling announce of: %s", e)
    EPGP:GetModule("slave").UnregisterMessage(self, e)
  end
  self.db.profile.events[e] = v
end

function mod:OnModuleEnable()
  for e, _ in pairs(mod.optionsArgs.events.values) do
    if self.db.profile.events[e] then
      Debug("Enabling announce of: %s (startup)", e)
      EPGP:GetModule("slave").RegisterMessage(self, e)
    end
  end
end

function mod:OnModuleDisable()
  EPGP:GetModule("slave").UnregisterAllCallbacks(self)
end
