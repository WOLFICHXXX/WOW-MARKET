// простые значки разделов: белые линии на прозрачном, в аддоне красятся SetVertexColor
const S = 'fill="none" stroke="#fff" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"';
const F = 'fill="#fff"';
const ICONS = {
  home: `<path ${S} d="M10 30 L32 11 L54 30"/><path ${S} d="M16 26 V52 H48 V26"/><path ${S} d="M27 52 V38 H37 V52"/>`,
  alts: `<circle ${S} cx="24" cy="22" r="8"/><path ${S} d="M9 50 C9 38 16 33 24 33 C32 33 39 38 39 50"/><circle ${S} cx="43" cy="19" r="6.5"/><path ${S} d="M41 30 C49 30 55 35 55 46"/>`,
  prof: `<path ${S} d="M25 10 H39"/><path ${S} d="M27 10 V26 L13 48 C11 52 13 55 17 55 H47 C51 55 53 52 51 48 L37 26 V10"/><path ${S} d="M19 41 H45"/>`,
  auc: `<g transform="rotate(-45 26 22)"><rect ${S} x="13" y="15" width="26" height="14" rx="2"/><path ${S} d="M17 15 V29 M35 15 V29"/></g><path ${S} d="M31 27 L50 46"/><path ${S} d="M10 55 H34"/><path ${S} d="M14 55 V50 H30 V55"/>`,
  cd: `<path ${S} d="M17 9 H47 M17 55 H47"/><path ${S} d="M21 9 C21 24 32 26 32 32 C32 38 21 40 21 55"/><path ${S} d="M43 9 C43 24 32 26 32 32 C32 38 43 40 43 55"/><path ${F} d="M25 51 C27 44 32 42 32 42 C32 42 37 44 39 51 Z"/>`,
  set: `<path ${S} d="M47.5 28.2 L53.7 28.3 L53.7 35.7 L47.5 35.8 L45.7 40.3 L50.0 44.7 L44.7 50.0 L40.3 45.7 L35.8 47.5 L35.7 53.7 L28.3 53.7 L28.2 47.5 L23.7 45.7 L19.3 50.0 L14.0 44.7 L18.3 40.3 L16.5 35.8 L10.3 35.7 L10.3 28.3 L16.5 28.2 L18.3 23.7 L14.0 19.3 L19.3 14.0 L23.7 18.3 L28.2 16.5 L28.3 10.3 L35.7 10.3 L35.8 16.5 L40.3 18.3 L44.7 14.0 L50.0 19.3 L45.7 23.7 Z"/><circle ${S} cx="32" cy="32" r="7"/>`,
  paw: `<ellipse ${F} cx="32" cy="42" rx="12" ry="10"/><ellipse ${F} cx="17" cy="28" rx="5.5" ry="7" transform="rotate(-20 17 28)"/><ellipse ${F} cx="26" cy="18" rx="5.5" ry="7.5" transform="rotate(-6 26 18)"/><ellipse ${F} cx="38" cy="18" rx="5.5" ry="7.5" transform="rotate(6 38 18)"/><ellipse ${F} cx="47" cy="28" rx="5.5" ry="7" transform="rotate(20 47 28)"/>`,
};
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 128, height: 128 } });
  for (const [n, body] of Object.entries(ICONS)) {
    await p.setContent(`<html><body style="margin:0;background:transparent"><svg width="128" height="128" viewBox="0 0 64 64">${body}</svg></body></html>`);
    await p.screenshot({ path: `${__dirname}/${n}.png`, omitBackground: true });
  }
  await b.close();
})();
