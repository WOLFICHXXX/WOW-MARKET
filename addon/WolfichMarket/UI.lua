-- WolfichMarket: оформление и виджеты (свои текстуры: тёмное дерево, бронза, золото)
local _, ns = ...
local L = ns.L
local M = ns.MEDIA
local UI = {}
ns.UI = UI

UI.GOLD = { 0.95, 0.80, 0.42 }
UI.TEXT = { 0.93, 0.89, 0.80 }
UI.DIM = { 0.66, 0.62, 0.53 }

-- рамка: фон-дерево + бронзовые кромки + уголки с заклёпками
function UI.Skin(f, opts)
  opts = opts or {}
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

function UI.Font(parent, size, color, layer, flags)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
  local c = color or UI.TEXT
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

function UI.Title(parent, text)
  local h = parent:CreateTexture(nil, "ARTWORK")
  h:SetTexture(M .. "header")
  h:SetPoint("TOPLEFT", 10, -9); h:SetPoint("TOPRIGHT", -10, -9); h:SetHeight(30)
  local logo = parent:CreateTexture(nil, "OVERLAY")
  logo:SetTexture(M .. "paw"); logo:SetSize(20, 20); logo:SetPoint("LEFT", h, "LEFT", 8, 0)
  local fs = UI.Font(parent, 14, UI.GOLD, "OVERLAY", "OUTLINE")
  fs:SetPoint("LEFT", logo, "RIGHT", 6, 0); fs:SetText(text)
  return fs, h
end

function UI.Button(parent, text, w, h, onClick, gold)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 100, h or 22)
  b:SetNormalTexture(M .. (gold and "btn-gold" or "btn"))
  b:SetHighlightTexture(M .. "btn-hover")
  b:SetPushedTexture(M .. "btn-down")
  b:SetDisabledTexture(M .. "btn-off")
  local fs = UI.Font(b, 11, gold and { 0.15, 0.09, 0.02 } or UI.TEXT, "OVERLAY")
  fs:SetPoint("CENTER"); fs:SetJustifyH("CENTER"); fs:SetText(text or "")
  b.label = fs
  function b:SetLabel(t) fs:SetText(t) end
  b:SetScript("OnDisable", function() fs:SetTextColor(0.5, 0.5, 0.5) end)
  b:SetScript("OnEnable", function() local c = gold and { 0.15, 0.09, 0.02 } or UI.TEXT; fs:SetTextColor(c[1], c[2], c[3]) end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Icon(parent, tex, size, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetTexture(M .. tex); b.tex = t
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(M .. tex); hl:SetBlendMode("ADD"); hl:SetAlpha(0.5)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  if onClick then b:SetScript("OnClick", onClick) end
  function b:SetIcon(name) t:SetTexture(M .. name); hl:SetTexture(M .. name) end
  return b
end

function UI.Check(parent, text, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(22, 22)
  local fs = UI.Font(c, 11, UI.TEXT); fs:SetPoint("LEFT", c, "RIGHT", 2, 0); fs:SetText(text)
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
    for k, b in ipairs(tabs) do
      b:SetNormalTexture(M .. (k == i and "btn-gold" or "btn"))
      local c = k == i and { 0.15, 0.09, 0.02 } or UI.TEXT
      b.label:SetTextColor(c[1], c[2], c[3])
    end
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
  function box:Layout()
    local n = math.max(1, math.floor((self:GetHeight() or 100) / rowH))
    for i = #self.rows + 1, n do
      local r = CreateFrame("Button", nil, self)
      r:SetHeight(rowH)
      r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH); r:SetPoint("RIGHT", bar, "LEFT", -2, 0)
      local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(M .. "row-hl")
      if i % 2 == 0 then local z = r:CreateTexture(nil, "BACKGROUND"); z:SetAllPoints(); z:SetColorTexture(1, 1, 1, 0.025) end
      makeRow(r)
      self.rows[i] = r
    end
    self.visible = n
  end
  function box:Refresh()
    if not self.visible then self:Layout() end
    local max = math.max(0, #self.data - self.visible)
    if self.offset > max then self.offset = max end
    bar:SetMinMaxValues(0, max); bar:SetValue(self.offset)
    if max == 0 then bar:Hide() else bar:Show() end
    for i, r in ipairs(self.rows) do
      local d = self.data[i + self.offset]
      if d and i <= self.visible then r.data = d; fillRow(r, d); r:Show() else r.data = nil; r:Hide() end
    end
    if self.empty then if #self.data == 0 then self.empty:Show() else self.empty:Hide() end end
  end
  function box:SetData(d) self.data = d or {}; self:Refresh() end
  box:SetScript("OnMouseWheel", function(self, delta) self.offset = math.max(0, self.offset - delta * 3); self:Refresh() end)
  bar:SetScript("OnValueChanged", function(_, v) v = math.floor(v + 0.5); if v ~= box.offset then box.offset = v; box:Refresh() end end)
  box:SetScript("OnSizeChanged", function(self) self.visible = nil; self:Refresh() end)
  local empty = UI.Font(box, 12, UI.DIM); empty:SetPoint("CENTER"); empty:SetJustifyH("CENTER"); empty:SetWordWrap(true); empty:SetWidth(260)
  box.empty = empty
  return box
end

-- поле ввода денег: золото / серебро / медь
function UI.MoneyInput(parent, onChange)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(170, 22)
  local boxes = {}
  local labels = { L"|cffffd100з|r", L"|cffc7c7cfс|r", L"|cffeda55fм|r" }
  local x = 0
  for i = 1, 3 do
    local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    e:SetSize(i == 1 and 50 or 28, 20); e:SetPoint("LEFT", x + 6, 0); e:SetAutoFocus(false); e:SetNumeric(true); e:SetMaxLetters(i == 1 and 6 or 2)
    local l = UI.Font(f, 11); l:SetPoint("LEFT", e, "RIGHT", 2, 0); l:SetText(labels[i])
    e:SetScript("OnTextChanged", function(_, user) if user and onChange then onChange(f:Get()) end end)
    boxes[i] = e
    x = x + (i == 1 and 70 or 46)
  end
  function f:Get() return (tonumber(boxes[1]:GetText()) or 0) * 10000 + (tonumber(boxes[2]:GetText()) or 0) * 100 + (tonumber(boxes[3]:GetText()) or 0) end
  function f:Set(c) c = math.max(0, math.floor((c or 0) + 0.5)); boxes[1]:SetText(math.floor(c / 10000)); boxes[2]:SetText(math.floor(c % 10000 / 100)); boxes[3]:SetText(c % 100) end
  return f
end

-- линейный график: точки { {t, price, qty}, ... }
function UI.Chart(parent)
  local f = CreateFrame("Frame", nil, parent)
  local plot = CreateFrame("Frame", nil, f)
  plot:SetPoint("TOPLEFT", 54, -6); plot:SetPoint("BOTTOMRIGHT", -8, 20)
  local frameBg = plot:CreateTexture(nil, "BACKGROUND"); frameBg:SetAllPoints(); frameBg:SetColorTexture(0, 0, 0, 0.3)
  f.lines, f.bars, f.labels, f.grid = {}, {}, {}, {}
  local msg = UI.Font(f, 12, UI.DIM); msg:SetPoint("CENTER", plot); msg:SetJustifyH("CENTER")
  local function line(i)
    local l = f.lines[i]
    if not l then
      if plot.CreateLine then l = plot:CreateLine(nil, "ARTWORK"); l:SetThickness(2)
      else l = plot:CreateTexture(nil, "ARTWORK"); l:SetSize(2, 2) end
      l:SetColorTexture(0.95, 0.78, 0.38, 1)
      f.lines[i] = l
    end
    l:Show(); return l
  end
  local function lbl(i)
    local s = f.labels[i] or UI.Font(f, 9, UI.DIM); f.labels[i] = s; s:Show(); return s
  end
  function f:SetPoints(pts)
    for _, l in ipairs(self.lines) do l:Hide() end
    for _, b in ipairs(self.bars) do b:Hide() end
    for _, s in ipairs(self.labels) do s:Hide() end
    for _, g in ipairs(self.grid) do g:Hide() end
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
    -- сетка и подписи цен
    for i = 0, 3 do
      local v = lo + (hi - lo) * i / 3
      local g = self.grid[i + 1] or plot:CreateTexture(nil, "BORDER"); self.grid[i + 1] = g
      g:SetColorTexture(1, 1, 1, 0.07); g:SetHeight(1); g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v)); g:SetPoint("RIGHT", plot); g:Show()
      local s = lbl(i + 1); s:ClearAllPoints(); s:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, Y(v)); s:SetText(ns.money(v, true))
    end
    -- объёмы — столбики
    local bw = math.max(1, W / #pts * 0.6)
    for i, p in ipairs(pts) do
      local b = self.bars[i] or plot:CreateTexture(nil, "BORDER"); self.bars[i] = b
      b:SetColorTexture(0.6, 0.77, 0.92, 0.18)
      b:ClearAllPoints(); b:SetPoint("BOTTOM", plot, "BOTTOMLEFT", X(p[1]), 0); b:SetSize(bw, math.max(1, (p[3] or 0) / qmax * H * 0.35)); b:Show()
    end
    -- линия цены
    for i = 2, #pts do
      local l = line(i - 1)
      local x1, y1, x2, y2 = X(pts[i - 1][1]), Y(pts[i - 1][2]), X(pts[i][1]), Y(pts[i][2])
      if l.SetStartPoint then l:SetStartPoint("BOTTOMLEFT", plot, x1, y1); l:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
      else l:ClearAllPoints(); l:SetPoint("CENTER", plot, "BOTTOMLEFT", x2, y2) end
    end
    -- подписи времени
    for k, idx in ipairs({ 1, math.floor((#pts + 1) / 2), #pts }) do
      local s = lbl(4 + k); s:ClearAllPoints()
      s:SetPoint(k == 1 and "TOPLEFT" or k == 3 and "TOPRIGHT" or "TOP", plot, "BOTTOMLEFT", X(pts[idx][1]), -3)
      s:SetText(date("%d.%m %H:%M", pts[idx][1]))
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
