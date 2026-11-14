// WOW-MARKET: сборщик цен аукциона WoW Forever (EU, Альянс) из API Blizzard.
// Запускается в GitHub Actions раз в час. Без внешних зависимостей (Node 20+).
//
// Окружение:
//   BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET — ключ разработчика (секреты репозитория)
//   SITE_URL   — адрес опубликованного сайта, откуда берём прошлую историю
//   OUT_DIR    — куда писать данные (по умолчанию site/data)
//   REGION     — eu (по умолчанию)
//   FACTION    — alliance | horde | neutral (по умолчанию alliance)
//   RULESET_ID, HOUSE_ID — ручной выбор, если автоопределение ошиблось
//   MOCK_DIR   — для тестов: читать ответы API из файлов вместо сети

import fs from 'node:fs/promises';
import path from 'node:path';

const env = process.env;
const REGION = (env.REGION || 'eu').toLowerCase();
const FACTION = (env.FACTION || 'alliance').toLowerCase();
const OUT_DIR = env.OUT_DIR || 'site/data';
const SITE_URL = (env.SITE_URL || '').replace(/\/$/, '');
const API = `https://${REGION}.api.blizzard.com`;
const NS_DYN = `dynamic-forever-${REGION}`;
const NS_STATIC = `static-forever-${REGION}`;
const SHARDS = 32;
const HOURLY_KEEP_H = 72;      // часовые точки: последние 72 часа
const DAILY_KEEP_D = 60;       // дневные точки: 60 дней
const NEW_ITEM_LOOKUPS = 1500; // сколько новых предметов уточнять за запуск
const MISS_RETRY_DAYS = 7;     // через сколько дней снова пробовать предмет, которого нет в API
const AH_MARKET_SHARE = 0.15;  // «рыночная» цена = средняя по самым дешёвым 15% объёма

const log = (...a) => console.log('[wow-market]', ...a);
const warn = (...a) => console.warn('[wow-market] ВНИМАНИЕ:', ...a);
const shardOf = (id) => id % SHARDS;
const now = new Date();
const nowTs = Math.floor(now.getTime() / 1000 / 3600) * 3600; // час, UTC, секунды
const today = now.toISOString().slice(0, 10);

// ---------- ввод/вывод ----------
async function readJsonFile(p, fallback) {
  try { return JSON.parse(await fs.readFile(p, 'utf8')); } catch { return fallback; }
}
async function writeJson(rel, obj) {
  const p = path.join(OUT_DIR, rel);
  await fs.mkdir(path.dirname(p), { recursive: true });
  await fs.writeFile(p, JSON.stringify(obj));
}
async function loadPrevious(rel, fallback) {
  // 1) локальный файл (тесты / повторный запуск), 2) опубликованный сайт
  const local = await readJsonFile(path.join(OUT_DIR, rel), undefined);
  if (local !== undefined) return local;
  if (!SITE_URL) return fallback;
  try {
    const r = await fetch(`${SITE_URL}/data/${rel}?t=${Date.now()}`);
    if (!r.ok) return fallback;
    return await r.json();
  } catch { return fallback; }
}

// ---------- API Blizzard ----------
let token = null;
async function getToken() {
  if (env.MOCK_DIR) return 'mock';
  const id = env.BLIZZARD_CLIENT_ID, secret = env.BLIZZARD_CLIENT_SECRET;
  if (!id || !secret) throw new Error('Нет секретов BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET');
  const r = await fetch(`https://oauth.battle.net/token`, {
    method: 'POST',
    headers: {
      'Authorization': 'Basic ' + Buffer.from(`${id}:${secret}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  if (!r.ok) throw new Error(`Токен не получен: HTTP ${r.status} ${await r.text()}`);
  return (await r.json()).access_token;
}

async function api(pathname, namespace, extra = '') {
  if (env.MOCK_DIR) {
    const name = pathname.replace(/^\/data\/wow\//, '').replace(/[\/]+/g, '_').replace(/_$/, '') + '.json';
    const p = path.join(env.MOCK_DIR, name);
    try { return { status: 200, data: JSON.parse(await fs.readFile(p, 'utf8')) }; }
    catch { return { status: 404, data: null }; }
  }
  const url = `${API}${pathname}?namespace=${namespace}${extra}`;
  for (let attempt = 1; attempt <= 4; attempt++) {
    const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (r.status === 429 || r.status >= 500) {
      await new Promise(res => setTimeout(res, 1000 * attempt * attempt));
      continue;
    }
    if (!r.ok) return { status: r.status, data: null };
    return { status: 200, data: await r.json() };
  }
  return { status: 429, data: null };
}

// Найти в произвольном JSON массив объектов, у которых есть id (и желательно name)
function findListWithIds(obj) {
  if (!obj || typeof obj !== 'object') return [];
  const out = [];
  const visit = (v, depth) => {
    if (depth > 4 || !v) return;
    if (Array.isArray(v)) {
      if (v.length && v.every(x => x && typeof x === 'object' && ('id' in x || (x.key && x.key.href)))) out.push(v);
      v.forEach(x => visit(x, depth + 1));
    } else if (typeof v === 'object') Object.values(v).forEach(x => visit(x, depth + 1));
  };
  visit(obj, 0);
  return out.sort((a, b) => b.length - a.length)[0] || [];
}
const idFromEntry = (e) => e.id ?? Number(String(e.key?.href || '').match(/\/(\d+)(?:\/|\?|$)/)?.[1]);
const nameOf = (e) => typeof e.name === 'string' ? e.name : (e.name?.ru_RU || e.name?.en_US || e.name?.en_GB || '');

async function pickHouse() {
  let rulesetId = env.RULESET_ID ? Number(env.RULESET_ID) : null;
  if (!rulesetId) {
    const r = await api('/data/wow/ruleset/index', NS_DYN, '&locale=en_GB');
    const list = findListWithIds(r.data);
    rulesetId = list.length ? idFromEntry(list[0]) : 1;
    log('Наборы правил:', list.map(e => `${idFromEntry(e)}:${nameOf(e)}`).join(', ') || '(нет ответа, беру 1)');
  }
  const idx = await api(`/data/wow/ruleset/${rulesetId}/auctions/`, NS_DYN, '&locale=en_GB');
  const houses = findListWithIds(idx.data).map(e => ({ id: idFromEntry(e), name: nameOf(e) }));
  log(`Аукционы набора ${rulesetId}:`, houses.map(h => `${h.id}:${h.name}`).join(', ') || '(нет)');
  let house = null;
  if (env.HOUSE_ID) house = houses.find(h => h.id === Number(env.HOUSE_ID)) || { id: Number(env.HOUSE_ID), name: 'вручную' };
  if (!house) {
    const rx = { alliance: /alliance|альянс/i, horde: /horde|орд/i, neutral: /neutral|нейтрал|goblin|booty|gadgetzan|everlook/i }[FACTION];
    house = houses.find(h => rx.test(h.name));
  }
  if (!house && houses.length) { house = houses[0]; warn(`Не нашёл аукцион «${FACTION}» по имени, беру первый: ${house.id} ${house.name}. Задайте HOUSE_ID.`); }
  return { rulesetId, house, houses };
}

function unitPriceOf(a) {
  const q = a.quantity || 1;
  if (a.unit_price) return a.unit_price;
  if (a.buyout) return Math.round(a.buyout / q);
  return null; // только ставка — пропускаем
}

async function fetchAuctions(rulesetId, houseId) {
  const lots = [];
  for (const suffix of ['', '/commodities']) {
    const r = await api(`/data/wow/ruleset/${rulesetId}/auctions/${houseId}${suffix}`, NS_DYN);
    const arr = r.data?.auctions;
    if (Array.isArray(arr)) { lots.push(...arr); log(`Лотов в ${houseId}${suffix || ''}: ${arr.length}`); }
    else log(`Лотов в ${houseId}${suffix || ''}: 0 (HTTP ${r.status})`);
  }
  return lots;
}

function aggregate(lots) {
  const by = new Map();
  for (const a of lots) {
    const id = a.item?.id ?? a.item_id;
    const unit = unitPriceOf(a);
    if (!id || !unit) continue;
    const q = a.quantity || 1;
    if (!by.has(id)) by.set(id, []);
    by.get(id).push([unit, q]);
  }
  const res = {};
  for (const [id, arr] of by) {
    arr.sort((x, y) => x[0] - y[0]);
    const total = arr.reduce((s, x) => s + x[1], 0);
    // взвешенная медиана
    let acc = 0, med = arr[arr.length - 1][0];
    for (const [p, q] of arr) { acc += q; if (acc >= total / 2) { med = p; break; } }
    // рыночная: средняя по самым дешёвым 15% объёма (минимум первый лот)
    const cap = Math.max(arr[0][1], Math.ceil(total * AH_MARKET_SHARE));
    let take = 0, sum = 0;
    for (const [p, q] of arr) { const t = Math.min(q, cap - take); if (t <= 0) break; sum += p * t; take += t; }
    const mkt = Math.round(sum / take);
    res[id] = { min: arr[0][0], mkt, med, qty: total, lots: arr.length };
  }
  return res;
}

// ---------- справочник предметов ----------
async function lookupItems(items, ids) {
  const todo = ids.filter(id => {
    const it = items[id];
    if (!it) return true;
    if (it.miss) return (Date.now() - Date.parse(it.miss)) / 864e5 >= MISS_RETRY_DAYS;
    return false;
  }).slice(0, NEW_ITEM_LOOKUPS);
  if (!todo.length) return 0;
  log(`Уточняю ${todo.length} предметов в справочнике…`);
  let done = 0, found = 0;
  const worker = async () => {
    while (todo.length) {
      const id = todo.shift();
      const r = await api(`/data/wow/item/${id}`, NS_STATIC, '&locale=ru_RU');
      if (r.data) {
        const d = r.data;
        items[id] = {
          n: nameOf(d) || null,
          q: d.quality?.type || null,
          c: d.item_class?.name ? nameOf(d.item_class) : null,
          s: d.item_subclass?.name ? nameOf(d.item_subclass) : null,
          v: d.sell_price ?? null,
          b: d.purchase_price ?? null,
        };
        found++;
      } else if (r.status === 404) {
        items[id] = { miss: today };
      }
      done++;
    }
  };
  await Promise.all(Array.from({ length: env.MOCK_DIR ? 1 : 16 }, worker));
  log(`Справочник: найдено ${found} из ${done}`);
  return found;
}

// ---------- история ----------
function updateHistory(shards, agg) {
  const cutoff = nowTs - HOURLY_KEEP_H * 3600;
  const dayCut = new Date(Date.now() - DAILY_KEEP_D * 864e5).toISOString().slice(0, 10);
  const touched = new Set();
  for (const [idStr, a] of Object.entries(agg)) {
    const id = Number(idStr);
    const sh = shards[shardOf(id)];
    const rec = sh[id] || (sh[id] = { h: [], d: [] });
    rec.h = rec.h.filter(p => p[0] > cutoff && p[0] !== nowTs);
    rec.h.push([nowTs, a.mkt, a.min, a.qty]);
    // дневная точка = среднее часовых за сегодня
    const todays = rec.h.filter(p => new Date(p[0] * 1000).toISOString().slice(0, 10) === today);
    const avg = (k) => Math.round(todays.reduce((s, p) => s + p[k], 0) / todays.length);
    rec.d = rec.d.filter(p => p[0] !== today && p[0] >= dayCut);
    rec.d.push([today, avg(1), Math.min(...todays.map(p => p[2])), avg(3)]);
    touched.add(id);
  }
  // предметы, которых сейчас нет на аукционе: только чистим старые точки
  for (const sh of shards) for (const [idStr, rec] of Object.entries(sh)) {
    if (touched.has(Number(idStr))) continue;
    rec.h = rec.h.filter(p => p[0] > cutoff);
    rec.d = rec.d.filter(p => p[0] >= dayCut);
    if (!rec.h.length && !rec.d.length) delete sh[idStr];
  }
}

function buildLatest(shards, agg) {
  const out = {};
  const pct = (a, b) => (b ? Math.round((a - b) / b * 1000) / 10 : null);
  for (const [idStr, a] of Object.entries(agg)) {
    const rec = shards[shardOf(Number(idStr))][idStr];
    const last24 = rec.h.filter(p => p[0] > nowTs - 24 * 3600 && p[0] < nowTs);
    const avg24 = last24.length ? Math.round(last24.reduce((s, p) => s + p[1], 0) / last24.length) : null;
    const d7 = rec.d.slice(-8, -1); // прошлые 7 дней без сегодня
    const avg7 = d7.length ? Math.round(d7.reduce((s, p) => s + p[1], 0) / d7.length) : null;
    // [min, mkt, med, qty, lots, avg24, avg7, chg24%, chg7%]
    out[idStr] = [a.min, a.mkt, a.med, a.qty, a.lots, avg24, avg7, pct(a.mkt, avg24), pct(a.mkt, avg7)];
  }
  return out;
}

// ---------- главный сценарий ----------
async function main() {
  const meta = await loadPrevious('meta.json', {});
  const items = await loadPrevious('items.json', {});
  const shards = [];
  for (let i = 0; i < SHARDS; i++) shards.push(await loadPrevious(`hist/h${i}.json`, {}));
  let latest = await loadPrevious('latest.json', null);

  let ok = false;
  try {
    token = await getToken();
    const { rulesetId, house, houses } = await pickHouse();
    if (!house) throw new Error('Не удалось найти ни одного аукциона в API');
    const lots = await fetchAuctions(rulesetId, house.id);
    if (!lots.length) throw new Error('API вернул пустой аукцион — старые данные не трогаю');
    const agg = aggregate(lots);
    updateHistory(shards, agg);
    latest = { t: nowTs, items: buildLatest(shards, agg) };
    await lookupItems(items, Object.keys(agg).map(Number));
    Object.assign(meta, {
      updatedAt: now.toISOString(), hourTs: nowTs, region: REGION, faction: FACTION,
      ruleset: rulesetId, house, houses, lots: lots.length, itemCount: Object.keys(agg).length,
      lastError: null,
    });
    ok = true;
  } catch (e) {
    warn(e.message);
    Object.assign(meta, { lastError: e.message, lastErrorAt: now.toISOString() });
  }

  // Пишем всё назад (даже при ошибке — чтобы сайт не потерял прошлые данные)
  await writeJson('meta.json', meta);
  await writeJson('items.json', items);
  if (latest) await writeJson('latest.json', latest);
  for (let i = 0; i < SHARDS; i++) await writeJson(`hist/h${i}.json`, shards[i]);
  log(ok ? `Готово: ${meta.itemCount} предметов, ${meta.lots} лотов.` : 'Завершено с ошибкой, опубликую прежние данные.');
}

main().catch(e => { console.error(e); process.exit(1); });
