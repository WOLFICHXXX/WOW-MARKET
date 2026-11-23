-- WolfichBars Forever 0.3.3
-- Compact secure action bars. No protected actions are changed during combat.
local ADDON, ns = ...
local ROOT, SETTINGS, MINIMAP_BUTTON
local pendingEnabled = nil
local refreshMinimap
local buttons, editorButtons, glow = {}, {}, {}
local db, currentClass, currentMode, editMode = nil, nil, "FARM", false
local needsRefresh = false
local inApply = false
local bindState = {expected=0, verified=0, uncertain=false}
local SAY = "|cffaa8be5WolfichBars|r: "
local function message(text) print(SAY..text) end
local function combat() return InCombatLockdown and InCombatLockdown() end
local function guard()
  if combat() then message("В бою нельзя менять панели, назначенные заклинания и клавиши.") return false end
  return true
end
local function playerClass()
  local _, token = UnitClass("player")
  return token or "WARLOCK"
end
local function freshSlots(class, which)
  local source = ns.templates[class] and ns.templates[class][which] or nil
  local slots={}
  for i=1,16 do
    local row=source and source[i]
    slots[i] = {id=(row and row[1] or 0), label=(row and row[2] or "")}
  end
  return slots
end
local function profile()
  db.classes = db.classes or {}
  currentClass = playerClass()
  if not db.classes[currentClass] then
    db.classes[currentClass]={active="FARM", FARM=freshSlots(currentClass,"FARM"), PVP=freshSlots(currentClass,"PVP")}
  end
  local p = db.classes[currentClass]
  if currentClass=="WARLOCK" and p.adaptive==nil then
    -- Keep earlier player setup as a backup; begin with one clean auto preset.
    p.previousFarm=p.FARM
    p.overrides={}
    p.adaptive=true
  end
  if not p.FARM then p.FARM=freshSlots(currentClass,"FARM") end
  if not p.PVP then p.PVP=freshSlots(currentClass,"PVP") end
  if p.active~="PVP" then p.active="FARM" end
  currentMode="FARM"
  return p
end
local function levelNow() return (UnitLevel and UnitLevel("player")) or 1 end
local function adaptiveEnabled()
  return currentClass=="WARLOCK" and currentMode=="FARM" and profile().adaptive~=false
end
local function isLearned(info,book)
  if not info then return false end
  local e=book.byID[info.id]
  if not e and info.en then e=book.byName[info.en] end
  if not e and info.ru then e=book.byName[info.ru] end
  if e then return true end
  if IsPlayerSpell then local ok,yes=pcall(IsPlayerSpell,info.id);if ok and yes then return true end end
  if IsSpellKnown then local ok,yes=pcall(IsSpellKnown,info.id);if ok and yes then return true end end
  return false
end
local function autoSlot(i,book)
  local p=profile()
  if p.overrides and p.overrides[i] then return p.overrides[i] end
  local choices=ns.farmPlan and ns.farmPlan[i]
  if not choices then return p.FARM[i] end
  local lvl=levelNow()
  -- Use the spellbook as authority. Character level alone never unlocks a button.
  local future
  for _,id in ipairs(choices) do
    local info=ns.abilityDB[id]
    if info then
      if lvl>=info.level and isLearned({id=id,en=info.en,ru=info.ru},book) then
        local chosen={id=id,label=info.en,unlocks=info.level,talent=info.talent}
        if i==1 and lvl>=8 and isLearned({id=980,en="Bane of Agony",ru="Бич агонии"},book) then
          chosen.macro="AFF_DOTS"
        end
        if future then chosen.pendingID=future.id;chosen.pendingLevel=future.level end
        return chosen
      end
      if not future then future={id=id,level=info.level,name=info.en} end
    end
  end
  -- Grey preview until the user actually trains the spell.
  if future then return {id=future.id,label=future.name,unlocks=future.level} end
  return {id=0,label=""}
end
local function slot(i,book)
  if adaptiveEnabled() then return autoSlot(i,book or {byID={},byName={}}) end
  return profile()[currentMode][i]
end
local function getSpellInfo(id)
  if not id or id==0 then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info=pcall(C_Spell.GetSpellInfo,id)
    if ok and info and info.name then return info end
  end
  if GetSpellInfo then
    local ok, name, _, icon=pcall(GetSpellInfo,id)
    if ok and name then return {name=name,iconID=icon} end
  end
  return nil
end
local function getIcon(id, override)
  if override then return override end
  if not id or id==0 then return 134400 end
  if C_Spell and C_Spell.GetSpellTexture then
    local ok,icon=pcall(C_Spell.GetSpellTexture,id)
    if ok and icon then return icon end
  end
  local inf=getSpellInfo(id)
  return inf and inf.iconID or 134400
end
local function spellBookIndex()
  local index={byID={},byName={},found=0,available=false}
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    index.available=true
    local bank=Enum.SpellBookSpellBank.Player
    for i=1,500 do
      local ok, info=pcall(C_SpellBook.GetSpellBookItemInfo,i,bank)
      if ok and type(info)=="table" and not info.isPassive then
        local name = info.name
        if not name and C_SpellBook.GetSpellBookItemName then
          local good, bookName = pcall(C_SpellBook.GetSpellBookItemName,i,bank)
          if good then name=bookName end
        end
        if name and name~="" then
          local found={id=info.spellID or info.actionID,name=name,icon=info.iconID}
          index.byName[name]=found
          if found.id then index.byID[found.id]=found end
          index.found=index.found+1
        end
      end
    end
  elseif C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
    index.available=true
    for i=1,500 do
      local ok,name=pcall(C_SpellBook.GetSpellBookItemName,i,Enum.SpellBookSpellBank.Player)
      if ok and type(name)=="string" and name~="" then
        index.byName[name]={name=name}
        index.found=index.found+1
      end
    end
  elseif GetSpellBookItemName then
    index.available=true
    for i=1,500 do
      local ok,name=pcall(GetSpellBookItemName,i,"spell")
      if ok and type(name)=="string" and name~="" then
        index.byName[name]={name=name}; index.found=index.found+1
      end
    end
  end
  return index
end
local function resolveSpell(s, index)
  if not s or not s.id or s.id==0 then return nil, nil, "Пустая ячейка" end
  local info=getSpellInfo(s.id)
  local suggested=(info and info.name) or ns.ru[s.id] or s.label or "Неизвестное заклинание"
  local entry=index.byID[s.id]
  if not entry then
    if info and info.name then entry=index.byName[info.name] end
    if not entry and s.label then entry=index.byName[s.label] end
    if not entry and ns.ru[s.id] then entry=index.byName[ns.ru[s.id]] end
    if not entry and ns.aliases and ns.aliases[s.id] then
      for _, alias in ipairs(ns.aliases[s.id]) do
        if index.byName[alias] then entry=index.byName[alias]; break end
      end
    end
  end
  if entry then return entry.name, entry.icon, entry.name end
  -- Some Forever spell lists do not expose a complete spellbook. Only use this
  -- fallback if the API positively reports an ability as known.
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok,known=pcall(C_SpellBook.IsSpellKnown,s.id)
    if ok and known and info and info.name then return info.name,info.iconID,info.name end
  end
  if IsPlayerSpell then
    local ok,known=pcall(IsPlayerSpell,s.id)
    if ok and known and info and info.name then return info.name,info.iconID,info.name end
  end
  if IsSpellKnown then
    local ok,known=pcall(IsSpellKnown,s.id)
    if ok and known and info and info.name then return info.name,info.iconID,info.name end
  end
  return nil,nil,suggested
end
-- Optional, secure, one-spell-per-press DoT macro for Affliction farming.
-- Only an addon-owned macro is edited. Never replace a user's unrelated macro.
local DOT_MACRO_NAME="WB_AFFDOTS"
local function ensureDotMacro(book)
  if not (CreateMacro and GetMacroIndexByName and GetMacroInfo) then return nil, nil end
  -- The secure macro changes only outside combat; its names come from the
  -- actual character spellbook so custom Forever/localized spells work.
  local order={172,980,348} -- Corruption, Bane of Agony, Immolate
  local steps={}
  for _,id in ipairs(order) do
    local name=resolveSpell({id=id,label=ns.abilityDB[id] and ns.abilityDB[id].en},book)
    if name then steps[#steps+1]={id=id,name=name} end
  end
  if #steps<2 or steps[1].id~=172 or steps[2].id~=980 then return nil,nil end
  local names={}
  for _,step in ipairs(steps) do names[#names+1]=step.name end
  local body="#showtooltip\n/castsequence reset=target/10 "..table.concat(names,", ")
  local index=GetMacroIndexByName(DOT_MACRO_NAME)
  if index and index>0 then
    local _,_,oldBody=GetMacroInfo(index)
    if oldBody==body then return index,steps end
    -- Never overwrite a user macro sharing our name unless it bears our signature.
    if type(oldBody)=="string" and oldBody:find("^#showtooltip\n/castsequence reset=target/") and EditMacro then
      local ok=pcall(EditMacro,index,DOT_MACRO_NAME,getIcon(172),body,1)
      if ok then return index,steps end
    end
    return nil,nil
  end
  local ok,newIndex=pcall(CreateMacro,DOT_MACRO_NAME,getIcon(172),body,1)
  if ok and type(newIndex)=="number" and newIndex>0 then return newIndex,steps end
  return nil,nil -- Macro slots full: normal Corruption stays usable.
end
local function actualBinding(key)
  if not GetBindingAction then return nil end
  local ok,result=pcall(GetBindingAction,key,true)
  if not ok then return nil end
  return result or ""
end
local function verifyBindings()
  local expected, verified, uncertain=0,0,false
  if db and db.bindings and db.enabled ~= false and ROOT and ROOT:IsShown() then
    for i,b in ipairs(buttons) do
      if b.ready then
        expected=expected+1
        local action=actualBinding(ns.keys[i])
        if action==nil then
          uncertain=true
        elseif string.find(action,b:GetName(),1,true) then
          verified=verified+1
        end
      end
    end
  end
  bindState.expected=expected
  bindState.verified=verified
  bindState.uncertain=uncertain
end
local function bindButtons(showFeedback)
  if not ROOT or not guard() then return end
  if not ClearOverrideBindings or not SetOverrideBindingClick then
    message("Этот клиент не предоставляет нужный API перехвата клавиш.")
    db.bindings=false
    return
  end
  ClearOverrideBindings(ROOT)
  if db.bindings and db.enabled ~= false and ROOT:IsShown() then
    for i,b in ipairs(buttons) do
      -- Only learned spells capture their shortcuts. Empty slots do not steal
      -- the player's original Q/E movement keys.
      if b.ready then
        local ok=pcall(SetOverrideBindingClick,ROOT,true,ns.keys[i],b:GetName(),"LeftButton")
        if not ok and SetOverrideBinding then
          pcall(SetOverrideBinding,ROOT,true,ns.keys[i],"CLICK "..b:GetName()..":LeftButton")
        end
      end
    end
  end
  verifyBindings()
  if ROOT and ROOT.hotkeys then
    local state
    if not db.bindings then state="KEYS OFF"
    elseif db.enabled == false then state="PAUSED"
    elseif bindState.expected==0 then state="NO SPELLS"
    elseif bindState.uncertain then state="KEYS ON ?"
    elseif bindState.verified==bindState.expected then state="KEYS ON"
    else state="KEYS "..bindState.verified.."/"..bindState.expected end
    ROOT.hotkeys:SetText(state)
    ROOT.hotkeys:GetFontString():SetTextColor(db.bindings and .45 or .95, db.bindings and .95 or .67, db.bindings and .61 or .52)
  end
  if showFeedback then
    if not db.bindings then
      message("Клавиши выключены — обычные назначения снова действуют.")
    else
      message("Привязки: "..bindState.verified.."/"..bindState.expected.." проверены. /wb test — подробности.")
      if bindState.expected>0 and bindState.verified < bindState.expected and not bindState.uncertain then
        message("Часть клавиш занята другим аддоном или не подтверждена клиентом.")
      end
    end
  end
end
local function refreshHeader()
  if not ROOT then return end
  local names={WARLOCK="WARLOCK",PRIEST="PRIEST",HUNTER="HUNTER"}
  ROOT.title:SetText("WOLFICH / "..(names[currentClass] or currentClass).." / FARM")
  -- Button shows the TARGET mode, while the title shows the ACTIVE mode.
  ROOT.mode:SetText("ПРЕСЕТ")
  ROOT.edit:SetText(editMode and "DONE" or "EDIT")
  ROOT.edit:GetFontString():SetTextColor(editMode and .45 or .95, editMode and .94 or .82, editMode and .61 or .94)
end
local function drawSlots()
  if not ROOT or not guard() then return end
  profile()
  local book=spellBookIndex()
  local readyCount=0
  local dotsIndex,dotsSteps=nil,nil
  if adaptiveEnabled() and levelNow()>=8 then dotsIndex,dotsSteps=ensureDotMacro(book) end
  for i,b in ipairs(buttons) do
    local s=slot(i,book)
    local castName, foundIcon, visualName=resolveSpell(s,book)
    local ready=castName~=nil
    b.ready=ready
    b.spellName=visualName
    b.spellID=s.id
    b.unlocks=s.unlocks
    b.pendingID=s.pendingID
    b.pendingLevel=s.pendingLevel
    if b.futureIcon then
      b.futureIcon:SetShown(s.pendingID~=nil)
      if s.pendingID then b.futureIcon:SetTexture(getIcon(s.pendingID));b.futureIcon:SetDesaturated(true) end
    end
    b.bookUncertain=(not ready and not book.available)
    if ready then readyCount=readyCount+1 end
    b.icon:SetTexture(getIcon(s.id,foundIcon))
    b.icon:SetDesaturated(not ready)
    b.icon:SetVertexColor(ready and 1 or .65,ready and 1 or .65,ready and 1 or .65)
    b.tint:SetAlpha(ready and .04 or .57)
    b.border:SetColorTexture(ready and .47 or .25,ready and .28 or .26,ready and .69 or .29,.94)
    b.empty:SetShown(not s.id or s.id==0)
    -- Macro is bound as a native secure action; a single press casts ONE DoT.
    local macroIndex=(i==1 and s.macro=="AFF_DOTS") and dotsIndex or nil
    b:SetAttribute("type1", ready and (macroIndex and "macro" or "spell") or nil)
    b:SetAttribute("spell1", ready and not macroIndex and castName or nil)
    b:SetAttribute("macro1", ready and macroIndex or nil)
    b:SetAttribute("type", ready and (macroIndex and "macro" or "spell") or nil)
    b:SetAttribute("spell", ready and not macroIndex and castName or nil)
    b:SetAttribute("macro", ready and macroIndex or nil)
    b.macroActive=macroIndex~=nil
    b.macroSteps=macroIndex and dotsSteps or nil
    if b.macroBadge then b.macroBadge:SetShown(b.macroActive) end
    if macroIndex then b.spellName="DoT макрос ("..#dotsSteps.." заклинания)" end
    editorButtons[i]:SetShown(editMode)
  end
  refreshHeader()
  if db.bindings and db.enabled ~= false then bindButtons(false) else bindButtons(false) end
  if SETTINGS and SETTINGS:IsShown() then SETTINGS:Refresh() end
end
local function updateDisplay()
  if not ROOT then return end
  if combat() then needsRefresh=true return end
  drawSlots()
end
local function setEditor(value)
  if not guard() then return end
  editMode=value and true or false
  updateDisplay()
  if editMode then
    message("РЕДАКТОР ВКЛ: открой книгу (P), перетащи способность на ячейку; ПКМ очищает.")
  else
    message("РЕДАКТОР ВЫКЛ: панель снова готова к использованию.")
  end
end
local function setMode(mode)
  if not guard() then return end
  mode="FARM" -- single leveling preset in v0.3
  profile().active=mode
  currentMode=mode
  updateDisplay()
  message("Активная раскладка: "..(mode=="PVP" and "PVP" or "FARM")..". Кнопка показывает режим для переключения.")
end
local function assignSpell(i,id)
  if not guard() then return end
  local num=tonumber(id) or 0
  local info=getSpellInfo(num)
  local newSlot={id=num,label=info and info.name or ""}
  if adaptiveEnabled() then
    local p=profile()
    p.overrides=p.overrides or {}
    p.overrides[i]=newSlot -- even empty slots are intentional edits
  else
    local s=slot(i)
    s.id=newSlot.id; s.label=newSlot.label
  end
  updateDisplay()
end
-- The minimap switch pauses the bar AND temporarily releases every override.
-- The saved keyboard preference survives pause/resume.
local function setEnabled(want, quiet)
  want = want and true or false
  if combat() then
    pendingEnabled=want
    message("Переключение отложено до окончания боя.")
    return
  end
  db.enabled=want
  db.hidden=not want
  if not want then
    editMode=false
    if SETTINGS then SETTINGS:Hide() end
    ROOT:Hide()
  else
    ROOT:Show()
    updateDisplay()
  end
  bindButtons(false)
  if refreshMinimap then refreshMinimap() end
  if not quiet then
    message(want and "Панели включены. Клавиши: "..(db.bindings and "сохранённый режим ON" or "OFF").."."
      or "Панели скрыты, перехват клавиш снят. Значок на миникарте остаётся.")
  end
end

local function setCompact(compact)
  if not guard() then return end
  db.compact=compact and true or false
  ROOT:SetHeight(db.compact and 106 or 176)
  for i=9,16 do
    buttons[i]:SetShown(not db.compact)
    editorButtons[i]:SetShown((not db.compact) and editMode)
  end
  ROOT.shiftLine:SetShown(not db.compact)
  ROOT.shiftTag:SetShown(not db.compact)
  if SETTINGS and SETTINGS:IsShown() then SETTINGS:Refresh() end
end
local function setScale(value)
  if not guard() then return end
  if not value or value<.65 or value>1.4 then return end
  db.scale=value
  ROOT:SetScale(value)
  if SETTINGS and SETTINGS:IsShown() then SETTINGS:Refresh() end
end
local function label(parent,font,anchor,text)
  local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontNormalSmall")
  t:SetPoint(unpack(anchor))
  t:SetText(text or "")
  return t
end
local function button(parent,caption,width,x,action)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
  b:SetSize(width,22)
  b:SetPoint("TOPRIGHT",parent,"TOPRIGHT",x,-7)
  -- WoW can put an invisible draggable child above buttons with equal frame levels.
  -- Force controls to their own higher level so they ALWAYS receive clicks.
  b:SetFrameLevel(parent:GetFrameLevel()+12)
  b:EnableMouse(true)
  b:RegisterForClicks("LeftButtonUp")
  b:SetText(caption)
  b:SetScript("OnClick",function(self,mouse)
    if mouse == "LeftButton" then action(self,mouse) end
  end)
  return b
end
local function showHelp()
  if not SETTINGS then return end
  SETTINGS:SetShown(not SETTINGS:IsShown())
  if SETTINGS:IsShown() then SETTINGS:Refresh() end
end
local function resetFarm()
  if not guard() then return end
  local p=profile()
  p.adaptive=true
  p.overrides={}
  editMode=false
  updateDisplay()
  message("Раскладка сброшена к адаптивному пресету по уровню.")
end
-- Live in-game farming instructions; derives key labels from the ACTUAL
-- current slots (including player overrides) and only suggests learned spells.
local function farmingInstructions()
  local function hotkey(spellID)
    for i,b in ipairs(buttons) do
      if b.ready and b.spellID==spellID then
        local key=ns.keyLabels[i] or tostring(i)
        if db and db.bindings~=true then return "["..key.." / мышь]" end
        return "["..key.."]"
      end
    end
    return nil
  end
  local lines={}
  local function add(t) lines[#lines+1]=t end
  local lvl=levelNow()
  local macroKey=nil
  for i,b in ipairs(buttons) do
    if b.ready and b.macroActive then
      macroKey=ns.keyLabels[i] or tostring(i)
      break
    end
  end
  if macroKey then
    local count=2
    for _,b in ipairs(buttons) do if b.macroActive and b.macroSteps then count=#b.macroSteps break end end
    add("1. Нажми ["..macroKey.."] "..count.." раза: Порча → Бич агонии"..(count>=3 and " → Жертвенный огонь." or "."))
    add("   Одна клавиша = ОДНО заклинание, между нажатиями ГКД.")
  else
    local corrupt,agony=hotkey(172),hotkey(980)
    if corrupt then add("1. Наложи Порчу "..corrupt..".") end
    if agony then add("2. Добавь Бич агонии "..agony.." на долгоживущую цель.") end
    if not corrupt and not agony then add("1. Изучи Порчу и Бич агонии у тренера — пока используй доступные заклинания.") end
  end
  local immolate=hotkey(348)
  if immolate then add("• Огненный DoT вручную: Жертвенный огонь "..immolate.." (выгоден на живучих мобах).") end
  local agonyKey=hotkey(980)
  if agonyKey then add("• Обновить проклятие отдельно: Бич агонии "..agonyKey.." (не сбрасывая макрос).") end
  local siphon=hotkey(18265)
  if siphon then add("+ Вытягивание жизни "..siphon.." на прочную цель (если взят талант).") end
  local drain,bolt=hotkey(689),hotkey(686)
  if drain then
    add("3. Если нужно здоровье — Похищение жизни "..drain..".")
  end
  if bolt then add("4. Добивай Стрелой Тьмы "..bolt.." или жезлом для экономии маны.") end
  local fear=hotkey(5782)
  if fear then add("! Враг подошёл / их несколько: Страх "..fear.." (берегись соседних мобов).") end
  local tap=hotkey(1454)
  if tap then add("! Мало маны: Жизнеотвод "..tap.." только при запасе здоровья.") end
  local soul=hotkey(1120)
  if soul then add("• Нужны осколки: добей цель Похищением души "..soul..".") end
  local stone=hotkey(6201)
  if stone then add("• Подготовка: создай и носи камень здоровья "..stone..".") end
  if lvl>=10 then
    local pet=hotkey(697)
    if pet then add("• Соло-фарм: призови демона Бездны "..pet.." и следи за агро.")
    else add("• Для безопасного фарма используй подходящего демона, доступного в книге.") end
  end
  if lvl>=8 and not macroKey and hotkey(172) and hotkey(980) then
    add("• Макрос DoT пока не создан: используй Порчу и Бич агонии раздельно.")
  end
  if db and db.bindings~=true then
    add("КЛАВИШИ ВЫКЛ: нажимай значки мышью или включи KEYS ON.")
  end
  return table.concat(lines,"\n")
end

local function makeSettings()
  local f=CreateFrame("Frame","WolfichBarsOptions",UIParent,"BackdropTemplate")
  f:SetSize(520,548)
  f:SetPoint("CENTER",UIParent,"CENTER",230,15)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true);f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart",function(self) self:StartMoving() end)
  f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=5,right=5,top=5,bottom=5}})
  f:SetBackdropColor(.028,.034,.057,.98);f:SetBackdropBorderColor(.37,.27,.50,1)
  local header=label(f,"GameFontNormalLarge",{"TOPLEFT",f,"TOPLEFT",18,-16},"WOLFICH / ПРЕСЕТЫ")
  header:SetTextColor(.86,.71,1)
  local close=CreateFrame("Button",nil,f,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",f,"TOPRIGHT",0,0)
  local line=f:CreateTexture(nil,"ARTWORK");line:SetPoint("TOPLEFT",f,18,-46);line:SetSize(484,1);line:SetColorTexture(.43,.33,.56,.65)
  local subtitle=label(f,"GameFontNormal",{"TOPLEFT",f,"TOPLEFT",20,-62},"АФФЛИ / ПРОКАЧКА И ФАРМ")
  subtitle:SetTextColor(.66,.92,.74)
  local status=label(f,"GameFontHighlight",{"TOPLEFT",f,"TOPLEFT",20,-88},"")
  status:SetWidth(477);status:SetJustifyH("LEFT")
  local desc=label(f,"GameFontHighlightSmall",{"TOPLEFT",f,"TOPLEFT",20,-113},"Пресет 01: изученные умения, ручные изменения и советы по уровню.")
  desc:SetWidth(480);desc:SetJustifyH("LEFT")
  local title=label(f,"GameFontNormal",{"TOPLEFT",f,"TOPLEFT",20,-142},"КАК ФАРМИТЬ / ПОШАГОВО")
  title:SetTextColor(.98,.78,.47)
  local guideBG=CreateFrame("Frame",nil,f,"BackdropTemplate")
  guideBG:SetPoint("TOPLEFT",f,"TOPLEFT",17,-161)
  guideBG:SetSize(486,245)
  guideBG:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
  guideBG:SetBackdropColor(.045,.055,.076,.95)
  guideBG:SetBackdropBorderColor(.28,.28,.38,.9)
  local scroll=CreateFrame("ScrollFrame",nil,guideBG,"UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",guideBG,"TOPLEFT",10,-9)
  scroll:SetPoint("BOTTOMRIGHT",guideBG,"BOTTOMRIGHT",-27,8)
  local inside=CreateFrame("Frame",nil,scroll)
  inside:SetSize(438,300)
  scroll:SetScrollChild(inside)
  local guide=inside:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  guide:SetPoint("TOPLEFT",inside,"TOPLEFT",0,0)
  guide:SetWidth(435)
  guide:SetJustifyH("LEFT")
  guide:SetJustifyV("TOP")
  local preset=label(f,"GameFontNormalSmall",{"TOPLEFT",f,"TOPLEFT",20,-418},"ПРЕСЕТ 01 / ФАРМ (АВТО)")
  preset:SetTextColor(.98,.78,.47)
  local reset=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  reset:SetSize(224,27);reset:SetPoint("TOPLEFT",f,"TOPLEFT",18,-443)
  reset:SetText("СБРОСИТЬ РАСКЛАДКУ")
  reset:SetFrameLevel(f:GetFrameLevel()+10)
  reset:SetScript("OnClick",resetFarm)
  local toggle=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  toggle:SetSize(242,27);toggle:SetPoint("LEFT",reset,"RIGHT",9,0)
  toggle:SetFrameLevel(f:GetFrameLevel()+10)
  toggle:SetScript("OnClick",function()
    if not guard() then return end
    local p=profile();p.adaptive=not (p.adaptive~=false)
    updateDisplay()
  end)
  local tip=label(f,"GameFontHighlightSmall",{"TOPLEFT",f,"TOPLEFT",20,-478},"EDIT — изменяй ячейки; сброс вернёт адаптивный пресет.")
  tip:SetWidth(480);tip:SetJustifyH("LEFT")
  local scaleMinus=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  scaleMinus:SetSize(112,23);scaleMinus:SetPoint("TOPLEFT",f,"TOPLEFT",18,-510)
  scaleMinus:SetText("МАСШТАБ -");scaleMinus:SetScript("OnClick",function() setScale(math.max(.65,(db.scale or 1)-.1)) end)
  local scalePlus=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  scalePlus:SetSize(112,23);scalePlus:SetPoint("LEFT",scaleMinus,"RIGHT",7,0)
  scalePlus:SetText("МАСШТАБ +");scalePlus:SetScript("OnClick",function() setScale(math.min(1.4,(db.scale or 1)+.1)) end)
  local note=label(f,"GameFontHighlightSmall",{"LEFT",scalePlus,"RIGHT",16,0},"")
  function f:Refresh()
    local p=profile();local on=p.adaptive~=false
    local count=0
    if p.overrides then for _ in pairs(p.overrides) do count=count+1 end end
    status:SetText("Уровень "..levelNow().."  |  Адаптация: "..(on and "ВКЛ" or "ВЫКЛ").."  |  Правок: "..count)
    status:SetTextColor(on and .53 or .99,on and .91 or .58,.68)
    toggle:SetText(on and "ОТКЛЮЧИТЬ АВТО" or "ВКЛЮЧИТЬ АВТО")
    note:SetText(string.format("%.1fx",db.scale or 1))
    guide:SetText(farmingInstructions())
    inside:SetHeight(math.max(240,guide:GetStringHeight()+12))
  end
  f:Hide();SETTINGS=f
end
local function makeActionButton(i)
  local secondary=i>8
  local size=secondary and 39 or 52
  local col=(i-1)%8
  local left=17+col*61+(secondary and 6 or 0)
  local top=secondary and -129 or -43
  local b=CreateFrame("Button","WolfichBarsAction"..i,ROOT,"SecureActionButtonTemplate")
  b:SetSize(size,size)
  b:SetPoint("TOPLEFT",ROOT,"TOPLEFT",left,top)
  b:RegisterForClicks("AnyUp","AnyDown")
  local frame=b:CreateTexture(nil,"BACKGROUND")
  frame:SetAllPoints(); frame:SetColorTexture(.13,.14,.18,1)
  b.icon=b:CreateTexture(nil,"ARTWORK")
  b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",2,-2)
  b.icon:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-2,2)
  b.tint=b:CreateTexture(nil,"OVERLAY")
  b.tint:SetAllPoints(b.icon); b.tint:SetColorTexture(0,0,0,1)
  b.border=b:CreateTexture(nil,"OVERLAY")
  b.border:SetPoint("TOPLEFT",b,"TOPLEFT",0,0)
  b.border:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",0,0)
  b.border:SetColorTexture(.32,.24,.43,.8)
  b.border:SetDrawLayer("BACKGROUND",1)
  local keyBG=b:CreateTexture(nil,"OVERLAY")
  keyBG:SetSize(secondary and 20 or 19,13)
  keyBG:SetPoint("TOPRIGHT",b,"TOPRIGHT",-1,-1)
  keyBG:SetColorTexture(0,0,0,.82)
  b.key=label(b,"GameFontNormalSmall",{"TOPRIGHT",b,"TOPRIGHT",-3,-1},ns.keyLabels[i])
  b.key:SetTextColor(1,.87,.52)
  -- Distinct visible badge for a macro; does not cover the hotkey label.
  local macroMark=b:CreateTexture(nil,"OVERLAY")
  macroMark:SetSize(17,15)
  macroMark:SetPoint("BOTTOMLEFT",b,"BOTTOMLEFT",1,1)
  macroMark:SetColorTexture(.10,.25,.12,.96)
  local macroText=label(b,"GameFontNormalSmall",{"BOTTOMLEFT",b,"BOTTOMLEFT",5,2},"M")
  macroText:SetTextColor(.55,1,.55)
  local macroBadge={SetShown=function(_,visible) macroMark:SetShown(visible);macroText:SetShown(visible) end}
  macroBadge:SetShown(false)
  b.macroBadge=macroBadge
  b.empty=label(b,"GameFontNormalLarge",{"CENTER",b,"CENTER",0,0},"+")
  b.empty:SetTextColor(.56,.56,.63)
  b:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    if self.macroActive and self.macroSteps then
      GameTooltip:SetText("МАКРОС: последовательные DoT",.62,1,.62)
      for stepIndex,step in ipairs(self.macroSteps) do
        local icon=getIcon(step.id)
        local texture=icon and ("|T"..tostring(icon)..":18:18:0:0|t ") or ""
        GameTooltip:AddLine(texture..stepIndex..". "..step.name,1,.88,.66)
      end
      GameTooltip:AddLine("1 нажатие = 1 заклинание; повторяй после ГКД",.78,.86,1,true)
      GameTooltip:AddLine("Сброс цепочки: другая цель или 10 сек без нажатия",.75,.75,.82,true)
      GameTooltip:AddLine("Бич агонии отдельно: [4], Жертвенный огонь: [R]",.9,.72,.55,true)
    elseif self.spellID and self.spellID~=0 and GameTooltip.SetSpellByID then
      local ok=pcall(GameTooltip.SetSpellByID,GameTooltip,self.spellID)
      if not ok then GameTooltip:SetText(self.spellName or "Заклинание") end
    else
      GameTooltip:SetText(self.spellName or "Пустая ячейка",1,.86,.61)
    end
    GameTooltip:AddLine("Клавиша: "..ns.keys[i],1,.8,.35)
    if not self.ready then
      GameTooltip:AddLine(self.bookUncertain and "Не удалось прочитать книгу заклинаний" or "Ещё не изучено / не найдено в книге",.95,.57,.57,true)
      if self.unlocks and levelNow()<self.unlocks then GameTooltip:AddLine("Доступно с уровня "..self.unlocks,1,.78,.39,true) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function() GameTooltip:Hide() end)
  buttons[i]=b
  local overlay=CreateFrame("Button",nil,ROOT)
  overlay:SetAllPoints(b)
  overlay:SetFrameLevel(b:GetFrameLevel()+5)
  overlay:RegisterForClicks("AnyUp")
  local shadow=overlay:CreateTexture(nil,"OVERLAY")
  shadow:SetAllPoints(); shadow:SetColorTexture(.25,.58,.93,.23)
  overlay:SetScript("OnReceiveDrag",function()
    if combat() then return end
    local kind, value=GetCursorInfo()
    if kind=="spell" and type(value)=="number" then assignSpell(i,value); ClearCursor() end
  end)
  overlay:SetScript("OnClick",function(_,mouse)
    if combat() then return end
    if mouse=="RightButton" then assignSpell(i,0); return end
    local kind,value=GetCursorInfo()
    if kind=="spell" and type(value)=="number" then
      assignSpell(i,value); ClearCursor()
    else
      message("Открой книгу (P) и перетащи заклинание на ячейку, или ПКМ очисти.")
    end
  end)
  overlay:Hide()
  editorButtons[i]=overlay
end
local function minimapPosition()
  if not MINIMAP_BUTTON or not Minimap then return end
  local angle=math.rad(db.minimapAngle or 225)
  local radius=(Minimap:GetWidth() or 140)*.5+5
  MINIMAP_BUTTON:ClearAllPoints()
  MINIMAP_BUTTON:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*radius,math.sin(angle)*radius)
end
refreshMinimap = function()
  if not MINIMAP_BUTTON then return end
  MINIMAP_BUTTON.icon:SetDesaturated(db.enabled == false)
  MINIMAP_BUTTON.icon:SetVertexColor(db.enabled == false and .55 or 1,db.enabled == false and .55 or .83,db.enabled == false and .55 or 1)
  MINIMAP_BUTTON:SetShown(not db.hideMinimap)
end
local function makeMinimap()
  if not Minimap then return end
  local b=CreateFrame("Button","WolfichBarsMinimapButton",Minimap)
  MINIMAP_BUTTON=b
  b:SetSize(32,32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(Minimap:GetFrameLevel()+8)
  b:RegisterForClicks("LeftButtonUp","RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local rim=b:CreateTexture(nil,"OVERLAY")
  rim:SetSize(53,53)
  rim:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  rim:SetPoint("TOPLEFT",b,"TOPLEFT",0,0)
  local bg=b:CreateTexture(nil,"BACKGROUND")
  bg:SetSize(20,20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT",b,"TOPLEFT",7,-5)
  b.icon=b:CreateTexture(nil,"ARTWORK")
  b.icon:SetSize(20,20)
  b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",7,-5)
  b.icon:SetTexture("Interface\\Icons\\Spell_Shadow_CurseOfAchimonde")
  b:SetScript("OnClick",function(_,mouse)
    if b.wasDragged then b.wasDragged=false return end
    if mouse=="RightButton" then showHelp()
    else setEnabled(not db.enabled) end
  end)
  b:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT")
    GameTooltip:AddLine("WolfichBars Forever",.85,.65,1)
    GameTooltip:AddLine("Сейчас: "..(db.enabled and "ВКЛЮЧЕН" or "ВЫКЛЮЧЕН"),db.enabled and .35 or 1,db.enabled and 1 or .55,.6)
    GameTooltip:AddLine("ЛКМ: показать / скрыть панели и их клавиши",1,1,1)
    GameTooltip:AddLine("ПКМ: открыть настройки",1,1,1)
    GameTooltip:AddLine("Перетаскивание: передвинуть значок",.7,.7,.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart",function(self)
    self.wasDragged=true
    self:SetScript("OnUpdate",function()
      local mx,my=Minimap:GetCenter()
      if not mx or not my then return end
      local scale=Minimap:GetEffectiveScale()
      local cx,cy=GetCursorPosition()
      if not cx or not cy or not scale or scale==0 then return end
      local dx,dy=cx/scale-mx,cy/scale-my
      if math.atan2 then
        db.minimapAngle=math.deg(math.atan2(dy,dx))
      else
        -- Lua implementations without atan2 still support a 2-argument atan in some clients.
        db.minimapAngle=math.deg(math.atan(dy/(dx==0 and .0001 or dx)))+(dx<0 and 180 or 0)
      end
      minimapPosition()
    end)
  end)
  b:SetScript("OnDragStop",function(self)
    self:SetScript("OnUpdate",nil)
  end)
  minimapPosition()
  refreshMinimap()
end

-- Optional entry in the standard AddOn Compartment (if supported).
function WolfichBars_CompartmentClick(_, mouse)
  if mouse=="RightButton" then showHelp() else setEnabled(not db.enabled) end
end
function WolfichBars_CompartmentEnter(_, frame)
  if not frame then return end
  GameTooltip:SetOwner(frame,"ANCHOR_LEFT")
  GameTooltip:AddLine("WolfichBars Forever")
  GameTooltip:AddLine("Нажать: панели ВКЛ / ВЫКЛ",1,1,1)
  GameTooltip:Show()
end
function WolfichBars_CompartmentLeave() GameTooltip:Hide() end

local function makeUI()
  ROOT=CreateFrame("Frame","WolfichBarsRoot",UIParent,"BackdropTemplate")
  ROOT:SetSize(510,176)
  ROOT:SetPoint("CENTER",UIParent,"CENTER",0,-185)
  ROOT:SetFrameStrata("MEDIUM")
  ROOT:SetMovable(true)
  ROOT:SetClampedToScreen(true)
  ROOT:EnableMouse(true)
  ROOT:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=11,insets={left=3,right=3,top=3,bottom=3}})
  ROOT:SetBackdropColor(.035,.043,.064,.92)
  ROOT:SetBackdropBorderColor(.31,.30,.39,.90)
  local drag=CreateFrame("Frame",nil,ROOT)
  -- FIX 0.2.3: the old drag frame covered the entire 510px header and ate
  -- clicks from PVP / EDIT / KEYS / HELP. Keep only the title as a drag handle.
  drag:SetPoint("TOPLEFT",ROOT,"TOPLEFT",3,-3)
  drag:SetSize(231,32)  -- ends at x=234; first control starts at x=250
  drag:SetFrameLevel(ROOT:GetFrameLevel()+2)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart",function() if not combat() and not db.locked then ROOT:StartMoving() end end)
  drag:SetScript("OnDragStop",function()
    ROOT:StopMovingOrSizing()
    local point,_,rel,x,y=ROOT:GetPoint(1)
    db.position={point=point,rel=rel,x=x,y=y}
  end)
  if db.position then
    ROOT:ClearAllPoints()
    ROOT:SetPoint(db.position.point or "CENTER",UIParent,db.position.rel or "CENTER",db.position.x or 0,db.position.y or -185)
  end
  ROOT.title=label(drag,"GameFontNormal",{"TOPLEFT",drag,"TOPLEFT",11,-7},"WOLFICH  /  WARLOCK")
  ROOT.title:SetTextColor(.86,.79,.96)
  ROOT.title:SetWidth(221); ROOT.title:SetJustifyH("LEFT")
  ROOT.help=button(ROOT,"?",27,-8,showHelp)
  ROOT.hotkeys=button(ROOT,"KEYS OFF",91,-42,function()
    if not guard() then return end
    db.bindings=not db.bindings
    bindButtons(true)
  end)
  ROOT.edit=button(ROOT,"EDIT",53,-140,function() setEditor(not editMode) end)
  ROOT.mode=button(ROOT,"ПРЕСЕТ",72,-200,showHelp)
  local headerHints = {
    {ROOT.mode, "Режим игры", "Адаптивный пресет Аффли и сброс расположения заклинаний."},
    {ROOT.edit, "Редактор ячеек", "Открой книгу заклинаний (P) и перетащи нужные способности. ПКМ удаляет."},
    {ROOT.hotkeys, "Горячие клавиши", "Включает/выключает временные привязки 1–4, Q/E/R/F и Shift. Не меняет постоянные настройки игры."},
    {ROOT.help, "Настройки", "Открыть окно параметров WolfichBars."},
  }
  for _,entry in ipairs(headerHints) do
    local control,title,description=entry[1],entry[2],entry[3]
    control:SetScript("OnEnter",function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self,"ANCHOR_TOP")
      GameTooltip:SetText(title,1,.84,.50)
      GameTooltip:AddLine(description,.94,.94,.94,true)
      GameTooltip:Show()
    end)
    control:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  end
  ROOT.shiftLine=ROOT:CreateTexture(nil,"ARTWORK")
  ROOT.shiftLine:SetHeight(1)
  ROOT.shiftLine:SetPoint("TOPLEFT",ROOT,"TOPLEFT",17,-109)
  ROOT.shiftLine:SetPoint("TOPRIGHT",ROOT,"TOPRIGHT",-17,-109)
  ROOT.shiftLine:SetColorTexture(.27,.28,.36,.72)
  ROOT.shiftTag=label(ROOT,"GameFontHighlightSmall",{"TOPLEFT",ROOT,"TOPLEFT",18,-113},"SHIFT")
  ROOT.shiftTag:SetTextColor(.54,.57,.70)
  for i=1,16 do makeActionButton(i) end
  ROOT:SetScale(db.scale or 1)
  if db.compact then setCompact(true) end
  if db.enabled == false then ROOT:Hide() end
  makeSettings()
  makeMinimap()
end
local function testBindings()
  if db.enabled == false then message("Панели сейчас скрыты через миникарту. Включи их ЛКМ или /wb show.") return end
  if not db.bindings then message("Сейчас клавиши ВЫКЛ. Нажми KEYS OFF на панели или введи /wb bind.") return end
  verifyBindings()
  message("Проверка: "..bindState.verified.."/"..bindState.expected.." изученных слотов.")
  for i,b in ipairs(buttons) do
    if b.ready then
      local action=actualBinding(ns.keys[i])
      local status=(action and string.find(action,b:GetName(),1,true)) and "OK" or "НЕ ПОДТВЕРЖДЕНО"
      message(ns.keys[i].." -> "..(b.spellName or "?").." ["..status.."]")
    end
  end
end
local function initialize()
  WolfichBarsDB=WolfichBarsDB or {}
  db=WolfichBarsDB
  if not db.scale or type(db.scale)~="number" then db.scale=1 end
  if type(db.bindings)~="boolean" then db.bindings=false end
  if type(db.enabled)~="boolean" then db.enabled=not (db.hidden==true) end
  db.hidden=not db.enabled
  if type(db.minimapAngle)~="number" then db.minimapAngle=225 end
  profile()
  makeUI()
  updateDisplay()
  message("v0.3.0 загружен. ЛКМ по миникарте — ВКЛ/ВЫКЛ; ПКМ — настройки. /wb test — клавиши.")
end
local ev=CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
for _,event in ipairs({"SPELLS_CHANGED","PLAYER_LEVEL_UP","ACTIVE_TALENT_GROUP_CHANGED","LEARNED_SPELL_IN_TAB"}) do pcall(ev.RegisterEvent,ev,event) end
ev:SetScript("OnEvent",function(_,event)
  if event=="PLAYER_LOGIN" then initialize()
  elseif event=="PLAYER_REGEN_DISABLED" then
    if editMode then
      editMode=false
      for i=1,16 do editorButtons[i]:Hide() end
      refreshHeader()
      needsRefresh=true
    end
  elseif event=="PLAYER_REGEN_ENABLED" then
    if pendingEnabled ~= nil then
      local want=pendingEnabled
      pendingEnabled=nil
      setEnabled(want)
    end
    if needsRefresh then needsRefresh=false; updateDisplay() end
  elseif ROOT then updateDisplay() end
end)
SLASH_WOLFICHBARS1="/wb"
SLASH_WOLFICHBARS2="/wolfichbars"
SlashCmdList.WOLFICHBARS=function(input)
  if not ROOT then return end
  local cmd,arg=(input or ""):match("^(%S*)%s*(.-)%s*$")
  cmd=string.lower(cmd or "")
  if cmd=="farm" then setMode("FARM")
  elseif cmd=="pvp" then setMode("PVP")
  elseif cmd=="edit" then setEditor(not editMode)
  elseif cmd=="bind" then
    if guard() then db.bindings=not db.bindings;bindButtons(true) end
  elseif cmd=="test" then testBindings()
  elseif cmd=="options" or cmd=="config" then showHelp()
  elseif cmd=="compact" then setCompact(not db.compact)
  elseif cmd=="show" then setEnabled(true)
  elseif cmd=="hide" then setEnabled(false)
  elseif cmd=="toggle" then setEnabled(not db.enabled)
  elseif cmd=="minimap" then
    if arg=="show" then db.hideMinimap=false
    elseif arg=="hide" then db.hideMinimap=true
    else db.hideMinimap=not db.hideMinimap end
    refreshMinimap()
    message("Значок миникарты: "..(db.hideMinimap and "скрыт (вернуть: /wb minimap show)" or "показан"))
  elseif cmd=="lock" then db.locked=not db.locked;message(db.locked and "Панель закреплена." or "Панель разблокирована.")
  elseif cmd=="scale" then
    local num=tonumber(arg)
    if num and num>=.65 and num<=1.4 then setScale(num) else message("Масштаб: /wb scale 0.9 (от 0.65 до 1.4)") end
  elseif cmd=="reset" then
    if guard() then
      resetFarm()
    end
  elseif cmd=="status" then
    message("Панели "..(db.enabled and "ON" or "OFF")..", режим "..currentMode..", клавиши "..(db.bindings and "ON" or "OFF")..", "..bindState.verified.."/"..bindState.expected.." подтверждено.")
  else
    message("/wb options | edit | bind | test | compact | scale 0.9 | lock | toggle | minimap | reset")
    message("Миникарта: ЛКМ — панели и клавиши ВКЛ/ВЫКЛ, ПКМ — настройки, перетащить — позиция. /wb minimap show — вернуть значок.")
    message("Кнопки: верх — 1 2 3 4 Q E R F, низ — Shift+те же. /wb edit — перетаскивание заклинаний из книги (P).")
  end
end