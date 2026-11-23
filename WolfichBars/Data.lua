local ADDON, ns = ...
ns.templates = {
  WARLOCK = {
    FARM = {
      {172, "Corruption"}, {980, "Bane of Agony"}, {689, "Drain Life"}, {686, "Shadow Bolt"},
      {5782, "Fear"}, {1454, "Life Tap"}, {348, "Immolate"}, {1120, "Drain Soul"},
      {18265, "Siphon Life"}, {6789, "Death Coil"}, {702, "Curse of Weakness"}, {693, "Create Soulstone"},
      {1098, "Subjugate Demon"}, {6201, "Create Healthstone"}, {698, "Ritual of Summoning"}, {6229, "Shadow Ward"},
    },
    PVP = {
      {172, "Corruption"}, {980, "Bane of Agony"}, {686, "Shadow Bolt"}, {689, "Drain Life"},
      {5782, "Fear"}, {6789, "Death Coil"}, {1454, "Life Tap"}, {18265, "Siphon Life"},
      {702, "Curse of Weakness"}, {1714, "Curse of Tongues"}, {5484, "Howl of Terror"}, {710, "Banish"},
      {6229, "Shadow Ward"}, {6201, "Create Healthstone"}, {348, "Immolate"}, {1120, "Drain Soul"},
    },
  },
}
ns.keys = {"1","2","3","4","Q","E","R","F","SHIFT-1","SHIFT-2","SHIFT-3","SHIFT-4","SHIFT-Q","SHIFT-E","SHIFT-R","SHIFT-F"}
ns.keyLabels = {"1","2","3","4","Q","E","R","F","S1","S2","S3","S4","SQ","SE","SR","SF"}
ns.ru = {
  [172]="Порча", [980]="Бич агонии", [689]="Похищение жизни", [686]="Стрела Тьмы", [5782]="Страх",
  [1454]="Жизнеотвод", [348]="Жертвенный огонь", [1120]="Похищение души", [18265]="Вытягивание жизни",
  [6789]="Лик смерти", [702]="Проклятие слабости", [693]="Создание камня души", [1098]="Подчинение демона",
  [6201]="Создание камня здоровья", [698]="Ритуал призыва", [6229]="Защита от темной магии",
  [1714]="Проклятие косноязычия", [5484]="Вой ужаса", [710]="Изгнание",
}
ns.aliases = {
  [980]={"Curse of Agony","Bane of Agony","Проклятие агонии","Бич агонии"},
  [1098]={"Enslave Demon","Subjugate Demon","Подчинение демона"},
  [693]={"Create Soulstone","Создание камня души"},
  [6201]={"Create Healthstone","Создание камня здоровья"},
  [6229]={"Shadow Ward","Защита от темной магии","Защита от Тьмы"},
  [172]={"Corruption","Порча"},
}

-- Variant names on Forever; the spellbook is the source of truth for casting.
-- WoW Forever Affliction: initial learn levels, not rank-up levels.
-- Based on Wowhead Forever Warlock leveling (2026-11) and cross-check with
-- talentsforever.com/warlock/abilities. Talent entries must be learned.
ns.abilityDB = {
  [686]={level=1,en="Shadow Bolt",ru="Стрела Тьмы"},
  [348]={level=1,en="Immolate",ru="Жертвенный огонь"},
  [687]={level=1,en="Demon Skin",ru="Шкура демона"},
  [688]={level=1,en="Summon Imp",ru="Призыв беса"},
  [172]={level=4,en="Corruption",ru="Порча"},
  [702]={level=4,en="Curse of Weakness",ru="Проклятие слабости"},
  [1454]={level=6,en="Life Tap",ru="Жизнеотвод"},
  [980]={level=8,en="Bane of Agony",ru="Бич агонии"},
  [5782]={level=8,en="Fear",ru="Страх"},
  [1120]={level=10,en="Drain Soul",ru="Похищение души"},
  [6201]={level=10,en="Create Healthstone",ru="Создание камня здоровья"},
  [697]={level=10,en="Summon Voidwalker",ru="Призыв демона Бездны",quest=true},
  [755]={level=12,en="Health Funnel",ru="Канал здоровья"},
  [689]={level=14,en="Drain Life",ru="Похищение жизни"},
  [693]={level=18,en="Create Soulstone",ru="Создание камня души"},
  [706]={level=20,en="Demon Armor",ru="Демонический доспех"},
  [5740]={level=20,en="Rain of Fire",ru="Огненный ливень"},
  [698]={level=20,en="Ritual of Summoning",ru="Ритуал призывания"},
  [712]={level=20,en="Summon Succubus",ru="Призыв суккуба",quest=true},
  [1714]={level=26,en="Curse of Tongues",ru="Проклятие косноязычия"},
  [710]={level=28,en="Banish",ru="Изгнание"},
  [1949]={level=30,en="Hellfire",ru="Адское Пламя"},
  [691]={level=30,en="Summon Felhunter",ru="Призыв охотника Скверны",quest=true},
  [18265]={level=30,en="Siphon Life",ru="Вытягивание жизни",talent=true},
  [6229]={level=32,en="Shadow Ward",ru="Защита от темной магии"},
  [2362]={level=36,en="Create Spellstone",ru="Создание камня чар"},
  [5484]={level=40,en="Howl of Terror",ru="Вой ужаса"},
  [1316697]={level=40,en="Wrack",ru="Судороги",talent=true},
  [6789]={level=42,en="Death Coil",ru="Лик смерти"},
}
-- Each position stays stable; replacement occurs automatically as abilities
-- become available. First candidate is most desirable, subsequent are fallback.
-- Leveling: quick-access combat spells first, summons and utility on Shift.
-- Slot 1 becomes a secure /castsequence macro after both DoTs are trained.
ns.farmPlan = {
  {172,686},            -- 1  DoT macro (Corruption -> Bane), or Corruption
  {686},                -- 2  Shadow Bolt filler
  {689,686},            -- 3  Drain Life / Shadow Bolt
  {980,348},            -- 4  Bane manual refresh / Immolate
  {5782,702},           -- Q  Fear
  {1454},               -- E  Life Tap
  {348},                -- R  Immolate
  {1120,686},           -- F  Drain Soul
  {18265,702},          -- S1 Siphon Life / Weakness
  {6201,687},           -- S2 Create Healthstone / Demon Skin
  {706,687},            -- S3 Demon Armor / Demon Skin
  {755,688},            -- S4 Health Funnel / Imp
  {6229,702},           -- SQ Shadow Ward / Weakness
  {693,687},            -- SE Soulstone / Demon Skin
  {5740,348},           -- SR Rain of Fire / Immolate
  {697,688},            -- SF Voidwalker / Imp
}
ns.farmSource = "https://www.wowhead.com/forever/ru/guide/classes/warlock/affliction/dps-leveling-tips"