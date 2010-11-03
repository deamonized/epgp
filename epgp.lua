-- This is the core addon.

local Debug = LibStub("LibDebug-1.0")
Debug:EnableDebugging()
local L = LibStub("AceLocale-3.0"):GetLocale("EPGP")

EPGP = LibStub("AceAddon-3.0"):NewAddon(
  "EPGP", "AceComm-3.0", "AceEvent-3.0", "AceConsole-3.0")
local EPGP = EPGP
EPGP:SetDefaultModuleState(false)
local modulePrototype = {
  IsDisabled = function (self, i) return not self:IsEnabled() end,
  SetEnabled = function (self, i, v)
                 if v then
                   Debug("Enabling module: %s", self:GetName())
                   self:Enable()
                 else
                   Debug("Disabling module: %s", self:GetName())
                   self:Disable()
                 end
                 self.db.profile.enabled = v
               end,
  GetDBVar = function (self, i) return self.db.profile[i[#i]] end,
  SetDBVar = function (self, i, v) self.db.profile[i[#i]] = v end,
}
EPGP:SetDefaultModulePrototype(modulePrototype)

local version = GetAddOnMetadata('EPGP', 'Version')
if not version or #version == 0 then
  version = "(development)"
end
EPGP.version = version

local CallbackHandler = LibStub("CallbackHandler-1.0")
if not EPGP.callbacks then
  EPGP.callbacks = CallbackHandler:New(EPGP)
end
local callbacks = EPGP.callbacks

local ep_data = {}
local gp_data = {}
local main_data = {}
local alt_data = {}
local ignored = {}
local standings = {}
local selected = {}
selected._count = 0  -- This is safe since _ is not allowed in names

local function EncodeNote(ep, gp)
  return string.format("%d,%d",
                       math.max(ep, 0),
                       math.max(gp - EPGP.db.profile.base_gp, 0))
end

local function AddEPGP(name, ep, gp)
  local total_ep = ep_data[name]
  local total_gp = gp_data[name]
  assert(total_ep ~= nil and total_gp ~=nil,
         string.format("%s is not a main!", tostring(name)))

  -- Compute the actual amounts we can add/subtract.
  if (total_ep + ep) < 0 then
    ep = -total_ep
  end
  if (total_gp + gp) < 0 then
    gp = -total_gp
  end

  GS:SetNote(name, EncodeNote(total_ep + ep,
                              total_gp + gp + EPGP.db.profile.base_gp))
  return ep, gp
end

-- A wrapper function to handle sort logic for selected
local function ComparatorWrapper(f)
  return function(a, b)
           local a_in_raid = not not UnitInRaid(a)
           local b_in_raid = not not UnitInRaid(b)
           if a_in_raid ~= b_in_raid then
             return not b_in_raid
           end

           local a_selected = selected[a]
           local b_selected = selected[b]

           if a_selected ~= b_selected then
             return not b_selected
           end

           return f(a, b)
         end
end

local comparators = {
  NAME = function(a, b)
           return a < b
         end,
  EP = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         return a_ep > b_ep
       end,
  GP = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         return a_gp > b_gp
       end,
  PR = function(a, b)
         local a_ep, a_gp = EPGP:GetEPGP(a)
         local b_ep, b_gp = EPGP:GetEPGP(b)

         local a_qualifies = a_ep >= EPGP.db.profile.min_ep
         local b_qualifies = b_ep >= EPGP.db.profile.min_ep

         if a_qualifies == b_qualifies then
           return a_ep/a_gp > b_ep/b_gp
         else
           return a_qualifies
         end
       end,
}
for k,f in pairs(comparators) do
  comparators[k] = ComparatorWrapper(f)
end

local function DestroyStandings()
  wipe(standings)
  callbacks:Fire("StandingsChanged")
end

local function RefreshStandings(order, showEveryone)
  Debug("Resorting standings")
  if UnitInRaid("player") then
    -- If we are in raid:
    ---  showEveryone = true: show all in raid (including alts) and
    ---  all leftover mains
    ---  showEveryone = false: show all in raid (including alts) and
    ---  all selected members
    for n in pairs(ep_data) do
      if showEveryone or UnitInRaid(n) or selected[n] then
        table.insert(standings, n)
      end
    end
    for n in pairs(main_data) do
      if UnitInRaid(n) or selected[n] then
        table.insert(standings, n)
      end
    end
  else
    -- If we are not in raid, show all mains
    for n in pairs(ep_data) do
      table.insert(standings, n)
    end
  end

  -- Sort
  table.sort(standings, comparators[order])
end

local function DeleteState(name)
  ignored[name] = nil
  -- If this is was an alt we need to fix the alts state
  local main = main_data[name]
  if main then
    if alt_data[main] then
      for i,alt in ipairs(alt_data[main]) do
        if alt == name then
          table.remove(alt_data[main], i)
          break
        end
      end
    end
    main_data[name] = nil
  end
  -- Delete any existing cached values
  ep_data[name] = nil
  gp_data[name] = nil
end

local function HandleDeletedGuildNote(callback, name)
  DeleteState(name)
  DestroyStandings()
end

function EPGP:StandingsShowEveryone(val)
  if val == nil then
    return self.db.profile.show_everyone
  end

  self.db.profile.show_everyone = not not val
  DestroyStandings()
end

function EPGP:GetNumMembers()
  if #standings == 0 then
    RefreshStandings(self.db.profile.sort_order, self.db.profile.show_everyone)
  end

  return #standings
end

function EPGP:SelectMember(name)
  if UnitInRaid("player") then
    -- Only allow selecting members that are not in raid when in raid.
    if UnitInRaid(name) then
      return false
    end
  end
  selected[name] = true
  selected._count = selected._count + 1
  DestroyStandings()
  return true
end

function EPGP:DeSelectMember(name)
  if UnitInRaid("player") then
    -- Only allow deselecting members that are not in raid when in raid.
    if UnitInRaid(name) then
      return false
    end
  end
  if not selected[name] then
    return false
  end
  selected[name] = nil
  selected._count = selected._count - 1
  DestroyStandings()
  return true
end

function EPGP:GetNumMembersInAwardList()
  if UnitInRaid("player") then
    return GetNumRaidMembers() + selected._count
  else
    if selected._count == 0 then
      return self:GetNumMembers()
    else
      return selected._count
    end
  end
end

function EPGP:IsMemberInAwardList(name)
  if UnitInRaid("player") then
    -- If we are in raid the member is in the award list if it is in
    -- the raid or the selected list.
    return UnitInRaid(name) or selected[name]
  else
    -- If we are not in raid and there is noone selected everyone will
    -- get an award.
    if selected._count == 0 then
      return true
    end
    return selected[name]
  end
end

function EPGP:IsMemberInExtrasList(name)
  return UnitInRaid("player") and selected[name]
end

function EPGP:IsAnyMemberInExtrasList()
  return selected._count ~= 0
end

function EPGP:CanResetEPGP()
  return CanEditOfficerNote()
end

function EPGP:ResetEPGP()
  assert(EPGP:CanResetEPGP())

  local zero_note = EncodeNote(0, 0)
  for name,_ in pairs(ep_data) do
    GS:SetNote(name, zero_note)
    local ep, gp, main = self:GetEPGP(name)
    assert(main == nil, "Corrupt alt data!")
    if ep > 0 then
      callbacks:Fire("EPAward", name, "Reset", -ep, true)
    end
    if gp > 0 then
      callbacks:Fire("GPAward", name, "Reset", -gp, true)
    end
  end
  callbacks:Fire("EPGPReset")
end

function EPGP:CanDecayEPGP()
  if not CanEditOfficerNote() or EPGP.db.profile.decay_p == 0 then
    return false
  end
  return true
end

function EPGP:DecayEPGP()
  assert(EPGP:CanDecayEPGP())

  local decay = EPGP.db.profile.decay_p  * 0.01
  local reason = string.format("Decay %d%%", EPGP.db.profile.decay_p)
  for name,_ in pairs(ep_data) do
    local ep, gp, main = self:GetEPGP(name)
    assert(main == nil, "Corrupt alt data!")
    local decay_ep = math.ceil(ep * decay)
    local decay_gp = math.ceil(gp * decay)
    decay_ep, decay_gp = AddEPGP(name, -decay_ep, -decay_gp)
    if decay_ep ~= 0 then
      callbacks:Fire("EPAward", name, reason, decay_ep, true)
    end
    if decay_gp ~= 0 then
      callbacks:Fire("GPAward", name, reason, decay_gp, true)
    end
  end
  callbacks:Fire("Decay", EPGP.db.profile.decay_p)
end

function EPGP:GetEPGP(name)
  local main = main_data[name]
  if main then
    name = main
  end
  if ep_data[name] then
    return ep_data[name], gp_data[name] + EPGP.db.profile.base_gp, main
  end
end

function EPGP:GetClass(name)
  return GS:GetClass(name)
end

function EPGP:CanIncEPBy(reason, amount)
  if not CanEditOfficerNote() then
    return false
  end
  if type(reason) ~= "string" or type(amount) ~= "number" or #reason == 0 then
    return false
  end
  if amount ~= math.floor(amount + 0.5) then
    return false
  end
  if amount < -99999 or amount > 99999 or amount == 0 then
    return false
  end
  return true
end

function EPGP:IncEPBy(name, reason, amount, mass, undo)
  -- When we do mass EP or decay we know what we are doing even though
  -- CanIncEPBy returns false
  assert(EPGP:CanIncEPBy(reason, amount) or mass or undo)
  assert(type(name) == "string")

  local ep, gp, main = self:GetEPGP(name)
  if not ep then
    self:Print(L["Ignoring EP change for unknown member %s"]:format(name))
    return
  end
  amount = AddEPGP(main or name, amount, 0)
  if amount then
    callbacks:Fire("EPAward", name, reason, amount, mass, undo)
  end
  self.db.profile.last_awards[reason] = amount
  return main or name
end

function EPGP:CanIncGPBy(reason, amount)
  if not CanEditOfficerNote() then
    return false
  end
  if type(reason) ~= "string" or type(amount) ~= "number" or #reason == 0 then
    return false
  end
  if amount ~= math.floor(amount + 0.5) then
    return false
  end
  if amount < -99999 or amount > 99999 or amount == 0 then
    return false
  end
  return true
end

function EPGP:IncGPBy(name, reason, amount, mass, undo)
  -- When we do mass GP or decay we know what we are doing even though
  -- CanIncGPBy returns false
  assert(EPGP:CanIncGPBy(reason, amount) or mass or undo)
  assert(type(name) == "string")

  local ep, gp, main = self:GetEPGP(name)
  if not ep then
    self:Print(L["Ignoring GP change for unknown member %s"]:format(name))
    return
  end
  _, amount = AddEPGP(main or name, 0, amount)
  if amount then
    callbacks:Fire("GPAward", name, reason, amount, mass, undo)
  end

  return main or name
end

function EPGP:BankItem(reason, undo)
  callbacks:Fire("BankedItem", GUILD_BANK, reason, 0, false, undo)
end

function EPGP:GetDecayPercent()
  return EPGP.db.profile.decay_p
end

function EPGP:GetExtrasPercent()
  return EPGP.db.profile.extras_p
end

function EPGP:GetBaseGP()
  return EPGP.db.profile.base_gp
end

function EPGP:GetMinEP()
  return EPGP.db.profile.min_ep
end

function EPGP:SetGlobalConfiguration(decay_p, extras_p, base_gp, min_ep)
  local guild_info = GetGuildInfoText()
  epgp_stanza = string.format(
    "-EPGP-\n@DECAY_P:%d\n@EXTRAS_P:%s\n@MIN_EP:%d\n@BASE_GP:%d\n-EPGP-",
    decay_p or DEFAULT_DECAY_P,
    extras_p or DEFAULT_EXTRAS_P,
    min_ep or DEFAULT_MIN_EP,
    base_gp or DEFAULT_BASE_GP)

  -- If we have a global configuration stanza we need to replace it
  Debug("epgp_stanza:\n%s", epgp_stanza)
  if guild_info:match("%-EPGP%-.*%-EPGP%-") then
    guild_info = guild_info:gsub("%-EPGP%-.*%-EPGP%-", epgp_stanza)
  else
    guild_info = epgp_stanza.."\n"..guild_info
  end
  Debug("guild_info:\n%s", guild_info)
  SetGuildInfoText(guild_info)
  GuildRoster()
end

function EPGP:GetMain(name)
  return main_data[name] or name
end

function EPGP:IncMassEPBy(reason, amount)
  local awarded = {}
  local extras_awarded = {}
  local extras_amount = math.floor(EPGP.db.profile.extras_p * 0.01 * amount)
  local extras_reason = reason .. " - " .. L["Standby"]

  for i=1,EPGP:GetNumMembers() do
    local name = EPGP:GetMember(i)
    if EPGP:IsMemberInAwardList(name) then
      -- EPGP:GetMain() will return the input name if it doesn't find a main,
      -- so we can't use it to validate that this actually is a character who
      -- can recieve EP.
      --
      -- EPGP:GetEPGP() returns nil for ep and gp, if it can't find a
      -- valid member based on the name however.
      local ep, gp, main = EPGP:GetEPGP(name)
      local main = main or name
      if ep and not awarded[main] and not extras_awarded[main] then
        if EPGP:IsMemberInExtrasList(name) then
          EPGP:IncEPBy(name, extras_reason, extras_amount, true)
          extras_awarded[name] = true
        else
          EPGP:IncEPBy(name, reason, amount, true)
          awarded[name] = true
        end
      end
    end
  end
  if next(awarded) then
    if next(extras_awarded) then
      callbacks:Fire("MassEPAward", awarded, reason, amount,
                     extras_awarded, extras_reason, extras_amount)
    else
      callbacks:Fire("MassEPAward", awarded, reason, amount)
    end
  end
end

function EPGP:ReportErrors(outputFunc)
  for name, note in pairs(ignored) do
    outputFunc(L["Invalid officer note [%s] for %s (ignored)"]:format(
                 note, name))
  end
end

local db
function EPGP:OnInitialize()
  -- Setup the DB. The DB will NOT be ready until after OnEnable is
  -- called on EPGP. We do not call OnEnable on modules until after
  -- the DB is ready to use.
  db = LibStub("AceDB-3.0"):New("EPGP_DB")

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
  db:RegisterDefaults(defaults)
  for name, module in self:IterateModules() do
    -- Each module gets its own namespace. If a module needs to set
    -- defaults, module.dbDefaults needs to be a table with
    -- defaults. Otherwise we initialize it to be enabled by default.
    if not module.dbDefaults then
      module.dbDefaults = {
        profile = {
          enabled = true
        }
      }
    end
    module.db = db:RegisterNamespace(name, module.dbDefaults)
  end
  -- After the database objects are created, we setup the
  -- options. Each module can inject its own options by defining:
  --
  -- * module.optionsName: The name of the options group for this module
  -- * module.optionsDesc: The description for this options group [short]
  -- * module.optionsArgs: The definition of this option group
  --
  -- In addition to the above EPGP will add an Enable checkbox for
  -- this module. It is also guaranteed that the name of the node this
  -- group will be in, is the same as the name of the module. This
  -- means you can get the name of the module from the info table
  -- passed to the callback functions by doing info[#info-1].
  --
  self:SetupOptions()

  -- New version note.
  if db.global.last_version ~= EPGP.version then
    db.global.last_version = EPGP.version
    StaticPopup_Show("EPGP_NEW_VERSION")
  end
end

function EPGP:RAID_ROSTER_UPDATE()
  if UnitInRaid("player") then
    -- If we are in a raid, make sure no member of the raid is
    -- selected
    for name,_ in pairs(selected) do
      if UnitInRaid(name) then
        selected[name] = nil
        selected._count = selected._count - 1
      end
    end
  else
    -- If we are not in a raid, this means we just left so remove
    -- everyone from the selected list.
    wipe(selected)
    selected._count = 0
    -- We also need to stop any recurring EP since they should stop
    -- once a raid stops.
    if self:RunningRecurringEP() then
      self:StopRecurringEP()
    end
  end
  DestroyStandings()
end

function EPGP:GUILD_ROSTER_UPDATE()
  if not IsInGuild() then
    for name, module in EPGP:IterateModules() do
      module:Disable()
    end
  else
    local guild = GetGuildInfo("player") or ""
    if #guild == 0 then
      Debug("Got empty guild. Running GuildRoster() again")
      GuildRoster()
    else
      if db:GetCurrentProfile() ~= guild then
        Debug("Setting DB profile to: %s", guild)
        db:SetProfile(guild)
      end
      -- This means we didn't initialize the db yet.
      if not EPGP.db then
        EPGP.db = db

        -- Enable all modules that are supposed to be enabled
        for name, module in EPGP:IterateModules() do
          if module.db.profile.enabled or not module.dbDefaults then
            Debug("Enabling module (startup): %s", name)
            module:Enable()
          end
        end
        -- Check if we have a recurring award we can resume
        if EPGP:CanResumeRecurringEP() then
          EPGP:ResumeRecurringEP()
        else
          EPGP:CancelRecurringEP()
        end
      end
    end
  end
end

function EPGP:OnEnable()
  self:RegisterEvent("RAID_ROSTER_UPDATE")
  self:RegisterEvent("GUILD_ROSTER_UPDATE")
  self:RegisterComm("EPGP_Sync", "ProcessSync")
  GuildRoster()
end
