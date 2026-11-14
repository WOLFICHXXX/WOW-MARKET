// WOW-MARKET: сборщик цен аукциона WoW Forever (EU, Альянс) из API Blizzard.
// Запускается в GitHub Actions раз в час. Без внешних зависимостей (Node 20+).
//
// Окружение:
//   BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET — ключ разработчика (секреты репозитория)
//   SITE_URL   — адрес опубликованного сайта, откуда берём прошлую историю
//   OUT_DIR    — куда писать данные (по умолчанию site/data)
//   REGION     — eu (по умолчанию)
//   FACTION    — alliance | horde | neutral (по умолчанию alliance)
//   RULESET_ID — ручной выбор набора правил
//   HOUSE_ID   — один или несколько аукционов через запятую (по умолчанию все аукционы фракции)
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
const NEW_ITEM_LOOKUPS = 15000; // сколько новых предметов уточнять за запуск
// где искать предмет: Forever, затем классика и розница (у Forever в справочнике нет почти половины предметов)
const ITEM_NAMESPACES = [`static-forever-${REGION}`, `static-classic1x-${REGION}`, `static-classic-${REGION}`, `static-${REGION}`];
const MISS_RETRY_DAYS = 3;     // через сколько дней снова пробовать предмет, которого нет в API
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

async function api(pathname, namespace, extra = '', headers = {}) {
  if (env.MOCK_DIR) {
    const name = pathname.replace(/^\/data\/wow\//, '').replace(/[\/]+/g, '_').replace(/_$/, '') + '.json';
    const p = path.join(env.MOCK_DIR, name);
    try { return { status: 200, data: JSON.parse(await fs.readFile(p, 'utf8')) }; }
    catch { return { status: 404, data: null }; }
  }
  const url = `${API}${pathname}?namespace=${namespace}${extra}`;
  for (let attempt = 1; attempt <= 4; attempt++) {
    const r = await fetch(url, { headers: { Authorization: `Bearer ${token}`, ...headers } });
    if (r.status === 304) return { status: 304, data: null, lastModified: headers['If-Modified-Since'] };
    if (r.status === 429 || r.status >= 500) {
      await new Promise(res => setTimeout(res, 1000 * attempt * attempt));
      continue;
    }
    if (!r.ok) return { status: r.status, data: null };
    return { status: 200, data: await r.json(), lastModified: r.headers.get('last-modified') };
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

async function pickHouses() {
  let rulesetId = env.RULESET_ID ? Number(env.RULESET_ID) : null;
  if (!rulesetId) {
    const r = await api('/data/wow/ruleset/index', NS_DYN, '&locale=en_GB');
    const list = findListWithIds(r.data);
    rulesetId = list.length ? idFromEntry(list[0]) : 1;
    log('Наборы правил:', list.map(e => `${idFromEntry(e)}:${nameOf(e)}`).join(', ') || '(нет ответа, беру 1)');
  }
  const idx = await api(`/data/wow/ruleset/${rulesetId}/auctions/`, NS_DYN, '&locale=en_GB');
  const all = findListWithIds(idx.data).map(e => ({ id: idFromEntry(e), name: nameOf(e) }));
  log(`Аукционы набора ${rulesetId}:`, all.map(h => `${h.id}:${h.name}`).join(', ') || '(нет)');
  let houses;
  if (env.HOUSE_ID) {
    const want = String(env.HOUSE_ID).split(/[,\s]+/).filter(Boolean).map(Number);
    houses = want.map(id => all.find(h => h.id === id) || { id, name: 'вручную' });
  } else {
    const rx = { alliance: /alliance|альянс/i, horde: /horde|орд/i, neutral: /neutral|нейтрал|goblin|booty|gadgetzan|everlook|blackwater/i }[FACTION];
    houses = all.filter(h => rx.test(h.name));
    if (!houses.length && all.length) { houses = [all[0]]; warn(`Не нашёл аукционы «${FACTION}», беру первый: ${all[0].id}. Задайте HOUSE_ID.`); }
  }
  return { rulesetId, houses, all };
}

// Разведка: какие миры есть в API (чтобы подписать аукционы названиями миров)
async function probeRulesets() {
  const out = {};
  const idx = await api('/data/wow/ruleset/index', NS_DYN, '&locale=ru_RU');
  log('Разведка ruleset/index:', JSON.stringify(idx.data).slice(0, 900));
  for (const e of findListWithIds(idx.data)) {
    const id = idFromEntry(e);
    const d = await api(`/data/wow/ruleset/${id}`, NS_DYN, '&locale=ru_RU');
    const a = await api(`/data/wow/ruleset/${id}/auctions/`, NS_DYN, '&locale=ru_RU');
    out[id] = { detail: d.data, houses: findListWithIds(a.data).map(h => idFromEntry(h)) };
    log(`Разведка ruleset/${id}: HTTP ${d.status}`, JSON.stringify(d.data).slice(0, 700), '| аукционы:', out[id].houses.join(','));
  }
  return out;
}

// Одинаковы ли аукционы в разных наборах правил (или номер аукциона = режим)?
async function probeCross(rp) {
  const out = [];
  for (const rid of Object.keys(rp || {})) for (const hid of [110, 111, 119, 123]) {
    const r = await api(`/data/wow/ruleset/${rid}/auctions/${hid}`, NS_DYN);
    const a = r.data?.auctions || [];
    const row = { rid: +rid, hid, status: r.status, lots: a.length, firstIds: a.slice(0, 3).map(x => x.id), lm: r.lastModified };
    out.push(row);
    log(`Разведка набор ${rid} (${rp[rid]?.detail?.name || ''}) аукцион ${hid}: ${a.length} лотов, первые id ${row.firstIds.join(',')}, ${row.lm}`);
  }
  return out;
}

async function probeRealms() {
  const out = {};
  for (const p of ['/data/wow/realm/index', '/data/wow/connected-realm/index']) {
    const r = await api(p, NS_DYN, '&locale=ru_RU');
    const list = findListWithIds(r.data);
    out[p] = { status: r.status, list: list.slice(0, 60).map(e => ({ id: idFromEntry(e), name: nameOf(e), slug: e.slug || null })) };
    log(`Разведка ${p}: HTTP ${r.status}, записей ${list.length}`, out[p].list.map(e => `${e.id}:${e.name || e.slug || ''}`).join(', ').slice(0, 600));
  }
  return out;
}

function unitPriceOf(a) {
  const q = a.quantity || 1;
  if (a.unit_price) return a.unit_price;
  if (a.buyout) return Math.round(a.buyout / q);
  return null; // только ставка — пропускаем
}

// Возвращает { lots, lm } или { unchanged: true }, если снимок не обновлялся с прошлого раза
async function fetchAuctions(rulesetId, houseId, prevLm) {
  const lots = [];
  let lm = null;
  for (const suffix of ['', '/commodities']) {
    const hdr = (!suffix && prevLm && !env.FORCE) ? { 'If-Modified-Since': prevLm } : {};
    const r = await api(`/data/wow/ruleset/${rulesetId}/auctions/${houseId}${suffix}`, NS_DYN, '', hdr);
    if (r.status === 304) { log(`Аукцион ${houseId}: снимок не изменился (${prevLm})`); return { unchanged: true }; }
    if (!suffix) lm = r.lastModified || null;
    const arr = r.data?.auctions;
    if (Array.isArray(arr)) { lots.push(...arr); log(`Лотов в ${houseId}${suffix || ''}: ${arr.length}`); }
    else log(`Лотов в ${houseId}${suffix || ''}: 0 (HTTP ${r.status})`);
  }
  return { lots, lm };
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
    if (it.miss) return it.mv !== 2 || (Date.now() - Date.parse(it.miss)) / 864e5 >= MISS_RETRY_DAYS;
    return false;
  }).slice(0, NEW_ITEM_LOOKUPS);
  if (!todo.length) return 0;
  log(`Уточняю ${todo.length} предметов в справочнике…`);
  let done = 0, found = 0;
  const nsCount = {};
  const worker = async () => {
    while (todo.length) {
      const id = todo.shift();
      let r = { status: 404, data: null }, nsUsed = null;
      for (const ns of ITEM_NAMESPACES) {
        r = await api(`/data/wow/item/${id}`, ns, '&locale=ru_RU');
        if (r.data) { nsUsed = ns; break; }
        if (r.status !== 404) break; // сбой сети — попробуем в следующий раз
      }
      if (r.data) {
        nsCount[nsUsed] = (nsCount[nsUsed] || 0) + 1;
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
        items[id] = { miss: today, mv: 2 }; // mv:2 — искали во всех справочниках
      }
      done++;
    }
  };
  await Promise.all(Array.from({ length: env.MOCK_DIR ? 1 : 24 }, worker));
  log(`Справочник: найдено ${found} из ${done}`, JSON.stringify(nsCount));
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
// Переопубликовать прошлые файлы аукциона (если в этот раз он не ответил)
async function preserveHouse(id) {
  const latest = await loadPrevious(`latest-${id}.json`, null);
  if (!latest) return false;
  await writeJson(`latest-${id}.json`, latest);
  for (let i = 0; i < SHARDS; i++) await writeJson(`hist/${id}/h${i}.json`, await loadPrevious(`hist/${id}/h${i}.json`, {}));
  return true;
}

async function main() {
  const meta = await loadPrevious('meta.json', {});
  const items = await loadPrevious('items.json', {});
  let ok = false;
  try {
    token = await getToken();
    const { rulesetId, houses } = await pickHouses();
    if (!houses.length) throw new Error('Не удалось найти ни одного аукциона в API');
    if (!meta.realmProbe || env.PROBE) meta.realmProbe = await probeRealms();
    if (!meta.rulesetProbe || env.PROBE) meta.rulesetProbe = await probeRulesets();
    if (!meta.crossProbe || env.PROBE) meta.crossProbe = await probeCross(meta.rulesetProbe);
    const prevHouses = Object.fromEntries((meta.houses || []).map(h => [h.id, h]));
    const done = [];
    let unchanged = 0;
    const allIds = new Set();
    for (const house of houses) {
      const prev = prevHouses[house.id];
      const res = await fetchAuctions(rulesetId, house.id, prev?.lm);
      if (res.unchanged) {
        if (await preserveHouse(house.id)) { done.push({ ...prev, checkedAt: now.toISOString() }); unchanged++; continue; }
        const again = await fetchAuctions(rulesetId, house.id, null); // старых файлов нет — качаем заново
        Object.assign(res, again, { unchanged: false });
      }
      const lots = res.lots;
      if (!lots.length) { log(`Аукцион ${house.id}: пусто, пропускаю`); continue; }
      const agg = aggregate(lots);
      const shards = [];
      for (let i = 0; i < SHARDS; i++) shards.push(await loadPrevious(`hist/${house.id}/h${i}.json`, {}));
      updateHistory(shards, agg);
      const latest = { t: nowTs, house: house.id, items: buildLatest(shards, agg) };
      await writeJson(`latest-${house.id}.json`, latest);
      for (let i = 0; i < SHARDS; i++) await writeJson(`hist/${house.id}/h${i}.json`, shards[i]);
      Object.keys(agg).forEach(id => allIds.add(Number(id)));
      done.push({ ...prev, id: house.id, name: house.name, lots: lots.length, itemCount: Object.keys(agg).length, updatedAt: now.toISOString(), checkedAt: now.toISOString(), lm: res.lm });
      log(`Аукцион ${house.id}: ${lots.length} лотов, ${Object.keys(agg).length} предметов`);
    }
    if (!done.length) throw new Error('Все аукционы пустые — старые данные не трогаю');
    // аукционы, которые в этот раз не ответили, оставляем со старыми данными
    for (const h of meta.houses || []) if (!done.some(d => d.id === h.id) && houses.some(x => x.id === h.id) && await preserveHouse(h.id)) done.push(h);
    done.sort((a, b) => a.id - b.id);
    if (allIds.size) await lookupItems(items, [...allIds]);
    const primary = done.reduce((a, b) => (b.lots > a.lots ? b : a));
    const fresh = done.length - unchanged > 0;
    Object.assign(meta, {
      v: 2, checkedAt: now.toISOString(), ...(fresh ? { updatedAt: now.toISOString(), hourTs: nowTs } : {}), region: REGION, faction: FACTION, ruleset: rulesetId,
      houses: done, house: { id: primary.id, name: primary.name },
      lots: done.reduce((s, h) => s + (h.lots || 0), 0), itemCount: allIds.size || meta.itemCount, lastError: null,
    });
    ok = true;
  } catch (e) {
    warn(e.message);
    Object.assign(meta, { lastError: e.message, lastErrorAt: now.toISOString() });
    for (const h of meta.houses || []) await preserveHouse(h.id);
  }
  await writeJson('meta.json', meta);
  await writeJson('items.json', items);
  log(ok ? `Готово: ${meta.houses.length} аукционов, ${meta.itemCount} предметов, ${meta.lots} лотов.` : 'Завершено с ошибкой, опубликую прежние данные.');
}

main().catch(e => { console.error(e); process.exit(1); });
