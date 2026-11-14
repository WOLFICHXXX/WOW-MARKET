// Сравнение снимка аукциона из игры с данными API по каждому аукциону (какой аукцион — наш режим)
import fs from 'node:fs/promises';
const SITE = process.env.SITE_URL;
const game = JSON.parse(await fs.readFile('test/ingame-pvp.json', 'utf8'));
const meta = await (await fetch(`${SITE}/data/meta.json?t=${Date.now()}`)).json();
console.log('Снимок из игры:', new Date(game.t * 1000).toISOString(), 'режим', game.mode, 'предметов', Object.keys(game.items).length);
const med = (a) => { a = a.filter(Number.isFinite).sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : null; };
for (const h of meta.houses || []) {
  const r = await fetch(`${SITE}/data/latest-${h.id}.json?t=${Date.now()}`); if (!r.ok) { console.log(h.id, 'нет данных'); continue; }
  const L = (await r.json()).items;
  let common = 0, exact = 0, close = 0; const pr = [], qr = [];
  for (const [id, [gmin, gqty]] of Object.entries(game.items)) {
    const a = L[id]; if (!a || !gmin) continue;
    common++;
    if (a[0] === gmin) exact++;
    const k = gmin / a[0]; pr.push(k); if (Math.abs(k - 1) < 0.1) close++;
    if (a[3]) qr.push(gqty / a[3]);
  }
  console.log(`Аукцион ${h.id}: общих ${common}, мин. цена совпала точно ${(exact / common * 100).toFixed(1)}%, в пределах 10% ${(close / common * 100).toFixed(1)}%, медиана цен игра/API ${med(pr)?.toFixed(3)}, медиана кол-ва игра/API ${med(qr)?.toFixed(3)}`);
}
