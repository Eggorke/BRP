sepgp = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceHook-2.1", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceModuleCore-2.0", "FuBarPlugin-2.0")
sepgp:SetModuleMixins("AceDebug-2.0")
local D = AceLibrary("Dewdrop-2.0")
local BZ = AceLibrary("Babble-Zone-2.2")
local C = AceLibrary("Crayon-2.0")
local BC = AceLibrary("Babble-Class-2.2")
local DF = AceLibrary("Deformat-2.0")
local G = AceLibrary("Gratuity-2.0")
local T = AceLibrary("Tablet-2.0")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")
sepgp.VARS = {
  basegp = 0,
  minep = 0,
  baseaward_ep = 10,
  baseaward_gp = 10,
  decay = 0.8,
  max = 1000,
  timeout = 60,
  minlevel = 55,
  maxloglines = 500,
  prefix = "SEPGP_PREFIX",
  reservechan = "Reserves",
  reserveanswer = "^(%+)(%a*)$",
  bop = C:Red("BoP"),
  boe = C:Yellow("BoE"),
  nobind = C:White("NoBind"),
  msgp = "Mainspec GP",
  osgp = "Offspec GP",
  bankde = "Bank-D/E",
  reminder = C:Red("Unassigned"),
}
sepgp.VARS.reservecall = string.format(L["{shootyepgp}Type \"+\" if on main, or \"+<YourMainName>\" (without quotes) if on alt within %dsec."],sepgp.VARS.timeout)
sepgp._playerName = (UnitName("player"))
local out = "|cff9664c8BRP:|r %s"
local raidStatus,lastRaidStatus
local lastUpdate = 0
local needInit,needRefresh = true
local admin,sanitizeNote
local shooty_debugchat
local running_check,running_bid
local partyUnit,raidUnit = {},{}
local hexColorQuality = {}
local reserves_blacklist,bids_blacklist = {},{}
local bidlink = {
}
local options
do
  for i=1,40 do
    raidUnit[i] = "raid"..i
  end
  for i=1,4 do
    partyUnit[i] = "party"..i
  end
  for i=-1,6 do
    hexColorQuality[ITEM_QUALITY_COLORS[i].hex] = i
  end
end
local admincmd, membercmd = {type = "group", handler = sepgp, args = {
    bids = {
      type = "execute",
      name = L["Bids"],
      desc = L["Show Bids Table."],
      func = function()
        sepgp_bids:Toggle()
      end,
      order = 1,
    },
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        sepgp_standings:Toggle()
      end,
      order = 2,
    },    
    clearloot = {
      type = "execute",
      name = L["ClearLoot"],
      desc = L["Clear Loot Table."],
      func = function()
        sepgp_looted = {}
        sepgp_loot:Refresh()
        sepgp:defaultPrint(L["Loot info cleared"])
      end,
      order = 3,
    },
    clearlogs = {
      type = "execute",
      name = L["ClearLogs"],
      desc = L["Clear Logs Table."],
      func = function()
        sepgp_log = {}
        sepgp_logs:Refresh()
        sepgp:defaultPrint(L["Logs cleared"])
      end,
      order = 4,
    },
    progress = {
      type = "execute",
      name = L["Progress"],
      desc = L["Print Progress Multiplier."],
      func = function()
        sepgp:defaultPrint(sepgp_progress)
      end,
      order = 5,
    },
    offspec = {
      type = "execute",
      name = L["Offspec"],
      desc = L["Print Offspec Price."],
      func = function()
        sepgp:defaultPrint(string.format("%s%%",sepgp_discount*100))
      end,
      order = 6,
    },    
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart brp if having startup problems."],
      func = function() 
        sepgp:OnEnable()
        sepgp:defaultPrint(L["Restarted"])
      end,
      order = 7,
    },
  }},
{type = "group", handler = sepgp, args = {
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        sepgp_standings:Toggle()
      end,
      order = 1,
    },
    progress = {
      type = "execute",
      name = L["Progress"],
      desc = L["Print Progress Multiplier."],
      func = function()
        sepgp:defaultPrint(sepgp_progress)
      end,
      order = 2,
    },
    offspec = {
      type = "execute",
      name = L["Offspec"],
      desc = L["Print Offspec Price."],
      func = function()
        sepgp:defaultPrint(string.format("%s%%",sepgp_discount*100))
      end,
      order = 3,
    },
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart brp if having startup problems."],
      func = function() 
        sepgp:OnEnable()
        sepgp:defaultPrint(L["Restarted"])
      end,
      order = 4,
    },    
  }}
  --[[{
    type = "execute",
    name = "Standings",
    desc = "Show Standings Table.",
    func = function()
      sepgp_standings:Toggle()
    end,
  }]]  
sepgp.cmdtable = function() 
  if (admin()) then
    return admincmd
  else
    return membercmd
  end
end
sepgp.reserves = {}
sepgp.bids_main,sepgp.bids_off,sepgp.bid_item = {},{},{}
sepgp.timer = CreateFrame("Frame")
sepgp.timer.cd_text = ""
sepgp.timer:Hide()
sepgp.timer:SetScript("OnUpdate",function() sepgp.OnUpdate(this,arg1) end)
sepgp.timer:SetScript("OnEvent",function() 
end)
sepgp.alts = {}

function sepgp:buildMenu()
  if not (options) then
    options = {
    type = "group",
    desc = L["shootyepgp options"],
    handler = self,
    args = { }
    }
    options.args["ep"] = {
      type = "group",
      name = L["|cff478ee5Naxx Points"],
      desc = L["Award Naxx Points for raid member."],
      order = 10,
      hidden = function() return not (admin()) end,
    }
    options.args["ep_raid"] = {
      type = "text",
      name = L["Naxx Points to Raid"],
      desc = L["Award Naxx Points to all raid members."],
      order = 20,
      get = "suggestedAwardEP",
      set = function(v) sepgp:award_raid_ep(tonumber(v)) end,
      usage = "<EP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < sepgp.VARS.max
      end
    }
    options.args["gp"] = {
      type = "group",
      name = L["|cff8c986cKara Points"],
      desc = L["Award Kara Points for raid member."],
      order = 30,
      hidden = function() return not (admin()) end,
    }
    options.args["gp_raid"] = {
      type = "text",
      name = L["Kara Points to Raid"],
      desc = L["Award Kara Points to all raid members."],
      order = 40,
      get = "suggestedAwardGP",
      set = function(v) sepgp:award_raid_gp(tonumber(v)) end,
      usage = "<GP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < sepgp.VARS.max
      end    
    }
    options.args["raid_only"] = {
      type = "toggle",
      name = L["|cfff4aa38Raid Only"],
      desc = L["Only show members in raid."],
      order = 80,
      get = function() return not not sepgp_raidonly end,
      set = function(v) 
        sepgp_raidonly = not sepgp_raidonly
        sepgp:SetRefresh(true)
      end,
    }
    options.args["report_channel"] = {
      type = "text",
      name = L["Reporting channel"],
      desc = L["Channel used by reporting functions."],
      order = 95,
      hidden = function() return not (admin()) end,
      get = function() return sepgp_saychannel end,
      set = function(v) sepgp_saychannel = v end,
      validate = { "PARTY", "RAID", "GUILD", "OFFICER" },
    }    
    options.args["decay"] = {
      type = "execute",
      name = L["|cff77ce5eDecay"],
      desc = string.format(L["Decays all by %s%%"],(1-(sepgp_decay or sepgp.VARS.decay))*100),
      order = 100,
      hidden = function() return not (admin()) end,
      func = function() sepgp:decay_epgp_v3() end 
    }    
    options.args["set_decay"] = {
      type = "range",
      name = L["Set Decay %"],
      desc = L["Set Decay percentage (Admin only)."],
      order = 110,
      usage = "<Decay>",
      get = function() return (1.0-sepgp_decay) end,
      set = function(v) 
        sepgp_decay = (1 - v)
        options.args["decay"].desc = string.format(L["Decays all by %s%%"],(1-sepgp_decay)*100)
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
      min = 0.01,
      max = 0.5,
      step = 0.01,
      bigStep = 0.05,
      isPercent = true,
      hidden = function() return not (admin()) end,    
    }
    options.args["reset"] = {
     type = "execute",
     name = L["|cffff4f00Reset Points"],
     desc = string.format(L["Resets everyone\'s Points to 0/%d (Admin only)."],sepgp.VARS.basegp),
     order = 120,
     hidden = function() return not (IsGuildLeader()) end,
     func = function() StaticPopup_Show("SHOOTY_EPGP_CONFIRM_RESET") end
    }
  end
  if (needInit) or (needRefresh) then
    local members = sepgp:buildRosterTable()
    -- self:debugPrint(string.format(L["Scanning %d members for Points data. (%s)"],table.getn(members),(sepgp_raidonly and "Raid" or "Full")))
    options.args["ep"].args = sepgp:buildClassMemberTable(members,"ep")
    options.args["gp"].args = sepgp:buildClassMemberTable(members,"gp")
    if (needInit) then needInit = false end
    if (needRefresh) then needRefresh = false end
  end
  return options
end

function sepgp:OnInitialize() -- ADDON_LOADED (1) unless LoD
  if sepgp_saychannel == nil then sepgp_saychannel = "GUILD" end
  if sepgp_decay == nil then sepgp_decay = sepgp.VARS.decay end
  if sepgp_minep == nil then sepgp_minep = sepgp.VARS.minep end
  if sepgp_progress == nil then sepgp_progress = "T1" end
  if sepgp_discount == nil then sepgp_discount = 0.25 end
  if sepgp_altspool == nil then sepgp_altspool = false end
  if sepgp_altpercent == nil then sepgp_altpercent = 1.0 end
  if sepgp_log == nil then sepgp_log = {} end
  if sepgp_looted == nil then sepgp_looted = {} end
  if sepgp_debug == nil then sepgp_debug = {} end
  self:RegisterDB("sepgp_fubar")
  self:RegisterDefaults("char",{})
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnInitialize"})
end

function sepgp:OnEnable() -- PLAYER_LOGIN (2)
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnEnable"})
  sepgp._playerLevel = UnitLevel("player")
  sepgp.extratip = (sepgp.extratip) or CreateFrame("GameTooltip","shootyepgp_tooltip",UIParent,"GameTooltipTemplate")
  sepgp._versionString = GetAddOnMetadata("shootyepgp","Version")
  sepgp._websiteString = GetAddOnMetadata("shootyepgp","X-Website")
  
  if (IsInGuild()) then
    if (GetNumGuildMembers()==0) then
      GuildRoster()
    end
  end

  self:RegisterEvent("GUILD_ROSTER_UPDATE",function() 
      if (arg1) then -- member join /leave
        sepgp:SetRefresh(true)
      end
    end)
  self:RegisterEvent("RAID_ROSTER_UPDATE",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  self:RegisterEvent("PARTY_MEMBERS_CHANGED",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  if sepgp._playerLevel and sepgp._playerLevel < MAX_PLAYER_LEVEL then
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
        if (arg1) then
          sepgp._playerLevel = tonumber(arg1)
          if sepgp._playerLevel == MAX_PLAYER_LEVEL then
            sepgp:UnregisterEvent("PLAYER_LEVEL_UP")
          end
          if sepgp._playerLevel and sepgp._playerLevel >= sepgp.VARS.minlevel then
            sepgp:testMain()
          end
        end
      end)
  end
  self:RegisterEvent("CHAT_MSG_RAID","captureLootCall")
  self:RegisterEvent("CHAT_MSG_RAID_LEADER","captureLootCall")
  self:RegisterEvent("CHAT_MSG_RAID_WARNING","captureLootCall")
  self:RegisterEvent("CHAT_MSG_WHISPER","captureBid")
  self:RegisterEvent("CHAT_MSG_LOOT","captureLoot")
  self:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED","tradeLoot")
  self:RegisterEvent("TRADE_ACCEPT_UPDATE","tradeLoot")

  if AceLibrary("AceEvent-2.0"):IsFullyInitialized() then
    self:AceEvent_FullyInitialized()
  else
    self:RegisterEvent("AceEvent_FullyInitialized")
  end
end

function sepgp:OnDisable()
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnDisable"})
  self:UnregisterAllEvents()
end

function sepgp:AceEvent_FullyInitialized() -- SYNTHETIC EVENT, later than PLAYER_LOGIN, PLAYER_ENTERING_WORLD (3)
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="AceEvent_FullyInitialized"})
  if self._hasInitFull then return end
  
  for i=1,NUM_CHAT_WINDOWS do
    local tab = getglobal("ChatFrame"..i.."Tab")
    local cf = getglobal("ChatFrame"..i)
    local tabName = tab:GetText()
    if tab ~= nil and (string.lower(tabName) == "debug") then
      shooty_debugchat = cf
      ChatFrame_RemoveAllMessageGroups(shooty_debugchat)
      shooty_debugchat:SetMaxLines(1024)
      break
    end
  end

  self:testMain()

  local delay = 2
  if self:IsEventRegistered("AceEvent_FullyInitialized") then
    self:UnregisterEvent("AceEvent_FullyInitialized")
    delay = 3
  end  
  if not self:IsEventScheduled("shootyepgpChannelInit") then
    self:ScheduleEvent("shootyepgpChannelInit",self.delayedInit,delay,self)
  end

  -- if pfUI loaded, skin the extra tooltip
  if not IsAddOnLoaded("pfUI-addonskins") then
    if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
      pfUI.api.CreateBackdrop(sepgp.extratip,nil,nil,tonumber(pfUI_config.tooltip.alpha))
    end
  end
  -- hook GiveMasterLoot to catch loot assign to members too far for chat parsing
  self:SecureHook("GiveMasterLoot")
  -- hook SetItemRef to parse our client bid links
  self:Hook("SetItemRef")
  -- hook tooltip to add our GP values
  self:TipHook()
  -- hook LootFrameItem_OnClick to add our own click handlers for bid calls
  self:SecureHook("LootFrameItem_OnClick")
  -- hook ContainerFrameItemButton_OnClick to add our own click handlers for bid calls
  self:Hook("ContainerFrameItemButton_OnClick")
  -- hook pfUI loot module :(
  if pfUI ~= nil and pfUI.loot ~= nil and type(pfUI.loot.UpdateLootFrame) == "function" then
    self:SecureHook(pfUI.loot, "UpdateLootFrame", "pfUI_UpdateLootFrame")
  end
  self._hasInitFull = true
end

sepgp._lastRosterRequest = false
function sepgp:OnMenuRequest()
  local now = GetTime()
  if not self._lastRosterRequest or (now - self._lastRosterRequest > 2) then
    self._lastRosterRequest = now
    self:SetRefresh(true)
    GuildRoster()
  end
  self._options = self:buildMenu()
  D:FeedAceOptionsTable(self._options)
end

function sepgp:TipHook()
  self:SecureHook(GameTooltip, "SetBagItem", function(this, bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    local ml_tip
    if (itemLink) then
      local is_master = (sepgp:lootMaster()) and true or nil
      local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
      if (link_found) then
        local bind = self:itemBinding(itemString) or ""
        ml_tip = is_master and bind == sepgp.VARS.boe
        if (ml_tip) then
          local frame = GetMouseFocus()
          if (frame) and (frame.IsFrameType ~= nil) and (frame:IsFrameType("Button"))  then
            if not (frame._hasExtraClicks) then
              frame:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
              frame._hasExtraClicks = true              
            end
          end
        end
      end
    end
  end
  )
  self:SecureHook(GameTooltip, "SetLootItem", function(this, slot)
    local is_master = (sepgp:lootMaster()) and true or nil
    if (is_master) then
      local frame = GetMouseFocus()
      if (frame) and (frame.IsFrameType ~= nil) and (frame:IsFrameType("Button"))  then
        if not (frame._hasExtraClicks) then
          frame:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
          frame._hasExtraClicks = true              
        end
      end
    end
  end
  ) 
  self:HookScript(GameTooltip, "OnHide", function()
    if sepgp.extratip:IsVisible() then sepgp.extratip:Hide() end
    self.hooks[GameTooltip]["OnHide"]()
  end
  )
  self:HookScript(ItemRefTooltip, "OnHide", function()
    if sepgp.extratip:IsVisible() then sepgp.extratip:Hide() end
    self.hooks[ItemRefTooltip]["OnHide"]()
  end
  )
end

function sepgp:delayedInit()
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="delayedInit"})
  if (IsInGuild()) then
    local guildName = (GetGuildInfo("player"))
    if (guildName) and guildName ~= "" then
      sepgp_reservechannel = string.format("%sReserves",(string.gsub(guildName," ",""))) -- TODO: Check if channel names can have chinese characters
    end
  end
  if sepgp_reservechannel == nil then sepgp_reservechannel = sepgp.VARS.reservechan end  
  local reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
  if (reservesChannelID) and (reservesChannelID ~= 0) then
    self:reservesToggle(true)
  end
  -- migrate EPGP storage if needed
  if IsGuildLeader() and ( (sepgp_dbver == nil) or (major_ver > sepgp_dbver) ) then
  end
  -- init options and comms
  self._options = self:buildMenu()
  self:RegisterChatCommand({"/brp","/belugaraidpoints"},self.cmdtable())
  self:RegisterEvent("CHAT_MSG_ADDON","addonComms")  
  -- broadcast our version
  self:addonMessage(addonMsg,"GUILD")
  if (IsGuildLeader()) then
    self:shareSettings()
  end
  -- safe officer note setting when we are admin
  if (admin()) then
    if not self:IsHooked("GuildRosterSetOfficerNote") then
      self:Hook("GuildRosterSetOfficerNote")
    end
  end
end

function sepgp:OnUpdate(elapsed)
  sepgp.timer.count_down = sepgp.timer.count_down - elapsed
  lastUpdate = lastUpdate + elapsed
  if sepgp.timer.count_down <= 0 then
    running_check = nil
    sepgp.timer:Hide()
    sepgp.timer.cd_text = L["|cffff0000Finished|r"]
    sepgp_reserves:Refresh()
  else
    sepgp.timer.cd_text = string.format(L["|cff00ff00%02d|r|cffffffffsec|r"],sepgp.timer.count_down)
  end
  if lastUpdate > 0.5 then
    lastUpdate = 0
    sepgp_reserves:Refresh()
  end
end

function sepgp:GuildRosterSetOfficerNote(index,note,fromAddon)
  if (fromAddon) then
    self.hooks["GuildRosterSetOfficerNote"](index,note)
  else
    local name, _, _, _, _, _, _, prevnote, _, _ = GetGuildRosterInfo(index)
    local _,_,_,oldepgp,_ = string.find(prevnote or "","(.*)({%d+:%d+})(.*)")
    local _,_,_,epgp,_ = string.find(note or "","(.*)({%d+:%d+})(.*)")
    if (sepgp_altspool) then
      local oldmain = self:parseAlt(name,prevnote)
      local main = self:parseAlt(name,note)
      if oldmain ~= nil then
        if main == nil or main ~= oldmain then 
          self:adminSay(string.format(L["Manually modified %s\'s note. Previous main was %s"],name,oldmain))
          self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Previous main was %s|r"],name,oldmain))
        end
      end
    end    
    if oldepgp ~= nil then
      if epgp == nil or epgp ~= oldepgp then
        self:adminSay(string.format(L["Manually modified %s\'s note. EPGP was %s"],name,oldepgp))
        self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. EPGP was %s|r"],name,oldepgp))
      end
    end
    local safenote = string.gsub(note,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    return self.hooks["GuildRosterSetOfficerNote"](index,safenote)    
  end
end

function sepgp:SetItemRef(link, name, button)
  if string.sub(link,1,9) == "shootybid" then
    local _,_,bid,masterlooter = string.find(link,"shootybid:(%d+):(%w+)")
    if bid == "1" then
      bid = "+"
    elseif bid == "2" then
      bid = "-"
    else
      bid = nil
    end
    if not self:inRaid(masterlooter) then
      masterlooter = nil
    end
    if (bid and masterlooter) then
      SendChatMessage(bid,"WHISPER",nil,masterlooter)
    end
    return
  end
  self.hooks["SetItemRef"](link, name, button)
  if (link and name and ItemRefTooltip) then
    if (strsub(link, 1, 4) == "item") then
      if (ItemRefTooltip:IsVisible()) then
        if (not DressUpFrame:IsVisible()) then
        end
        ItemRefTooltip.isDisplayDone = nil
      end
    end
  end
end

function sepgp:LootFrameItem_OnClick(button,data)
  if not IsShiftKeyDown() then return end
  if not UnitInRaid("player") then return end
  if not (self:lootMaster()) then 
    self:defaultPrint(L["Need MasterLooter to perform Bid Calls!"])
    UIErrorsFrame:AddMessage(L["Need MasterLooter to perform Bid Calls!"],1,0,0)
    return 
  end
  local slot, quality
  if data ~= nil then
    slot,quality = data:GetID(), data.quality
  else
    slot = LootFrame.selectedSlot or 0
    quality = LootFrame.selectedQuality or -1
    if not (this._hasExtraClicks) then 
      this:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
      this._hasExtraClicks = true
    end
  end
  if LootSlotIsItem(slot) and quality >= 3 then 
    local itemLink = GetLootSlotLink(slot)
    if (itemLink) then
      if button == "LeftButton" then
        self:widestAudience(string.format(L["Whisper %s for %s"],sepgp._playerName,itemLink))
      elseif button == "RightButton" then
        self:widestAudience(string.format(L["Whisper %s for %s"],sepgp._playerName,itemLink))
      elseif button == "MiddleButton" then
        self:widestAudience(string.format(L["Whisper %s for %s"],sepgp._playerName,itemLink))
      end
    end
  end
end

function sepgp:ContainerFrameItemButton_OnClick(button,ignoreModifiers)
  if not IsAltKeyDown() then 
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers) 
  end
  if not UnitInRaid("player") then 
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers) 
  end
  if not (self:lootMaster()) then
    self:defaultPrint(L["Need MasterLooter to perform Bid Calls!"])
    UIErrorsFrame:AddMessage(L["Need MasterLooter to perform Bid Calls!"],1,0,0)
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers) 
  end
  if not (this._hasExtraClicks) then
    this:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
    this._hasExtraClicks = true
  end
  local bag,slot = this:GetParent():GetID(), this:GetID()
  local itemLink = GetContainerItemLink(bag, slot)
  if (itemLink) then
    local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
    if (link_found) then
      local bind = self:itemBinding(itemString) or ""
      if (bind == self.VARS.boe) then
        if button == "LeftButton" then
          self:widestAudience(string.format(L["Whisper %s a + for %s (mainspec)"],sepgp._playerName,itemLink))
          return
        elseif button == "RightButton" then
          self:widestAudience(string.format(L["Whisper %s a - for %s (offspec)"],sepgp._playerName,itemLink))
          return
        elseif button == "MiddleButton" then
          self:widestAudience(string.format(L["Whisper %s a + or - for %s (mainspec or offspec)"],sepgp._playerName,itemLink))
          return
        end    
      end      
    end
  end
  return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers) 
end

function sepgp:pfUI_UpdateLootFrame()
  for slotid, pflootitem in pairs(pfUI.loot.slots) do
    if not self:IsHooked(pflootitem,"OnClick") then
      pflootitem:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
      self:HookScript(pflootitem,"OnClick",function()
          self:LootFrameItem_OnClick(arg1,this)
          self.hooks[this]["OnClick"](this,arg1)
        end)
    end
  end
end

-------------------
-- Communication
-------------------
function sepgp:flashFrame(frame)
  local tabFlash = getglobal(frame:GetName().."TabFlash")
  if ( not frame.isDocked or (frame == SELECTED_DOCK_FRAME) or UIFrameIsFlashing(tabFlash) ) then
    return
  end
  tabFlash:Show()
  UIFrameFlash(tabFlash, 0.25, 0.25, 60, nil, 0.5, 0.5)
end

function sepgp:debugPrint(msg)
  if (shooty_debugchat) then
    shooty_debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(shooty_debugchat)
  else
    self:defaultPrint(msg)
  end
end

function sepgp:defaultPrint(msg)
  if not DEFAULT_CHAT_FRAME:IsVisible() then
    FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(out,msg))
end

function sepgp:bidPrint(link,masterlooter,need,greed,bid)
  if (chatframe) then
    chatframe:AddMessage(" ")
    chatframe:AddMessage(string.format(out,msg),NORMAL_FONT_COLOR.r,NORMAL_FONT_COLOR.g,NORMAL_FONT_COLOR.b)
  end
end

function sepgp:simpleSay(msg)
  SendChatMessage(string.format("Beluga Raid Points: %s",msg), sepgp_saychannel)
end

function sepgp:adminSay(msg)
  -- API is broken on Elysium
  -- local g_listen, g_speak, officer_listen, officer_speak, g_promote, g_demote, g_invite, g_remove, set_gmotd, set_publicnote, view_officernote, edit_officernote, set_guildinfo = GuildControlGetRankFlags() 
  -- if (officer_speak) then
  SendChatMessage(string.format("Beluga Raid Points: %s",msg),"OFFICER")
  -- end
end

function sepgp:widestAudience(msg)
  local channel = "SAY"
  if UnitInRaid("player") then
    if (IsRaidLeader() or IsRaidOfficer()) then
      channel = "RAID_WARNING"
    else
      channel = "RAID"
    end
  elseif UnitExists("party1") then
    channel = "PARTY"
  end
  SendChatMessage(msg, channel)
end

function sepgp:addonMessage(message,channel,sender)
  SendAddonMessage(self.VARS.prefix,message,channel,sender)
end

function sepgp:addonComms(pref,message,channel,sender)
  -- fix pallypower
  local ok, err = pcall(function()
    if type(pref) == "string" and pref:upper():match("^PLPWR$") then
      return
    end
    if type(message) == "string" and message:find("ASELF", 1, true) then
      return
    end
  end)

  if not ok then
    return
  end



  if not pref == self.VARS.prefix then return end -- we don't care for messages from other addons
  if sender == self._playerName then return end -- we don't care for messages from ourselves
  local name_g,class,rank = self:verifyGuildMember(sender,true)
  if not (name_g) then return end -- only accept messages from guild members
  local who,what,amount
  for name,epgp,change in string.gfind(message,"([^;]+);([^;]+);([^;]+)") do
    who=name
    what=epgp
    amount=tonumber(change)
  end
  if (who) and (what) and (amount) then
    local msg
    local for_main = (sepgp_main and (who == sepgp_main))
    if (who == self._playerName) or (for_main) then
      if what == "EP" then
        if amount < 0 then
          msg = string.format(L["You have received %d Naxx Points."],amount)
        else
          msg = string.format(L["You have been awarded %d EP."],amount)
        end
      elseif what == "GP" then
        msg = string.format(L["You have received %d Kara Points."],amount)
      end
    elseif who == "ALL" and what == "DECAY" then
      msg = string.format(L["%s%% decay to EP and GP."],amount)
    elseif who == "RAID" and what == "AWARD" then
      msg = string.format(L["%d Points awarded to Raid."],amount)
    elseif who == "RESERVES" and what == "AWARD" then
      msg = string.format(L["%d EP awarded to Reserves."],amount)
      end
      if (IsGuildLeader()) then
        self:shareSettings()
      end
    elseif who == "SETTINGS" then
      for progress,discount,decay,minep,alts,altspct in string.gfind(what, "([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)") do
        discount = tonumber(discount)
        decay = tonumber(decay)
        minep = tonumber(minep)
        alts = (alts == "true") and true or false
        altspct = tonumber(altspct)
        local settings_notice
        if progress and progress ~= sepgp_progress then
          sepgp_progress = progress
          settings_notice = L["New raid progress"]
        end
        if discount and discount ~= sepgp_discount then
          sepgp_discount = discount
          if (settings_notice) then
            settings_notice = settings_notice..L[", offspec price %"]
          else
            settings_notice = L["New offspec price %"]
          end
        end
        if minep and minep ~= sepgp_minep then
          sepgp_minep = minep
          settings_notice = L["New Minimum EP"]
          sepgp:refreshPRTablets()
        end
        if decay and decay ~= sepgp_decay then
          sepgp_decay = decay
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", decay %"]
            else
              settings_notice = L["New decay %"]
            end
          end
        end
        if alts ~= nil and alts ~= sepgp_altspool then
          sepgp_altspool = alts
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts"]
            else
              settings_notice = L["New Alts"]
            end
          end          
        end
        if altspct and altspct ~= sepgp_altpercent then
          sepgp_altpercent = altspct
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts ep %"]
            else
              settings_notice = L["New Alts EP %"]
            end
          end          
        end
        if (settings_notice) and settings_notice ~= "" then
          local sender_rank = string.format("%s(%s)",C:Colorize(BC:GetHexColor(class),sender),rank)
          settings_notice = settings_notice..string.format(L[" settings accepted from %s"],sender_rank)
          self:defaultPrint(settings_notice)
          self._options.args["progress_tier_header"].name = string.format(L["Progress Setting: %s"],sepgp_progress)
          self._options.args["set_discount_header"].name = string.format(L["Offspec Price: %s%%"],sepgp_discount*100)
          self._options.args["set_min_ep_header"].name = string.format(L["Minimum EP: %s"],sepgp_minep)
        end
      end
    end
    if msg and msg~="" then
      self:defaultPrint(msg)
      self:my_epgp(for_main)
  end
end

function sepgp:shareSettings(force)
  local now = GetTime()
  if self._lastSettingsShare == nil or (now - self._lastSettingsShare > 30) or (force) then
    self._lastSettingsShare = now
    local addonMsg = string.format("SETTINGS;%s:%s:%s:%s:%s:%s;1",sepgp_progress,sepgp_discount,sepgp_decay,sepgp_minep,tostring(sepgp_altspool),sepgp_altpercent)
    self:addonMessage(addonMsg,"GUILD")
  end
end

function sepgp:refreshPRTablets()
  --if not T:IsAttached("sepgp_standings") then
  sepgp_standings:Refresh()
  --end
  --if not T:IsAttached("sepgp_bids") then
  --end
end

---------------------
-- EPGP Operations
---------------------
function sepgp:init_notes_v2(guild_index,note,officernote)
  if not tonumber(note) or (tonumber(note) < 0) then
    GuildRosterSetPublicNote(guild_index,0)
  end
  if not tonumber(officernote) or (tonumber(officernote) < sepgp.VARS.basegp) then
    GuildRosterSetOfficerNote(guild_index,sepgp.VARS.basegp,true)
  end
end

function sepgp:init_notes_v3(guild_index,name,officernote)
  local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
  if not (ep and gp) then
    local initstring = string.format("{%d:%d}",0,sepgp.VARS.basegp)
    local newnote = string.format("%s%s",officernote,initstring)
    newnote = string.gsub(newnote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    officernote = newnote
  else
    officernote = string.gsub(officernote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

function sepgp:update_epgp_v3(ep,gp,guild_index,name,officernote,special_action)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  local newnote
  if (ep) then
    ep = math.max(0,ep)
    newnote = string.gsub(officernote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
      return string.format("%s%s%s%s%s",head,ep,divider,oldgp,tail)
      end)
  end
  if (gp) then
    gp =  math.max(sepgp.VARS.basegp,gp)
    if (newnote) then
      newnote = string.gsub(newnote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    else
      newnote = string.gsub(officernote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    end
  end
  if (newnote) then
    GuildRosterSetOfficerNote(guild_index,newnote,true)
  end
end

function sepgp:update_ep_v2(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:init_notes_v2(i,note,officernote)
      GuildRosterSetPublicNote(i,ep)
    end
  end
end

function sepgp:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(ep,nil,i,name,officernote)
    end
  end  
end

function sepgp:update_gp_v2(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:init_notes_v2(i,note,officernote)
      GuildRosterSetOfficerNote(i,gp,true) 
    end
  end
end

function sepgp:update_gp_v3(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(nil,gp,i,name,officernote) 
    end
  end  
end

function sepgp:get_ep_v2(getname,note) -- gets ep by name or note
  if (note) then
    if tonumber(note)==nil then return 0 end
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if tonumber(note)==nil then note=0 end
    if (name==getname) then return tonumber(note) end
  end
  return(0)
end

function sepgp:get_ep_v3(getname,officernote) -- gets ep by name or note
  if (officernote) then
    local _,_,ep = string.find(officernote,".*{(%d+):%d+}.*")
    return tonumber(ep)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local _,_,ep = string.find(officernote,".*{(%d+):%d+}.*")
    if (name==getname) then return tonumber(ep) end
  end
  return
end

function sepgp:get_gp_v2(getname,officernote) -- gets gp by name or officernote
  if (officernote) then
    if tonumber(officernote)==nil then return sepgp.VARS.basegp end
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if tonumber(officernote)==nil then officernote=sepgp.VARS.basegp end
    if (name==getname) then return tonumber(officernote) end
  end
  return(sepgp.VARS.basegp)
end

function sepgp:get_gp_v3(getname,officernote) -- gets gp by name or officernote
  if (officernote) then
    local _,_,gp = string.find(officernote,".*{%d+:(%d+)}.*")
    return tonumber(gp)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local _,_,gp = string.find(officernote,".*{%d+:(%d+)}.*")
    if (name==getname) then return tonumber(gp) end
  end
  return
end

function sepgp:award_raid_ep(ep) -- awards ep to raid members in zone
  if GetNumRaidMembers()>0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= sepgp.VARS.minlevel then
        self:givename_ep(name,ep)
      end
    end
    self:simpleSay(string.format(L["Giving %d Naxx Points to all raidmembers"],ep))
    self:addToLog(string.format(L["Giving %d Naxx Points to all raidmembers"],ep))    
    local addonMsg = string.format("RAID;AWARD;%s",ep)
    self:addonMessage(addonMsg,"RAID")
    self:refreshPRTablets()
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

function sepgp:award_raid_gp(gp) -- awards gp to raid members in zone
  if GetNumRaidMembers()>0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= sepgp.VARS.minlevel then
        self:givename_gp(name,gp)
      end
    end
    self:simpleSay(string.format(L["Giving %d Kara Points to all raidmembers"],gp))
    self:addToLog(string.format(L["Giving %d Kara Points to all raidmembers"],gp))    
    local addonMsg = string.format("RAID;AWARD;%s",gp)
    self:addonMessage(addonMsg,"RAID")
    self:refreshPRTablets()
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

function sepgp:award_reserve_ep(ep) -- awards ep to reserve list
  if table.getn(sepgp.reserves) > 0 then
    for i, reserve in ipairs(sepgp.reserves) do
      local name, class, rank, alt = unpack(reserve)
      self:givename_ep(name,ep)
    end
    self:simpleSay(string.format(L["Giving %d ep to active reserves"],ep))
    self:addToLog(string.format(L["Giving %d ep to active reserves"],ep))
    local addonMsg = string.format("RESERVES;AWARD;%s",ep)
    self:addonMessage(addonMsg,"RAID")
    sepgp.reserves = {}
    reserves_blacklist = {}
    self:refreshPRTablets()
  end
end

function sepgp:givename_ep(getname,ep) -- awards ep to a single character
  if not (admin()) then return end
  local postfix, alt = ""
  if (sepgp_altspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      ep = self:num_round(sepgp_altpercent*ep)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end
  local newep = ep + (self:get_ep_v3(getname) or 0) 
  self:update_ep_v3(getname,newep) 
  self:debugPrint(string.format(L["Giving %d Naxx Points to %s%s."],ep,getname,postfix))
  if ep < 0 then -- inform admins and victim of penalties
    local msg = string.format(L["Awarding %d Naxx Points to %s%s."],ep,getname,postfix)
    self:adminSay(msg)
    self:addToLog(msg)
    local addonMsg = string.format("%s;%s;%s",getname,"EP",ep)
    self:addonMessage(addonMsg,"GUILD")
  end  
end

function sepgp:givename_gp(getname,gp) -- assigns gp to a single character
  if not (admin()) then return end
  local postfix, alt = ""
  if (sepgp_altspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end
  local oldgp = (self:get_gp_v3(getname) or sepgp.VARS.basegp) 
  local newgp = gp + oldgp
  self:update_gp_v3(getname,newgp) 
  self:debugPrint(string.format(L["Giving %d Kara Points to %s%s."],gp,getname,postfix))
  if gp < 0 then -- inform admins and victim of penalties
    local msg = string.format(L["Awarding %d Kara Points to %s%s."],gp,getname,postfix)
    self:adminSay(msg)
    self:addToLog(msg)
  local addonMsg = string.format("%s;%s;%s",getname,"GP",gp)
  self:addonMessage(addonMsg,"GUILD")  
  end
end

function sepgp:decay_epgp_v2() -- decays entire roster's ep and gp
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,ep,gp,_,_ = GetGuildRosterInfo(i)
    ep = tonumber(ep)
    gp = tonumber(gp)
    if ep == nil then 
    else 
      if gp == nil then
        local msg = string.format(L["%s\'s officernote is broken:%q"],name,tostring(gp))
        self:debugPrint(msg)
        self:adminSay(msg)
      else
        ep = math.max(0,self:num_round(ep*sepgp_decay))
    	  GuildRosterSetPublicNote(i,ep)
    	  gp = math.max(sepgp.VARS.basegp,self:num_round(gp*sepgp_decay))
    	  GuildRosterSetOfficerNote(i,gp,true)
      end
    end
  end
  local msg = string.format(L["All Points decayed by %d%%"],(1-sepgp_decay)*100)
  self:simpleSay(msg)
  if not (sepgp_saychannel=="OFFICER") then self:adminSay(msg) end
  self:addToLog(msg)
end

function sepgp:decay_epgp_v3()
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
    if (ep and gp) then
      ep = self:num_round(ep*sepgp_decay)
      gp = self:num_round(gp*sepgp_decay)
      self:update_epgp_v3(ep,gp,i,name,officernote)
    end
  end
  local msg = string.format(L["All Points decayed by %s%%"],(1-sepgp_decay)*100)
  self:simpleSay(msg)
  if not (sepgp_saychannel=="OFFICER") then self:adminSay(msg) end
  local addonMsg = string.format("ALL;DECAY;%s",(1-(sepgp_decay or sepgp.VARS.decay))*100)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  self:refreshPRTablets() 
end

function sepgp:gp_reset_v2()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      GuildRosterSetOfficerNote(i, sepgp.VARS.basegp,true)
    end
    self:debugPrint(string.format(L["All GP has been reset to %d."],sepgp.VARS.basegp))
    self:adminSay(string.format(L["All GP has been reset to %d."],sepgp.VARS.basegp))
    self:addToLog(string.format(L["All GP has been reset to %d."],sepgp.VARS.basegp))
  end
end

function sepgp:gp_reset_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(0,sepgp.VARS.basegp,i,name,officernote)
      end
    end
    local msg = L["All Points has been reset to 0/%d."]
    self:debugPrint(string.format(msg,sepgp.VARS.basegp))
    self:adminSay(string.format(msg,sepgp.VARS.basegp))
    self:addToLog(string.format(msg,sepgp.VARS.basegp))
  end
end

function sepgp:capcalc(ep,gp,gain)
  -- CAP_EP = EP_GAIN*DECAY/(1-DECAY) CAP_PR = CAP_EP/base_gp
  local pr = ep/gp
  local ep_decayed = self:num_round(ep*sepgp_decay)
  local gp_decayed = math.max(sepgp.VARS.basegp,self:num_round(gp*sepgp_decay))
  local cycle_gain = tonumber(gain)
  local cap_ep
  if (cycle_gain) then
    cap_ep = self:num_round(cycle_gain*sepgp_decay/(1-sepgp_decay))
  end
  return cap_ep
end

function sepgp:my_epgp_announce(use_main)
  local ep,gp
  if (use_main) then
    ep,gp = (self:get_ep_v3(sepgp_main) or 0), (self:get_gp_v3(sepgp_main) or sepgp.VARS.basegp)
  else
    ep,gp = (self:get_ep_v3(self._playerName) or 0), (self:get_gp_v3(self._playerName) or sepgp.VARS.basegp)
  end
  local pr = ep/gp
  local msg = string.format(L["You now have: |cffffff00%d |cff478ee5Naxx |cffff7f00Points |cffffff00%d |cff8c986cKara |cffff7f00Points"], ep,gp)
  self:defaultPrint(msg)
  local pr_decay, cap_ep, cap_pr = self:capcalc(ep,gp)
end

function sepgp:my_epgp(use_main)
  GuildRoster()
  self:ScheduleEvent("shootyepgpRosterRefresh",self.my_epgp_announce,3,self,use_main)
end

---------
-- Menu
---------
sepgp.hasIcon = "Interface\\LootFrame\\FishingLoot-Icon"
sepgp.title = "Beluga Raid Points"
sepgp.defaultMinimapPosition = 180
sepgp.defaultPosition = "RIGHT"
sepgp.cannotDetachTooltip = true
sepgp.tooltipHiddenWhenEmpty = falseSetRefresh
sepgp.independentProfile = true

function sepgp:OnTooltipUpdate()
  local hint = L["|cffffff00Click|r to toggle Standings.%s \n|cffffff00Right-Click|r for Options."]
  if (admin()) then
    hint = string.format(hint,L[" \n|cffffff00Shift+Click|r to toggle Loot. \n|cffffff00Ctrl+Shift+Click|r to toggle Logs."])
  else
    hint = string.format(hint,"")
  end
  T:SetHint(hint)
end

function sepgp:OnClick()
  local is_admin = admin()
  if (IsControlKeyDown() and IsShiftKeyDown() and is_admin) then
    sepgp_logs:Toggle()
  elseif (IsShiftKeyDown() and is_admin) then
    sepgp_loot:Toggle()      
  else
    sepgp_standings:Toggle()
  end
end

function sepgp:SetRefresh(flag)
  needRefresh = flag
  if (flag) then
    self:refreshPRTablets()
  end
end

function sepgp:buildRosterTable()
  local g, r = { }, { }
  local numGuildMembers = GetNumGuildMembers(1)
  if (sepgp_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      if (name) then
        r[name] = true
      end
    end
  end
  sepgp.alts = {}
  for i = 1, numGuildMembers do
    local member_name,_,_,level,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    if member_name and member_name ~= "" then
      local main, main_class, main_rank = self:parseAlt(member_name,officernote)
      local is_raid_level = tonumber(level) and level >= sepgp.VARS.minlevel
      if (main) then
        if ((self._playerName) and (name == self._playerName)) then
          if (not sepgp_main) or (sepgp_main and sepgp_main ~= main) then
            sepgp_main = main
            self:defaultPrint(L["Your main has been set to %s"],sepgp_main)
          end
        end
        main = C:Colorize(BC:GetHexColor(main_class), main)
        sepgp.alts[main] = sepgp.alts[main] or {}
        sepgp.alts[main][member_name] = class
      end
      if (sepgp_raidonly) and next(r) then
        if r[member_name] and is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      else
        if is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      end
    end
  end
  return g
end

function sepgp:buildClassMemberTable(roster,epgp)
  local desc,usage
  if epgp == "ep" then
    desc = L["Naxx Points to %s."]
    usage = "<EP>"
  elseif epgp == "gp" then
    desc = L["Kara Points to %s."]
    usage = "<GP>"
  end
  local c = { }
  for i,member in ipairs(roster) do
    local class,name = member.class, member.name
    if (class) and (c[class] == nil) then
      c[class] = { }
      c[class].type = "group"
      c[class].name = C:Colorize(BC:GetHexColor(class),class)
      c[class].desc = class .. " members"
      c[class].hidden = function() return not (admin()) end
      c[class].args = { }
    end
    if (name) and (c[class].args[name] == nil) then
      c[class].args[name] = { }
      c[class].args[name].type = "text"
      c[class].args[name].name = name
      c[class].args[name].desc = string.format(desc,name)
      c[class].args[name].usage = usage
      if epgp == "ep" then
        c[class].args[name].get = "suggestedAwardEP"
        c[class].args[name].set = function(v) sepgp:givename_ep(name, tonumber(v)) sepgp:refreshPRTablets() end
      elseif epgp == "gp" then
        c[class].args[name].get = "suggestedAwardGP"
        c[class].args[name].set = function(v) sepgp:givename_gp(name, tonumber(v)) sepgp:refreshPRTablets() end
      end
      c[class].args[name].validate = function(v) return (type(v) == "number" or tonumber(v)) and tonumber(v) < sepgp.VARS.max end
    end
  end
  return c
end

---------------
-- Alts
---------------
function sepgp:parseAlt(name,officernote)
  if (officernote) then
    local _,_,_,main,_ = string.find(officernote or "","(.*){([%a][%a]%a*)}(.*)")
    if type(main)=="string" and (string.len(main) < 13) then
      main = self:camelCase(main)
      local g_name, g_class, g_rank, g_officernote = self:verifyGuildMember(main)
      if (g_name) then
        return g_name, g_class, g_rank, g_officernote
      else
        return nil
      end
    else
      return nil
    end
  else
    for i=1,GetNumGuildMembers(1) do
      local g_name, _, _, _, g_class, _, g_note, g_officernote, _, _ = GetGuildRosterInfo(i)
      if (name == g_name) then
        return self:parseAlt(g_name, g_officernote)
      end
    end
  end
  return nil
end


---------------
-- Reserves
---------------
function sepgp:reservesToggle(flag)
  local reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
  if (flag) then -- we want in
    if (reservesChannelID) and reservesChannelID ~= 0 then
      sepgp.reservesChannelID = reservesChannelID
      if not self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
      end
      return true
    else
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      JoinChannelByName(sepgp_reservechannel)
      return
    end
  else -- we want out
    if (reservesChannelID) and reservesChannelID ~= 0 then
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      LeaveChannelByName(sepgp_reservechannel)
      return
    else
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end      
      return false
    end
  end
end

function sepgp:reservesChannelChange(msg,_,_,_,_,_,_,_,channel)
  if (msg) and (channel) and (channel == sepgp_reservechannel) then
    if msg == "YOU_JOINED" then
      sepgp.reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
      RemoveChatWindowChannel(DEFAULT_CHAT_FRAME:GetID(), sepgp_reservechannel)
      self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
    elseif msg == "YOU_LEFT" then
      sepgp.reservesChannelID = nil 
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end
    end
    self:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    D:Close()
  end
end

function sepgp:afkcheck_reserves()
  if (running_check) then return end
  if sepgp.reservesChannelID ~= nil and ((GetChannelName(sepgp.reservesChannelID)) == sepgp.reservesChannelID) then
    reserves_blacklist = {}
    sepgp.reserves = {}
    running_check = true
    sepgp.timer.count_down = sepgp.VARS.timeout
    sepgp.timer:Show()
    SendChatMessage(sepgp.VARS.reservecall,"CHANNEL",nil,sepgp.reservesChannelID)
    sepgp_reserves:Toggle(true)
  end
end

function sepgp:sendReserverResponce()
  if sepgp.reservesChannelID ~= nil then
    if (sepgp_main) then
      if sepgp_main == self._playerName then
        SendChatMessage("+","CHANNEL",nil,sepgp.reservesChannelID)
      else
        SendChatMessage(string.format("+%s",sepgp_main),"CHANNEL",nil,sepgp.reservesChannelID)
      end
    end
  end
end

function sepgp:captureReserveChatter(text, sender, _, _, _, _, _, _, channel)
  if not (channel) or not (channel == sepgp_reservechannel) then return end
  local reserve, reserve_class, reserve_rank, reserve_alt = nil,nil,nil,nil
  local r,_,rdy,name = string.find(text,sepgp.VARS.reserveanswer)
  if (r) and (running_check) then
    if (rdy) then
      if (name) and (name ~= "") then
        if (not self:inRaid(name)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(name)
          if reserve ~= sender then
            reserve_alt = sender
          end
        end
      else
        if (not self:inRaid(sender)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(sender)    
        end
      end
      if reserve and reserve_class and reserve_rank then
        if reserve_alt then
          if not reserves_blacklist[reserve_alt] then
            reserves_blacklist[reserve_alt] = true
            table.insert(sepgp.reserves,{reserve,reserve_class,reserve_rank,reserve_alt})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r trying to add %s to Reserves, but has already added a member. Discarding!"],reserve_alt,reserve))
          end
        else
          if not reserves_blacklist[reserve] then
            reserves_blacklist[reserve] = true
            table.insert(sepgp.reserves,{reserve,reserve_class,reserve_rank})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r has already been added to Reserves. Discarding!"],reserve))
          end
        end
      end
    end
    return
  end
  local q = string.find(text,L["^{shootyepgp}Type"])
  if (q) and not (running_check) then
    if --[[(not UnitInRaid("player")) or]] (not self:inRaid(sender)) then
      StaticPopup_Show("SHOOTY_EPGP_RESERVE_AFKCHECK_RESPONCE")
    end
  end
end

---------
-- Bids
---------
local lootCall = {}
lootCall.whisp = {
  "^(w)[%s%p%c]+.+",".+[%s%p%c]+(w)$",".+[%s%p%c]+(w)[%s%p%c]+.*",".*[%s%p%c]+(w)[%s%p%c]+.+",
  "^(whisper)[%s%p%c]+.+",".+[%s%p%c]+(whisper)$",".+[%s%p%c]+(whisper)[%s%p%c]+.*",".*[%s%p%c]+(whisper)[%s%p%c]+.+",
  ".+[%s%p%c]+(bid)[%s%p%c]*.*",".*[%s%p%c]*(bid)[%s%p%c]+.+"
}
lootCall.ms = {
  ".+(%+).*",".*(%+).+", 
  "^(ms)[%s%p%c]+.+",".+[%s%p%c]+(ms)$",".+[%s%p%c]+(ms)[%s%p%c]+.*",".*[%s%p%c]+(ms)[%s%p%c]+.+", 
  ".+(mainspec).*",".*(mainspec).+"
}
lootCall.os = {
  ".+(%-).*",".*(%-).+", 
  "^(os)[%s%p%c]+.+",".+[%s%p%c]+(os)$",".+[%s%p%c]+(os)[%s%p%c]+.*",".*[%s%p%c]+(os)[%s%p%c]+.+", 
  ".+(offspec).*",".*(offspec).+"
}
lootCall.bs = { -- blacklist
  "^(roll)[%s%p%c]+.+",".+[%s%p%c]+(roll)$",".*[%s%p%c]+(roll)[%s%p%c]+.*"
}
function sepgp:captureLootCall(text, sender)
  if not (string.find(text, "|Hitem:", 1, true)) then return end
  local linkstriptext, count = string.gsub(text,"|c%x+|H[eimt:%d]+|h%[[%w%s',%-]+%]|h|r"," ; ")
  if count > 1 then return end
  local lowtext = string.lower(linkstriptext)
  local whisperkw_found, mskw_found, oskw_found, link_found, blacklist_found
  for _,f in ipairs(lootCall.bs) do
    blacklist_found = string.find(lowtext,f)
    if (blacklist_found) then return end
  end
  local _, itemLink, itemColor, itemString, itemName
  for _,f in ipairs(lootCall.whisp) do
    whisperkw_found = string.find(lowtext,f)
    if (whisperkw_found) then break end
  end
  for _,f in ipairs(lootCall.ms) do
    mskw_found = string.find(lowtext,f)
    if (mskw_found) then break end
  end
  for _,f in ipairs(lootCall.os) do
    oskw_found = string.find(lowtext,f)
    if (oskw_found) then break end
  end
  if (whisperkw_found) or (mskw_found) or (oskw_found) then
    _,_,itemLink = string.find(text,"(|c%x+|H[eimt:%d]+|h%[[%w%s',%-]+%]|h|r)")
    if (itemLink) and (itemLink ~= "") then
      link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
    end
    if (link_found) then
      local quality = hexColorQuality[itemColor] or -1
      if (quality >= 3) then
        if (IsRaidLeader() or self:lootMaster()) and (sender == self._playerName) then
          self:clearBids(true)
          sepgp.bid_item.link = itemString
          sepgp.bid_item.linkFull = itemLink
          sepgp.bid_item.name = string.format("%s%s|r",itemColor,itemName)
          self:ScheduleEvent("shootyepgpBidTimeout",self.clearBids,300,self)
          running_bid = true
        end
        self:bidPrint(itemLink,sender,mskw_found,oskw_found,whisperkw_found)
      end
    end
  end
end

local lootBid = {}
lootBid.ms = {"(%+)",".+(%+).*",".*(%+).+",".*(%+).*","(ms)","(need)"}
lootBid.os = {"(%-)",".+(%-).*",".*(%-).+",".*(%-).*","(os)","(greed)"}
function sepgp:captureBid(text, sender)
  if not (running_bid) then return end
  if not (IsRaidLeader() or self:lootMaster()) then return end
  if not sepgp.bid_item.link then return end
  local mskw_found,oskw_found
  local lowtext = string.lower(text)
  for _,f in ipairs(lootBid.ms) do
    mskw_found = string.find(text,f)
    if (mskw_found) then break end
  end
  for _,f in ipairs(lootBid.os) do
    oskw_found = string.find(text,f)
    if (oskw_found) then break end
  end
  if (mskw_found) or (oskw_found) then
    if self:inRaid(sender) then
      if bids_blacklist[sender] == nil then
        for i = 1, GetNumGuildMembers(1) do
          local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
          if name == sender then
            local ep = (self:get_ep_v3(name,officernote) or 0) 
            local gp = (self:get_gp_v3(name,officernote) or sepgp.VARS.basegp)
            local main_name
            if (sepgp_altspool) then
              local main, main_class, main_rank, main_offnote = self:parseAlt(name,officernote)
              if (main) then
                ep = (self:get_ep_v3(main,main_offnote) or 0)
                gp = (self:get_gp_v3(main,main_offnote) or sepgp.VARS.basegp)
                main_name = main
              end
            end
            if (mskw_found) then
              bids_blacklist[sender] = true
              if (sepgp_altspool) and (main_name) then
                table.insert(sepgp.bids_main,{name,class,ep,gp,ep/gp,main_name})
              else
                table.insert(sepgp.bids_main,{name,class,ep,gp,ep/gp})
              end
            elseif (oskw_found) then
              bids_blacklist[sender] = true
              if (sepgp_altspool) and (main_name) then
                table.insert(sepgp.bids_off,{name,class,ep,gp,ep/gp,main_name})
              else
                table.insert(sepgp.bids_off,{name,class,ep,gp,ep/gp})
              end
            end
            sepgp_bids:Toggle(false)
            return
          end
        end
      end
    end
  end
end

function sepgp:clearBids(reset)
  if reset~=nil then
  end
  sepgp.bid_item = {}
  sepgp.bids_main = {}
  sepgp.bids_off = {}
  bids_blacklist = {}
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end
  running_bid = false
end

----------------
-- Loot Tracker
----------------
-- /script DEFAULT_CHAT_FRAME:AddMessage("\124cffa335ee\124Hitem:16864:0:0:0:0:0:0:0:0\124h[Belt of Might]\124h\124r");
-- test: "You receive loot: \124cffa335ee\124Hitem:16866:0:0:0\124h[Helm of Might]\124h\124r."
-- test: /run sepgp:captureLoot("Raerlas receives loot: \124cffa335ee\124Hitem:16846:0:0:0\124h[Giantstalker's Helmet]\124h\124r.")
-- test: /run sepgp:captureLoot("You receive loot: \124cffa335ee\124Hitem:16864:0:0:0\124h[Belt of Might]\124h\124r.")
sepgp.loot_index = {
  time=1,
  player=2,
  player_c=3,
  item=4,
  bind=5,
  price=6,
  off_price=7,
  action=8,
  update=9
}
function sepgp:captureLoot(message)
  if not (UnitInRaid("player") and self:lootMaster() and admin()) then return end
  local who,what,amount,player,itemLink
  who,what,amount = DF:Deformat(message,LOOT_ITEM_MULTIPLE)
  if (amount) then -- skip multiples / stacks
  else
    player, itemLink = DF:Deformat(message,LOOT_ITEM)
  end
  who,what,amount = YOU, DF:Deformat(message,LOOT_ITEM_SELF_MULTIPLE)
  if (amount) then -- skip multiples / stacks
  else
    if not (player and itemLink) then
      player, itemLink = YOU, DF:Deformat(message,LOOT_ITEM_SELF)
    end
  end
  if not (player and itemLink) then return end
  self:processLoot(player,itemLink,"chat")
end

function sepgp:GiveMasterLoot(slot, index)
  if LootSlotIsItem(slot) then
    local texture, itemname, quantity, quality = GetLootSlotInfo(slot)
    if quantity == 1 and quality >= 3 then -- not a stack and rare or higher
      local itemLink = GetLootSlotLink(slot)
      local player = GetMasterLootCandidate(index)
      if not (player and itemLink) then return end
      self:processLoot(player,itemLink,"masterloot")
    end
  end
end

function sepgp:findLootReminder(itemLink)
  for i,data in ipairs(sepgp_looted) do
    if data[self.loot_index.item] == itemLink and data[self.loot_index.action] == self.VARS.reminder then
      return data
    end
  end
end

function sepgp:tradeLoot(playerState,targetState)
  if not (UnitInRaid("player") and self:lootMaster() and admin()) then return end
  if (playerState ~= nil and targetState ~= nil) and playerState == 1 and targetState == 1 then
    local itemLink
    for id=1,MAX_TRADABLE_ITEMS do
      itemLink = GetTradePlayerItemLink(id)
      if (itemLink) then
        break  
      end
    end
        local bind = self:itemBinding(itemString)
        if UnitExists("target") and UnitIsPlayer("target") and UnitCanCooperate("player","target") and (not UnitIsUnit("player","target")) then
          local tradeTarget = UnitName("target")
          local _, class = self:verifyGuildMember(tradeTarget,true)
          if not (class) then return end
          local target_color = C:Colorize(BC:GetHexColor(class),tradeTarget)
          local timestamp = date("%b/%d %H:%M:%S")
          local data = self:findLootReminder(itemLink)
          if (data) then
            data[self.loot_index.time] = timestamp
            data[self.loot_index.player] = tradeTarget
            data[self.loot_index.player_c] = target_color
            data[self.loot_index.update] = 1
            local dialog = StaticPopup_Show("SHOOTY_EPGP_AUTO_GEARPOINTS",data[self.loot_index.player_c],data[self.loot_index.item],data)
            if (dialog) then
              dialog.data = data
        end
      end
    end
  end
end

sepgp.item_bind_patterns = {
  CRAFT = "("..ITEM_SPELL_TRIGGER_ONUSE..")",
  BOP = "("..ITEM_BIND_ON_PICKUP..")",
  QUEST = "("..ITEM_BIND_QUEST..")",
  BOU = "("..ITEM_BIND_ON_EQUIP..")",
  BOE = "("..ITEM_BIND_ON_USE..")"
}
function sepgp:itemBinding(item)
  G:SetHyperlink(item)
  if G:Find(self.item_bind_patterns.CRAFT,2,4,nil,true) then
  else
    if G:Find(self.item_bind_patterns.BOP,2,4,nil,true) then
      return sepgp.VARS.bop
    elseif G:Find(self.item_bind_patterns.QUEST,2,4,nil,true) then
      return sepgp.VARS.bop
    elseif G:Find(self.item_bind_patterns.BOE,2,4,nil,true) then
      return sepgp.VARS.boe
    elseif G:Find(self.item_bind_patterns.BOU,2,4,nil,true) then
      return sepgp.VARS.boe
    else
      return sepgp.VARS.nobind
    end
  end
  return
end

function sepgp:addOrUpdateLoot(data,update)
  if not (update) then
    table.insert(sepgp_looted,data)
  end
end

function sepgp:testLootPrompt()
  raidStatus = UnitInRaid("player") and true or false
  if lastRaidStatus == nil then
    lastRaidStatus = raidStatus
  end
  if (raidStatus == false) and (lastRaidStatus == true) then
    local hasLoot = table.getn(sepgp_looted)
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_CLEAR_LOOT")
    if (not (dialog)) and (hasLoot > 0) then
      StaticPopup_Show("SHOOTY_EPGP_CLEAR_LOOT",hasLoot)
    end
  end
  lastRaidStatus = raidStatus
end

------------
-- Logging
------------
function sepgp:addToLog(line,skipTime)
  local over = table.getn(sepgp_log)-sepgp.VARS.maxloglines+1
  if over > 0 then
    for i=1,over do
      table.remove(sepgp_log,1)
    end
  end
  local timestamp
  if (skipTime) then
    timestamp = ""
  else
    timestamp = date("%b/%d %H:%M:%S")
  end
  table.insert(sepgp_log,{timestamp,line})
end

------------
-- Utility 
------------
function sepgp:num_round(i)
  return math.floor(i+0.5)
end

function sepgp:strsplit(delimiter, subject)
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

function sepgp:processLootDupe(player,itemName,source)
  local now = GetTime()
  local player_name = player == YOU and self._playerName or player
  local player_item = string.format("%s%s",player_name,itemName)
  if ((self._lastPlayerItem) and self._lastPlayerItem == player_item)
  and ((self._lastPlayerItemTime) and (now - self._lastPlayerItemTime) < 3)
  and ((self._lastPlayerItemSource) and self._lastPlayerItemSource ~= source) then
    return true, player_item, now
  end
  return false, player_item, now
end

function sepgp:processLoot(player,itemLink,source)
  local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")  
  if link_found then
    local dupe, player_item, now = self:processLootDupe(player,itemName,source)
    if dupe then
      return
    end
    local bind = self:itemBinding(itemString)
    if not (bind) then return end
    if (not (price)) or (price == 0) then
      return
    end
    local class,_
    if player == YOU then player = self._playerName end
    if player == self._playerName then 
      class = UnitClass("player") -- localized
    else
      _, class = self:verifyGuildMember(player,true) -- localized
    end
    if not (class) then return end
    self._lastPlayerItem, self._lastPlayerItemTime, self._lastPlayerItemSource = player_item, now, source
    local player_color = C:Colorize(BC:GetHexColor(class),player)
    local off_price = math.floor(price*sepgp_discount)
    local quality = hexColorQuality[itemColor] or -1
    local timestamp = date("%b/%d %H:%M:%S")
    local data = {[self.loot_index.time]=timestamp,[self.loot_index.player]=player,[self.loot_index.player_c]=player_color,[self.loot_index.item]=itemLink,[self.loot_index.bind]=bind,[self.loot_index.price]=price,[self.loot_index.off_price]=off_price}
    local dialog = StaticPopup_Show("SHOOTY_EPGP_AUTO_GEARPOINTS",data[self.loot_index.player_c],data[self.loot_index.item],data)
    if (dialog) then
      dialog.data = data
    end
  end
end

function sepgp:verifyGuildMember(name,silent)
  for i=1,GetNumGuildMembers(1) do
    local g_name, g_rank, g_rankIndex, g_level, g_class, g_zone, g_note, g_officernote, g_online = GetGuildRosterInfo(i)
    if (string.lower(name) == string.lower(g_name)) and (tonumber(g_level) >= sepgp.VARS.minlevel) then 
    -- == MAX_PLAYER_LEVEL]]
      return g_name, g_class, g_rank, g_officernote
    end
  end
  if (name) and name ~= "" and not (silent) then
    self:defaultPrint(string.format(L["%s not found in the guild or not max level!"],name))
  end
  return
end

function sepgp:inRaid(name)
  for i=1,GetNumRaidMembers() do
    if name == (UnitName(raidUnit[i])) then
      return true
    end
  end
  return false
end

function sepgp:lootMaster()
  local method, lootmasterID = GetLootMethod()
  if method == "master" and lootmasterID == 0 then
    return true
  else
    return false
  end
end

function sepgp:testMain()
  if (sepgp_main == nil) or (sepgp_main == "") then
    if (IsInGuild()) then
      StaticPopup_Show("SHOOTY_EPGP_SET_MAIN")
    end
  end
end

function sepgp:make_escable(framename,operation)
  local found
  for i,f in ipairs(UISpecialFrames) do
    if f==framename then
      found = i
    end
  end
  if not found and operation=="add" then
    table.insert(UISpecialFrames,framename)
  elseif found and operation=="remove" then
    table.remove(UISpecialFrames,found)
  end
end

local raidZones = {[L["Molten Core"]]="T1",[L["Onyxia\'s Lair"]]="T1.5",[L["Blackwing Lair"]]="T2",[L["Ahn\'Qiraj"]]="T2.5",[L["Naxxramas"]]="T3"}
local zone_multipliers = {
  ["T3"] =   {["T3"]=1,["T2.5"]=0.75,["T2"]=0.5,["T1.5"]=0.25,["T1"]=0.25},
  ["T2.5"] = {["T3"]=1,["T2.5"]=1,   ["T2"]=0.7,["T1.5"]=0.4, ["T1"]=0.4},
  ["T2"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=0.5, ["T1"]=0.5},
  ["T1"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=1,   ["T1"]=1}
}
function sepgp:suggestedAwardEP()
  local currentTier, zoneEN, zoneLoc, checkTier, multiplier
  local inInstance, instanceType = IsInInstance()
  if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
    currentTier = "T1.5"   
  end
  if (inInstance) and (instanceType == "raid") then
    zoneLoc = GetRealZoneText()
    if (BZ:HasReverseTranslation(zoneLoc)) then
      zoneEN = BZ:GetReverseTranslation(zoneLoc)
      checkTier = raidZones[zoneEN]
      if (checkTier) then
        currentTier = checkTier
      end
    end
  end
  if not currentTier then 
    return sepgp.VARS.baseaward_ep
  else
    multiplier = zone_multipliers[sepgp_progress][currentTier]
  end
  if (multiplier) then
    return multiplier*sepgp.VARS.baseaward_ep
  else
    return sepgp.VARS.baseaward_ep
  end
end

function sepgp:suggestedAwardGP()
  local currentTier, zoneEN, zoneLoc, checkTier, multiplier
  local inInstance, instanceType = IsInInstance()
  if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
    currentTier = "T1.5"   
  end
  if (inInstance) and (instanceType == "raid") then
    zoneLoc = GetRealZoneText()
    if (BZ:HasReverseTranslation(zoneLoc)) then
      zoneEN = BZ:GetReverseTranslation(zoneLoc)
      checkTier = raidZones[zoneEN]
      if (checkTier) then
        currentTier = checkTier
      end
    end
  end
  if not currentTier then 
    return sepgp.VARS.baseaward_gp
  else
    multiplier = zone_multipliers[sepgp_progress][currentTier]
  end
  if (multiplier) then
    return multiplier*sepgp.VARS.baseaward_gp
  else
    return sepgp.VARS.baseaward_gp
  end
end

function sepgp:camelCase(word)
  return string.gsub(word,"(%a)([%w_']*)",function(head,tail) 
    return string.format("%s%s",string.upper(head),string.lower(tail)) 
    end)
end

admin = function()
  return (CanEditOfficerNote() --[[and CanEditPublicNote()]])
end

sanitizeNote = function(prefix,epgp,postfix)
  -- reserve 12 chars for the epgp pattern {xxxxx:yyyy} max public/officernote = 31
  local remainder = string.format("%s%s",prefix,postfix)
  local clip = math.min(31-12,string.len(remainder))
  local prepend = string.sub(remainder,1,clip)
  return string.format("%s%s",prepend,epgp)
end

-------------
-- Dialogs
-------------
StaticPopupDialogs["SHOOTY_EPGP_CLEAR_LOOT"] = {
  text = L["There are %d loot drops stored. It is recommended to clear loot info before a new raid. Do you want to clear it now?"],
  button1 = TEXT(YES),
  button2 = L["Show me"],
  OnAccept = function()
    sepgp_looted = {}
    sepgp:defaultPrint(L["Loot info cleared"])
  end,
  OnCancel = function(_,reason)
    if reason == "clicked" then
      sepgp_loot:Toggle(true)
      sepgp:defaultPrint(L["Loot info can be cleared at any time from the Tablet context menu or '/shooty clearloot' command"])
    end
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 0,
  hideOnEscape = 1
}

StaticPopupDialogs["SHOOTY_EPGP_CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL Points?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    sepgp:gp_reset_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}

local sepgp_auto_gp_menu = {
  --{text = "Choose an Action", isTitle = true},
  {text = L["Add MainSpec GP"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if (dialog) then
      local data = dialog.data
      local player, price = data[sepgp.loot_index.player], data[sepgp.loot_index.price]
      sepgp:givename_gp((player==YOU and sepgp._playerName or player),price)
      sepgp:refreshPRTablets()
      data[sepgp.loot_index.action] = sepgp.VARS.msgp
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp_loot:Refresh()
    end
  end},
  {text = L["Add OffSpec GP"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if (dialog) then
      local data = dialog.data
      local player, off_price = data[sepgp.loot_index.player], data[sepgp.loot_index.off_price]
      sepgp:givename_gp((player==YOU and sepgp._playerName or player),off_price)
      sepgp:refreshPRTablets()
      data[sepgp.loot_index.action] = sepgp.VARS.osgp
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp_loot:Refresh()
    end
  end},
  {text = L["Bank or D/E"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if (dialog) then
      local data = dialog.data
      data[sepgp.loot_index.action] = sepgp.VARS.bankde
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp_loot:Refresh()
    end
  end}
}
function sepgp:EasyMenu_Initialize(level, menuList)
  for i, info in ipairs(menuList) do
    if (info.text) then
      info.index = i
      UIDropDownMenu_AddButton( info, level )
    end
  end
end
function sepgp:EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, level)
  if ( displayMode == "MENU" ) then
    menuFrame.displayMode = displayMode
  end
  UIDropDownMenu_Initialize(menuFrame, function() sepgp:EasyMenu_Initialize(level, menuList) end, displayMode, level)
  ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y)
end

-- GLOBALS: sepgp_saychannel,sepgp_groupbyclass,sepgp_groupbyarmor,sepgp_groupbyrole,sepgp_raidonly,sepgp_decay,sepgp_minep,sepgp_reservechannel,sepgp_main,sepgp_progress,sepgp_discount,sepgp_altspool,sepgp_altpercent,sepgp_log,sepgp_dbver,sepgp_looted,sepgp_debug,sepgp_fubar
-- GLOBALS: sepgp,sepgp_prices,sepgp_standings,sepgp_bids,sepgp_loot,sepgp_reserves,sepgp_alts,sepgp_logs
