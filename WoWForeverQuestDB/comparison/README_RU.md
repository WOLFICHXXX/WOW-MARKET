# Сопоставление QuestieDB из AddOns.zip и WOLFICH QuestDB v1.1

**Источник архива:** `QuestieDB/QuestieDB_Forever.toc`, Questie 12.12.0 / QuestieDB 1.1.4, `Interface 16001`. Из архива извлечены CBOR-данные заданий и NPC/Object spawns; координаты `-1/-1` и значения вне диапазона 0–100 отброшены. **Сведения не проверялись на живом сервере.**

**Источник v1.1:** `WoWForeverQuestDB/dist/quests.csv`, `locations.csv` (Questie/Trinity/Norgannon + ForeverDB).

| Показатель | Количество |
|---|---:|
| Заданий в QuestieDB-архиве | 6080 |
| Заданий в нашей v1.1 | 4753 |
| Общие ID | 4753 |
| Есть только в QuestieDB | **1327** |
| Есть только в v1.1 | 0 |
| Задания с координатами выдачи/сдачи в QuestieDB (x/y 0–100) | 5668 |
| Задания с координатами выдачи/сдачи в v1.1 | 3711 |
| **Доп. координаты для уже известных заданий** | **809** |
| Доп. координаты для новых ID | 1230 |
| Задания, где координаты есть только в v1.1 | 82 |
| Общее число ID с координатами после объединения кандидатов | 5750 |
| Отличающихся английских названий для общего ID | 20 |
| Новые записи с `<NYI>`/`<TXT>` | 14 |
| Русские названия в архиве | 5804 |

**Главное:** все ID из нашей v1.1 присутствуют в QuestieDB. Поэтому QuestieDB — расширение по охвату, **но не замена**: старая база содержит item-награды, ForeverDB-локации с меткой наблюдения и самостоятельную статистику источников; QuestieDB предоставляет координаты NPC/объектов, новые квесты и дополнительные условия.

## Что стоит переносить

1. Добавить 1327 новых ID в **отдельный слой `questie_candidate`**, пока не подтверждена доступность на сервере; записи NYI отсечь.
2. 809 общих заданий можно дополнить точками QuestieDB с качеством `questie_unverified` (ни в коем случае не `forever_observed`).
3. При расхождении названий сохранить оба варианта и происхождение, не затирать русские переводы и наблюдения ForeverDB.
4. Сохранить уже имеющиеся награды и 82 квестов с координатами только из ForeverDB.

### Примеры новых заданий
- 490 — Награда за фурболгов Кривой Сосны
- 960 — Размышление Ону
- 5640 — Молитва отчаяния
- 5669 — <NYI> A Blessing of Light
- 5670 — <NYI> A Blessing of Light
- 5671 — <NYI> A Blessing of Light
- 5678 — Arcane Feedback
- 5686 — <NYI> The Light Protects You
- 5687 — <NYI> The Light Protects You
- 5691 — <NYI> <TXT> In the Dark it was Created
- 5692 — <NYI> In the Dark It was Created
- 5693 — <NYI> In the Dark It was Created
- 5704 — <NYI> <TXT> Undead Priest Robe
- 5705 — <NYI> No Longer a Shadow
- 5706 — <NYI> No Longer a Shadow
- 5707 — <NYI> <TXT> Flirting With Darkness
- 5708 — <NYI> Flirting With Darkness
- 5709 — <NYI> Flirting With Darkness
- 7668 — Угроза Темного Губителя
- 7669 — Снова в Главный склеп
- 7670 — Лорд Грейсон Тенелом
- 7790 — У истока реки
- 8152 — Спешное бегство
- 60860 — Your Reward has Arrived!
- 60870 — A Special Gift
- 65593 — Сердца влюбленных
- 65597 — Связывание
- 65602 — Лучшие друзья
- 65603 — Связывание
- 65604 — Связывание

### Примеры конфликтов английских названий
- 117 — Thunderbrew / Thunderbrew Lager
- 176 — WANTED: "Hogger" / Wanted:  "Hogger"
- 684 — WANTED: Marez Cowl / Wanted!  Marez Cowl
- 685 — WANTED: Otto and Falconcrest / Wanted!  Otto and Falconcrest
- 1658 — Crashing the Wickerman Festival / Crashing the Wickerman Festival (PvP)
- 5047 — Pip Quickwit, At Your Service! / Finkle Einhorn, At Your Service!
- 5147 — WANTED: Arnak Grimtotem / Wanted - Arnak Grimtotem
- 5214 — The Great Ezra Grimm / The Great Fras Siabi
- 5226 — Return to Chillwind Camp / Return to Chillwind Point
- 5644 — Dark Sacrifice / Devouring Plague
- 5646 — Dark Sacrifice / Devouring Plague
- 5679 — Dark Sacrifice / Devouring Plague
- 5713 — One Shot.  One Kill. / One Shot. One Kill.
- 6984 — A Smokywood Pastures' Thank You! / A Smokywood Pastures Thank You!
- 7045 — A Smokywood Pastures' Thank You! / A Smokywood Pastures Thank You!
- 7507 — Nostro's Compendium / Foror's Compendium
- 8044 — The Rage of Mugamba / The Rage of Mount Mugamba
- 8148 — Maelstrom's Wrath / The Maelstrom's Wrath
- 92516 — Hippogryph Harassment / Hippogryph Harrassment
- 92597 — Reading the Leylines / Reading the Ley Lines

**Подробная построчная сверка всех 6080 ID:** [AddOns_QuestieDB_Forever_vs_v1.1.csv](AddOns_QuestieDB_Forever_vs_v1.1.csv). Файл UTF-8 с разделителем `;`, открывается Excel.

**Примечание о датах:** поле `X-BUILD-TIME` архива указывает `2023-11-14T22:13:20Z` при версиях Questie 12.12.0 и QuestieDB 1.1.4. Считаем временную метку недостаточным подтверждением актуальности источника.

**Условия лицензирования:** Questie / QuestieDB распространяются по GPLv3, при дальнейшем распространении производных материалов соблюдать лицензию и указать исходные источники.
