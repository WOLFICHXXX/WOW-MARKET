/* WOLFICH Market — программа для Windows (Electron).
   Сама сканирует аукцион WoW Forever по расписанию (свой ключ Blizzard) или берёт данные с сайта WOW-MARKET,
   подхватывает скан профессий прямо из папки игры, ставит аддон и присылает уведомления. */
const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, shell, dialog, safeStorage, net, Notification } = require("electron");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { spawn, execFile } = require("child_process");
const { luaToScans } = require("./savedvars");

const SITE = "https://wolfichxxx.github.io/WOW-MARKET";
const PORTS = [47391, 47392, 47393, 47394];
const MIN_INTERVAL = 5;            // минут
app.commandLine.appendSwitch("log-level", "3");
app.setAppUserModelId("WOLFICH.Market");

if (!app.requestSingleInstanceLock()) { app.quit(); }
app.on("second-instance", () => showWindow());

const USER = () => app.getPath("userData");
const DATA = () => path.join(USER(), "data");
const SETTINGS_FILE = () => path.join(USER(), "settings.json");
const ICON = path.join(__dirname, "icon.png");

let win = null, tray = null, server = null, port = 0, quitting = false;

/* ---------- настройки ---------- */
const DEFAULTS = {
  source: "site",          // site | blizzard
  clientId: "", secret: "", // secret хранится зашифрованным (secretEnc)
  intervalMin: 60,
  houses: "",              // пусто = все аукционы Альянса
  wowDir: "",
  autoImport: true,
  notifyShop: true, notifySignals: true,
  tray: true, autostart: false,
};
let settings = { ...DEFAULTS };
function loadSettings() {
  try { settings = { ...DEFAULTS, ...JSON.parse(fs.readFileSync(SETTINGS_FILE(), "utf8")) }; } catch (e) { settings = { ...DEFAULTS }; }
  if (settings.secretEnc) {
    try { settings.secret = safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(Buffer.from(settings.secretEnc, "base64")) : Buffer.from(settings.secretEnc, "base64").toString(); }
    catch (e) { settings.secret = ""; }
  }
}
function saveSettings() {
  const out = { ...settings };
  delete out.secret;
  if (settings.secret) out.secretEnc = (safeStorage.isEncryptionAvailable() ? safeStorage.encryptString(settings.secret) : Buffer.from(settings.secret)).toString("base64");
  else delete out.secretEnc;
  fs.mkdirSync(USER(), { recursive: true });
  fs.writeFileSync(SETTINGS_FILE(), JSON.stringify(out, null, 2));
}
const publicSettings = () => ({ ...settings, secret: settings.secret ? "••••••••" : "", secretEnc: undefined, hasSecret: !!settings.secret });

/* ---------- журнал ---------- */
const logLines = [];
function log(line) {
  const s = `${new Date().toLocaleTimeString("ru-RU")}  ${String(line).replace(/^\[wow-market\]\s*/, "")}`;
  logLines.push(s); if (logLines.length > 300) logLines.shift();
  if (win && !win.isDestroyed()) win.webContents.send("log", s);
}

/* ---------- сканирование по расписанию ---------- */
let timer = null, running = false, nextAt = 0, lastRun = null;
function schedule(delayMs) {
  clearTimeout(timer);
  const ms = delayMs != null ? delayMs : Math.max(MIN_INTERVAL, +settings.intervalMin || 60) * 60000;
  nextAt = Date.now() + ms;
  timer = setTimeout(() => scan("расписание"), ms);
  sendStatus();
}
function status() { return { running, nextAt, lastRun, source: settings.source, intervalMin: settings.intervalMin }; }
function sendStatus() { if (win && !win.isDestroyed()) win.webContents.send("status", status()); updateTray(); }

async function scan(reason) {
  if (running) return { ok: false, err: "уже идёт" };
  running = true; sendStatus();
  const t0 = Date.now();
  log(`Сканирование (${reason}), источник: ${settings.source === "blizzard" ? "свой ключ Blizzard" : "сайт WOW-MARKET"}`);
  let res;
  try { res = settings.source === "blizzard" && settings.clientId && settings.secret ? await scanBlizzard() : await scanSite(); }
  catch (e) { res = { ok: false, err: String(e.message || e) }; }
  running = false;
  lastRun = { at: Date.now(), ok: res.ok, err: res.err || null, sec: Math.round((Date.now() - t0) / 1000) };
  log(res.ok ? `Готово за ${lastRun.sec} с` : `Ошибка: ${res.err}`);
  schedule();
  if (win && !win.isDestroyed()) win.webContents.send("data-updated", lastRun);
  return res;
}

function scanBlizzard() {
  return new Promise((resolve) => {
    const env = {
      ...process.env, ELECTRON_RUN_AS_NODE: "1",
      BLIZZARD_CLIENT_ID: settings.clientId, BLIZZARD_CLIENT_SECRET: settings.secret,
      OUT_DIR: DATA(), SITE_URL: SITE, REGION: "eu", FACTION: "alliance", HOUSE_ID: settings.houses || "",
    };
    const p = spawn(process.execPath, [path.join(__dirname, "fetch.mjs")], { env, windowsHide: true });
    let lastErr = "";
    const onData = (b) => String(b).split(/\r?\n/).filter(Boolean).forEach((l) => { log(l); if (/ВНИМАНИЕ|Error/.test(l)) lastErr = l; });
    p.stdout.on("data", onData); p.stderr.on("data", onData);
    p.on("close", (code) => {
      let meta = {}; try { meta = JSON.parse(fs.readFileSync(path.join(DATA(), "meta.json"), "utf8")); } catch (e) {}
      resolve(code === 0 && !meta.lastError ? { ok: true } : { ok: false, err: meta.lastError || lastErr || `код ${code}` });
    });
  });
}

async function getUrl(url, ms) {
  const ac = new AbortController(), tm = setTimeout(() => ac.abort(), ms || 30000);
  try { const r = await net.fetch(url + (url.includes("?") ? "&" : "?") + "t=" + Date.now(), { cache: "no-store", signal: ac.signal }); return r.ok ? Buffer.from(await r.arrayBuffer()) : null; }
  catch (e) { return null; } finally { clearTimeout(tm); }
}
async function scanSite() {
  const meta = await getUrl(`${SITE}/data/meta.json`, 20000);
  if (!meta) return { ok: false, err: "сайт WOW-MARKET не отвечает" };
  fs.mkdirSync(DATA(), { recursive: true });
  const m = JSON.parse(meta.toString());
  let prev = {}; try { prev = JSON.parse(fs.readFileSync(path.join(DATA(), "meta.json"), "utf8")); } catch (e) {}
  if (prev.updatedAt === m.updatedAt && fs.existsSync(path.join(DATA(), "items.json"))) { log("На сайте нет новых данных"); return { ok: true }; }
  const files = ["items.json", ...(m.houses || []).filter((h) => h.lots).map((h) => `latest-${h.id}.json`)];
  for (const f of files) {
    const b = await getUrl(`${SITE}/data/${f}`, 60000);
    if (!b) return { ok: false, err: `не скачался ${f}` };
    fs.writeFileSync(path.join(DATA(), f), b);
  }
  // история: старые шарды больше не нужны — графики подтянутся с сайта по запросу
  fs.rmSync(path.join(DATA(), "hist"), { recursive: true, force: true });
  fs.writeFileSync(path.join(DATA(), "meta.json"), meta);
  log(`С сайта: ${m.houses?.length || 0} аукционов, обновлено ${new Date(m.updatedAt).toLocaleString("ru-RU")}`);
  return { ok: true };
}

/* ---------- локальный сервер интерфейса: файлы программы + данные ---------- */
const TYPES = { ".html": "text/html; charset=utf-8", ".json": "application/json", ".js": "text/javascript", ".png": "image/png", ".zip": "application/zip" };
function startServer() {
  return new Promise((resolve, reject) => {
    const tryPort = (i) => {
      if (i >= PORTS.length) return reject(new Error("нет свободного порта"));
      const s = http.createServer(handle);
      s.once("error", () => tryPort(i + 1));
      s.listen(PORTS[i], "127.0.0.1", () => { server = s; port = PORTS[i]; resolve(); });
    };
    tryPort(0);
  });
}
async function handle(req, res) {
  let u = decodeURIComponent((req.url || "/").split("?")[0]);
  if (u === "/") u = "/index.html";
  if (u.includes("..")) { res.writeHead(400); return res.end(); }
  let file;
  if (u.startsWith("/data/")) {
    file = path.join(DATA(), u.slice(6));
    if (!fs.existsSync(file)) {          // нет локально (например, история в режиме «сайт») — берём с сайта
      const b = await getUrl(SITE + u, 30000);
      if (!b) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { "content-type": TYPES[path.extname(u)] || "application/octet-stream", "cache-control": "no-store" });
      return res.end(b);
    }
  } else file = path.join(__dirname, u);
  fs.readFile(file, (err, b) => {
    if (err) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream", "cache-control": "no-store" });
    res.end(b);
  });
}

/* ---------- папка игры, аддон, скан из SavedVariables ---------- */
function run(file, args) {
  return new Promise((r) => execFile(file, args, { windowsHide: true, timeout: 5000, encoding: "utf8" }, (e, out) => r(String(out || ""))));
}
const isWow = (d) => { try { return fs.existsSync(path.join(d, "_forever_")); } catch (e) { return false; } };
async function findWow() {
  if (settings.wowDir && isWow(settings.wowDir)) return settings.wowDir;
  const cand = [];
  if (process.platform === "win32") {
    for (const key of ["HKLM\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft", "HKLM\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft", "HKCU\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft"]) {
      const m = /InstallPath\s+REG_\w+\s+(.+)/i.exec(await run("reg.exe", ["query", key, "/v", "InstallPath"]));
      if (m) { const p = m[1].trim().replace(/[\\/]+$/, ""); cand.push(p, path.dirname(p)); }
    }
    for (const d of ["C:", "D:", "E:", "F:", "G:"]) for (const sub of ["\\Program Files (x86)\\World of Warcraft", "\\Program Files\\World of Warcraft", "\\World of Warcraft", "\\Games\\World of Warcraft", "\\Battle.net\\World of Warcraft", "\\Blizzard\\World of Warcraft"]) cand.push(d + sub);
  }
  for (const c of cand) if (isWow(c)) { settings.wowDir = c; saveSettings(); return c; }
  return "";
}
function svFiles(wow) {
  const out = [];
  const acc = path.join(wow, "_forever_", "WTF", "Account");
  let list = []; try { list = fs.readdirSync(acc); } catch (e) { return out; }
  for (const a of list) {
    const f = path.join(acc, a, "SavedVariables", "WolfichMarket.lua");
    try { const st = fs.statSync(f); out.push({ file: f, mtime: st.mtimeMs }); } catch (e) {}
  }
  return out;
}
async function readScans() {
  const wow = await findWow();
  if (!wow) return { ok: false, err: "папка игры не найдена — укажите её в настройках" };
  const files = svFiles(wow);
  if (!files.length) return { ok: false, err: "в игре ещё нет данных аддона: откройте профессии и выйдите из игры или наберите /reload" };
  const texts = [];
  for (const f of files) {
    try { texts.push(...luaToScans(fs.readFileSync(f.file, "utf8"))); } catch (e) { log(`Не прочитал ${f.file}: ${e.message}`); }
  }
  return { ok: true, texts, files: files.length };
}
let svStamp = "";
function watchSaved() {
  setInterval(async () => {
    if (!settings.autoImport || !settings.wowDir) return;
    const stamp = svFiles(settings.wowDir).map((f) => f.mtime).join(",");
    if (stamp && stamp !== svStamp) {
      const first = !svStamp; svStamp = stamp;
      if (!first) { log("Игра сохранила новый скан профессий — подхватываю"); if (win && !win.isDestroyed()) win.webContents.send("scans-changed"); }
    }
  }, 20000);
}
function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    if (e.isDirectory()) copyDir(s, d); else fs.copyFileSync(s, d);
  }
}
/* --- аддон: версии и обновление с сайта --- */
const tocVersion = (file) => { try { return (/^## Version:\s*(\S+)/m.exec(fs.readFileSync(file, "utf8")) || [])[1] || ""; } catch (e) { return ""; } };
const cmpVer = (a, b) => { const x = String(a).split(".").map(Number), y = String(b).split(".").map(Number); for (let i = 0; i < 3; i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d; } return 0; };
const addonDir = (wow) => path.join(wow, "_forever_", "Interface", "AddOns", "WolfichMarket");

async function addonInfo() {
  const wow = await findWow();
  const installed = wow ? tocVersion(path.join(addonDir(wow), "WolfichMarket.toc")) : "";
  const bundled = tocVersion(path.join(__dirname, "addon", "WolfichMarket", "WolfichMarket.toc"));
  let latest = "";
  const v = await getUrl(`${SITE}/addon/version.json`, 15000);
  try { if (v) latest = JSON.parse(v.toString()).version || ""; } catch (e) {}
  const best = latest && (!bundled || cmpVer(latest, bundled) >= 0) ? latest : bundled;
  return { wow: wow || "", installed, latest: best, fromSite: !!latest, update: !!wow && (!installed || cmpVer(best, installed) > 0) };
}

/* Распаковка zip без сторонних библиотек (store / deflate) */
function unzip(buf) {
  const zlib = require("zlib");
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new Error("архив повреждён");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = [];
  for (let k = 0; k < count; k++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error("архив повреждён");
    const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28), elen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32), loc = buf.readUInt32LE(p + 42);
    const name = buf.slice(p + 46, p + 46 + nlen).toString("utf8").replace(/\\/g, "/");
    p += 46 + nlen + elen + clen;
    if (name.endsWith("/")) continue;
    const start = loc + 30 + buf.readUInt16LE(loc + 26) + buf.readUInt16LE(loc + 28);
    const raw = buf.slice(start, start + csize);
    out.push({ name, data: method === 8 ? zlib.inflateRawSync(raw) : raw });
  }
  return out;
}

async function installAddon() {
  const wow = await findWow();
  if (!wow) return { ok: false, err: "папка игры не найдена — укажите её в настройках" };
  const dst = addonDir(wow);
  let files = null, from = "сайта";
  const zip = await getUrl(`${SITE}/addon/WolfichMarket.zip`, 60000);
  if (zip) {
    try { files = unzip(zip).filter((f) => f.name.startsWith("WolfichMarket/") && !f.name.includes("..")); if (!files.some((f) => /WolfichMarket\.toc$/.test(f.name))) files = null; }
    catch (e) { log("Архив аддона с сайта не распаковался: " + e.message); files = null; }
  }
  try {
    const tmp = dst + ".new";
    fs.rmSync(tmp, { recursive: true, force: true });
    if (files) {
      for (const f of files) { const out = path.join(tmp, f.name.slice("WolfichMarket/".length)); fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, f.data); }
    } else {
      from = "программы";
      copyDir(path.join(__dirname, "addon", "WolfichMarket"), tmp);
    }
    // меняем папку целиком: старые файлы не остаются
    fs.rmSync(dst, { recursive: true, force: true });
    fs.renameSync(tmp, dst);
  } catch (e) { return { ok: false, err: "не удалось записать: " + e.message + " (запустите программу от имени администратора)" }; }
  const v = tocVersion(path.join(dst, "WolfichMarket.toc"));
  log(`Аддон ${v} установлен из ${from}: ${dst}`);
  return { ok: true, dir: dst, version: v, from };
}

/* ---------- окно и трей ---------- */
function createWindow(hidden) {
  win = new BrowserWindow({
    width: 1180, height: 820, minWidth: 420, minHeight: 560, show: !hidden,
    title: "WOLFICH Market", icon: ICON, backgroundColor: "#090b10", autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false, backgroundThrottling: false },
  });
  win.setMenu(null);
  win.loadURL(`http://127.0.0.1:${port}/`);
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/i.test(url)) shell.openExternal(url); return { action: "deny" }; });
  win.webContents.on("will-navigate", (e, url) => { if (!url.startsWith(`http://127.0.0.1:${port}`)) { e.preventDefault(); shell.openExternal(url); } });
  win.on("close", (e) => { if (!quitting && settings.tray) { e.preventDefault(); win.hide(); } });
  win.on("closed", () => { win = null; });
}
function showWindow() { if (!win) createWindow(false); else { if (win.isMinimized()) win.restore(); win.show(); win.focus(); } }
function updateTray() {
  if (!tray) return;
  const next = nextAt ? new Date(nextAt).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" }) : "—";
  tray.setToolTip(`WOLFICH Market — ${running ? "сканирую…" : "следующий скан в " + next}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Открыть", click: showWindow },
    { label: running ? "Сканирую…" : "Сканировать сейчас", enabled: !running, click: () => scan("вручную") },
    { type: "separator" },
    { label: "Выход", click: () => { quitting = true; app.quit(); } },
  ]));
}

/* ---------- IPC ---------- */
ipcMain.handle("get-settings", () => publicSettings());
ipcMain.handle("set-settings", (e, patch) => {
  const p = { ...patch };
  if (p.secret === "••••••••") delete p.secret;          // не меняли
  if (p.intervalMin != null) p.intervalMin = Math.max(MIN_INTERVAL, Math.round(+p.intervalMin) || 60);
  const intervalChanged = p.intervalMin != null && p.intervalMin !== settings.intervalMin;
  const sourceChanged = p.source != null && p.source !== settings.source;
  const keyChanged = (p.secret != null && p.secret !== settings.secret) || (p.clientId != null && p.clientId !== settings.clientId) || (p.houses != null && p.houses !== settings.houses);
  Object.assign(settings, p);
  saveSettings();
  if (p.autostart != null) app.setLoginItemSettings({ openAtLogin: !!settings.autostart, args: ["--hidden"] });
  if (sourceChanged || (keyChanged && settings.source === "blizzard")) scan("новые настройки"); else if (intervalChanged && !running) schedule();
  return publicSettings();
});
ipcMain.handle("status", () => status());
ipcMain.handle("log", () => logLines.slice());
ipcMain.handle("scan-now", () => scan("вручную"));
ipcMain.handle("read-scans", () => readScans());
ipcMain.handle("install-addon", () => installAddon());
ipcMain.handle("addon-info", () => addonInfo());
ipcMain.handle("find-wow", () => findWow());
ipcMain.handle("pick-wow", async () => {
  const r = await dialog.showOpenDialog(win, { title: "Папка World of Warcraft (в ней есть _forever_)", properties: ["openDirectory"] });
  if (r.canceled || !r.filePaths[0]) return { ok: false };
  let d = r.filePaths[0];
  if (/[\\/]_forever_$/i.test(d)) d = path.dirname(d);
  if (!isWow(d)) return { ok: false, err: "в этой папке нет _forever_" };
  settings.wowDir = d; saveSettings(); return { ok: true, dir: d };
});
ipcMain.handle("notify", (e, title, body) => { if (Notification.isSupported()) { const n = new Notification({ title, body, icon: ICON }); n.on("click", showWindow); n.show(); } });
ipcMain.handle("open-data", () => shell.openPath(DATA()));
ipcMain.handle("app-version", () => app.getVersion());

/* ---------- запуск ---------- */
app.whenReady().then(async () => {
  loadSettings();
  fs.mkdirSync(DATA(), { recursive: true });
  await startServer();
  const hidden = process.argv.includes("--hidden");
  createWindow(hidden);
  try { tray = new Tray(nativeImage.createFromPath(ICON).resize({ width: 16, height: 16 })); tray.on("click", showWindow); } catch (e) { tray = null; }
  updateTray();
  findWow().then((d) => { if (d) log(`Папка игры: ${d}`); });
  watchSaved();
  // первый скан сразу, если данных нет или они устарели
  let meta = {}; try { meta = JSON.parse(fs.readFileSync(path.join(DATA(), "meta.json"), "utf8")); } catch (e) {}
  if (meta.checkedAt || meta.updatedAt) lastRun = { at: Date.parse(meta.checkedAt || meta.updatedAt), ok: !meta.lastError, err: meta.lastError || null };
  const age = meta.checkedAt || meta.updatedAt ? Date.now() - Date.parse(meta.checkedAt || meta.updatedAt) : Infinity;
  const interval = Math.max(MIN_INTERVAL, +settings.intervalMin || 60) * 60000;
  schedule(age >= interval ? 1500 : interval - age);
});
app.on("before-quit", () => { quitting = true; });
app.on("window-all-closed", () => { if (!settings.tray) app.quit(); });
