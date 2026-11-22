-- WolfichMarket: оформление и виджеты (свои текстуры: тёмное дерево, бронза, золото)
local _, ns = ...
local L = ns.L
local M = ns.MEDIA
local UI = {}
ns.UI = UI

UI.GOLD = { 0.94, 0.76, 0.39 }
UI.TEXT = { 0.91, 0.92, 0.90 }
UI.DIM = { 0.66, 0.72, 0.75 }
-- цвета графиков и рамок (прежнее минималистичное оформление)
UI.PAL = {
  brass = { 0.95, 0.78, 0.38 }, brassLight = { 0.95, 0.80, 0.42 }, brassDark = { 0.42, 0.33, 0.17 },
  sea = { 0.40, 0.85, 0.80 }, up = { 0.47, 0.85, 0.54 }, down = { 1.0, 0.48, 0.40 },
}

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
  -- простая рамка (как у главного окна): ткань с лапками, тонкая золотая кромка, шапка 40 px
  flat = { title = { 16, -20 }, close = { -8, -7, 26, 26 }, btn = "mbtn" },
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
-- украшение фона: несколько едва заметных лапок (места - доли размера окна)
function UI.PawsBG(f)
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
end
-- рамка окна: уголки, кристаллы и лапа - без растяжения; s - масштаб частей
function UI.FrameSkin(f, s)
  s = s or 0.5
  f.wmTheme, f.wmScale = "win", s
  local W = ns.WIN
  local function tex(name, layer, sub) local t = f:CreateTexture(nil, layer or "BORDER", nil, sub or 0); UI.WinTex(t, name); return t end
  local function sz(k) local v = W[k] or { 100, 100 }; return v[1] * s, v[2] * s end
  local c = tex("f-c", "BACKGROUND", -8); c:SetPoint("TOPLEFT", 44 * s, -58 * s); c:SetPoint("BOTTOMRIGHT", -46 * s, 34 * s)
  UI.PawsBG(f)
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
  -- щиток с лапой ниже рамки - выступает вниз, верх совпадает с нижней кромкой
  local _, emh = sz("f-em"); q = tex("f-em", "BORDER", 2); q:SetSize(emw, emh); q:SetPoint("TOP", f, "BOTTOM", 0, bh)
  return f
end
-- 2026 authored TGA pack. Independent of the retired media/win look.
function UI.WolfTex(texture, name)
  if texture then
    texture:SetTexture(M .. "wolf2026\\" .. name)
    texture:SetTexCoord(0, 1, 0, 1)
  end
end
-- True nine-slice painted fantasy frame, sourced from approved-panel.tga.
-- Texture corners stay proportionate while the center stretches to its frame.
function UI.OrnatePanel(frame, alpha, cap)
  cap = cap or 14
  alpha = alpha or 0.93
  local pieces = {
    { "tl", 0, 0.15, 0, 0.16, "TOPLEFT" },
    { "tr", 0.85, 1, 0, 0.16, "TOPRIGHT" },
    { "bl", 0, 0.15, 0.84, 1, "BOTTOMLEFT" },
    { "br", 0.85, 1, 0.84, 1, "BOTTOMRIGHT" },
  }
  for _, p in ipairs(pieces) do
    local t = frame:CreateTexture(nil, "BORDER", nil, 2)
    UI.WolfTex(t, "approved-panel")
    t:SetTexCoord(p[2], p[3], p[4], p[5])
    t:SetSize(cap, cap)
    t:SetPoint(p[6], frame, p[6])
    t:SetAlpha(alpha)
  end
  -- Image-atlas strips contain black scenery; stretching them produced
  -- thick black bands in the header and on short recipe panels.
  -- Preserve painted corner motifs, but join them with fine bronze lines.
  local function rim(pointA, pointB, ax, ay, bx, by, horizontal)
    local t = frame:CreateTexture(nil, "BORDER", nil, 1)
    t:SetColorTexture(0.68, 0.51, 0.28, alpha * 0.78)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    t:SetPoint(pointA, frame, pointA, ax, ay)
    t:SetPoint(pointB, frame, pointB, bx, by)
  end
  rim("TOPLEFT", "TOPRIGHT", cap, -1, -cap, -1, true)
  rim("BOTTOMLEFT", "BOTTOMRIGHT", cap, 1, -cap, 1, true)
  rim("TOPLEFT", "BOTTOMLEFT", 1, -cap, 1, cap, false)
  rim("TOPRIGHT", "BOTTOMRIGHT", -1, -cap, -1, cap, false)
  local center = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
  UI.WolfTex(center, "approved-panel")
  -- Use only the unornamented navy center; lower panorama should not repeat
  -- across wide/short frames (particularly Settings and Chart dialogs).
  center:SetTexCoord(0.27, 0.73, 0.20, 0.48)
  center:SetPoint("TOPLEFT", frame, "TOPLEFT", cap, -cap)
  center:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -cap, cap)
  center:SetAlpha(alpha * 0.70)
end
-- панель внутри окна: тёмная подложка и тонкая золотая кромка
function UI.Box(f, alpha)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -6); bg:SetAllPoints(); bg:SetColorTexture(0.045, 0.065, 0.085, alpha or 0.62)
  UI.OrnatePanel(f, 0.86, 12)
  local function line(p1, p2, horiz)
    local t = f:CreateTexture(nil, "BORDER", nil, 3); t:SetColorTexture(0.31, 0.37, 0.40, 0.95)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
    t:SetPoint(p1); t:SetPoint(p2)
  end
  line("TOPLEFT", "TOPRIGHT", true); line("BOTTOMLEFT", "BOTTOMRIGHT", true); line("TOPLEFT", "BOTTOMLEFT"); line("TOPRIGHT", "BOTTOMRIGHT")
  -- Slim bronze bevel: no artwork dependency, no mouse interception.
  local highlight = f:CreateTexture(nil, "BORDER", nil, 2)
  highlight:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  highlight:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  highlight:SetHeight(1)
  highlight:SetColorTexture(0.70, 0.53, 0.28, 0.65)
  local foot = f:CreateTexture(nil, "BORDER", nil, 2)
  foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
  foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  foot:SetHeight(1)
  foot:SetColorTexture(0.15, 0.21, 0.24, 0.92)
  f.wmBox = true
  return f
end

-- рамка из 9 частей: UI.Skin(f, { theme = "main" | "ah" | "mcard" | "acard", scale = ... })
-- с 2.43 окна и панели - в оформлении нового макета: окна - рамка из частей, карточки и меню - простая панель
function UI.Skin(f, opts)
  opts = opts or {}
  if winReady() and not opts.old then
    if opts.theme == "main" or opts.theme == "ah" then return UI.FlatSkin(f, opts) end
    return UI.Box(f, opts.alpha or (opts.theme and 0.42 or 0.9))
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
  if parent.wmTheme == "flat" then
    local logo = parent:CreateTexture(nil, "OVERLAY"); logo:SetSize(18, 18); logo:SetPoint("LEFT", parent, "TOPLEFT", 14, -20)
    UI.WolfTex(logo, "approved-nav-paw"); logo:SetVertexColor(0.95, 0.78, 0.38)
    local fs = parent:CreateFontString(nil, "OVERLAY"); setFont(fs, UI.TITLE_FONT, 19, "")
    fs:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    fs:SetPoint("LEFT", logo, "RIGHT", 8, 0); fs:SetText(text)
    return fs, logo
  end
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
  if parent.wmTheme == "flat" then
    b = CreateFrame("Button", nil, parent); b:SetSize(26, 26); b:SetPoint("TOPRIGHT", -8, -7)
    local cx = UI.Font(b, 16, UI.DIM); cx:SetPoint("CENTER"); cx:SetText("×"); b.x = cx
    b:SetScript("OnEnter", function() cx:SetTextColor(1, 0.85, 0.4) end)
    b:SetScript("OnLeave", function() cx:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3]) end)
  elseif th and th.close then
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

-- кнопка (2.43.33): своя плоская - заливка и тонкая кромка, без картинок; b:SetGold(on) - золотая (главная / выбрана) или тёмная
local GOLD_TXT, DARK_TXT = { 1.00, 0.93, 0.74 }, { 0.94, 0.88, 0.77 }
local BTN = {
  dark = { bg = { 0.085, 0.115, 0.14, 0.96 }, edge = { 0.35, 0.43, 0.47, 1 } },
  gold = { bg = { 0.83, 0.63, 0.29, 1 }, edge = { 0.96, 0.81, 0.49, 1 } },
  off = { bg = { 0.055, 0.072, 0.084, 0.88 }, edge = { 0.22, 0.28, 0.30, 1 } },
}
UI.BTN_COLORS = BTN
function UI.Button(parent, text, w, h, onClick, gold)
  local b = CreateFrame("Button", nil, parent)
  w, h = w or 100, h or 22
  -- Use the requested size, without the former extra four pixels.
  b:SetSize(w, h)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
  -- Three-piece real painted button; the ornate caps never stretch.
  local skinLeft = b:CreateTexture(nil, "ARTWORK", nil, -2)
  skinLeft:SetWidth(14)
  skinLeft:SetPoint("TOPLEFT", b, "TOPLEFT")
  skinLeft:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
  local skinRight = b:CreateTexture(nil, "ARTWORK", nil, -2)
  skinRight:SetWidth(14)
  skinRight:SetPoint("TOPRIGHT", b, "TOPRIGHT")
  skinRight:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
  local skinMid = b:CreateTexture(nil, "ARTWORK", nil, -3)
  skinMid:SetPoint("TOPLEFT", skinLeft, "TOPRIGHT")
  skinMid:SetPoint("BOTTOMRIGHT", skinRight, "BOTTOMLEFT")
  local edges = UI.Edge(b, 0, 0, 0, 1, "BORDER")
  local bevelTop = b:CreateTexture(nil, "BORDER", nil, 2)
  bevelTop:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  bevelTop:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
  bevelTop:SetHeight(1)
  local bevelBottom = b:CreateTexture(nil, "BORDER", nil, 2)
  bevelBottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
  bevelBottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  bevelBottom:SetHeight(1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1); hl:SetColorTexture(1, 0.85, 0.45, 0.14)
  local fs = b:CreateFontString(nil, "OVERLAY")
  local FONT = UI.BOLD
  local base = math.max(10, math.min(12, math.floor(h * 0.42)))
  setFont(fs, FONT, base, "") -- шрифт до первого SetText, иначе игра выдаёт ошибку
  -- надпись строго по центру кнопки: по горизонтали и по вертикали
  fs:SetPoint("CENTER", 0, 0); fs:SetJustifyH("CENTER"); if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end; fs:SetWordWrap(false)
  b.label = fs
  local isGold
  local function sw() return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0 end
  -- надпись не выходит за кнопку; не влезает - шрифт меньше, до 9
  local function fit()
    local maxw = (b:GetWidth() or w) - 10
    local size = base
    setFont(fs, FONT, size, ""); fs:SetWidth(0)
    while sw() > maxw and size > 9 do size = size - 1; setFont(fs, FONT, size, "") end
    if sw() > maxw then fs:SetWidth(maxw) end
  end
  local function paint()
    local en = b:IsEnabled() ~= false
    local st = not en and BTN.off or (isGold and BTN.gold or BTN.dark)
    bg:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], st.bg[4])
    local variant = (not en and "dark") or (isGold and "gold" or "dark")
    for _, piece in ipairs({ skinLeft, skinMid, skinRight }) do
      UI.WolfTex(piece, "approved-button-" .. variant)
      piece:SetAlpha(en and 0.90 or 0.37)
      piece:SetVertexColor(0.90, 0.89, 0.85)
    end
    skinLeft:SetTexCoord(0,0.18,0,1)
    skinMid:SetTexCoord(0.18,0.82,0,1)
    skinRight:SetTexCoord(0.82,1,0,1)
    for _, t in ipairs(edges) do t:SetColorTexture(st.edge[1], st.edge[2], st.edge[3], st.edge[4]) end
    if en and isGold then
      bevelTop:SetColorTexture(0.90, 0.75, 0.48, 0.52)
      bevelBottom:SetColorTexture(0.31, 0.20, 0.06, 0.60)
    else
      bevelTop:SetColorTexture(0.58, 0.48, 0.30, en and 0.75 or 0.30)
      bevelBottom:SetColorTexture(0.015, 0.025, 0.035, 0.9)
    end
    local c = not en and { 0.6, 0.56, 0.48 } or (isGold and GOLD_TXT or DARK_TXT)
    fs:SetTextColor(c[1], c[2], c[3])
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.95) end
  end
  function b:SetGold(on) isGold = on and true or false; paint() end
  function b:IsGold() return isGold end
  function b:SetLabel(t) fs:SetText(t or ""); fit() end
  -- ширина по тексту (шрифт base не уменьшается): для кнопок со своей шириной
  function b:FitWidth(minW, maxW)
    setFont(fs, FONT, base, ""); fs:SetWidth(0)
    local tw = sw()
    self:SetWidth(math.max(minW or 0, math.min(maxW or 1000, math.floor(tw + 22))))
    fit()
    return self:GetWidth()
  end
  b:SetGold(gold); b:SetLabel(text)
  b:SetScript("OnDisable", paint)
  b:SetScript("OnEnable", paint)
  b:HookScript("OnMouseDown", function(self) if self:IsEnabled() ~= false then fs:SetPoint("CENTER", 1, -1) end end)
  b:HookScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
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
  local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0.025, 0.045, 0.060, 0.95)
  local th = bar:CreateTexture(nil, "OVERLAY"); th:SetColorTexture(0.85, 0.68, 0.37, 1); th:SetSize(8, 28)
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
      local hl = r:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(0.75, 0.56, 0.28, 0.16)
      if i % 2 == 0 then
        local z = r:CreateTexture(nil, "BACKGROUND")
        z:SetAllPoints()
        z:SetColorTexture(0.14, 0.20, 0.24, 0.28)
      end
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
    local bg = det:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.040, 0.075, 0.095, 0.98)
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
        if r.tri then r.tri:SetShown(not d.header); pcall(r.tri.tex.SetRotation, r.tri.tex, self:IsOpen(d) and -math.pi / 2 or 0) end
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
-- график цены (2.44): крупный и подробный.
-- Линия цены с заливкой под ней, столбики «продано» (на сколько уменьшилось выставленное количество между снимками),
-- сетка, шкалы цены (слева) и штук (справа), линии минимума / среднего / максимума, период (24 ч / 3 д / 7 д / 30 д / всё),
-- перекрестие с подсказкой под курсором. f.compact - маленький вид (без периода, сетки и перекрестия).
local PERIODS = { { 24, "24 ч" }, { 72, "3 д" }, { 168, "7 д" }, { 720, "30 д" }, { 0, "Всё" } }
local function moneyShort(v) return ns.money(v, true) end
function UI.Chart(parent)
  local P = UI.PAL
  local f = CreateFrame("Frame", nil, parent)
  local plot = CreateFrame("Frame", nil, f)
  f.plot = plot
  f.lines, f.bars, f.labels, f.grid, f.vgrid, f.slines, f.slabels, f.fill, f.refl, f.reflbl = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
  local bg = plot:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.32)
  UI.Edge(plot, P.brassDark[1], P.brassDark[2], P.brassDark[3], 0.8, "BORDER")
  -- легенда и строка цифр над графиком
  f.legend = UI.Font(f, 10, UI.DIM, "OVERLAY")
  f.legend:SetText("|cfff2c761— " .. L"цена" .. "|r   |cff66d9cc— " .. L"продано, шт" .. "|r")
  f.stats = UI.Font(f, 11, UI.TEXT, "OVERLAY"); f.stats:SetJustifyH("LEFT")
  local msg = UI.Font(f, 12, UI.DIM); msg:SetPoint("CENTER", plot); msg:SetJustifyH("CENTER")
  -- кнопки периода
  f.periodBtns = {}
  for i, pd in ipairs(PERIODS) do
    local b = UI.Button(f, L(pd[2]), 46, 16, function() ns.DB.settings.chartRange = pd[1]; f:SetPoints(f.allPts) end)
    f.periodBtns[i] = b; b.hours = pd[1]
  end
  local function layout()
    local compact = f.compact
    local small = compact or f.mid -- без строки цифр и кнопок периода
    -- Reserve space for period buttons above the plot frame.
    -- Mid-sized recipe charts have their own title above the plot. Reserve
    -- that text row instead of drawing price labels and bars under it.
    local top = compact and 6 or (f.mid and 31 or 61)
    plot:ClearAllPoints()
    plot:SetPoint("TOPLEFT", compact and 46 or 58, -top); plot:SetPoint("BOTTOMRIGHT", compact and -30 or -40, compact and 16 or 30)
    f.stats:ClearAllPoints(); f.stats:SetPoint("TOPLEFT", 4, -2); f.stats:SetPoint("RIGHT", -250, 0)
    f.legend:ClearAllPoints(); f.legend:SetPoint("BOTTOMLEFT", plot, "TOPLEFT", 0, 8)
    local x = 0
    for k = #f.periodBtns, 1, -1 do
      local b = f.periodBtns[k]
      b:ClearAllPoints(); b:SetPoint("BOTTOMRIGHT", plot, "TOPRIGHT", -x, 15); x = x + 50
      b:SetShown(not small)
    end
    f.stats:SetShown(not small)
    f.legend:SetShown(not small and not f.noLegend)
  end
  f.Layout = layout
  local function tex(pool, i, layer, sub)
    local t = pool[i]; if not t then t = plot:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0); pool[i] = t end
    t:Show(); return t
  end
  local function seg(pool, i, r, g, b, a, thick)
    local l = pool[i]
    if not l then
      if plot.CreateLine then l = plot:CreateLine(nil, "ARTWORK", nil, 3); l:SetThickness(thick or 2.5) else l = plot:CreateTexture(nil, "ARTWORK", nil, 3); l:SetSize(2, 2) end
      UI.LineTex(l, r, g, b, a); pool[i] = l
    end
    l:Show(); return l
  end
  local function setSeg(l, x1, y1, x2, y2)
    if l.SetStartPoint then l:SetStartPoint("BOTTOMLEFT", plot, x1, y1); l:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
    else l:ClearAllPoints(); l:SetPoint("CENTER", plot, "BOTTOMLEFT", x2, y2) end
  end
  local function lbl(pool, i, size, col)
    local s = pool[i]; if not s then s = UI.Font(f, size or 9, col or UI.DIM, "OVERLAY"); pool[i] = s end
    s:Show(); return s
  end
  -- перекрестие и подсказка под курсором
  local vline = plot:CreateTexture(nil, "OVERLAY"); vline:SetWidth(1); vline:SetColorTexture(1, 0.9, 0.6, 0.45); vline:Hide()
  local hline = plot:CreateTexture(nil, "OVERLAY"); hline:SetHeight(1); hline:SetColorTexture(1, 0.9, 0.6, 0.25); hline:Hide()
  local dot = plot:CreateTexture(nil, "OVERLAY", nil, 2); dot:SetSize(7, 7); dot:SetColorTexture(P.brassLight[1], P.brassLight[2], P.brassLight[3], 1); dot:Hide()
  f.hover = { vline = vline, hline = hline, dot = dot }
  local function hideHover() vline:Hide(); hline:Hide(); dot:Hide(); if GameTooltip and GameTooltip:IsOwned(f) then GameTooltip:Hide() end end
  plot:EnableMouse(true)
  plot:SetScript("OnLeave", hideHover)
  plot:SetScript("OnEnter", function()
    if f.compact and f.onClick then GameTooltip:SetOwner(f, "ANCHOR_CURSOR"); GameTooltip:AddLine(L"Клик - большой подробный график", 0.95, 0.78, 0.4); GameTooltip:Show() end
  end)
  plot:SetScript("OnMouseUp", function() if f.onClick then f.onClick() end end)
  plot:SetScript("OnUpdate", function()
    if f.compact or not f.view or not plot:IsMouseOver() then return end
    -- график закрыт другим окном (большой график, окно сигнала) - курсор не над ним
    local focus = (GetMouseFoci and (GetMouseFoci() or {})[1]) or (GetMouseFocus and GetMouseFocus())
    if focus and focus ~= plot then if vline:IsShown() then hideHover(); f.hoverIdx = nil end return end
    local cx = GetCursorPosition and (select(1, GetCursorPosition()) / (plot:GetEffectiveScale() or 1)) or nil
    local left = plot:GetLeft()
    if not cx or not left then return end
    local x = cx - left
    local best, bd
    for i, p in ipairs(f.view) do local d = math.abs(f.X(p[1]) - x); if not bd or d < bd then best, bd = i, d end end
    if not best then return end
    local p = f.view[best]
    local px, py = f.X(p[1]), f.Y(p[2])
    vline:ClearAllPoints(); vline:SetPoint("TOP", plot, "TOPLEFT", px, 0); vline:SetPoint("BOTTOM", plot, "BOTTOMLEFT", px, 0); vline:Show()
    hline:ClearAllPoints(); hline:SetPoint("LEFT", plot, "BOTTOMLEFT", 0, py); hline:SetPoint("RIGHT", plot, "BOTTOMRIGHT", 0, py); hline:Show()
    dot:ClearAllPoints(); dot:SetPoint("CENTER", plot, "BOTTOMLEFT", px, py); dot:Show()
    if f.hoverIdx ~= best then
      f.hoverIdx = best
      GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
      GameTooltip:AddLine(date("%d.%m.%Y  %H:%M", math.floor(p[1])), 1, 0.85, 0.5)
      GameTooltip:AddDoubleLine(L"цена", ns.money(p[2]), 0.85, 0.8, 0.7, 1, 1, 1)
      if f.sold and f.sold[best] and f.sold[best] > 0 then GameTooltip:AddDoubleLine(L"продано с прошлого снимка", f.sold[best] .. " " .. L"шт", 0.85, 0.8, 0.7, 0.3, 0.75, 0.7) end
      if p[3] then GameTooltip:AddDoubleLine(L"выставлено", p[3] .. " " .. L"шт", 0.85, 0.8, 0.7, 0.8, 0.8, 0.8) end
      if f.onClick then GameTooltip:AddLine(L"Клик - большой подробный график", 0.95, 0.78, 0.4) end
      GameTooltip:Show()
    end
  end)
  f:EnableMouse(true)
  f:SetScript("OnMouseUp", function(self) if self.onClick then self.onClick() end end)

  function f:SetPoints(all)
    self.allPts = all
    layout()
    for _, pool in ipairs({ self.lines, self.slines, self.slabels, self.bars, self.labels, self.grid, self.vgrid, self.fill, self.refl, self.reflbl, self.peakLbl or {}, self.dots or {} }) do
      for _, t in pairs(pool) do t:Hide() end -- pairs: в пуле столбиков бывают пропуски
    end
    hideHover(); self.hoverIdx = nil
    -- период: точки за последние N часов (в компактном виде - всё)
    local hours = (not self.compact and not self.mid) and (ns.DB and ns.DB.settings.chartRange) or 0
    if hours == nil then hours = 168 end
    for _, b in ipairs(self.periodBtns) do b:SetGold(b.hours == hours) end
    local pts = all or {}
    if hours and hours > 0 and #pts > 0 then
      local from = time() - hours * 3600
      local cut = {}
      for _, p in ipairs(pts) do if p[1] >= from then cut[#cut + 1] = p end end
      -- точка перед началом периода - чтобы линия начиналась от края
      if #cut < #pts and #cut > 0 then
        local prev; for _, p in ipairs(pts) do if p[1] < from then prev = p end end
        if prev then table.insert(cut, 1, { from, prev[2], prev[3] }) end
      end
      pts = cut
    end
    self.view = pts
    if #pts < 2 then
      msg:SetText(#(all or {}) >= 2 and L"За этот период точек нет - выберите период длиннее." or L"Мало данных для графика.\nКаждый снимок аукциона добавляет точку.")
      msg:Show(); self.stats:SetText("") return
    end
    msg:Hide()
    local W, H = plot:GetWidth(), plot:GetHeight()
    if W < 10 or H < 10 then return end
    local t0, t1, lo, hi, sum = pts[1][1], pts[#pts][1], math.huge, 0, 0
    for _, p in ipairs(pts) do lo = math.min(lo, p[2]); hi = math.max(hi, p[2]); sum = sum + p[2] end
    local minV, maxV, avgV = lo, hi, sum / #pts
    if hi == lo then hi = hi * 1.1 + 1; lo = lo * 0.9 end
    local pad = (hi - lo) * 0.12; hi = hi + pad; lo = math.max(0, lo - pad)
    -- цена занимает верхние 72%, внизу - полоса столбиков «продано»
    local VB = self.compact and 0.18 or 0.26
    local X = function(t) return (t - t0) / math.max(1, t1 - t0) * W end
    local Y = function(v) return H * VB + (v - lo) / (hi - lo) * H * (1 - VB) end
    self.X, self.Y = X, Y
    -- сетка цены и подписи слева
    local steps = self.compact and 2 or self.mid and 3 or 5
    for i = 0, steps do
      local v = lo + (hi - lo) * i / steps
      local g = tex(self.grid, i + 1, "BORDER")
      g:SetColorTexture(1, 0.9, 0.7, i == 0 and 0.14 or 0.06); g:SetHeight(1); g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v)); g:SetPoint("RIGHT", plot); g:Show()
      local s = lbl(self.labels, i + 1, self.compact and 9 or 10); s:ClearAllPoints(); s:SetPoint("RIGHT", plot, "BOTTOMLEFT", -5, Y(v)); s:SetText(moneyShort(v))
    end
    -- вертикальная сетка и подписи времени: 2-6 меток без наложения
    local nT = self.compact and 2 or math.max(2, math.min(6, math.floor(W / 150)))
    for k = 0, nT do
      local t = t0 + (t1 - t0) * k / nT
      local x = X(t)
      if not self.compact then
        local g = tex(self.vgrid, k + 1, "BORDER"); g:SetColorTexture(1, 0.9, 0.7, 0.05); g:SetWidth(1); g:ClearAllPoints()
        g:SetPoint("TOP", plot, "TOPLEFT", x, 0); g:SetPoint("BOTTOM", plot, "BOTTOMLEFT", x, 0)
      end
      local s = lbl(self.labels, steps + 2 + k, 9); s:ClearAllPoints()
      s:SetPoint(k == 0 and "TOPLEFT" or k == nT and "TOPRIGHT" or "TOP", plot, "BOTTOMLEFT", x, -7)
      s:SetText(date((t1 - t0) > 2 * 86400 and "%d.%m" or "%d.%m %H:%M", math.floor(t)))
    end
    -- продано между снимками: столбики внизу (морская волна)
    local sold, smax = { 0 }, 0
    for i = 2, #pts do
      local a, b = pts[i - 1][3], pts[i][3]
      local v = (a and b and a > b) and (a - b) or 0
      sold[i] = v; if v > smax then smax = v end
    end
    self.sold = sold
    if smax > 0 then
      local band = H * VB - 2
      local bw = math.max(2, math.min(14, W / #pts * 0.6))
      for i = 2, #pts do
        if sold[i] > 0 then
          local bar = tex(self.bars, i - 1, "ARTWORK", 1)
          bar:SetColorTexture(P.sea[1], P.sea[2], P.sea[3], 0.75)
          bar:ClearAllPoints(); bar:SetSize(bw, math.max(1, sold[i] / smax * band)); bar:SetPoint("BOTTOM", plot, "BOTTOMLEFT", X(pts[i][1]), 1)
        end
      end
      -- шкала штук справа
      for k, v in ipairs(self.compact and { smax } or { math.floor(smax / 2 + 0.5), smax }) do
        local s = lbl(self.slabels, k, 9); s:ClearAllPoints(); s:SetPoint("LEFT", plot, "BOTTOMRIGHT", 5, v / smax * band)
        s:SetText("|cff66d9cc" .. v .. "|r")
      end
    end
    -- заливка под линией цены: тонкие столбцы с прозрачностью (только в большом виде)
    if not self.compact then
      local colW = 3
      local n = math.floor(W / colW)
      local j = 1
      for c = 0, n - 1 do
        local x = c * colW + colW / 2
        local t = t0 + (t1 - t0) * x / W
        while j < #pts - 1 and pts[j + 1][1] < t do j = j + 1 end
        local a, b = pts[j], pts[math.min(j + 1, #pts)]
        local k = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 0
        local v = a[2] + (b[2] - a[2]) * math.max(0, math.min(1, k))
        local col = tex(self.fill, c + 1, "ARTWORK", -1)
        local hgt = Y(v) - H * VB
        col:SetColorTexture(P.brass[1], P.brass[2], P.brass[3], 0.16)
        col:ClearAllPoints(); col:SetSize(colW, math.max(1, hgt)); col:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c * colW, H * VB)
      end
    end
    -- линии минимума, среднего и максимума
    if not self.compact and not self.mid then
      local refs = { { minV, P.up, L"мин" }, { avgV, { 0.75, 0.68, 0.55 }, L"сред" }, { maxV, P.down, L"макс" } }
      for k, r in ipairs(refs) do
        local l = tex(self.refl, k, "ARTWORK", 0); l:SetColorTexture(r[2][1], r[2][2], r[2][3], 0.45); l:SetHeight(1)
        l:ClearAllPoints(); l:SetPoint("LEFT", plot, "BOTTOMLEFT", 0, Y(r[1])); l:SetPoint("RIGHT", plot, "BOTTOMRIGHT", 0, Y(r[1]))
        local s = lbl(self.reflbl, k, 9); s:ClearAllPoints(); s:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -4, Y(r[1]) + 1)
        s:SetText(string.format("|cff%02x%02x%02x%s %s|r", math.floor(r[2][1] * 255), math.floor(r[2][2] * 255), math.floor(r[2][3] * 255), r[3], moneyShort(r[1])))
      end
    end
    -- линия цены поверх всего
    for i = 2, #pts do
      local l = seg(self.lines, i - 1, P.brassLight[1], P.brassLight[2], P.brassLight[3], 1, self.compact and 2 or 2.6)
      setSeg(l, X(pts[i - 1][1]), Y(pts[i - 1][2]), X(pts[i][1]), Y(pts[i][2]))
    end
    -- последняя точка
    self.dots = self.dots or {}
    local last = pts[#pts]
    local d = self.dots[1] or plot:CreateTexture(nil, "OVERLAY"); self.dots[1] = d
    d:SetColorTexture(P.brassLight[1], P.brassLight[2], P.brassLight[3], 1); d:SetSize(self.compact and 5 or 7, self.compact and 5 or 7)
    d:ClearAllPoints(); d:SetPoint("CENTER", plot, "BOTTOMLEFT", X(last[1]), Y(last[2])); d:Show()
    -- цифры над графиком: сейчас, мин, макс, сред, изменение за период, продано за период
    if not self.compact and not self.mid then
      local first = pts[1][2]
      local chg = first > 0 and (last[2] - first) / first * 100 or 0
      local soldSum = 0; for _, v in ipairs(sold) do soldSum = soldSum + v end
      self.stats:SetText(L"сейчас" .. " |cffffffff" .. ns.money(last[2], true) .. "|r   " .. L"мин" .. " |cff78d98a" .. moneyShort(minV) .. "|r   "
        .. L"макс" .. " |cffff7a66" .. moneyShort(maxV) .. "|r   " .. L"сред" .. " " .. moneyShort(avgV) .. "   "
        .. (chg >= 0 and "|cff78d98a+" or "|cffff7a66") .. string.format("%.1f%%", chg) .. "|r   " .. L"продано" .. " |cff66d9cc" .. soldSum .. "|r")
    end
  end
  layout()
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
-- звезда «Избранное» у любого предмета: клик - добавить / убрать
function UI.Star(parent, size, getId)
  local b = UI.Icon(parent, "star-off", size or 14, L"Избранное", function(self) local id = getId(self); if id then ns.ToggleMark(id); self:Update(id) end end)
  function b:Update(id) id = id or getId(self); self:SetIcon(id and ns.IsMarked(id) and "star-on" or "star-off") end
  return b
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
    UI.Skin(sigDlg, { theme = "acard", scale = 0.3, alpha = 0.97 }) -- непрозрачное: под ним ничего не видно и не нажимается
    sigDlg.icon = sigDlg:CreateTexture(nil, "ARTWORK"); sigDlg.icon:SetSize(26, 26); sigDlg.icon:SetPoint("TOPLEFT", 18, -16)
    sigDlg.star = UI.Star(sigDlg, 16, function() return sigDlg.id end); sigDlg.star:SetPoint("TOPRIGHT", -16, -18)
    sigDlg.name = UI.Font(sigDlg, 13, UI.GOLD); sigDlg.name:SetPoint("TOPLEFT", sigDlg.icon, "TOPRIGHT", 8, -1); sigDlg.name:SetPoint("RIGHT", sigDlg.star, "LEFT", -6, 0)
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
  sigDlg.icon:SetTexture(ns.itemIcon(id)); sigDlg.name:SetText(ns.itemLinkText(id)); sigDlg.star:Update(id)
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
  -- сверху - строка легенды и чисел (продано за 24 ч, лоты) на всю ширину; ниже слева - цифры, справа - график
  det.legend = UI.Font(det, 10, UI.DIM); det.legend:SetPoint("TOPLEFT", 16, -5); det.legend:SetPoint("RIGHT", -10, 0)
  local lw = opts.leftW or 170
  local left = CreateFrame("Frame", nil, det); left:SetPoint("TOPLEFT", 16, -24); left:SetPoint("BOTTOMLEFT", 16, 8); left:SetWidth(lw)
  det.lbl, det.val = {}, {}
  for i = 1, 3 do
    local l = UI.Font(left, 10, UI.DIM); l:SetPoint("TOPLEFT", 0, -(i - 1) * 32); l:SetWidth(lw - 6)
    local v = UI.Font(left, 12, UI.TEXT); UI.SetFont(v, UI.BOLD, 12, ""); v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2); v:SetWidth(lw - 6)
    det.lbl[i], det.val[i] = l, v
  end
  det.btn = UI.Button(left, "", lw - 20, 18); det.btn:SetPoint("BOTTOMLEFT", 0, 0)
  det.compactLegend = opts.compact
  det.chart = UI.Chart(det); det.chart.noLegend = true; det.chart.compact = opts.compact; det.chart.mid = not opts.compact
  -- клик по графику - большое окно с подробным графиком этого предмета
  det.chart.onClick = function() if det.id and ns.ShowChartDialog then ns.ShowChartDialog(det.id) end end
  det.chart:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0); det.chart:SetPoint("BOTTOMRIGHT", -6, 0)
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
    -- над графиком: продано за 24 ч и сколько сейчас лотов
    local sold, lots, qty = ns.SoldIn(id, 24), ns.LotsNow(id)
    -- в узкой панели - без подписей линий (цвета линий и так видны), только числа
    self.legend:SetText((self.compactLegend and "" or ("|cfff2c761— " .. L"цена" .. "|r   |cff66d9cc— " .. L"продано, шт" .. "|r     ")) .. L"продано за 24 ч" .. ": |cffffffff" .. (sold or "-") .. "|r   " .. L"лотов" .. ": |cffffffff" .. (lots or "-") .. (qty and qty > 0 and (" |cffaaaaaa(" .. qty .. " " .. L"шт" .. ")|r") or "") .. "|r")
    local h = ns.History(id)
    ns.After(0, function() if self.id == id then self.chart:SetPoints(h) end end)
  end
  return det
end

-- ---------- компактное главное окно: узкая полоса значков слева, тонкая шапка, плоская рамка ----------
-- область содержимого - того же размера, что в большом окне (разделы не перестраиваются)
local CONTENT_W, CONTENT_H = 961, 546
local RAIL, PAD, HEAD = 164, 16, 42
UI.COMPACT_SIZE = { RAIL + PAD + CONTENT_W + PAD, HEAD + 10 + CONTENT_H + 14 }
-- свои простые значки разделов (белые линии, красятся цветом): media\\win\\nav-*.tga, исходник - tools\\icons
local NAV_ICONS = { "nav-home", "nav-prof", "nav-auc", "nav-set" }
local IC_DIM, IC_HOVER, IC_ON = { 0.62, 0.56, 0.44 }, { 0.92, 0.84, 0.66 }, { 0.95, 0.78, 0.38 }
local function edge(f, r, g, b, a, layer)
  local L = {}
  for i = 1, 4 do L[i] = f:CreateTexture(nil, layer or "BORDER"); L[i]:SetColorTexture(r, g, b, a) end
  L[1]:SetPoint("TOPLEFT"); L[1]:SetPoint("TOPRIGHT"); L[1]:SetHeight(1)
  L[2]:SetPoint("BOTTOMLEFT"); L[2]:SetPoint("BOTTOMRIGHT"); L[2]:SetHeight(1)
  L[3]:SetPoint("TOPLEFT"); L[3]:SetPoint("BOTTOMLEFT"); L[3]:SetWidth(1)
  L[4]:SetPoint("TOPRIGHT"); L[4]:SetPoint("BOTTOMRIGHT"); L[4]:SetWidth(1)
  return L
end
UI.Edge = edge
-- простая рамка окна (вместо рамки из картинок): ткань с лапками, тонкая золотая кромка, линия под шапкой
function UI.FlatSkin(f, opts)
  opts = opts or {}
  f.wmTheme, f.wmScale = "flat", 1
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8); bg:SetAllPoints(); bg:SetColorTexture(0.035, 0.055, 0.075, 1)
  -- Use the same newly painted navy/gold material as the main window.
  -- Do not add the outdated floating paw pattern behind charts.
  UI.OrnatePanel(f, 0.68, 12)
  edge(f, 0.47, 0.40, 0.25, 1)
  local head = opts.head or 40
  local hl = f:CreateTexture(nil, "BORDER"); hl:SetColorTexture(0.39, 0.33, 0.20, 1); hl:SetHeight(1)
  hl:SetPoint("TOPLEFT", 1, -head); hl:SetPoint("TOPRIGHT", -1, -head)
  return f
end
function UI.MainChromeCompact(win, onNav, navTips)
  local W, H = UI.COMPACT_SIZE[1], UI.COMPACT_SIZE[2]
  win:SetSize(W, H)
  local GOLD_EDGE = { 0.55, 0.41, 0.23, 1 }
  -- полоса значков
  local rail = CreateFrame("Frame", nil, win); rail:SetPoint("TOPLEFT"); rail:SetPoint("BOTTOMLEFT"); rail:SetWidth(RAIL)
  local rb = rail:CreateTexture(nil, "BACKGROUND", nil, -8); rb:SetAllPoints(); rb:SetColorTexture(0.025, 0.040, 0.055, 1)
  -- Original graphical side texture (384x1517): same aspect as our rail.
  local railArt = rail:CreateTexture(nil, "BACKGROUND", nil, -7)
  -- The tall painting has a large crown at its top. Crop it to the quiet
  -- navy center and reserve the top 75px for the readable brand/navigation.
  railArt:SetPoint("TOPLEFT", rail, "TOPLEFT", 4, -77)
  railArt:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -4, 6)
  UI.WolfTex(railArt, "approved-sidebar")
  railArt:SetTexCoord(0.14, 0.86, 0.24, 0.82)
  railArt:SetAlpha(0.84)
  edge(rail, unpack(GOLD_EDGE))
  local railAccent = rail:CreateTexture(nil, "BORDER", nil, 2)
  railAccent:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -2, -2)
  railAccent:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -2, 2)
  railAccent:SetWidth(2)
  railAccent:SetColorTexture(0.68, 0.50, 0.23, 0.78)
  -- основная часть
  local main = CreateFrame("Frame", nil, win); main:SetPoint("TOPLEFT", RAIL - 1, 0); main:SetPoint("BOTTOMRIGHT")
  -- фон - прежняя ткань с едва заметными лапками
  local mb = main:CreateTexture(nil, "BACKGROUND", nil, -8); mb:SetAllPoints(); mb:SetColorTexture(0.035, 0.055, 0.075, 1)
  local mainArt = main:CreateTexture(nil, "BACKGROUND", nil, -7)
  mainArt:SetAllPoints()
  UI.WolfTex(mainArt, "approved-panel")
  mainArt:SetTexCoord(0.27, 0.73, 0.20, 0.48)
  mainArt:SetAlpha(0.14)
  -- The dark inset keeps real item names and costs legible over art.
  edge(main, unpack(GOLD_EDGE))
  UI.OrnatePanel(main, 0.93, 16)
  -- Fine inner stroke gives the old-world bronze frame a second edge.
  local insetTop = main:CreateTexture(nil, "BORDER", nil, 2)
  insetTop:SetPoint("TOPLEFT", main, "TOPLEFT", 3, -3)
  insetTop:SetPoint("TOPRIGHT", main, "TOPRIGHT", -3, -3)
  insetTop:SetHeight(1)
  insetTop:SetColorTexture(0.78, 0.59, 0.30, 0.55)
  local insetBottom = main:CreateTexture(nil, "BORDER", nil, 2)
  insetBottom:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 3, 3)
  insetBottom:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -3, 3)
  insetBottom:SetHeight(1)
  insetBottom:SetColorTexture(0.33, 0.25, 0.15, 0.8)
  win.frameBox = main
  -- шапка: название раздела крупно, рядом «WolfichMarket vX» мелко; линия под шапкой
  local top = CreateFrame("Frame", nil, win); top:SetPoint("TOPLEFT", RAIL, 0); top:SetPoint("TOPRIGHT"); top:SetHeight(HEAD)
  top:SetFrameLevel((main:GetFrameLevel() or 1) + 2)
  local headerBg = top:CreateTexture(nil, "BACKGROUND", nil, -5)
  headerBg:SetAllPoints()
  headerBg:SetColorTexture(0.048, 0.070, 0.088, 1)
  local headerArt = top:CreateTexture(nil, "BACKGROUND", nil, -4)
  -- The illustration is a complete header with a large wolf/crown. Using
  -- all of it in a 42px toolbar draws golden strokes THROUGH the text.
  -- Use only its dark center as the toolbar texture; the title stays clear.
  headerArt:SetPoint("TOPLEFT", top, "TOPLEFT", 1, -2)
  headerArt:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -1, 2)
  -- A quiet texture behind the toolbar; keep the moon/wolf illustration
  -- out of the narrow text strip entirely.
  UI.WolfTex(headerArt, "approved-panel")
  headerArt:SetTexCoord(0.27, 0.73, 0.20, 0.48)
  headerArt:SetAlpha(0.46)
  local hl = top:CreateTexture(nil, "BORDER")
  hl:SetColorTexture(0.76, 0.55, 0.24, 1)
  hl:SetHeight(2); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT")
  local sub = top:CreateFontString(nil, "OVERLAY"); setFont(sub, UI.TITLE_FONT, 20, "")
  sub:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]); sub:SetPoint("LEFT", PAD, 0)
  local title = UI.Font(top, 12, UI.DIM); title:SetPoint("LEFT", sub, "RIGHT", 10, -1); title:SetText("·  WolfichMarket")
  win.chromeTitle, win.chromeSub = title, sub
  win.chromeVer = UI.Font(top, 11, UI.DIM); win.chromeVer:SetPoint("LEFT", title, "RIGHT", 6, 0)
  local close = CreateFrame("Button", nil, top); close:SetSize(26, 26); close:SetPoint("RIGHT", -8, 0)
  local cx = UI.Font(close, 16, UI.DIM); cx:SetPoint("CENTER"); cx:SetText("×")
  close:SetScript("OnEnter", function() cx:SetTextColor(1, 0.85, 0.4) end)
  close:SetScript("OnLeave", function() cx:SetTextColor(UI.DIM[1], UI.DIM[2], UI.DIM[3]) end)
  close:SetScript("OnClick", function() win:Hide() end)
  win.closeBtn = close
  -- значок-волк сверху полосы
  local logo = rail:CreateTexture(nil, "ARTWORK"); logo:SetSize(24, 24); logo:SetPoint("TOPLEFT", rail, "TOPLEFT", 9, -13); UI.WolfTex(logo, "approved-nav-paw"); logo:SetVertexColor(1, 1, 1)
  local brand = UI.Font(rail, 15, UI.GOLD)
  brand:SetPoint("TOP", rail, "TOP", 0, -19)
  brand:SetText("WOLFICH")
  local sep = rail:CreateTexture(nil, "BORDER"); sep:SetColorTexture(0.65, 0.49, 0.27, 0.9); sep:SetSize(RAIL - 24, 1); sep:SetPoint("TOP", 0, -60)
  -- The approved portrait appears below the navigation, without blocking it.
  local wolf = rail:CreateTexture(nil, "ARTWORK", nil, -1)
  -- The crest was undersized inside the 164px rail; use its full
  -- painted silhouette while retaining clear air above/below the emblem.
  wolf:SetSize(132, 132)
  wolf:SetPoint("BOTTOM", rail, "BOTTOM", 0, 22)
  UI.WolfTex(wolf, "approved-wolf-emblem")
  wolf:SetTexCoord(0, 1, 0, 1)
  wolf:SetAlpha(0.95)
  -- кнопки разделов: значок 44x44, выбранный - золотая обводка и свечение, подпись - при наведении
  local nav = {}
  for i, c in ipairs(NAV_ICONS) do
    local b = CreateFrame("Button", nil, rail); b:SetSize(RAIL - 16, 44); b:SetPoint("TOP", rail, "TOP", 0, -72 - (i - 1) * 52)
    b:SetFrameLevel((rail:GetFrameLevel() or 1) + 2)
    -- подложка выбранного раздела и золотая черта у левого края полосы
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.22, 0.36, 0.42, 0.65); b.bg:Hide()
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.83, 0.63, 0.31, 0.13)
    b.selTop = b:CreateTexture(nil, "BORDER", nil, 2)
    b.selTop:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.selTop:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    b.selTop:SetHeight(1)
    b.selTop:SetColorTexture(0.91, 0.72, 0.36, 0.75)
    b.selTop:Hide()
    b.selBottom = b:CreateTexture(nil, "BORDER", nil, 2)
    b.selBottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.selBottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.selBottom:SetHeight(1)
    b.selBottom:SetColorTexture(0.44, 0.34, 0.19, 0.80)
    b.selBottom:Hide()
    b.bar = b:CreateTexture(nil, "BORDER"); b.bar:SetColorTexture(0.94, 0.75, 0.37, 1); b.bar:SetSize(3, 34); b.bar:SetPoint("LEFT", b, "LEFT", -1, 0); b.bar:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(33, 33); b.icon:SetPoint("LEFT", b, "LEFT", 4, 0); UI.WolfTex(b.icon, "approved-" .. c)
    b.text = UI.Font(b, 12, UI.TEXT)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -5, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetText(navTips and navTips[i] or "")
    local function tint(t) b.icon:SetVertexColor(1, 1, 1); b.icon:SetAlpha(t == IC_DIM and 0.73 or 1) end
    tint(IC_DIM)
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1); b.glow:SetPoint("TOPLEFT", -4, 4); b.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    b.pulse = b:CreateTexture(nil, "OVERLAY", nil, 2); b.pulse:SetAllPoints(b.glow); UI.WinTex(b.pulse, "slot-glow"); b.pulse:SetBlendMode("ADD"); b.pulse:SetVertexColor(0.45, 0.78, 1); b.pulse:Hide()
    b:SetScript("OnEnter", function(self)
      if not self.on then tint(IC_HOVER) end
      if navTips and navTips[i] then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(navTips[i], 1, 0.82, 0); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self) if not self.on then tint(IC_DIM) end; GameTooltip:Hide() end)
    b:SetScript("OnClick", function() onNav(i) end)
    function b:SetOn(on)
      self.on = on; tint(on and IC_ON or IC_DIM); self.bg:SetShown(on and true or false); self.bar:SetShown(on and true or false)
      self.selTop:SetShown(on and true or false); self.selBottom:SetShown(on and true or false)
      self.text:SetTextColor(on and UI.GOLD[1] or UI.TEXT[1], on and UI.GOLD[2] or UI.TEXT[2], on and UI.GOLD[3] or UI.TEXT[3])
    end
    function b:SetPulse(on)
      self.pulse:SetShown(on)
      self:SetScript("OnUpdate", on and function(me) me.pulse:SetAlpha(0.35 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 3.5))) end or nil)
    end
    nav[i] = b
  end
  win.nav = nav
  -- перетаскивание за шапку и полосу
  for _, f in ipairs({ top, rail }) do
    f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() win:StartMoving() end)
    f:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  end
  local content = CreateFrame("Frame", nil, win); content:SetPoint("TOPLEFT", RAIL + PAD, -(HEAD + 10)); content:SetSize(CONTENT_W, CONTENT_H)
  content:SetFrameLevel((top:GetFrameLevel() or 1) + 1)
  return content
end

