/* Чтение SavedVariables аддона WolfichMarket (файл WolfichMarket.lua из папки WTF)
   и превращение в тот же текст «WM1», что выдаёт /wm в игре. */

function parseLua(src) {
  let i = 0;
  const n = src.length;
  const ws = () => {
    for (;;) {
      while (i < n && /\s/.test(src[i])) i++;
      if (src.startsWith("--[[", i)) { const e = src.indexOf("]]", i + 4); i = e < 0 ? n : e + 2; continue; }
      if (src.startsWith("--", i)) { const e = src.indexOf("\n", i); i = e < 0 ? n : e + 1; continue; }
      break;
    }
  };
  const str = () => {
    const q = src[i++]; let out = "";
    while (i < n && src[i] !== q) {
      if (src[i] === "\\") {
        const c = src[i + 1];
        if (/[0-9]/.test(c)) { let d = ""; i++; while (d.length < 3 && /[0-9]/.test(src[i])) d += src[i++]; out += String.fromCharCode(+d); continue; }
        out += ({ n: "\n", t: "\t", r: "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n" })[c] ?? c; i += 2; continue;
      }
      out += src[i++];
    }
    i++;
    return out;
  };
  const value = () => {
    ws();
    const c = src[i];
    if (c === "{") return table();
    if (c === '"' || c === "'") return str();
    if (src.startsWith("[[", i)) { const e = src.indexOf("]]", i); const s = src.slice(i + 2, e); i = e + 2; return s; }
    const m = /^(-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?)|true|false|nil|[A-Za-z_][A-Za-z0-9_]*)/.exec(src.slice(i, i + 64));
    if (!m) throw new Error("непонятный символ в позиции " + i);
    i += m[0].length;
    if (m[0] === "true") return true;
    if (m[0] === "false") return false;
    if (m[0] === "nil") return null;
    const num = Number(m[0]);
    return isNaN(num) ? m[0] : num;
  };
  const table = () => {
    i++; // {
    const obj = {}; let idx = 1;
    for (;;) {
      ws();
      if (src[i] === "}") { i++; return obj; }
      let key;
      if (src[i] === "[") { i++; key = value(); ws(); i++; /* ] */ ws(); i++; /* = */ }
      else {
        const m = /^[A-Za-z_][A-Za-z0-9_]*\s*=(?!=)/.exec(src.slice(i, i + 80));
        if (m) { key = m[0].replace(/\s*=$/, ""); i += m[0].length; }
      }
      const v = value();
      if (key === undefined) key = idx++;
      obj[key] = v;
      ws();
      if (src[i] === "," || src[i] === ";") i++;
    }
  };
  const vars = {};
  for (;;) {
    ws();
    if (i >= n) break;
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i, i + 80));
    if (!m) break;
    i += m[0].length; ws();
    if (src[i] !== "=") break;
    i++;
    vars[m[0]] = value();
  }
  return vars;
}

const arr = (t) => { if (!t || typeof t !== "object") return []; const out = []; for (let k = 1; t[k] !== undefined; k++) out.push(t[k]); return out; };
const clean = (s) => String(s ?? "").replace(/[\^\r\n]/g, " ");

/* Возвращает массив строк WM1 — по одной на персонажа */
function luaToScans(src) {
  const db = parseLua(src).WolfichMarketDB;
  if (!db) return [];
  const names = db.names || {}, vendor = db.vendor || {};
  const out = [];
  for (const [charKey, c] of Object.entries(db.chars || {})) {
    const lines = [`WM1^${clean(charKey)}^${Math.floor(Date.now() / 1000)}`];
    const used = new Set();
    for (const s of arr(c.skills)) lines.push(["S", clean(s.name), s.skill || 0, s.max || 0].join("^"));
    for (const [prof, p] of Object.entries(c.profs || {})) {
      lines.push(["P", clean(prof), p.skill || 0, p.max || 0, p.t || 0].join("^"));
      for (const r of arr(p.recipes)) {
        const reag = arr(r.reag).map((x) => { const a = arr(x); used.add(a[0]); return `${a[0]}x${a[1]}`; });
        if (r.out) used.add(r.out);
        lines.push(["R", clean(prof), r.id || 0, clean(r.name), r.out || 0, r.qmin || 1, r.qmax || 1, r.diff == null ? -1 : r.diff, reag.join(",")].join("^"));
      }
    }
    for (const [id, price] of Object.entries(vendor)) { lines.push(`V^${id}^${price}`); used.add(+id); }
    for (const id of used) if (names[id]) lines.push(`N^${id}^${clean(names[id])}`);
    if (lines.length > 1) out.push(lines.join("\n"));
  }
  return out;
}

module.exports = { parseLua, luaToScans };
