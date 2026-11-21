// Загрузка архива аддона на CurseForge (WoW Forever).
// Окружение: CF_API_KEY, CF_PROJECT_ID, FILE (путь к zip), VERSION (например 1.0.1),
//            CF_GAME_VERSION — необязательно: точное имя версии игры на CurseForge, если автоподбор ошибся.
import fs from 'node:fs/promises';
import path from 'node:path';

const { CF_API_KEY, CF_PROJECT_ID, FILE, VERSION, CF_GAME_VERSION, CHANGELOG } = process.env;
const BASE = 'https://wow.curseforge.com/api';
const log = (...a) => console.log('[curseforge]', ...a);

if (!CF_API_KEY || !CF_PROJECT_ID) { log('Нет CF_API_KEY / CF_PROJECT_ID — пропускаю загрузку на CurseForge.'); process.exit(0); }

const get = async (p) => {
  const r = await fetch(BASE + p, { headers: { 'X-Api-Token': CF_API_KEY } });
  if (!r.ok) throw new Error(`${p}: HTTP ${r.status} ${await r.text()}`);
  return r.json();
};

const types = await get('/game/version-types');
const versions = await get('/game/versions');
const foreverTypes = types.filter(t => /forever/i.test(`${t.name} ${t.slug}`));
log('Типы версий Forever:', foreverTypes.map(t => `${t.id}:${t.name}`).join(', ') || '(не найдены)');

let pick;
if (CF_GAME_VERSION) {
  pick = versions.filter(v => v.name === CF_GAME_VERSION || v.slug === CF_GAME_VERSION);
} else {
  const pool = versions.filter(v => foreverTypes.some(t => t.id === v.gameVersionTypeID));
  log('Версии Forever:', pool.map(v => `${v.id}:${v.name}`).join(', ') || '(нет)');
  pool.sort((a, b) => b.id - a.id);
  pick = pool.slice(0, 1); // самая свежая
}
if (!pick.length) {
  throw new Error('Не нашёл версию игры Forever на CurseForge. Задайте переменную CF_GAME_VERSION (имя версии со страницы загрузки файла).');
}
log('Загружаю для версии игры:', pick.map(v => v.name).join(', '));

// заметки к выпуску (на английском) - раздел «## VERSION» из docs/CHANGELOG.md
let notes = CHANGELOG;
if (!notes) {
  try {
    const md = await fs.readFile('docs/CHANGELOG.md', 'utf8');
    const esc = VERSION.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const m = md.match(new RegExp('^## ' + esc + '\\s*\\n([\\s\\S]*?)(?=^## |(?![\\s\\S]))', 'm'));
    if (m) notes = `## WolfichMarket ${VERSION}\n\n` + m[1].trim();
    // SINCE - прошлая версия на CurseForge: заметки всех версий между ней и VERSION (без неё самой)
    const SINCE = (process.env.SINCE || '').trim();
    if (m && SINCE) {
      const start = md.indexOf('## ' + VERSION + '\n');
      const end = md.indexOf('\n## ' + SINCE + '\n');
      if (start >= 0 && end > start) {
        const body = md.slice(start, end).replace(/\n---\s*\n/g, '\n').replace(/^## (\S+)\s*$/gm, '## $1').trim();
        notes = `# WolfichMarket ${VERSION}\n\n` + body;
      }
    }
  } catch (e) { log('Нет docs/CHANGELOG.md'); }
}
log(notes ? 'Заметки к выпуску найдены.' : 'Заметок к выпуску нет - будет только номер версии.');

const buf = await fs.readFile(FILE);
const form = new FormData();
form.append('metadata', JSON.stringify({
  changelog: notes || `WolfichMarket ${VERSION}`,
  changelogType: 'markdown',
  displayName: `WolfichMarket ${VERSION}`,
  gameVersions: pick.map(v => v.id),
  releaseType: 'release',
}));
form.append('file', new Blob([buf], { type: 'application/zip' }), path.basename(FILE));

const r = await fetch(`${BASE}/projects/${CF_PROJECT_ID}/upload-file`, { method: 'POST', headers: { 'X-Api-Token': CF_API_KEY }, body: form });
const text = await r.text();
if (!r.ok) throw new Error(`Загрузка не удалась: HTTP ${r.status} ${text}`);
log('Готово:', text);
