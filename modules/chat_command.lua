local mod = EPGP:NewModule("chat_command", "AceConsole-3.0")

local Debug = LibStub("LibDebug-1.0")

local GP = LibStub("LibGearPoints-1.0")

function mod:ProcessChatCommand(str)
  str = str:gsub("%%t", UnitName("target") or "notarget")
  local command, nextpos = self:GetArgs(str, 1)
  if command == "config" then
    InterfaceOptionsFrame_OpenToCategory("EPGP")
  elseif command == "debug" then
    Debug:Toggle()
  elseif command == "massep" then
    local reason, amount = self:GetArgs(str, 2, nextpos)
    amount = tonumber(amount)
    if EPGP:CanIncEPBy(reason, amount) then
      EPGP:IncMassEPBy(reason, amount)
    end
  elseif command == "ep" then
    local member, reason, amount = self:GetArgs(str, 3, nextpos)
    amount = tonumber(amount)
    if EPGP:CanIncEPBy(reason, amount) then
      EPGP:IncEPBy(member, reason, amount)
    end
  elseif command == "gp" then
    local member, itemlink, amount = self:GetArgs(str, 3, nextpos)
    EPGP:Print(member, itemlink, amount)
    if amount then
      amount = tonumber(amount)
    else
      local gp1, gp2 = GP:GetValue(itemlink)
      EPGP:Print(gp1, gp2)
      -- Only automatically fill amount if we have a single GP value.
      if gp1 and not gp2 then
        amount = gp1
      end
    end

    if EPGP:CanIncGPBy(itemlink, amount) then
      EPGP:IncGPBy(member, itemlink, amount)
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

function mod:ToggleUI()
  if EPGPFrame and IsInGuild() then
    if EPGPFrame:IsShown() then
      HideUIPanel(EPGPFrame)
    else
      ShowUIPanel(EPGPFrame)
    end
  end
end

function mod:OnEnable()
  self:RegisterChatCommand("epgp", "ProcessChatCommand")
end
