// Генерирует фальшивые ответы API в test/mock и фальшивую историю — для локальной проверки.
// node test/make-mock.mjs && MOCK_DIR=test/mock OUT_DIR=test/out node scripts/fetch.mjs
import fs from 'node:fs/promises';
import path from 'node:path';

const dir = path.join(path.dirname(new URL(import.meta.url).pathname), 'mock');
await fs.mkdir(dir, { recursive: true });
const w = (n, d) => fs.writeFile(path.join(dir, n), JSON.stringify(d));

await w('ruleset_index.json', { rulesets: [{ key: { href: 'x/ruleset/1?' }, id: 1, name: 'Forever' }] });
await w('ruleset_1_auctions.json', { auctions: [
  { id: 110, name: 'Alliance Auction House' }, { id: 111, name: 'Alliance Auction House' }, { id: 113, name: 'Horde Auction House' }, { id: 119, name: 'Alliance Auction House' }, { id: 116, name: 'Blackwater Auction House' }] });

// id, имя, качество, класс, подкласс, базовая цена (медь), объём
const ITEMS = [
  [2589, 'Льняная ткань', 'COMMON', 'Хозяйственные товары', 'Ткань', 12, 900],
  [2592, 'Шерстяная ткань', 'COMMON', 'Хозяйственные товары', 'Ткань', 35, 600],
  [2770, 'Медная руда', 'COMMON', 'Хозяйственные товары', 'Металл и камни', 45, 500],
  [2840, 'Медный слиток', 'COMMON', 'Хозяйственные товары', 'Металл и камни', 60, 300],
  [765, 'Мироцвет', 'COMMON', 'Хозяйственные товары', 'Трава', 30, 400],
  [2447, 'Мироцвет', 'COMMON', 'Хозяйственные товары', 'Трава', 25, 700],
  [785, 'Магороза', 'COMMON', 'Хозяйственные товары', 'Трава', 70, 350],
  [2449, 'Земляной корень', 'COMMON', 'Хозяйственные товары', 'Трава', 40, 380],
  [3820, 'Удавник', 'COMMON', 'Хозяйственные товары', 'Трава', 160, 160],
  [118, 'Слабое лечебное зелье', 'COMMON', 'Расходуемые', 'Зелья', 25, 120],
  [858, 'Малое лечебное зелье', 'COMMON', 'Расходуемые', 'Зелья', 90, 90],
  [2455, 'Слабое зелье маны', 'COMMON', 'Расходуемые', 'Зелья', 60, 80],
  [2458, 'Эликсир силы огра', 'COMMON', 'Расходуемые', 'Эликсиры', 260, 40],
  [5997, 'Эликсир малой защиты', 'COMMON', 'Расходуемые', 'Эликсиры', 120, 30],
  [2672, 'Жилистое волчье мясо', 'COMMON', 'Хозяйственные товары', 'Кулинария', 20, 260],
  [2680, 'Пряная волчатина', 'COMMON', 'Расходуемые', 'Еда и напитки', 55, 70],
  [6888, 'Яйцо курицы-несушки', 'COMMON', 'Хозяйственные товары', 'Кулинария', 30, 120],
  [2318, 'Тонкая кожа', 'COMMON', 'Хозяйственные товары', 'Кожа', 18, 800],
  [2319, 'Средняя кожа', 'COMMON', 'Хозяйственные товары', 'Кожа', 55, 400],
  [4306, 'Шёлковая ткань', 'COMMON', 'Хозяйственные товары', 'Ткань', 140, 450],
  [3371, 'Пустая фляга', 'COMMON', 'Хозяйственные товары', 'Прочее', 6, 0],
  [2996, 'Рулон льняного полотна', 'COMMON', 'Хозяйственные товары', 'Ткань', 70, 90],
  [6948, 'Камень возвращения', 'COMMON', 'Прочее', 'Хлам', 0, 0],
  [2319 + 100000, 'Неизвестный предмет', 'COMMON', null, null, 0, 0],
  [6219, 'Гаечный ключ', 'COMMON', 'Хозяйственные товары', 'Прочее', 300, 6],
  [12359, 'Ториевый слиток', 'COMMON', 'Хозяйственные товары', 'Металл и камни', 900, 140],
  [7909, 'Аквамарин', 'UNCOMMON', 'Хозяйственные товары', 'Металл и камни', 3500, 20],
  [14047, 'Руническая ткань', 'COMMON', 'Хозяйственные товары', 'Ткань', 950, 900],
  [13444, 'Сильное зелье маны', 'COMMON', 'Расходуемые', 'Зелья', 4800, 60],
  [13446, 'Сильное лечебное зелье', 'COMMON', 'Расходуемые', 'Зелья', 3900, 75],
  [9187, 'Эликсир высшей ловкости', 'COMMON', 'Расходуемые', 'Эликсиры', 22000, 12],
  [8846, 'Кровь Героя', 'COMMON', 'Хозяйственные товары', 'Трава', 1400, 110],
  [10620, 'Ториевая руда', 'COMMON', 'Хозяйственные товары', 'Металл и камни', 2100, 200],
  [16204, 'Сияющий осколок', 'RARE', 'Хозяйственные товары', 'Наложение чар', 2400, 25],
  [10940, 'Странная пыль', 'COMMON', 'Хозяйственные товары', 'Наложение чар', 80, 300],
  [15050, 'Ремни из чёрной драконьей чешуи', 'EPIC', 'Доспехи', 'Кожа', 1800000, 1],
  [2575, 'Красная льняная рубашка', 'UNCOMMON', 'Доспехи', 'Ткань', 1200, 8],
];

let seed = 7;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const lots = [];
let lotId = 1;
for (const [id, , , c, , base, vol] of ITEMS) {
  if (!base || !vol || !c) continue;
  // «скачки»: несколько предметов подешевели/подорожали
  const spike = { 3820: 1.6, 2458: 0.55, 785: 1.4, 13444: 0.7, 2770: 0.65 }[id] || 1;
  let left = vol;
  while (left > 0) {
    const q = Math.min(left, 1 + Math.floor(rnd() * 20));
    left -= q;
    const unit = Math.max(1, Math.round(base * spike * (0.85 + rnd() * 0.6)));
    lots.push({ id: lotId++, item: { id }, quantity: q, unit_price: unit, time_left: 'LONG' });
  }
}
lots.push({ id: lotId++, item: { id: 2589 }, quantity: 1, bid: 5, time_left: 'SHORT' }); // только ставка
await w('ruleset_1_auctions_110.json', { auctions: lots });
await w('ruleset_1_auctions_119.json', { auctions: lots.filter((_, i) => i % 3 === 0).map(l => ({ ...l, unit_price: Math.round(l.unit_price * 1.3) })) });
await w('ruleset_1_auctions_111.json', {});

for (const [id, n, q, c, s] of ITEMS) {
  if (!c) continue; // «404»
  await w(`item_${id}.json`, { id, name: n, quality: { type: q }, item_class: { name: c }, item_subclass: { name: s }, sell_price: 4, purchase_price: 20 });
}

// Фальшивая история за 72 ч и 30 дней, чтобы графики и «24 ч / 7 дн» заработали
const out = path.join(path.dirname(dir), 'out', 'hist', '110');
await fs.mkdir(out, { recursive: true });
const nowTs = Math.floor(Date.now() / 3600e3) * 3600;
const shards = Array.from({ length: 32 }, () => ({}));
for (const [id, , , c, , base, vol] of ITEMS) {
  if (!base || !vol || !c) continue;
  const h = [], d = [];
  for (let i = 72; i >= 1; i--) {
    const t = nowTs - i * 3600;
    const m = Math.round(base * (1 + 0.12 * Math.sin(i / 7) + (rnd() - 0.5) * 0.1));
    h.push([t, m, Math.round(m * 0.88), Math.round(vol * (0.8 + rnd() * 0.4))]);
  }
  for (let i = 30; i >= 1; i--) {
    const day = new Date(Date.now() - i * 864e5).toISOString().slice(0, 10);
    const m = Math.round(base * (1 + 0.2 * Math.sin(i / 5) + (rnd() - 0.5) * 0.1));
    d.push([day, m, Math.round(m * 0.85), Math.round(vol * (0.8 + rnd() * 0.4))]);
  }
  shards[id % 32][id] = { h, d };
}
for (let i = 0; i < 32; i++) await fs.writeFile(path.join(out, `h${i}.json`), JSON.stringify(shards[i]));
console.log(`mock: ${lots.length} лотов, ${ITEMS.length} предметов, история записана`);
