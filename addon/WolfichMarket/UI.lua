-- WolfichMarket: оформление и виджеты (свои текстуры: тёмное дерево, бронза, золото)
local _, ns = ...
local L = ns.L
local M = ns.MEDIA
local UI = {}
ns.UI = UI

UI.GOLD = { 0.95, 0.80, 0.42 }
UI.TEXT = { 0.93, 0.89, 0.80 }
UI.DIM = { 0.66, 0.62, 0.53 }

-- шрифты нового макета (2.43): Inter - текст и кнопки, Forum - заголовки (оба с кириллицей, лицензия OFL - media\fonts).
-- Без толстой обводки игры (она даёт «лесенку») - мягкая тень.
UI.GAME_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.FONT = ns.MEDIA .. "fonts\\Inter-Regular.ttf"
UI.BOLD = ns.MEDIA .. "fonts\\Inter-SemiBold.ttf"
UI.TITLE_FONT = ns.MEDIA .. "fonts\\Forum-Regular.ttf"
local OURS = { [UI.FONT] = true, [UI.BOLD] = true, [UI.TITLE_FONT] = true }
-- шрифты макета рассчитаны на 13-15 px: наши шрифты - на 12% крупнее заданного размера
UI.FONT_K = 1.12
local function setFont(fs, font, size, flags)
  if OURS[font] and flags == "OUTLINE" then flags = "" end
  if OURS[font] then size = math.floor(size * UI.FONT_K + 0.5) end
  local ok = fs:SetFont(font, size, flags or "")
  if ok == false then fs:SetFont(UI.GAME_FONT, size, "OUTLINE") return end
  if OURS[font] and fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.85) end
end
UI.SetFont = setFont

-- темы оформления (макеты пользователя, нарезанные tools/make_skin.py)
-- scale - во сколько раз уменьшать части макета; title/close - места в пикселях макета
UI.THEMES = {
  -- новый макет: места заголовка и крестика - в пикселях рамки (умножаются на масштаб)
  win = { title = { 64, -74 }, close = { -20, -13, 48, 48 }, btn = "mbtn" },
  main = { scale = 0.85, title = { 84, -40 }, close = { -2, -6, 60, 62 }, btn = "mbtn" },
  ah = { scale = 0.5, title = { 186, -60 }, close = { -56, -38, 56, 48 }, btn = "abtn" },
  mcard = { scale = 0.5, btn = "mbtn" },
  acard = { scale = 0.3, btn = "abtn" },
}
-- текстура оформления: картинка лежит в углу текстуры-степени-двойки, берём только её
function UI.SkinTex(t, name)
  if not t then return end
  t:SetTexture(M .. "skin\\" .. name)
  local tc = ns.SKIN_TC and ns.SKIN_TC[name]
  if tc then t:SetTexCoord(0, tc[1], 0, tc[2]) else t:SetTexCoord(0, 1, 0, 1) end
end
local function themeOf(f)
  local n = 0
  while f and n < 30 do
    if f.wmTheme then return f.wmTheme end
    f = f.GetParent and f:GetParent() or nil; n = n + 1
  end
end
UI.ThemeOf = themeOf

-- старая рамка (дерево + бронза) - для всплывающих уведомлений
local function plainSkin(f, opts)
  if ns.WIN_TC and ns.WIN_TC["f-tl"] and not opts.old then return UI.Box(f, opts.alpha or 0.92) end
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetTexture(M .. "bg", "REPEAT", "REPEAT")
  bg:SetHorizTile(true); bg:SetVertTile(true)
  bg:SetPoint("TOPLEFT", 4, -4); bg:SetPoint("BOTTOMRIGHT", -4, 4)
  bg:SetVertexColor(1, 1, 1, opts.alpha or 0.97)
  local shade = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  shade:SetPoint("TOPLEFT", 4, -4); shade:SetPoint("BOTTOMRIGHT", -4, 4)
  shade:SetColorTexture(0, 0, 0, 0.25)
  local e = 8
  local function edge(tex, p1, p2, horiz)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetTexture(M .. tex)
    if horiz then t:SetHeight(e) else t:SetWidth(e) end
    t:SetPoint(p1[1], f, p1[2], p1[3], p1[4]); t:SetPoint(p2[1], f, p2[2], p2[3], p2[4])
    return t
  end
  edge("edge-h", { "TOPLEFT", "TOPLEFT", 10, 0 }, { "TOPRIGHT", "TOPRIGHT", -10, 0 }, true)
  local b = edge("edge-h", { "BOTTOMLEFT", "BOTTOMLEFT", 10, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 0 }, true); b:SetTexCoord(0, 1, 1, 0)
  edge("edge-v", { "TOPLEFT", "TOPLEFT", 0, -10 }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 10 }, false)
  local r = edge("edge-v", { "TOPRIGHT", "TOPRIGHT", 0, -10 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 10 }, false); r:SetTexCoord(1, 0, 0, 1)
  local cs = opts.corner or 22
  local coords = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
  for pt, c in pairs(coords) do
    local t = f:CreateTexture(nil, "ARTWORK", nil, 2)
    t:SetTexture(M .. "corner"); t:SetSize(cs, cs); t:SetPoint(pt, f, pt, 0, 0); t:SetTexCoord(unpack(c))
  end
  return f
end

-- ---------- оформление нового макета (2.43): рамка из частей и простые панели ----------
local function winReady() return ns.WIN and ns.WIN_TC and ns.WIN_TC["f-tl"] ~= nil end
-- рамка окна: уголки, кристаллы и лапа - без растяжения; s - масштаб частей
function UI.FrameSkin(f, s)
  s = s or 0.5
  f.wmTheme, f.wmScale = "win", s
  local W = ns.WIN
  local function tex(name, layer, sub) local t = f:CreateTexture(nil, layer or "BORDER", nil, sub or 0); UI.WinTex(t, name); return t end
  local function sz(k) local v = W[k] or { 100, 100 }; return v[1] * s, v[2] * s end
  local c = tex("f-c", "BACKGROUND", -8); c:SetPoint("TOPLEFT", 44 * s, -58 * s); c:SetPoint("BOTTOMRIGHT", -46 * s, 34 * s)
  -- украшение фона: несколько едва заметных лапок (места - доли размера окна)
  if ns.WIN_TC["paw-bg"] then
    local PAWS = { { 0.10, 0.24, 0.17, -25, 0.075 }, { 0.32, 0.72, 0.12, 15, 0.06 }, { 0.56, 0.30, 0.10, -8, 0.05 },
      { 0.80, 0.64, 0.16, 30, 0.07 }, { 0.91, 0.17, 0.09, -40, 0.05 }, { 0.46, 0.90, 0.08, 10, 0.045 } }
    local paws = {}
    for i, p in ipairs(PAWS) do
      local t = f:CreateTexture(nil, "BACKGROUND", nil, -7); UI.WinTex(t, "paw-bg"); t:SetVertexColor(0.95, 0.75, 0.42); t:SetAlpha(p[5])
      pcall(t.SetRotation, t, math.rad(p[4]))
      paws[i] = t
    end
    local function place()
      local w, h = f:GetWidth() or 0, f:GetHeight() or 0
      if w < 50 or h < 50 then return end
      for i, p in ipairs(PAWS) do
        local t, size = paws[i], math.min(w, h) * p[3]
        t:SetSize(size, size); t:ClearAllPoints(); t:SetPoint("CENTER", f, "TOPLEFT", w * p[1], -h * p[2])
      end
    end
    place()
    if f.HookScript then f:HookScript("OnSizeChanged", place) end
  end
  local tlw, tlh = sz("f-tl"); local trw = sz("f-tr"); local lw = sz("f-l"); local blw, bh = sz("f-bl"); local brw = sz("f-br"); local emw = sz("f-em")
  local t = tex("f-t"); t:SetHeight(tlh); t:SetPoint("TOPLEFT", tlw, 0); t:SetPoint("TOPRIGHT", -trw, 0)
  local l = tex("f-l"); l:SetWidth(lw); l:SetPoint("TOPLEFT", 0, -tlh); l:SetPoint("BOTTOMLEFT", 0, bh)
  local r = tex("f-r"); r:SetWidth(lw); r:SetPoint("TOPRIGHT", 0, -tlh); r:SetPoint("BOTTOMRIGHT", 0, bh)
  -- нижняя планка - только между уголками (иначе её концы торчат за рамку)
  local bf = tex("f-bf"); bf:SetHeight(bh); bf:SetPoint("BOTTOMLEFT", blw * 0.6, 0); bf:SetPoint("BOTTOMRIGHT", -brw * 0.6, 0)
  local q = tex("f-tl", "BORDER", 1); q:SetSize(tlw, tlh); q:SetPoint("TOPLEFT")
  q = tex("f-tr", "BORDER", 1); q:SetSize(trw, tlh); q:SetPoint("TOPRIGHT")
  q = tex("f-bl", "BORDER", 1); q:SetSize(blw, bh); q:SetPoint("BOTTOMLEFT")
  q = tex("f-br", "BORDER", 1); q:SetSize(brw, bh); q:SetPoint("BOTTOMRIGHT")
  q = tex("f-em", "BORDER", 2); q:SetSize(emw, bh); q:SetPoint("BOTTOM")
  return f
end
-- панель внутри окна: тёмная подложка и тонкая золотая кромка
function UI.Box(f, alpha)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -6); bg:SetAllPoints(); bg:SetColorTexture(0.02, 0.02, 0.03, alpha or 0.42)
  local function line(p1, p2, horiz)
    local t = f:CreateTexture(nil, "BORDER", nil, 3); t:SetColorTexture(0.42, 0.33, 0.17, 0.95)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
    t:SetPoint(p1); t:SetPoint(p2)
  end
  line("TOPLEFT", "TOPRIGHT", true); line("BOTTOMLEFT", "BOTTOMRIGHT", true); line("TOPLEFT", "BOTTOMLEFT"); line("TOPRIGHT", "BOTTOMRIGHT")
  f.wmBox = true
  return f
end

-- рамка из 9 частей: UI.Skin(f, { theme = "main" | "ah" | "mcard" | "acard", scale = ... })
-- с 2.43 окна и панели - в оформлении нового макета: окна - рамка из частей, карточки и меню - простая панель
function UI.Skin(f, opts)
  opts = opts or {}
  if winReady() and not opts.old then
    if opts.theme == "main" or opts.theme == "ah" then return UI.FrameSkin(f, opts.frame or (opts.theme == "ah" and 0.55 or 0.42)) end
    return UI.Box(f, opts.theme and 0.42 or 0.9)
  end
  local sz = opts.theme and ns.SKIN and ns.SKIN[opts.theme]
  if not sz then return plainSkin(f, opts) end
  local s = opts.scale or UI.THEMES[opts.theme].scale
  f.wmTheme, f.wmScale = opts.theme, s
  local function tex(k, layer, sub)
    local t = f:CreateTexture(nil, layer or "BORDER", nil, sub or 0); UI.SkinTex(t, opts.theme .. "-" .. k); return t
  end
  -- фон под рамкой: от внутреннего края кромки (рамка к нему плавно растворяется - без швов)
  local ins = sz.inset or { sz.l * 0.5, sz.t * 0.5, sz.r * 0.5, sz.b * 0.5 }
  local c = tex("c", "BACKGROUND", -8)
  c:SetPoint("TOPLEFT", ins[1] * s, -ins[2] * s); c:SetPoint("BOTTOMRIGHT", -ins[3] * s, ins[4] * s)
  local t = tex("t"); t:SetHeight(sz.t * s); t:SetPoint("TOPLEFT", sz.tl[1] * s, 0); t:SetPoint("TOPRIGHT", -sz.tr[1] * s, 0)
  local b = tex("b"); b:SetHeight(sz.b * s); b:SetPoint("BOTTOMLEFT", sz.bl[1] * s, 0); b:SetPoint("BOTTOMRIGHT", -sz.br[1] * s, 0)
  local l = tex("l"); l:SetWidth(sz.l * s); l:SetPoint("TOPLEFT", 0, -sz.tl[2] * s); l:SetPoint("BOTTOMLEFT", 0, sz.bl[2] * s)
  local r = tex("r"); r:SetWidth(sz.r * s); r:SetPoint("TOPRIGHT", 0, -sz.tr[2] * s); r:SetPoint("BOTTOMRIGHT", 0, sz.br[2] * s)
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
    local q = tex(k, "BORDER", 1); q:SetSize(sz[k][1] * s, sz[k][2] * s)
    q:SetPoint(({ tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" })[k])
  end
  return f
end

function UI.Font(parent, size, color, layer, flags)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  setFont(fs, UI.FONT, size or 12, flags or "OUTLINE")
  local c = color or UI.TEXT
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

function UI.Title(parent, text)
  local th = parent.wmTheme and UI.THEMES[parent.wmTheme]
  if th and th.title then
    local s = parent.wmScale
    local fs = parent:CreateFontString(nil, "OVERLAY")
    setFont(fs, UI.TITLE_FONT, (parent.wmTheme == "win" and 17) or (s >= 0.8 and 18 or 15), "OUTLINE")
    fs:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    fs:SetPoint("LEFT", parent, "TOPLEFT", th.title[1] * s, th.title[2] * s); fs:SetText(text)
    return fs
  end
  local h = parent:CreateTexture(nil, "ARTWORK")
  h:SetTexture(M .. "header")
  h:SetPoint("TOPLEFT", 10, -9); h:SetPoint("TOPRIGHT", -10, -9); h:SetHeight(30)
  local logo = parent:CreateTexture(nil, "OVERLAY")
  logo:SetTexture(M .. "paw"); logo:SetSize(20, 20); logo:SetPoint("LEFT", h, "LEFT", 8, 0)
  local fs = UI.Font(parent, 14, UI.GOLD, "OVERLAY", "OUTLINE")
  fs:SetPoint("LEFT", logo, "RIGHT", 6, 0); fs:SetText(text)
  return fs, h
end

-- невидимая кнопка поверх нарисованного в рамке крестика
function UI.Close(parent, onClick)
  local th = parent.wmTheme and UI.THEMES[parent.wmTheme]
  local b
  if th and th.close then
    local s = parent.wmScale
    b = CreateFrame("Button", nil, parent)
    b:SetSize(th.close[3] * s, th.close[4] * s); b:SetPoint("TOPRIGHT", th.close[1] * s, th.close[2] * s)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.4, 0.18)
  else
    b = CreateFrame("Button", nil, parent, "UIPanelCloseButton"); b:SetPoint("TOPRIGHT", -8, -8)
  end
  b:SetScript("OnClick", onClick or function() parent:Hide() end)
  return b
end

-- кнопка из 3 частей (края + растягиваемая середина); b:SetGold(on) - золотая/тёмная
-- оформление 2.43: кнопки нового макета (золотая - тёмный текст, тёмная - золотой)
local GOLD_TXT, DARK_TXT = { 0.17, 0.10, 0.02 }, { 0.97, 0.83, 0.53 }
local function hasWinBtn() return ns.WIN_TC and ns.WIN_TC["btn-dark-l"] ~= nil end
function UI.Button(parent, text, w, h, onClick, gold)
  local b = CreateFrame("Button", nil, parent)
  w, h = w or 100, h or 22
  b:SetSize(w, h)
  local th = themeOf(parent)
  local pre = (th and UI.THEMES[th] and UI.THEMES[th].btn) or "mbtn"
  local win = hasWinBtn()
  local cap = win and math.max(4, math.floor(h * (ns.WIN_BTN_CAP or 0.4) + 0.5)) or math.max(4, math.floor(h * 36 / 82 + 0.5))
  if cap * 2 > w - 2 then cap = math.floor((w - 2) / 2) end
  local parts, hls = {}, {}
  local function place(t, k)
    if k == "l" then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(cap)
    elseif k == "r" then t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(cap)
    else t:SetPoint("TOPLEFT", cap, 0); t:SetPoint("BOTTOMRIGHT", -cap, 0) end
  end
  for _, k in ipairs({ "l", "m", "r" }) do
    local t = b:CreateTexture(nil, "BACKGROUND"); place(t, k); parts[k] = t
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); place(hl, k); hl:SetBlendMode("ADD"); hl:SetAlpha(0.35); hls[k] = hl
  end
  local fs = b:CreateFontString(nil, "OVERLAY")
  local FONT = win and UI.BOLD or UI.FONT
  local base = math.max(11, math.min(13, math.floor(h * 0.5)))
  setFont(fs, FONT, base, "") -- шрифт до первого SetText, иначе игра выдаёт ошибку
  fs:SetPoint("CENTER", 0, 1); fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
  b.label = fs
  local isGold
  local function sw() return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0 end
  -- надпись - только между краями кнопки (рамки по бокам не заходит); не влезает - шрифт меньше, до 9
  local function fit()
    local maxw = (b:GetWidth() or w) - cap - 8
    local size = base
    setFont(fs, FONT, size, ""); fs:SetWidth(0)
    while sw() > maxw and size > 9 do size = size - 1; setFont(fs, FONT, size, "") end
    if sw() > maxw then fs:SetWidth(maxw) end
  end
  -- вид: золотая (выбрана) или тёмная; выключенная - всегда тёмная с приглушённым, но читаемым текстом
  local function paint()
    local en = b:IsEnabled() ~= false
    local kind = (isGold and en) and "-gold-" or "-dark-"
    if win then for k, t in pairs(parts) do UI.WinTex(t, "btn" .. kind .. k); UI.WinTex(hls[k], "btn" .. kind .. k) end
    else for k, t in pairs(parts) do UI.SkinTex(t, pre .. kind .. k); UI.SkinTex(hls[k], pre .. kind .. k) end end
    for _, t in pairs(parts) do t:SetDesaturated(not en); t:SetAlpha(en and 1 or 0.85) end
    local c = not en and { 0.82, 0.78, 0.68 } or (isGold and GOLD_TXT or DARK_TXT)
    fs:SetTextColor(c[1], c[2], c[3])
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, (isGold and en) and 0 or 0.85) end
  end
  function b:SetGold(on) isGold = on and true or false; paint() end
  function b:IsGold() return isGold end
  function b:SetLabel(t) fs:SetText(t or ""); fit() end
  -- ширина по тексту (шрифт base не уменьшается): для кнопок со своей шириной
  function b:FitWidth(minW, maxW)
    setFont(fs, FONT, base, ""); fs:SetWidth(0)
    local tw = sw()
    self:SetWidth(math.max(minW or 0, math.min(maxW or 1000, math.floor(tw + cap + 18))))
    fit()
    return self:GetWidth()
  end
  b:SetGold(gold); b:SetLabel(text)
  b:SetScript("OnDisable", paint)
  b:SetScript("OnEnable", paint)
  b:HookScript("OnMouseDown", function(self) if self:IsEnabled() ~= false then fs:SetPoint("CENTER", 1, 0) end end)
  b:HookScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 1) end)
  b:HookScript("OnSizeChanged", fit)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Icon(parent, tex, size, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); b.tex = t
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetBlendMode("ADD"); hl:SetAlpha(0.5)
  local function set(name)
    local sk = name:match("^skin\\(.+)$")
    if sk then UI.SkinTex(t, sk); UI.SkinTex(hl, sk) else t:SetTexture(M .. name); hl:SetTexture(M .. name) end
  end
  set(tex)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  if onClick then b:SetScript("OnClick", onClick) end
  function b:SetIcon(name) set(name) end
  return b
end

-- галочка в стиле оформления
function UI.CheckBox(parent, size)
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(size or 20, size or 20)
  if ns.WIN_TC and ns.WIN_TC["chk-on"] then
    c:SetNormalTexture(M .. "win\\chk-off"); UI.WinTex(c:GetNormalTexture(), "chk-off")
    c:SetCheckedTexture(M .. "win\\chk-on"); UI.WinTex(c:GetCheckedTexture(), "chk-on")
    c:SetDisabledCheckedTexture(M .. "win\\chk-on"); UI.WinTex(c:GetDisabledCheckedTexture(), "chk-on")
    local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); UI.WinTex(hl, "chk-off"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.35)
    return c
  end
  c:SetNormalTexture(M .. "skin\\mchk-off"); UI.SkinTex(c:GetNormalTexture(), "mchk-off")
  c:SetCheckedTexture(M .. "skin\\mchk-on"); UI.SkinTex(c:GetCheckedTexture(), "mchk-on")
  c:SetDisabledCheckedTexture(M .. "skin\\mchk-on"); UI.SkinTex(c:GetDisabledCheckedTexture(), "mchk-on")
  local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); UI.SkinTex(hl, "mchk-off"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.4)
  return c
end

function UI.Check(parent, text, get, set)
  local c = UI.CheckBox(parent, 20)
  local fs = UI.Font(c, 11, UI.TEXT); fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(text)
  c.label = fs
  c:SetScript("OnShow", function(self) self:SetChecked(get()) end)
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  c:SetChecked(get())
  return c
end

-- вкладки: набор кнопок, одна активна
function UI.Tabs(parent, names, onSelect)
  local tabs, x = {}, 12
  for i, n in ipairs(names) do
    local b = UI.Button(parent, n, 92, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -44)
    x = x + 96
    b:SetScript("OnClick", function() tabs.select(i) end)
    tabs[i] = b
  end
  function tabs.select(i)
    for k, b in ipairs(tabs) do b:SetGold(k == i) end
    tabs.current = i
    onSelect(i)
  end
  return tabs
end

-- прокручиваемый список строк фиксированной высоты
function UI.List(parent, rowH, makeRow, fillRow)
  local box = CreateFrame("Frame", nil, parent)
  box.rows, box.data, box.offset = {}, {}, 0
  box:EnableMouseWheel(true)
  local bar = CreateFrame("Slider", nil, box)
  bar:SetWidth(8); bar:SetPoint("TOPRIGHT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0)
  bar:SetOrientation("VERTICAL"); bar:SetMinMaxValues(0, 0); bar:SetValueStep(1)
  local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.35)
  local th = bar:CreateTexture(nil, "OVERLAY"); th:SetColorTexture(0.85, 0.66, 0.32, 0.9); th:SetSize(8, 28)
  bar:SetThumbTexture(th)
  box.bar = bar
  -- раскрытие строки (box:EnableDetail): слева треугольник, под строкой - панель на n строк
  local DX = 0
  function box:Layout()
    local n = math.max(1, math.floor((self:GetHeight() or 100) / rowH))
    for i = #self.rows + 1, n do
      local r = CreateFrame("Button", nil, self)
      r.box = self
      r:SetHeight(rowH)
      r:SetPoint("TOPLEFT", DX, -(i - 1) * rowH); r:SetPoint("RIGHT", bar, "LEFT", -2, 0)
      local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(M .. "row-hl")
      if i % 2 == 0 then local z = r:CreateTexture(nil, "BACKGROUND"); z:SetAllPoints(); z:SetColorTexture(1, 1, 1, 0.025) end
      if self.detailN then
        local t = CreateFrame("Button", nil, r); t:SetSize(14, rowH); t:SetPoint("RIGHT", r, "LEFT", -1, 0)
        t.tex = t:CreateTexture(nil, "ARTWORK"); t.tex:SetSize(11, 11); t.tex:SetPoint("CENTER"); UI.WinTex(t.tex, "tri")
        local th = t:CreateTexture(nil, "HIGHLIGHT"); th:SetSize(11, 11); th:SetPoint("CENTER"); UI.WinTex(th, "tri"); th:SetBlendMode("ADD")
        t:SetScript("OnClick", function() local d = r.data; if d then box:Toggle(d) end end)
        t:SetScript("OnEnter", function(self2) GameTooltip:SetOwner(self2, "ANCHOR_LEFT"); GameTooltip:AddLine(L"Подробнее: себестоимость, прибыль и график", 1, 1, 1); GameTooltip:Show() end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.tri = t
      end
      makeRow(r)
      self.rows[i] = r
    end
    self.visible = n
  end
  function box:EnableDetail(n, make, fill, keyOf)
    self.detailN, self.keyOf = n, keyOf or function(d) return d.id end
    DX = 16
    for _, r in ipairs(self.rows) do r:Hide() end
    self.rows = {}; self.visible = nil
    local det = CreateFrame("Frame", nil, self)
    det:SetHeight(n * rowH)
    local bg = det:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.42)
    local ln = det:CreateTexture(nil, "BORDER"); ln:SetHeight(1); ln:SetPoint("BOTTOMLEFT"); ln:SetPoint("BOTTOMRIGHT"); ln:SetColorTexture(0.55, 0.42, 0.2, 0.6)
    make(det); det.fill = fill; det:Hide()
    self.det = det
    if self.SetClipsChildren then self:SetClipsChildren(true) end
  end
  -- строка раскрыта? / раскрыть-свернуть
  function box:IsOpen(d) return self.openKey ~= nil and d and self.keyOf(d) == self.openKey end
  function box:Toggle(d)
    local k = d and self.keyOf(d)
    if k == nil or self.openKey == k then self.openKey = nil else self.openKey = k; self.openData = d end
    self:Refresh()
  end
  -- данные с пустыми местами под раскрытой строкой
  function box:View()
    if not self.detailN or self.openKey == nil then return self.data end
    local v, found = {}, false
    for _, d in ipairs(self.data) do
      v[#v + 1] = d
      if not found and self.keyOf(d) == self.openKey then
        found = true; self.openData = d
        for k = 1, self.detailN do v[#v + 1] = { _det = d, _k = k } end
      end
    end
    if not found then self.openKey = nil end
    return v
  end
  function box:Refresh()
    if not self.visible then self:Layout() end
    local view = self:View()
    self.view = view
    local max = math.max(0, #view - self.visible)
    if self.offset > max then self.offset = max end
    bar:SetMinMaxValues(0, max); bar:SetValue(self.offset)
    if max == 0 then bar:Hide() else bar:Show() end
    local first
    for i, d in ipairs(view) do if d._det then first = i; break end end
    for i, r in ipairs(self.rows) do
      local d = view[i + self.offset]
      if d and not d._det and i <= self.visible then
        r.data = d; fillRow(r, d); r:Show()
        if r.tri then pcall(r.tri.tex.SetRotation, r.tri.tex, self:IsOpen(d) and -math.pi / 2 or 0) end
      else r.data = nil; r:Hide() end
    end
    local det = self.det
    if det then
      local slot = first and (first - self.offset) or nil
      if slot and slot > -self.detailN + 1 and slot <= self.visible then
        det:ClearAllPoints(); det:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(slot - 1) * rowH); det:SetPoint("RIGHT", bar, "LEFT", -2, 0)
        if det.key ~= self.openKey or not det:IsShown() then det.key = self.openKey; det:Show(); det.fill(det, self.openData) end
      else det:Hide(); det.key = nil end
    end
    if self.empty then if #self.data == 0 then self.empty:Show() else self.empty:Hide() end end
  end
  function box:SetData(d) self.data = d or {}; if self.det then self.det.key = nil end; self:Refresh() end
  box:SetScript("OnMouseWheel", function(self, delta) self.offset = math.max(0, self.offset - delta * 3); self:Refresh() end)
  bar:SetScript("OnValueChanged", function(_, v) v = math.floor(v + 0.5); if v ~= box.offset then box.offset = v; box:Refresh() end end)
  box:SetScript("OnSizeChanged", function(self) self.visible = nil; self:Refresh() end)
  local empty = UI.Font(box, 12, UI.DIM); empty:SetPoint("CENTER"); empty:SetJustifyH("CENTER"); empty:SetWordWrap(true); empty:SetWidth(260)
  box.empty = empty
  return box
end

-- поле ввода денег: золото / серебро / медь
function UI.MoneyInput(parent, onChange, compact)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(compact and 132 or 170, 22)
  local boxes = {}
  local labels = { L"|cffffd100з|r", L"|cffc7c7cfс|r", L"|cffeda55fм|r" }
  local x = 0
  for i = 1, 3 do
    local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    e:SetSize(compact and (i == 1 and 38 or 22) or (i == 1 and 50 or 28), compact and 18 or 20); e:SetPoint("LEFT", x + 6, 0); e:SetAutoFocus(false); e:SetNumeric(true); e:SetMaxLetters(i == 1 and 6 or 2)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local l = UI.Font(f, 11); l:SetPoint("LEFT", e, "RIGHT", 2, 0); l:SetText(labels[i])
    e:SetScript("OnTextChanged", function(_, user) if user and onChange then onChange(f:Get()) end end)
    boxes[i] = e
    x = x + (compact and (i == 1 and 54 or 36) or (i == 1 and 70 or 46))
  end
  f.boxes = boxes
  function f:HasFocus() for _, e in ipairs(boxes) do if e:HasFocus() then return true end end return false end
  function f:Clear() for _, e in ipairs(boxes) do e:SetText("") end end
  function f:Get() return (tonumber(boxes[1]:GetText()) or 0) * 10000 + (tonumber(boxes[2]:GetText()) or 0) * 100 + (tonumber(boxes[3]:GetText()) or 0) end
  function f:Set(c) c = math.max(0, math.floor((c or 0) + 0.5)); boxes[1]:SetText(math.floor(c / 10000)); boxes[2]:SetText(math.floor(c % 10000 / 100)); boxes[3]:SetText(c % 100) end
  return f
end

-- сглаженная линия: текстура с мягкими краями поперёк толщины (вместо «лесенки»)
function UI.LineTex(l, r, g, b, a)
  if ns.WIN_TC and ns.WIN_TC["line"] and l.SetTexture then
    l:SetTexture(M .. "win\\line", nil, nil, "TRILINEAR"); l:SetVertexColor(r, g, b, a or 1)
  else l:SetColorTexture(r, g, b, a or 1) end
end
-- линейный график: точки { {t, price, qty}, ... }
function UI.Chart(parent)
  local f = CreateFrame("Frame", nil, parent)
  local plot = CreateFrame("Frame", nil, f)
  plot:SetPoint("TOPLEFT", 54, -16); plot:SetPoint("BOTTOMRIGHT", -40, 20)
  local frameBg = plot:CreateTexture(nil, "BACKGROUND"); frameBg:SetAllPoints(); frameBg:SetColorTexture(0, 0, 0, 0.3)
  f.lines, f.bars, f.labels, f.grid, f.slines, f.slabels = {}, {}, {}, {}, {}, {}
  -- легенда: две линии - цена и продано (шт)
  f.legend = UI.Font(f, 9, UI.DIM, "OVERLAY"); f.legend:SetPoint("BOTTOMRIGHT", plot, "TOPRIGHT", 0, 2)
  f.legend:SetText("|cfff2c761— " .. L"цена" .. "|r   |cff66d9cc— " .. L"продано, шт (примерно)" .. "|r")
  local msg = UI.Font(f, 12, UI.DIM); msg:SetPoint("CENTER", plot); msg:SetJustifyH("CENTER")
  local function line(i)
    local l = f.lines[i]
    if not l then
      if plot.CreateLine then l = plot:CreateLine(nil, "ARTWORK"); l:SetThickness(3.5)
      else l = plot:CreateTexture(nil, "ARTWORK"); l:SetSize(2, 2) end
      UI.LineTex(l, 0.95, 0.78, 0.38, 1)
      f.lines[i] = l
    end
    l:Show(); return l
  end
  local function lbl(i)
    local s = f.labels[i] or UI.Font(f, 9, UI.DIM); f.labels[i] = s; s:Show(); return s
  end
  -- клик по графику (если задан f.onClick) - например, открыть большой график
  f:EnableMouse(true)
  f:SetScript("OnMouseUp", function(self) if self.onClick then self.onClick() end end)
  function f:SetPoints(pts)
    for _, l in ipairs(self.lines) do l:Hide() end
    for _, l in ipairs(self.slines) do l:Hide() end
    for _, s in ipairs(self.slabels) do s:Hide() end
    for _, b in ipairs(self.bars) do b:Hide() end
    for _, s in ipairs(self.labels) do s:Hide() end
    for _, g in ipairs(self.grid) do g:Hide() end
    for _, s in ipairs(self.peakLbl or {}) do s:Hide() end
    for _, d in ipairs(self.dots or {}) do d:Hide() end
    self.legend:SetShown(not self.compact and not self.noLegend)
    if not pts or #pts < 2 then msg:SetText(L"Мало данных для графика.\nКаждый снимок аукциона добавляет точку."); msg:Show() return end
    msg:Hide()
    local W, H = plot:GetWidth(), plot:GetHeight()
    if W < 10 or H < 10 then return end
    local t0, t1, lo, hi, qmax = pts[1][1], pts[#pts][1], math.huge, 0, 1
    for _, p in ipairs(pts) do lo = math.min(lo, p[2]); hi = math.max(hi, p[2]); qmax = math.max(qmax, p[3] or 0) end
    if hi == lo then hi = hi * 1.1 + 1; lo = lo * 0.9 end
    local pad = (hi - lo) * 0.1; hi = hi + pad; lo = math.max(0, lo - pad)
    local X = function(t) return (t - t0) / math.max(1, t1 - t0) * W end
    local Y = function(v) return (v - lo) / (hi - lo) * H end
    -- сетка и подписи цен (в компактном виде - только низ и верх)
    local steps = self.compact and 1 or 3
    for i = 0, steps do
      local v = lo + (hi - lo) * i / steps
      local g = self.grid[i + 1] or plot:CreateTexture(nil, "BORDER"); self.grid[i + 1] = g
      g:SetColorTexture(1, 1, 1, 0.07); g:SetHeight(1); g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v)); g:SetPoint("RIGHT", plot); g:Show()
      local s = lbl(i + 1); s:ClearAllPoints(); s:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, Y(v)); s:SetText(ns.money(v, true))
    end
    -- вторая линия: сколько продано между снимками (на сколько уменьшилось выставленное количество)
    local sold, smax = {}, 0
    for i = 2, #pts do
      local a, b = pts[i - 1][3], pts[i][3]
      local v = (a and b and a > b) and (a - b) or 0
      sold[i] = v; if v > smax then smax = v end
    end
    sold[1] = 0
    if smax > 0 then
      local SY = function(v) return v / smax * H * 0.85 end
      for i = 2, #pts do
        local l = self.slines[i - 1]
        if not l then
          if plot.CreateLine then l = plot:CreateLine(nil, "ARTWORK"); l:SetThickness(3) else l = plot:CreateTexture(nil, "ARTWORK"); l:SetSize(2, 2) end
          UI.LineTex(l, 0.4, 0.85, 0.8, 0.9); self.slines[i - 1] = l
        end
        local x1, y1, x2, y2 = X(pts[i - 1][1]), SY(sold[i - 1]), X(pts[i][1]), SY(sold[i])
        if l.SetStartPoint then l:SetStartPoint("BOTTOMLEFT", plot, x1, y1); l:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
        else l:ClearAllPoints(); l:SetPoint("CENTER", plot, "BOTTOMLEFT", x2, y2) end
        l:Show()
      end
      -- шкала справа: штуки
      for k, v in ipairs(self.compact and { smax } or { 0, math.floor(smax / 2 + 0.5), smax }) do
        local s = self.slabels[k] or UI.Font(f, 9, UI.DIM); self.slabels[k] = s
        s:ClearAllPoints(); s:SetPoint("LEFT", plot, "BOTTOMRIGHT", 4, SY(v)); s:SetText("|cff66d9cc" .. v .. "|r"); s:Show()
      end
    end
    -- линия цены
    for i = 2, #pts do
      local l = line(i - 1)
      local x1, y1, x2, y2 = X(pts[i - 1][1]), Y(pts[i - 1][2]), X(pts[i][1]), Y(pts[i][2])
      if l.SetStartPoint then l:SetStartPoint("BOTTOMLEFT", plot, x1, y1); l:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
      else l:ClearAllPoints(); l:SetPoint("CENTER", plot, "BOTTOMLEFT", x2, y2) end
    end
    -- подписи цен на пиках: максимум, минимум и до 3 самых высоких локальных пиков
    if self.compact then
      -- компактно: только точка и цена последнего снимка
      self.dots = self.dots or {}; self.peakLbl = self.peakLbl or {}
      local p = pts[#pts]
      local d = self.dots[1] or plot:CreateTexture(nil, "OVERLAY"); self.dots[1] = d
      d:SetColorTexture(1, 0.85, 0.4, 1); d:SetSize(6, 6); d:ClearAllPoints(); d:SetPoint("CENTER", plot, "BOTTOMLEFT", X(p[1]), Y(p[2])); d:Show()
    elseif self.showPeaks then
      self.peakLbl = self.peakLbl or {}; self.dots = self.dots or {}
      for _, s in ipairs(self.peakLbl) do s:Hide() end
      for _, d in ipairs(self.dots) do d:Hide() end
      -- все пики и провалы (локальные максимумы и минимумы), начиная с самых заметных; подписи не налезают друг на друга
      local cand, maxI, minI, sum = {}, 1, 1, 0
      for i, p in ipairs(pts) do
        sum = sum + p[2]
        if p[2] > pts[maxI][2] then maxI = i end
        if p[2] < pts[minI][2] then minI = i end
        local a, b = pts[i - 1], pts[i + 1]
        if a and b then
          if p[2] > a[2] and p[2] >= b[2] then cand[#cand + 1] = { i, true }
          elseif p[2] < a[2] and p[2] <= b[2] then cand[#cand + 1] = { i, false } end
        end
      end
      local mean = sum / #pts
      table.sort(cand, function(a, b) return math.abs(pts[a[1]][2] - mean) > math.abs(pts[b[1]][2] - mean) end)
      local pick, used = { { maxI, true }, { minI, false } }, { [maxI] = true, [minI] = true }
      for _, c in ipairs(cand) do
        if #pick >= 10 then break end
        local i, far = c[1], true
        for _, q in ipairs(pick) do
          if q[2] == c[2] and math.abs(X(pts[q[1]][1]) - X(pts[i][1])) < 40 then far = false end
        end
        if far and not used[i] then pick[#pick + 1] = c; used[i] = true end
      end
      for k, q in ipairs(pick) do
        local p, up = pts[q[1]], q[2]
        local d = self.dots[k] or plot:CreateTexture(nil, "OVERLAY"); self.dots[k] = d
        d:SetColorTexture(up and 1 or 0.6, up and 0.85 or 0.77, up and 0.4 or 0.92, 1); d:SetSize(5, 5)
        d:ClearAllPoints(); d:SetPoint("CENTER", plot, "BOTTOMLEFT", X(p[1]), Y(p[2])); d:Show()
        local s = self.peakLbl[k] or UI.Font(plot, 10, UI.GOLD, "OVERLAY", "OUTLINE"); self.peakLbl[k] = s
        s:ClearAllPoints(); s:SetPoint(up and "BOTTOM" or "TOP", plot, "BOTTOMLEFT", math.max(24, math.min(W - 24, X(p[1]))), Y(p[2]) + (up and 5 or -5))
        s:SetText(ns.money(p[2], true)); s:Show()
      end
    end
    -- подписи времени (без наложения: близкие друг к другу пропускаются)
    local mid = math.floor((#pts + 1) / 2)
    local xs = { X(pts[1][1]), X(pts[mid][1]), X(pts[#pts][1]) }
    local show = { xs[3] - xs[1] >= 150, not self.compact and (xs[2] - xs[1] >= 80) and (xs[3] - xs[2] >= 80), true }
    for k, idx in ipairs({ 1, mid, #pts }) do
      local s = lbl(4 + k); s:ClearAllPoints()
      if show[k] then
        s:SetPoint(k == 1 and "TOPLEFT" or k == 3 and "TOPRIGHT" or "TOP", plot, "BOTTOMLEFT", xs[k], -3)
        s:SetText(date("%d.%m %H:%M", pts[idx][1]))
      else s:Hide() end
    end
  end
  return f
end

-- всплывающее уведомление в стиле аддона
local toast
function UI.Toast(title, text, icon)
  if not toast then
    toast = CreateFrame("Frame", "WolfichMarketToast", UIParent)
    toast:SetSize(340, 64); toast:SetPoint("TOP", UIParent, "TOP", 0, -140); toast:SetFrameStrata("HIGH")
    UI.Skin(toast, { corner = 16 })
    local glow = toast:CreateTexture(nil, "BACKGROUND", nil, -6); glow:SetTexture(M .. "glow"); glow:SetPoint("TOPLEFT", -30, 20); glow:SetPoint("BOTTOMRIGHT", 30, -20); glow:SetAlpha(0.35)
    toast.icon = toast:CreateTexture(nil, "OVERLAY"); toast.icon:SetSize(36, 36); toast.icon:SetPoint("LEFT", 14, 0)
    toast.title = UI.Font(toast, 13, UI.GOLD, "OVERLAY", "OUTLINE"); toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, -1); toast.title:SetPoint("RIGHT", -12, 0)
    toast.text = UI.Font(toast, 11, UI.TEXT); toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4); toast.text:SetPoint("RIGHT", -12, 0); toast.text:SetWordWrap(true)
    toast:EnableMouse(true); toast:SetScript("OnMouseUp", function(self) self:Hide() end)
    toast:Hide()
  end
  toast.icon:SetTexture(icon or (M .. "paw"))
  toast.title:SetText(title); toast.text:SetText(text or "")
  toast:SetAlpha(1); toast:Show()
  toast.hideAt = GetTime() + 8
  toast:SetScript("OnUpdate", function(self)
    local left = self.hideAt - GetTime()
    if left < 1 then self:SetAlpha(math.max(0, left)) end
    if left <= 0 then self:Hide(); self:SetScript("OnUpdate", nil) end
  end)
end

-- ---------- новое главное окно (2.43): текстуры media\win ----------
function UI.WinTex(t, name)
  if not t then return end
  t:SetTexture(M .. "win\\" .. name, nil, nil, "TRILINEAR")
  -- без привязки к пикселям: уменьшенные картинки рамок и значков - гладкие, без «лесенки»
  if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false); pcall(t.SetTexelSnappingBias, t, 0) end
  local tc = ns.WIN_TC and ns.WIN_TC[name]
  if tc then t:SetTexCoord(0, tc[1], 0, tc[2]) else t:SetTexCoord(0, 1, 0, 1) end
end

-- надпись сверху по центру экрана (как предупреждение рейда)
function UI.TopNotice(text, icon)
  local msg = (icon and ("|T" .. icon .. ":26:26|t ") or "") .. text
  if RaidNotice_AddMessage and RaidWarningFrame then
    local ok = pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 1, g = 0.82, b = 0.3 }, 6)
    if ok then return end
  end
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0.3) end
end

-- колокольчик сигнала у предмета: горит, если на предмет стоит сигнал; клик - окно своей цены
function ns.HasSignal(id)
  if not id then return false end
  local t = ns.DB.target and ns.DB.target[id]
  local d = ns.DB.alarmDir and ns.DB.alarmDir[id]
  return (t and (t.buy or t.sell)) and true or (d ~= nil)
end
function UI.Bell(parent, size, getId)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); UI.WinTex(hl, "bell-on"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.45)
  function b:Update(id) UI.WinTex(self.tex, ns.HasSignal(id or getId(self)) and "bell-on" or "bell-off") end
  b:SetScript("OnClick", function(self) local id = getId(self); if id then ns.OpenSignalDialog(id) end end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(L"Сигнал по цене", 1, 0.82, 0)
    GameTooltip:AddLine(L"Своя цена покупки или продажи: уведомление придёт, когда цена на аукционе до неё дойдёт.", 1, 1, 1, true); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.WinTex(b.tex, "bell-off")
  return b
end

-- окно сигнала: купить, если не дороже / продать, если не дешевле
local sigDlg
function ns.OpenSignalDialog(id)
  if not id then return end
  if not sigDlg then
    sigDlg = CreateFrame("Frame", "WolfichMarketSignalDialog", UIParent)
    sigDlg:SetSize(400, 178); sigDlg:SetPoint("CENTER"); sigDlg:SetFrameStrata("DIALOG"); sigDlg:EnableMouse(true); sigDlg:SetToplevel(true)
    sigDlg:SetMovable(true); sigDlg:RegisterForDrag("LeftButton"); sigDlg:SetClampedToScreen(true)
    sigDlg:SetScript("OnDragStart", sigDlg.StartMoving); sigDlg:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "WolfichMarketSignalDialog")
    UI.Skin(sigDlg, { theme = "acard", scale = 0.3 })
    sigDlg.icon = sigDlg:CreateTexture(nil, "ARTWORK"); sigDlg.icon:SetSize(26, 26); sigDlg.icon:SetPoint("TOPLEFT", 18, -16)
    sigDlg.name = UI.Font(sigDlg, 13, UI.GOLD); sigDlg.name:SetPoint("TOPLEFT", sigDlg.icon, "TOPRIGHT", 8, -1); sigDlg.name:SetPoint("RIGHT", -18, 0)
    sigDlg.now = UI.Font(sigDlg, 10, UI.DIM); sigDlg.now:SetPoint("TOPLEFT", sigDlg.name, "BOTTOMLEFT", 0, -2)
    local l1 = UI.Font(sigDlg, 11); l1:SetPoint("TOPLEFT", 20, -58); l1:SetText(L"Купить, если цена не выше:")
    sigDlg.buy = UI.MoneyInput(sigDlg, nil, true); sigDlg.buy:SetPoint("TOPRIGHT", -18, -54)
    local l2 = UI.Font(sigDlg, 11); l2:SetPoint("TOPLEFT", 20, -86); l2:SetText(L"Продать, если цена не ниже:")
    sigDlg.sell = UI.MoneyInput(sigDlg, nil, true); sigDlg.sell:SetPoint("TOPRIGHT", -18, -82)
    sigDlg.save = UI.Button(sigDlg, L"Сохранить", 110, 24, function()
      ns.SetSignal(sigDlg.id, sigDlg.buy:Get(), sigDlg.sell:Get()); sigDlg:Hide()
    end, true)
    sigDlg.save:SetPoint("BOTTOMRIGHT", -18, 16)
    sigDlg.del = UI.Button(sigDlg, L"Убрать сигнал", 120, 24, function() ns.SetSignal(sigDlg.id, 0, 0); sigDlg:Hide() end)
    sigDlg.del:SetPoint("RIGHT", sigDlg.save, "LEFT", -6, 0)
    local cancel = UI.Button(sigDlg, L"Отмена", 80, 24, function() sigDlg:Hide() end); cancel:SetPoint("BOTTOMLEFT", 18, 16)
  end
  sigDlg.id = id
  sigDlg.icon:SetTexture(ns.itemIcon(id)); sigDlg.name:SetText(ns.itemLinkText(id))
  local p = ns.AHPrice(id)
  sigDlg.now:SetText(L"сейчас на аукционе" .. ": " .. (p and ns.money(p, true) or L"нет цены"))
  local t = ns.DB.target and ns.DB.target[id] or {}
  if t.buy then sigDlg.buy:Set(t.buy) else sigDlg.buy:Clear() end
  if t.sell then sigDlg.sell:Set(t.sell) else sigDlg.sell:Clear() end
  sigDlg:Show()
end
-- записать сигнал: свои цены покупки и продажи (0 - нет); попадает в списки «Сигналы»
function ns.SetSignal(id, buy, sell)
  if not id then return end
  ns.DB.target = ns.DB.target or {}; ns.DB.alarmDir = ns.DB.alarmDir or {}; ns.DB.targetHit = ns.DB.targetHit or {}
  local t = {}
  if buy and buy > 0 then t.buy = buy end
  if sell and sell > 0 then t.sell = sell end
  ns.DB.target[id] = next(t) and t or nil
  ns.DB.alarmDir[id] = (t.buy and t.sell) and "both" or (t.buy and "buy") or (t.sell and "sell") or nil
  ns.DB.targetHit[id .. "buy"], ns.DB.targetHit[id .. "sell"] = nil, nil
  ns.Fire("MARKS")
end

-- раскрытая строка предмета: слева себестоимость и прибыль (или цены), справа - график цены и продаж
function UI.ItemDetail(det, opts)
  opts = opts or {}
  local left = CreateFrame("Frame", nil, det); left:SetPoint("TOPLEFT", 16, -8); left:SetPoint("BOTTOMLEFT", 16, 8); left:SetWidth(opts.leftW or 170)
  det.lbl, det.val = {}, {}
  for i = 1, 3 do
    local l = UI.Font(left, 10, UI.DIM); l:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
    local v = UI.Font(left, 13, UI.TEXT, "OVERLAY", "OUTLINE"); v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2)
    det.lbl[i], det.val[i] = l, v
  end
  det.btn = UI.Button(left, "", 120, 22); det.btn:SetPoint("BOTTOMLEFT", 0, 0)
  det.chart = UI.Chart(det); det.chart.noLegend = true; det.chart.compact = opts.compact
  det.chart:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 4); det.chart:SetPoint("BOTTOMRIGHT", -6, 0)
  det.legend = UI.Font(det, 9, UI.DIM); det.legend:SetPoint("TOPRIGHT", -46, -3)
  det.legend:SetText("|cfff2c761— " .. L"цена" .. "|r   |cff66d9cc— " .. L"продано, шт" .. "|r")
  function det:Set(id)
    self.id = id
    local unit, rec, _, ck, prof = ns.CraftCost(id)
    local function pf(v) return v and ((v >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(v, true) .. "|r") or "|cff777777-|r" end
    if rec then
      self.lbl[1]:SetText(L"Себестоимость крафта"); self.val[1]:SetText(ns.money(unit, true))
      self.lbl[2]:SetText(L"Прибыль на Ф"); self.val[2]:SetText(pf(ns.ProfitIn(rec, "main")))
      self.lbl[3]:SetText(L"Прибыль на Общ"); self.val[3]:SetText(pf(ns.ProfitIn(rec, "neutral")))
      self.btn:SetLabel(L"В план"); self.btn:Show()
      self.btn:SetScript("OnClick", function() ns.AddPlan(rec, ck or ns.charKey, prof, 1) end)
    else
      self.lbl[1]:SetText(L"Себестоимость крафта"); self.val[1]:SetText(L"|cff888888не крафтится|r")
      local v = ns.DB.vendor[id]
      self.lbl[2]:SetText(L"Цена на Ф"); self.val[2]:SetText(ns.money(ns.PriceIn("main", id), true))
      self.lbl[3]:SetText(L"Цена на Общ" .. (v and ("  |cffaaaaaa" .. L"торговец" .. " " .. ns.money(v, true) .. "|r") or "")); self.val[3]:SetText(ns.money(ns.PriceIn("neutral", id), true))
      self.btn:SetLabel(L"Найти на аукционе"); self.btn:Show()
      self.btn:SetScript("OnClick", function() ns.SearchAH(id) end)
    end
    local h = ns.History(id)
    ns.After(0, function() if self.id == id then self.chart:SetPoints(h) end end)
  end
  return det
end

-- рамка нового главного окна: колонка разделов, шапка, рамка с тканью; возвращает область содержимого
-- окно как на макете: 1260 x 780; K - масштаб колонки и шапки относительно первой сборки (1080 x 700)
local K = 780 / 700
local WIN_W, WIN_H = 1260, 780
UI.WIN_SIZE = { WIN_W, WIN_H }
local NAV = { { 146, 66 }, { 212, 69 }, { 281, 71 }, { 352, 69 }, { 421, 71 }, { 492, 72 } }
function UI.MainChrome(win, onNav, navTips)
  win:SetSize(WIN_W, WIN_H)
  local s = 0.74 * K
  local function k(v) return math.floor(v * K + 0.5) end
  -- мягкая чёрная тень только в щелях: между шапкой и рамкой и между колонкой и рамкой (края спрятаны под картинками)
  local gapTop = win:CreateTexture(nil, "BACKGROUND", nil, -8); UI.WinTex(gapTop, "shade")
  gapTop:SetPoint("TOPLEFT", k(120), -k(28)); gapTop:SetPoint("BOTTOMRIGHT", win, "TOPLEFT", WIN_W - k(70), -k(128))
  local gapLeft = win:CreateTexture(nil, "BACKGROUND", nil, -8); UI.WinTex(gapLeft, "shade")
  gapLeft:SetPoint("TOPLEFT", k(132), -k(60)); gapLeft:SetPoint("BOTTOMRIGHT", win, "TOPLEFT", k(214), -k(640))
  local fr = CreateFrame("Frame", nil, win); fr:SetPoint("TOPLEFT", k(168), -k(90)); fr:SetPoint("BOTTOMRIGHT", 0, 2)
  win.frameBox = fr
  UI.FrameSkin(fr, s)
  local function tex(parent, name, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BORDER", nil, sub or 0); UI.WinTex(t, name); return t
  end
  -- шапка и колонка - поверх рамки; правый конец шапки - до украшения рамки
  local top = CreateFrame("Frame", nil, win); top:SetAllPoints(); top:SetFrameLevel((fr:GetFrameLevel() or 1) + 5)
  local bar = tex(top, "bar", "ARTWORK"); bar:SetPoint("TOPLEFT", k(150), -2); bar:SetSize(WIN_W - k(150) - k(113), k(102))
  local side = tex(top, "side", "ARTWORK", 2); side:SetPoint("TOPLEFT", 0, 0); side:SetSize(k(175), k(692))
  local title = top:CreateFontString(nil, "OVERLAY"); setFont(title, UI.TITLE_FONT, 26, "OUTLINE")
  title:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]); title:SetPoint("LEFT", top, "TOPLEFT", k(380), -k(52)); title:SetText("WolfichMarket")
  local sub = UI.Font(top, 13, UI.DIM); sub:SetPoint("LEFT", title, "RIGHT", 14, -1)
  win.chromeTitle, win.chromeSub = title, sub
  -- крестик нарисован в правом верхнем углу рамки
  local close = CreateFrame("Button", nil, top); close:SetSize(k(38), k(38)); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -k(13), -k(98))
  local chl = close:CreateTexture(nil, "HIGHLIGHT"); chl:SetAllPoints(); chl:SetColorTexture(1, 0.85, 0.4, 0.2)
  close:SetScript("OnClick", function() win:Hide() end)
  win.closeBtn = close
  -- кнопки разделов: свечение строго внутри клетки
  local nav = {}
  for i, p in ipairs(NAV) do
    local b = CreateFrame("Button", nil, top); b:SetPoint("TOPLEFT", k(36), -k(p[1])); b:SetSize(k(92), k(p[2]))
    b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetAllPoints(); UI.WinTex(b.glow, "slot-glow"); b.glow:SetBlendMode("ADD"); b.glow:SetVertexColor(1, 0.8, 0.35); b.glow:SetAlpha(0)
    b.pulse = b:CreateTexture(nil, "OVERLAY", nil, 1); b.pulse:SetAllPoints(); UI.WinTex(b.pulse, "slot-glow"); b.pulse:SetBlendMode("ADD"); b.pulse:SetVertexColor(0.45, 0.78, 1); b.pulse:Hide()
    b:SetScript("OnEnter", function(self)
      if not self.on then self.glow:SetAlpha(0.45) end
      if navTips and navTips[i] then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(navTips[i], 1, 0.82, 0); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self) if not self.on then self.glow:SetAlpha(0) end; GameTooltip:Hide() end)
    b:SetScript("OnClick", function() onNav(i) end)
    function b:SetOn(on) self.on = on; self.glow:SetAlpha(on and 0.95 or 0) end
    -- пульсирующее голубое свечение (готов кулдаун)
    function b:SetPulse(on)
      self.pulse:SetShown(on)
      self:SetScript("OnUpdate", on and function(me) me.pulse:SetAlpha(0.35 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 3.5))) end or nil)
    end
    nav[i] = b
  end
  win.nav = nav
  -- перетаскивание за шапку и колонку
  top:EnableMouse(true); top:RegisterForDrag("LeftButton")
  top:SetScript("OnDragStart", function() win:StartMoving() end)
  top:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  top:SetHitRectInsets(0, 0, 0, 0)
  local content = CreateFrame("Frame", nil, win); content:SetPoint("TOPLEFT", k(218), -k(146)); content:SetPoint("BOTTOMRIGHT", -k(50), k(64))
  content:SetFrameLevel((top:GetFrameLevel() or 1) + 1)
  return content
end
