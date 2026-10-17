// 산수화 배경 밑그림 렌더러.
// LingDong- 의 shan-shui-inf (MIT, https://github.com/LingDong-/shan-shui-inf) 페이지를
// Chromium으로 열어 시드별 16:9 산수화(1920×1080)를 PNG로 찍는다.
// 찍은 밑그림은 generate_art.py가 색·낙관을 더해 assets/art/bg/ 배경으로 만든다.
//
// 실행:
//   curl -sSfL -o <작업폴더>/index.html https://raw.githubusercontent.com/LingDong-/shan-shui-inf/master/index.html
//   node tools/art/render_shanshui.js <작업폴더>/index.html <출력폴더> 시드[:가로위치] ...
// playwright가 필요하다. (전역 설치 또는 NODE_PATH)

const fs = require('fs');
const path = require('path');

function loadPlaywright() {
  for (const name of ['playwright', '/opt/node22/lib/node_modules/playwright']) {
    try { return require(name); } catch (e) { /* 다음 후보 */ }
  }
  throw new Error('playwright를 찾을 수 없습니다.');
}

const [, , htmlPath, outDir, ...specs] = process.argv;
if (!htmlPath || !outDir || specs.length === 0) {
  console.error('사용법: node render_shanshui.js index.html 출력폴더 시드[:가로위치] ...');
  process.exit(1);
}

// 원본 페이지를 고친 사본: 현대 송전탑을 빼고, 16:9 창 크기로 그리고, 메뉴 버튼을 숨긴다.
let html = fs.readFileSync(htmlPath, 'utf-8');
const replacements = [
  ['return Arch.transmissionTower01(x + xoff, y + yoff, seed);', 'return "";'],
  ['windx: 3000', 'windx: 1422'],
  ['<body style="margin:0">', '<body style="margin:0"><style>#SETTING,#SOURCE_BTN,#MENU,#L,#R{display:none!important}</style>'],
];
for (const [from, to] of replacements) {
  if (!html.includes(from)) throw new Error('원본 페이지가 바뀌어 고칠 곳을 못 찾음: ' + from);
  html = html.replace(from, to);
}
fs.mkdirSync(outDir, { recursive: true });
const patched = path.resolve(outDir, '_shanshui_patched.html');
fs.writeFileSync(patched, html);

(async () => {
  const { chromium } = loadPlaywright();
  const options = {};
  if (fs.existsSync('/opt/pw-browsers/chromium-1194/chrome-linux/chrome')) {
    options.executablePath = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
  }
  const browser = await chromium.launch(options);
  // 창 1422×800을 1920×1080으로 찍는다.
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1920 / 1422 });
  for (const spec of specs) {
    const [seed, cursx] = spec.split(':');
    await page.goto('file://' + patched + '?seed=' + seed);
    await page.evaluate((cx) => {
      MEM.cursx = Number(cx || 0);
      update();
    }, cursx);
    const svg = await page.$('#SVG');
    const file = path.join(outDir, `shanshui_${seed}_${cursx || 0}.png`);
    await svg.screenshot({ path: file });
    console.log(file);
  }
  await browser.close();
  fs.unlinkSync(patched);
})();
