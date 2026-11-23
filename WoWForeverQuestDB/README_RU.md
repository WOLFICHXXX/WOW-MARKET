# Wolfich QuestDB · WoW Forever

База заданий для Альянса, Орды и общих квестов. Форматы: SQLite, CSV, HTML.

**Источники:**
- [QuestieDB / TrinityCore Forever / NorgannonDB](https://github.com/tyler3497/forever-quests) — версии данных 1.3.0, 4 630 квестов в основной выгрузке.
- [ForeverDB](https://foreverdb.net) — независимые данные 3 862 квестов с именами NPC и координатами, где имеются. **Data from ForeverDB.net**.
- [QuestieDB / ruRU Forever](https://github.com/Questie/QuestieDB/tree/master/l10n/Forever) — русские названия заданий, NPC, предметов, переводы целей (базовая локализация и наблюдения). Переводы привязаны к **ID**, не машинные. Там, где перевод отсутствует, остаётся английское имя.

**Ограничения данных:** это открытые датасеты, не подтверждённая полная база действующего игрового сервера. Русские переводы из QuestieDB не являются независимой проверкой русскоязычного клиента. Выгрузка Questie хранит коэффициенты наград опыта/денег, а не итоговые суммы — не считайте их готовыми значениями XP и меди. Координаты из ForeverDB бывают **`forever_observed`** (согласно источнику наблюдались в WoW Forever) и **`classic_or_unverified`** (Classic/независимо не подтверждены). Сами мы не проверяли позиции в игре. Для части заданий координаты отсутствуют.

## Готовые файлы

Если сборка успешно опубликована, файлы находятся в папке `dist/`:

- `wow_forever_quests.sqlite` — основная база SQLite (включает сырой JSON обеих выгрузок).
- `quests_browser.html` — автономный **русскоязычный** HTML-поиск; умеет искать также английские названия и фильтровать координаты по достоверности.
- `quests.csv` — задания на русском и английском, русские тексты целей и ссылки на источники.
- `locations.csv` — NPC/объекты, русские имена, координаты и качество `forever_observed`/`classic_or_unverified`.
- `rewards.csv` — награды: русские имена предметов при наличии перевода, репутация, коэффициенты XP/денег.
- `chains.csv` — связи квестовых цепочек.
- `coverage.json` — статистика покрытия и пропусков.

## Как собрать/обновить самостоятельно

Требуется Python 3.9+ и подключение к интернету:

```powershell
py -3 build_db.py --out dist
```

Первый запуск скачивает публичные JSON и локализацию QuestieDB `ruRU` в `.source-cache/` и создаёт базу. Повторное построение из уже скачанных данных без интернета:

```powershell
py -3 build_db.py --out dist --offline
```

## SQLite-таблицы

`quests` — идентификаторы, `title`/`title_ru`, `objective_text`/`objective_text_ru`, источники переводов, уровни, фракции, зоны, флаги, исходные JSON; `actors` — начальные/конечные NPC/предметы/объекты и координаты с `coordinate_quality`; `objectives` — цели; `rewards` — все категории наград; `quest_links` — цепочки и исключения; `zones` — зоны, `meta` — происхождение. `quest_search` — полнотекстовый поиск FTS5 по обоим языкам (если доступен).

Пример SQL:

```sql
SELECT id,coalesce(title_ru,title) AS name,quest_level,zone_name FROM quests
WHERE faction IN ('Альянс','Обе') AND min_level <= 20
ORDER BY quest_level,id;
```

Выбрать задания с наблюдавшимися в WoW Forever координатами выдачи:

```sql
SELECT q.id,coalesce(q.title_ru,q.title),a.name_ru,a.x,a.y,a.zone
FROM quests q JOIN actors a ON q.id=a.quest_id
WHERE a.role='start' AND a.coordinate_quality='forever_observed';
```

Лицензии и условия исходных данных и локализаций — в исходных репозиториях. Названия и переводы даны для удобства поиска по базе, с сохранением происхождения.