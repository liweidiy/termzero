/**
 * 屏幕 -> ArkUI Span 游程 (Phase 1b)。
 *
 * 一行 = 一个 Text, 行内按 (fg, bg, bold, underline) 游程合并成尽量少的 Span。
 * TermRow.rev 是行修订号: 内容没变的行 key 不变, ForEach 不会重建那行的 Span。
 */
import {
  VtScreen,
  VtCell,
  VtPen,
  DEFAULT_BG,
  DEFAULT_BG_RGB,
  DEFAULT_FG,
  DEFAULT_FG_RGB,
  COLOR_DEFAULT,
  resolveColor
} from './VtScreen';

export class TermRun {
  text: string = '';
  fg: string = DEFAULT_FG;
  bg: string = DEFAULT_BG;
  bold: boolean = false;
  underline: boolean = false;
}

export class TermRow {
  key: string = '';
  rev: number = -1;
  runs: TermRun[] = [];
}

function dimColor(rgb: number): number {
  const r: number = Math.round(((rgb >> 16) & 0xFF) * 0.55);
  const g: number = Math.round(((rgb >> 8) & 0xFF) * 0.55);
  const b: number = Math.round((rgb & 0xFF) * 0.55);
  return (r << 16) | (g << 8) | b;
}

/** 把一行 cell 编成游程; cursorOn=true 时光标所在 cell 反显成块光标。 */
export function buildRowRuns(screen: VtScreen, y: number, cursorOn: boolean): TermRun[] {
  const runs: TermRun[] = [];
  const cols: number = screen.cols;
  const curX: number = screen.cursorX();
  const curY: number = screen.cursorY();
  let lastIndex: number = -1;
  let currentKey: string = '';

  for (let x = 0; x < cols; x++) {
    const cell: VtCell = screen.cellAt(y, x);
    if (cell.skip) {
      continue;
    }
    const isCursor: boolean = cursorOn && y === curY && x === curX;
    const pen: VtPen = cell.pen;
    // 光标格 = 反显; 已经反显的格被光标"翻回"正常, 与真终端一致。
    const invert: boolean = pen.inverse !== isCursor;
    let fgValue: number;
    let bgValue: number;
    if (invert) {
      // 反显要交换"实际生效"的颜色, 默认色也要参与交换。
      fgValue = pen.bg === COLOR_DEFAULT ? DEFAULT_BG_RGB : pen.bg;
      bgValue = pen.fg === COLOR_DEFAULT ? DEFAULT_FG_RGB : pen.fg;
    } else {
      fgValue = pen.fg;
      bgValue = pen.bg;
    }
    let fgStr: string = resolveColor(fgValue, DEFAULT_FG);
    let bgStr: string = resolveColor(bgValue, DEFAULT_BG);
    if (pen.dim) {
      const base: number = fgValue === COLOR_DEFAULT ? DEFAULT_FG_RGB : fgValue;
      fgStr = resolveColor(dimColor(base), DEFAULT_FG);
    }
    const key: string = `${fgStr}|${bgStr}|${pen.bold ? 1 : 0}|${pen.underline ? 1 : 0}`;
    if (lastIndex >= 0 && key === currentKey) {
      const prev: TermRun = runs[lastIndex];
      prev.text = prev.text + cell.ch;
      continue;
    }
    const run: TermRun = new TermRun();
    run.text = cell.ch;
    run.fg = fgStr;
    run.bg = bgStr;
    run.bold = pen.bold;
    run.underline = pen.underline;
    runs.push(run);
    lastIndex = runs.length - 1;
    currentKey = key;
  }

  // 行尾空格不渲染(默认底色下无视觉差别); 带显式底色的尾格保留。
  while (runs.length > 0) {
    const last: TermRun = runs[runs.length - 1];
    if (last.bg !== DEFAULT_BG) {
      break;
    }
    const text: string = last.text;
    let end: number = text.length;
    while (end > 0 && text.charCodeAt(end - 1) === 0x20) {
      end = end - 1;
    }
    last.text = text.substring(0, end);
    if (last.text.length === 0) {
      runs.pop();
      continue;
    }
    break;
  }
  return runs;
}

/** 行缓存版整屏构建: 只有 rev 变了的行才重算游程, 其余行复用同一个 TermRow 对象。 */
export function buildScreenRows(screen: VtScreen, cache: TermRow[], cursorOn: boolean): TermRow[] {
  const rowCount: number = screen.rows;
  const out: TermRow[] = [];
  for (let y = 0; y < rowCount; y++) {
    const rev: number = y < screen.rowRev.length ? screen.rowRev[y] : 0;
    const cached: TermRow | undefined = y < cache.length ? cache[y] : undefined;
    if (cached !== undefined && cached.rev === rev) {
      out.push(cached);
      continue;
    }
    const row: TermRow = new TermRow();
    row.rev = rev;
    row.key = `${y}:${rev}`;
    row.runs = buildRowRuns(screen, y, cursorOn);
    out.push(row);
  }
  return out;
}
