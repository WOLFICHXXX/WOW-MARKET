-- Сжимает addon/WolfichMarket/RecipeSources.lua до того, что нужно без «Где взять»:
-- навык рецепта (s), названия (n), результат (cr), материалы (rg), пометка «нет в игре» (na), список профессий.
-- Запуск: texlua tools/strip_sources.lua
local ns = {}
local f = assert(loadfile("addon/WolfichMarket/RecipeSources.lua"))
f("WolfichMarket", ns)
local S = ns.RS
local out = {}
local function w(s) out[#out + 1] = s end
local function q(s) return string.format("%q", s) end
w("-- Данные рецептов WoW Forever: навык, названия, результат и материалы (без «Где взять»).")
w("-- Сгенерировано tools/strip_sources.lua из данных tools/make_sources.py. Не править вручную.")
w("local _, ns = ...")
w("local S = { r = {}, names = {}, prof = {} }")
w("ns.RS = S")
local ids = {}
for id in pairs(S.r) do ids[#ids + 1] = id end
table.sort(ids)
w(";(function() local t = S.r")
for i, id in ipairs(ids) do
  local d = S.r[id]
  local parts = {}
  if d.s then parts[#parts + 1] = "s=" .. d.s end
  if d.na then parts[#parts + 1] = "na=true" end
  if d.n then parts[#parts + 1] = "n={" .. q(d.n[1] or "") .. "," .. q(d.n[2] or "") .. "}" end
  if d.cr then parts[#parts + 1] = "cr={" .. table.concat(d.cr, ",") .. "}" end
  if d.rg then
    local r = {}
    for _, x in ipairs(d.rg) do r[#r + 1] = "{" .. x[1] .. "," .. x[2] .. "}" end
    parts[#parts + 1] = "rg={" .. table.concat(r, ",") .. "}"
  end
  w("t[" .. id .. "]={" .. table.concat(parts, ",") .. "}")
  if i % 1500 == 0 then w("end)()"); w(";(function() local t = S.r") end
end
w("end)()")
local names = {}
for n in pairs(S.names) do names[#names + 1] = n end
table.sort(names)
w(";(function() local t = S.names")
for i, n in ipairs(names) do
  w("t[" .. q(n) .. "]=" .. S.names[n])
  if i % 1500 == 0 then w("end)()"); w(";(function() local t = S.names") end
end
w("end)()")
local slugs = {}
for k in pairs(S.prof) do slugs[#slugs + 1] = k end
table.sort(slugs)
for _, k in ipairs(slugs) do
  local p = S.prof[k]
  w("S.prof[" .. q(k) .. "]={ru=" .. q(p.ru or "") .. ",en=" .. q(p.en or "") .. ",line=" .. tostring(p.line or "nil") .. ",ids={" .. table.concat(p.ids, ",") .. "}}")
end
local fh = assert(io.open("addon/WolfichMarket/RecipeData.lua", "w"))
fh:write(table.concat(out, "\n") .. "\n"); fh:close()
print("рецептов", #ids, "названий", #names, "профессий", #slugs)
