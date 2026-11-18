import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

const repo = process.cwd();
const base = path.join(repo, 'stage3-RIS与毫米波通感一体化联合优化算法方案/ppt');
const build = path.join(base, '.build-results-20261118');
const runtime = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1112-737-0_26.1112.737.0_x64__3k8sg7r9htsxt/dependencies';
process.env.RUNTIME_NODE_MODULES = path.join(runtime, 'node/node_modules');
const skill = 'C:/Users/Fubuki/.codex/plugins/cache/openai-primary-runtime/presentations/26.1112.11217/skills/presentations';
const { Presentation, PresentationFile } = await import(pathToFileURL(path.join(runtime, 'node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs')).href);
const { applyPresentationChartFont } = await import(pathToFileURL(path.join(skill, 'container_tools/artifact_tool_utils.mjs')).href);
await fs.mkdir(build, { recursive: true });

const dirs = {
  angle: 'server-results/uav-angle_fix/4f9433326972dd994d1bca6ad70ebc400b68f5de',
  hover: 'server-results/uav-foundation/d2b32c912e12937a14302726f5f09fa8f606a54e',
  snr: 'server-results/uav-snr_angle/b4a3004492e52291b9f82991e0b583e397538168',
};
const evidence = {};
async function read(kind, name) {
  const file = path.join(repo, dirs[kind], name);
  const bytes = await fs.readFile(file);
  evidence[`${kind}/${name}`] = { path: file, sha256: createHash('sha256').update(bytes).digest('hex') };
  return bytes.toString('utf8').replace(/^\uFEFF/, '');
}
async function json(kind, name) { return JSON.parse(await read(kind, name)); }
async function csv(kind, name) {
  const lines = (await read(kind, name)).trim().split(/\r?\n/);
  const columns = lines.shift().split(',');
  return lines.map(line => {
    const cells = line.split(',');
    assert.equal(cells.length, columns.length, 'Unexpected CSV structure');
    return Object.fromEntries(columns.map((column, i) => [column, isNaN(Number(cells[i])) ? cells[i] : Number(cells[i])]));
  });
}
const angle = await json('angle', 'summary.json');
const hover = await json('hover', 'summary.json');
for (const kind of Object.keys(dirs)) assert.equal((await json(kind, 'verification.json')).passed, true);
const angleRows = await csv('angle', 'case_metrics.csv');
const hoverRows = await csv('hover', 'case_metrics.csv');
const snrRows = await csv('snr', 'case_metrics.csv');
const curves = await csv('snr', 'snr_summary.csv');
assert.equal(angleRows.length, 3600); assert.equal(hoverRows.length, 3600);
assert.equal(snrRows.length, 8100); assert.equal(curves.length, 27);
const mean = values => values.reduce((a, b) => a + b, 0) / values.length;
const rmse = rows => Math.sqrt(mean(rows.flatMap(r => [r.target1_error_m ** 2, r.target2_error_m ** 2])));
for (const [summary, rows] of [[angle, angleRows], [hover, hoverRows]]) {
  for (let ri = 0; ri < summary.rcs_m2.length; ri++) for (let mi = 0; mi < summary.methods.length; mi++) {
    const selected = rows.filter(r => r.rcs_m2 === summary.rcs_m2[ri] && r.method === summary.methods[mi]);
    assert.equal(selected.length, 300);
    assert.ok(Math.abs(rmse(selected) - summary.position_rmse_m[ri][mi]) < 1e-8);
    assert.ok(Math.abs(mean(selected.map(r => r.failure)) - summary.failure_rate[ri][mi]) < 1e-12);
  }
}
for (const point of curves) {
  const all = snrRows.filter(r => r.rcs_m2 === point.rcs_m2 && r.reference_snr_db === point.reference_snr_db);
  const used = all.filter(r => r.ris_fine_used === 1);
  assert.equal(all.length, 300); assert.equal(used.length, point.ris_fine_cases);
  assert.ok(Math.abs(used.length / 300 - point.ris_fine_coverage) < 1e-12);
  assert.ok(Math.abs(mean(all.map(r => r.strict_failure)) - point.strict_failure_rate) < 1e-12);
  if (used.length) {
    const checked = Math.sqrt(mean(used.flatMap(r => [r.target1_angle_error_deg ** 2, r.target2_angle_error_deg ** 2])));
    assert.ok(Math.abs(checked - point.angle_rmse_deg) < 1e-10);
  } else assert.equal(point.angle_rmse_deg, 'NaN');
}
const tail = [10, 100, 1000].map(rcs => {
  const rows = snrRows.filter(r => r.rcs_m2 === rcs && r.reference_snr_db === -20 && r.ris_fine_used === 1);
  const sorted = rows.map(r => r.case_angle_rmse_deg).sort((a, b) => a - b);
  assert.equal(rows.length, 300);
  return { rcs, median: (sorted[149] + sorted[150]) / 2, outliers: rows.filter(r => r.case_angle_rmse_deg > 5).map(r => r.trial), maxCase: Math.max(...sorted), point: curves.find(r => r.rcs_m2 === rcs && r.reference_snr_db === -20) };
});
assert.ok(tail.every(t => t.outliers.length === 2));

const FONT = 'Microsoft YaHei';
const c = { bg: '#F8FAFC', navy: '#0B1F3A', ink: '#0F172A', slate: '#475569', muted: '#64748B', teal: '#0E8F8F', orange: '#D98B00', rose: '#CF4963', border: '#E2E8F0', gray: '#94A3B8' };
const p = Presentation.create({ slideSize: { width: 1280, height: 720 } });
function text(slide, name, value, x, y, w, h, size = 20, color = c.ink, bold = false, align = 'left') {
  const shape = slide.shapes.add({ geometry: 'textbox', name, position: { left: x, top: y, width: w, height: h }, fill: 'none', line: { fill: 'none', width: 0 } });
  shape.text = value;
  shape.text.style = { typeface: FONT, fontSize: size, color, bold, alignment: align, verticalAlignment: 'top', insets: 0, autoFit: 'none', wrap: 'square' };
  return shape;
}
function rect(slide, x, y, w, h, fill) {
  return slide.shapes.add({ geometry: 'rect', position: { left: x, top: y, width: w, height: h }, fill, line: { fill: 'none', width: 0 } });
}
function page(section, title, number, notes) {
  const s = p.slides.add(); s.background.fill = c.bg;
  rect(s, 0, 0, 1280, 7.2, c.teal); rect(s, 52.8, 41.3, 7.2, 69.1, c.teal);
  text(s, 'section', section, 78.7, 32.6, 900, 26, 12.7, c.teal, true);
  text(s, 'title', title, 78.7, 56, 1140, 53, 30.6, c.navy, true);
  rect(s, 78.7, 121.9, 1126, 1, c.border);
  text(s, 'brand', 'RIS × mmWave', 1056, 35.5, 173, 22, 11.3, c.muted, false, 'right');
  text(s, 'footer', 'RIS 通感一体化 · 目标定位全流程', 78.7, 689.3, 770, 20, 11.3, c.muted);
  text(s, 'page', String(number).padStart(2, '0'), 1147, 688, 53, 23, 12, c.teal, true, 'right');
  s.speakerNotes.text = notes;
  return s;
}
function table(s, values, x, y, widths, rowHeight = 54, size = 18) {
  const totalWidth = widths.reduce((a, b) => a + b, 0);
  const t = s.tables.add({ rows: values.length, columns: widths.length, left: x, top: y, width: totalWidth, height: values.length * rowHeight, columnWidths: widths, values });
  t.styleOptions = { headerRow: true, bandedRows: false };
  t.borders.assign({ style: 'solid', fill: c.border, width: 0.7 });
  for (let r = 0; r < values.length; r++) {
    t.rows[r].height = rowHeight;
    for (let col = 0; col < widths.length; col++) {
      const cell = t.getCell(r, col);
      cell.fill = r === 0 ? c.navy : r % 2 ? '#FFFFFF' : '#F1F5F9';
      cell.text.style = { typeface: FONT, fontSize: size, color: r === 0 ? '#FFFFFF' : c.ink, bold: r === 0 || col === 0, insets: { left: 12, right: 10, top: 9, bottom: 6 }, verticalAlignment: 'middle', wrap: 'square' };
    }
  }
  return t;
}
const chartText = { typeface: FONT, fontSize: 16, fill: c.slate };
function bar(s, name, values, categories, frame, max, unit = '定位 RMSE / m') {
  const chart = s.charts.add('bar', { position: frame, categories, series: [{ name, values, fill: c.teal, points: values.map((_, i) => ({ idx: i, fill: [c.gray, '#BAC4D0', c.teal, c.orange][i] })) }], barOptions: { direction: 'column', grouping: 'clustered', varyColors: false, gapWidth: 100 }, hasLegend: false, chartFill: '#FFFFFF', plotAreaFill: '#FFFFFF', xAxis: { visible: true, textStyle: chartText, majorGridlines: null }, yAxis: { visible: true, title: { text: unit, textStyle: chartText }, min: 0, max, numberFormatCode: max > 20 ? '0' : '0.0', textStyle: chartText, majorGridlines: { fill: c.border, width: 0.6 } }, dataLabels: { showValue: true, position: 'outEnd', numberFormatCode: '0.00', textStyle: { ...chartText, fontSize: 17, bold: true, fill: c.navy } } });
  applyPresentationChartFont(chart, { fontFamily: FONT }); return chart;
}
function scatter(s, rows, coverage, frame) {
  const chart = s.charts.add('scatter', { position: frame, scatterOptions: { style: 'lineWithMarkers' }, series: [10, 100, 1000].map((rcs, i) => {
    const data = rows.filter(r => r.rcs_m2 === rcs && (coverage || r.ris_fine_cases > 0));
    return { name: `RCS = ${rcs} m²`, smooth: false, xValues: data.map(r => r.reference_snr_db), values: data.map(r => coverage ? r.ris_fine_coverage : r.angle_rmse_deg), line: { fill: [c.teal, c.orange, c.rose][i], width: 2.8 }, marker: { symbol: ['circle', 'square', 'triangle'][i], size: 7, fill: [c.teal, c.orange, c.rose][i] } };
  }), hasLegend: true, legend: { position: 'top', overlay: false, textStyle: { ...chartText, fontSize: 17 } }, chartFill: '#FFFFFF', plotAreaFill: '#FFFFFF', xAxis: { visible: true, title: { text: '参考 SNR / dB', textStyle: chartText }, min: -60, max: -20, majorUnit: 5, numberFormatCode: '0', textStyle: chartText, majorGridlines: null }, yAxis: { visible: true, title: { text: coverage ? 'RIS 精估计覆盖率' : '球面角度 RMSE / °', textStyle: chartText }, min: 0, max: coverage ? 1.05 : 3.3, majorUnit: coverage ? 0.25 : 0.5, numberFormatCode: coverage ? '0%' : '0.0', textStyle: chartText, majorGridlines: { fill: c.border, width: 0.6 } } });
  chart.xAxis = { crossesAt: -60 };
  chart.yAxis = { crossesAt: 0, tickLabelPosition: 'low' };
  applyPresentationChartFont(chart, { fontFamily: FONT }); return chart;
}
const sourceNotes = kind => `数据来源：${path.join(repo, dirs[kind])}\n完整服务器结果，使用原始全量阵列、子载波和 CPI。\n`;
const f2 = n => Number(n).toFixed(2);

{
  const s = page('11 / 新增实验 · 2026-11-18', '已完成的仿真与统计口径', 12, sourceNotes('angle') + sourceNotes('hover') + sourceNotes('snr') + '前 11 页保留原定位流程。补充实验包括全阵列粗测角诊断、静态无人机悬停位置选择，以及固定悬停位置下的 RIS SNR–角度扫描。各实验的统计对象不同，不能拼接为同一收益序列。');
  text(s, 'lead', '三组实验均已在服务器完成，图中数值来自保存的逐样本结果', 79, 147, 1130, 40, 22, c.navy, true);
  table(s, [['实验', '场景与工况', '本轮比较', '结论适用范围'], ['测角修复', '300 场景 × 3 档 RCS', '4 种粗测角处理', '关闭 RIS，单独诊断测角'], ['无人机悬停选点', '300 场景 × 3 档 RCS', '固定 / 选点，含 NoRIS 与 RIS', '9 点离散选址，非飞行轨迹'], ['SNR–角度扫描', '300 × 3 档 RCS × 9 个 SNR', 'RCS = 10 / 100 / 1000 m²', '固定悬停，RIS 参与精估计']], 79, 213, [200, 280, 340, 306], 67, 17.5);
  text(s, 'budget', '完整资源：28 GHz，12,672 子载波，16 Tx / 64 Rx，256 符号 / CPI，256 单元 2-bit RIS', 79, 508, 1128, 54, 19.5, c.slate);
  text(s, 'metric', '统计口径：定位实验保留失败样本。SNR 图的角度 RMSE 以实际进入 RIS 精估计的样本为条件，覆盖率另报。', 79, 579, 1128, 66, 20, c.navy, true);
}
{
  const s = page('12 / 测角修复', '全阵列匹配明显改善 RCS = 10 的定位误差', 13, sourceNotes('angle') + 'RCS=10 m²，300 个配对场景，关闭 RIS。四方法使用相同 RD 峰、相同观测及噪声，只改变粗测角处理。图为最终三维定位 RMSE。70.62% 的配对 bootstrap 95% 区间为 [61.24%,81.05%]。严格失败包含捕获、可行性及任一目标位置误差大于5m。');
  text(s, 'lead', '同一份空间数据，只改变粗测角处理。此页对照关闭 RIS。', 79, 148, 1127, 35, 20, c.slate);
  bar(s, 'RCS = 10 m²', angle.position_rmse_m[1], ['原方法', '只改符号', '取消消除', '全阵列匹配'], { left: 70, top: 207, width: 706, height: 354 }, 150);
  text(s, 'gain', 'RMSE 降低 70.62%', 817, 222, 385, 50, 28, c.teal, true);
  text(s, 'ci', '配对 95% CI：61.24%–81.05%', 817, 282, 390, 42, 18, c.slate);
  text(s, 'failure', '严格失败率\n86.33% 降至 77.67%', 817, 343, 385, 75, 22, c.navy, true);
  text(s, 'reason', '全阵列匹配利用 64 路整体相位结构。弱回波下，相邻阵元相位差更容易产生离群值。', 817, 443, 385, 112, 20, c.slate);
  text(s, 'scope', '修复有效，但 RCS = 10 的 RMSE 仍为 36.90 m。RCS = 1 时四种方法仍全部严格失败。', 79, 594, 1128, 59, 20, c.navy, true);
}
{
  const s = page('13 / 无人机悬停选点', '悬停选点降低定位误差，RIS 额外收益仍待确认', 14, sourceNotes('hover') + '300个场景，RCS=1/10/100 m²，共900工况、3600方法记录。候选点为80m高度上的3×3网格，以带噪位置先验选点，不使用真实目标坐标。左右图纵轴量程不同。NoRIS/RIS分别选点，二者总体差异不能归为RIS净效应。所用几何样本沿用已观察样本集，尚无独立留出验证。');
  text(s, 'lead', '固定高度 80 m，从 9 个候选点选悬停位置。以带噪先验选点，未使用目标真值。', 79, 148, 1128, 42, 20, c.slate);
  text(s, 'rcs10', 'RCS = 10 m²', 90, 203, 520, 34, 22, c.navy, true);
  text(s, 'rcs100', 'RCS = 100 m²', 680, 203, 520, 34, 22, c.navy, true);
  const categories = ['固定无RIS', '固定RIS', '选点无RIS', '选点RIS'];
  bar(s, '定位 RMSE', hover.position_rmse_m[1], categories, { left: 70, top: 248, width: 550, height: 305 }, 340);
  bar(s, '定位 RMSE', hover.position_rmse_m[2], categories, { left: 660, top: 248, width: 550, height: 305 }, 9);
  text(s, 'gain10', '带 RIS 的选点改善：62.98%  [51.37%, 75.02%]', 85, 563, 540, 48, 18, c.teal, true);
  text(s, 'gain100', '带 RIS 的选点改善：54.29%  [40.04%, 64.16%]', 675, 563, 540, 48, 18, c.teal, true);
  text(s, 'scope', '左右纵轴量程不同。误差下降来自选点对比，尚未证明 RIS 稳定优于同位置 NoRIS，也未验证连续轨迹。', 79, 623, 1128, 45, 18.5, c.navy, true);
}
{
  const s = page('14 / SNR–角度结果 · 三档 RCS', '角度 RMSE 在高 SNR 处仍有约 1.2° 平台', 15, sourceNotes('snr') + '固定悬停[0,0,80]m、静止目标，300配对场景×3RCS×9SNR=8100工况。参考SNR定义为200m、1m²目标的参考回波与噪声之比，通过缩放热噪声设置。它不等于每个样本实测输入SNR。曲线是RIS精估计可用样本上两目标球面方向误差RMSE，误差棒为4000次配对场景bootstrap的95%区间。-60dB没有样本进入RIS精估计，RMSE未定义。直达路径负责粗捕获，两组RIS配置用于精估计。此轮没有RIS/NoRIS对照，也没有悬停优化。');
  text(s, 'lead', '固定悬停，300 场景 × 3 档 RCS × 9 个参考 SNR，共 8,100 工况。三条曲线的精估计均带 RIS。', 79, 148, 1130, 48, 19.5, c.slate);
  scatter(s, curves, false, { left: 68, top: 206, width: 1145, height: 367 });
  text(s, 'snrdef', '横轴为 200 m、RCS = 1 m² 的参考 SNR，通过调整噪声设置。误差棒为配对 95% bootstrap 区间。', 79, 584, 1130, 42, 18, c.slate);
  text(s, 'condition', '角度 RMSE 仅统计进入 RIS 精估计的样本。−60 dB 覆盖率为 0，RMSE 未定义，未画为零。', 79, 632, 1130, 37, 18.5, c.navy, true);
}
{
  const s = page('15 / 覆盖率与失败率', '低 SNR 首先受粗捕获限制，覆盖率必须一起看', 16, sourceNotes('snr') + '覆盖率=实际进入可行RIS精估计的场景数/300。角度RMSE的条件样本在不同SNR下可能不同。严格失败=粗捕获失败、粗设计不可行、RIS精设计不可行，或任一目标三维定位误差>5m。右表是全部300场景的严格失败率。-20dB每档RCS为2/300，即0.67%。-55dB分别71%、10.67%、0.67%。');
  text(s, 'lead', '粗捕获仍使用直达路径。只有通过捕获与设计可行性检查，才进入 RIS 精估计。', 79, 148, 1128, 42, 20, c.slate);
  scatter(s, curves, true, { left: 64, top: 219, width: 770, height: 357 });
  text(s, 'fail-title', '全部场景的严格失败率', 859, 223, 350, 40, 22, c.navy, true);
  table(s, [['RCS / m²', '−55 dB', '−20 dB'], ...[10, 100, 1000].map(rcs => [String(rcs), ...[-55, -20].map(snr => `${f2(curves.find(r => r.rcs_m2 === rcs && r.reference_snr_db === snr).strict_failure_rate * 100)}%`)])], 859, 285, [116, 116, 116], 53, 17);
  text(s, 'zero', '−60 dB：三档 RCS 的\nRIS 精估计覆盖率均为 0%', 859, 524, 345, 65, 19.5, c.rose, true);
  text(s, 'failuredef', '严格失败：捕获失败、设计不可行，或任一目标定位误差 > 5 m。全部失败都计入右表。', 79, 615, 1127, 50, 19.5, c.navy, true);
}
{
  const s = page('16 / 高 SNR 的离群样本', '少数大误差样本主导了平均角度 RMSE', 17, sourceNotes('snr') + '表中SNR=-20dB，三档RCS均有300/300样本进入RIS精估计。普通RMSE在两目标和300场景上计算。中位数是逐场景两目标角度RMSE的中位数，仅作补充，未取代总体RMSE，也未删除失败样本。>5°按逐场景角度RMSE判断。共同离群trial编号：' + tail.map(t => `RCS=${t.rcs}: ${t.outliers.join(',')}`).join('; ') + '。工程校准、真实目标RCS和实测信道验证均未完成。');
  text(s, 'lead', '参考 SNR = −20 dB，三档 RCS 均为 300 / 300 场景进入 RIS 精估计', 79, 148, 1127, 44, 21, c.slate);
  table(s, [['RCS / m²', '总体角度 RMSE', '95% CI / °', '逐场景中位数', '>5° 场景数'], ...tail.map(t => [String(t.rcs), `${t.point.angle_rmse_deg.toFixed(3)}°`, `${t.point.ci95_lower_deg.toFixed(3)}–${t.point.ci95_upper_deg.toFixed(3)}`, `${t.median.toFixed(4)}°`, `${t.outliers.length} / 300`])], 79, 222, [160, 235, 245, 245, 241], 67, 20);
  text(s, 'explain', '提高 RCS 后，大多数场景的误差明显变小，但每档仍有 2 个大误差场景。平方平均放大了这些离群值的影响。', 79, 522, 1126, 67, 22, c.navy, true);
  text(s, 'limit', '中位数用于解释分布，不能代替 RMSE。当前结果应优先排查离群场景，不能只靠提高 RCS 或 SNR。', 79, 613, 1126, 52, 20, c.slate);
}
{
  const s = page('17 / 当前结论与下一步', '优先修复离群场景，再验证同位置 RIS 净收益', 18, sourceNotes('angle') + sourceNotes('hover') + sourceNotes('snr') + '这些结论只针对当前静态LoS与设定RCS的仿真模型。尚未验证连续飞行轨迹、能耗、移动跟踪、真实28GHz目标RCS或实测信道。已有悬停实验沿用观察过的几何，下一轮需新几何和随机种子。');
  text(s, 'verified', '已验证', 79, 165, 510, 45, 26, c.teal, true);
  text(s, 'next', '下一步', 692, 165, 514, 45, 26, c.navy, true);
  text(s, 'known1', '全阵列匹配测角改善弱回波表现\nRCS = 10 的定位 RMSE 降低 70.62%，但严格失败率仍为 77.67%。', 79, 239, 510, 111, 22, c.ink, true);
  text(s, 'known2', '无人机悬停选点有效\n当前证据支持 9 个候选点的离散选址收益，独立场景验证尚未完成。', 79, 378, 510, 111, 22, c.ink, true);
  text(s, 'todo1', '1  排查高 SNR 下的两个离群场景\n核对粗测角、局部窗口和目标关联，比较修复前后全部样本误差。', 692, 239, 514, 111, 22, c.ink);
  text(s, 'todo2', '2  新场景中固定同一悬停位置\n配对比较 NoRIS 与 RIS，同时报告定位误差、失败率与精估计覆盖率。', 692, 378, 514, 111, 22, c.ink);
  text(s, 'scope', '工程边界：RCS 仍为设定参数，尚未用 28 GHz 真实目标 RCS 和实测信道校准。当前结果不支持工程可用性结论。', 79, 562, 1128, 81, 22, c.rose, true);
}

assert.equal(p.slides.items.length, 7);
await (await PresentationFile.exportPptx(p)).save(path.join(build, 'appendix.raw.pptx'));
await fs.writeFile(path.join(build, 'evidence.json'), JSON.stringify({ sources: evidence, tail, curves, sourceSlideCount: 11, finalSlideCount: 18, checks: { angleRows: angleRows.length, hoverRows: hoverRows.length, snrRows: snrRows.length, rawMetricsRecomputed: true } }, null, 2));
await fs.writeFile(path.join(build, 'appendix.layout.json'), JSON.stringify(p.toProto(), null, 2));
console.log(JSON.stringify({ appendixSlides: p.slides.items.length, output: path.join(build, 'appendix.raw.pptx'), tails: tail.map(t => ({ rcs: t.rcs, median: t.median, outliers: t.outliers, maxCase: t.maxCase })) }, null, 2));
