/**
 * VT100 子集屏幕模型 (Phase 1b)。
 *
 * 网格 Cell + 光标 + SGR 画笔 + 滚动区 + 备用屏幕缓冲(47/1047/1049)。
 * 只建模, 不解析(解析在 VtParser), 不渲染(渲染在 VtRender / Terminal 页)。
 *
 * 未建模: 鼠标上报、OSC 52 剪贴板、DA 应答、DECSCUSR 光标形状、双宽/双高字符。
 */

/** 默认前景/背景, 与 resources 里的 $color.terminal_text / $color.terminal_bg 保持一致。 */
export const DEFAULT_FG: string = '#E8E8E8';
export const DEFAULT_BG: string = '#1E1E1E';
export const DEFAULT_FG_RGB: number = 0xE8E8E8;
export const DEFAULT_BG_RGB: number = 0x1E1E1E;
/** 画笔里的 "用默认色" 哨兵。 */
export const COLOR_DEFAULT: number = -1;

/** xterm 256 色表: 0-15 基本色。 */
const BASIC16: number[] = [
  0x000000, 0xCD0000, 0x00CD00, 0xCDCD00, 0x0000EE, 0xCD00CD, 0x00CDCD, 0xE5E5E5,
  0x7F7F7F, 0xE50000, 0x00E500, 0xE5E500, 0x5C5CFF, 0xE500E5, 0x00E5E5, 0xFFFFFF
];
/** xterm 256 色表: 16-231 的 6x6x6 彩cube 取值。 */
const CUBE_LEVELS: number[] = [0, 95, 135, 175, 215, 255];
/** xterm 256 色表: 232-255 灰阶。 */
const GRAY_RAMP: number[] = [
  0x08, 0x12, 0x1C, 0x26, 0x30, 0x3A, 0x44, 0x4E, 0x58, 0x62, 0x6C, 0x76,
  0x80, 0x8A, 0x94, 0x9E, 0xA8, 0xB2, 0xBC, 0xC6, 0xD0, 0xDA, 0xE4, 0xEE
];

function buildPalette(): number[] {
  const table: number[] = [];
  for (let i = 0; i < 16; i++) {
    table.push(BASIC16[i]);
  }
  for (let r = 0; r < 6; r++) {
    for (let g = 0; g < 6; g++) {
      for (let b = 0; b < 6; b++) {
        const rgb: number = (CUBE_LEVELS[r] << 16) | (CUBE_LEVELS[g] << 8) | CUBE_LEVELS[b];
        table.push(rgb);
      }
    }
  }
  for (let i = 0; i < 24; i++) {
    table.push((GRAY_RAMP[i] << 16) | (GRAY_RAMP[i] << 8) | GRAY_RAMP[i]);
  }
  return table;
}

const PALETTE: number[] = buildPalette();

export function paletteColor(index: number): number {
  if (index < 0) {
    return index;
  }
  return PALETTE[index & 0xFF];
}

function hex2(value: number): string {
  const s: string = value.toString(16);
  return s.length < 2 ? `0${s}` : s;
}

export function toHexColor(rgb: number): string {
  return `#${hex2((rgb >> 16) & 0xFF)}${hex2((rgb >> 8) & 0xFF)}${hex2(rgb & 0xFF)}`.toUpperCase();
}

/** 256 色 / 真彩 -> 解析后的 #RRGGBB; COLOR_DEFAULT 回落 fallback。 */
export function resolveColor(value: number, fallback: string): string {
  if (value === COLOR_DEFAULT) {
    return fallback;
  }
  return toHexColor(value);
}

function mixToward(rgb: number, factor: number): number {
  const r: number = Math.round(((rgb >> 16) & 0xFF) * factor);
  const g: number = Math.round(((rgb >> 8) & 0xFF) * factor);
  const b: number = Math.round((rgb & 0xFF) * factor);
  return (r << 16) | (g << 8) | b;
}

/** 东亚宽字符(占两列)。取常用区块, 够用 vim/top/中文 shell 输出。 */
export function isWideCode(code: number): boolean {
  if (code < 0x1100) {
    return false;
  }
  if (code <= 0x115F) {
    return true;
  }
  if (code >= 0x2E80 && code <= 0x303E) {
    return true;
  }
  if (code >= 0x3041 && code <= 0x33FF) {
    return true;
  }
  if (code >= 0x3400 && code <= 0x4DBF) {
    return true;
  }
  if (code >= 0x4E00 && code <= 0x9FFF) {
    return true;
  }
  if (code >= 0xA000 && code <= 0xA4CF) {
    return true;
  }
  if (code >= 0xAC00 && code <= 0xD7A3) {
    return true;
  }
  if (code >= 0xF900 && code <= 0xFAFF) {
    return true;
  }
  if (code >= 0xFE10 && code <= 0xFE19) {
    return true;
  }
  if (code >= 0xFE30 && code <= 0xFE6F) {
    return true;
  }
  if (code >= 0xFF00 && code <= 0xFF60) {
    return true;
  }
  if (code >= 0xFFE0 && code <= 0xFFE6) {
    return true;
  }
  return false;
}

/** 组合符号(零宽), 不推进光标。 */
export function isCombiningCode(code: number): boolean {
  return (code >= 0x0300 && code <= 0x036F) || (code >= 0x1AB0 && code <= 0x1AFF);
}

/** SGR 画笔状态。 */
export class VtPen {
  fg: number = COLOR_DEFAULT;
  bg: number = COLOR_DEFAULT;
  bold: boolean = false;
  dim: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  blink: boolean = false;
  inverse: boolean = false;

  reset(): void {
    this.fg = COLOR_DEFAULT;
    this.bg = COLOR_DEFAULT;
    this.bold = false;
    this.dim = false;
    this.italic = false;
    this.underline = false;
    this.blink = false;
    this.inverse = false;
  }

  copyFrom(other: VtPen): void {
    this.fg = other.fg;
    this.bg = other.bg;
    this.bold = other.bold;
    this.dim = other.dim;
    this.italic = other.italic;
    this.underline = other.underline;
    this.blink = other.blink;
    this.inverse = other.inverse;
  }
}

export class VtCell {
  ch: string = ' ';
  pen: VtPen = new VtPen();
  /** 宽字符右半(渲染时跳过, 避免重复着色/重复字形)。 */
  skip: boolean = false;

  clear(): void {
    this.ch = ' ';
    this.pen.reset();
    this.skip = false;
  }

  copyFrom(other: VtCell): void {
    this.ch = other.ch;
    this.pen.copyFrom(other.pen);
    this.skip = other.skip;
  }
}

/** 一块屏幕缓冲(主屏 / 备用屏)。 */
export class VtBuffer {
  cols: number = 80;
  rows: number = 24;
  cells: VtCell[] = [];
  cursorX: number = 0;
  cursorY: number = 0;
  scrollTop: number = 0;
  scrollBottom: number = 23;
  savedX: number = 0;
  savedY: number = 0;
  /** xterm 的 deferred wrap: 写满末列先挂起, 下一个字符才折行。 */
  pendingWrap: boolean = false;

  build(cols: number, rows: number): void {
    this.cols = cols;
    this.rows = rows;
    this.cells = [];
    for (let i = 0; i < cols * rows; i++) {
      this.cells.push(new VtCell());
    }
    this.cursorX = 0;
    this.cursorY = 0;
    this.scrollTop = 0;
    this.scrollBottom = rows - 1;
    this.savedX = 0;
    this.savedY = 0;
    this.pendingWrap = false;
  }

  cell(x: number, y: number): VtCell {
    return this.cells[y * this.cols + x];
  }
}

const MAIN_SCREEN: number = 0;
const ALT_SCREEN: number = 1;

export class VtScreen {
  cols: number = 80;
  rows: number = 24;
  buffers: VtBuffer[] = [new VtBuffer(), new VtBuffer()];
  activeIndex: number = MAIN_SCREEN;
  pen: VtPen = new VtPen();
  savedPen: VtPen = new VtPen();
  autoWrap: boolean = true;
  cursorVisible: boolean = true;
  applicationCursorKeys: boolean = false;
  applicationKeypad: boolean = false;
  bracketedPaste: boolean = false;
  /** 每行修订号: 内容/光标变了的行 +1, 渲染层据此决定哪几行需要重建 Span。 */
  rowRev: number[] = [];
  /** 修订号基准代: 每次 reset/resize 递增, 保证跨代的 key 不会撞上旧缓存。 */
  private revBase: number = 0;
  /** 任意一次变更递增, 页面做节流/调试参考。 */
  contentRev: number = 0;

  constructor() {
    this.buffers[MAIN_SCREEN].build(this.cols, this.rows);
    this.buffers[ALT_SCREEN].build(this.cols, this.rows);
    this.resetRowRev();
  }

  private resetRowRev(): void {
    this.revBase = this.revBase + 1;
    this.rowRev = [];
    for (let y = 0; y < this.rows; y++) {
      this.rowRev.push(this.revBase);
    }
  }

  buf(): VtBuffer {
    return this.buffers[this.activeIndex];
  }

  mainBuf(): VtBuffer {
    return this.buffers[MAIN_SCREEN];
  }

  cursorX(): number {
    return this.buf().cursorX;
  }

  cursorY(): number {
    return this.buf().cursorY;
  }

  inAltScreen(): boolean {
    return this.activeIndex === ALT_SCREEN;
  }

  cellAt(y: number, x: number): VtCell {
    return this.buf().cell(x, y);
  }

  private markRow(y: number): void {
    if (y >= 0 && y < this.rows) {
      this.rowRev[y] = this.rowRev[y] + 1;
      this.contentRev = this.contentRev + 1;
    }
  }

  private markRange(y0: number, y1: number): void {
    let a: number = y0 < 0 ? 0 : y0;
    let b: number = y1 >= this.rows ? this.rows - 1 : y1;
    for (let y = a; y <= b; y++) {
      this.rowRev[y] = this.rowRev[y] + 1;
    }
    this.contentRev = this.contentRev + 1;
  }

  private clampX(x: number): number {
    if (x < 0) {
      return 0;
    }
    return x >= this.cols ? this.cols - 1 : x;
  }

  resize(cols: number, rows: number): boolean {
    let newCols: number = cols < 2 ? 2 : cols;
    let newRows: number = rows < 2 ? 2 : rows;
    if (newCols === this.cols && newRows === this.rows) {
      return false;
    }
    const oldCols: number = this.cols;
    const oldRows: number = this.rows;
    const oldBuffers: VtBuffer[] = this.buffers;
    this.cols = newCols;
    this.rows = newRows;
    const fresh: VtBuffer[] = [new VtBuffer(), new VtBuffer()];
    fresh[MAIN_SCREEN].build(newCols, newRows);
    fresh[ALT_SCREEN].build(newCols, newRows);
    const copyRows: number = oldRows < newRows ? oldRows : newRows;
    const copyCols: number = oldCols < newCols ? oldCols : newCols;
    for (let b = 0; b < 2; b++) {
      const src: VtBuffer = oldBuffers[b];
      const dst: VtBuffer = fresh[b];
      for (let y = 0; y < copyRows; y++) {
        for (let x = 0; x < copyCols; x++) {
          dst.cells[y * newCols + x].copyFrom(src.cells[y * oldCols + x]);
        }
      }
      dst.cursorX = this.clampX(src.cursorX);
      dst.cursorY = src.cursorY >= newRows ? newRows - 1 : src.cursorY;
      dst.savedX = this.clampX(src.savedX);
      dst.savedY = src.savedY >= newRows ? newRows - 1 : src.savedY;
      dst.scrollTop = 0;
      dst.scrollBottom = newRows - 1;
      dst.pendingWrap = false;
    }
    this.buffers = fresh;
    this.resetRowRev();
    this.contentRev = this.contentRev + 1;
    return true;
  }

  /** RIS: 全清 + 画笔复位 + 回主屏 + 滚动区复位。窗口标题保留。 */
  reset(): void {
    this.activeIndex = MAIN_SCREEN;
    this.pen.reset();
    this.savedPen.reset();
    this.autoWrap = true;
    this.cursorVisible = true;
    this.applicationCursorKeys = false;
    this.applicationKeypad = false;
    this.bracketedPaste = false;
    this.buffers[MAIN_SCREEN].build(this.cols, this.rows);
    this.buffers[ALT_SCREEN].build(this.cols, this.rows);
    this.resetRowRev();
    this.contentRev = this.contentRev + 1;
  }

  // ---------- 光标 ----------

  setCursor(col: number, row: number): void {
    const b: VtBuffer = this.buf();
    const oldY: number = b.cursorY;
    b.cursorX = this.clampX(col);
    b.cursorY = row < 0 ? 0 : (row >= this.rows ? this.rows - 1 : row);
    b.pendingWrap = false;
    this.markRow(oldY);
    this.markRow(b.cursorY);
  }

  moveCursor(dx: number, dy: number): void {
    const b: VtBuffer = this.buf();
    const oldY: number = b.cursorY;
    b.pendingWrap = false;
    if (dy > 0) {
      b.cursorY = b.cursorY + dy;
      if (b.cursorY > b.scrollBottom) {
        b.cursorY = b.scrollBottom;
      }
    } else if (dy < 0) {
      b.cursorY = b.cursorY + dy;
      if (b.cursorY < b.scrollTop) {
        b.cursorY = b.scrollTop;
      }
    }
    b.cursorX = this.clampX(b.cursorX + dx);
    this.markRow(oldY);
    this.markRow(b.cursorY);
  }

  saveCursor(): void {
    const b: VtBuffer = this.buf();
    b.savedX = b.cursorX;
    b.savedY = b.cursorY;
    this.savedPen.copyFrom(this.pen);
  }

  restoreCursor(): void {
    const b: VtBuffer = this.buf();
    const oldY: number = b.cursorY;
    b.cursorX = this.clampX(b.savedX);
    b.cursorY = b.savedY >= this.rows ? this.rows - 1 : b.savedY;
    b.pendingWrap = false;
    this.pen.copyFrom(this.savedPen);
    this.markRow(oldY);
    this.markRow(b.cursorY);
  }

  setCursorVisible(visible: boolean): void {
    if (this.cursorVisible !== visible) {
      this.cursorVisible = visible;
      this.markRange(0, this.rows - 1);
    }
  }

  carriageReturn(): void {
    const b: VtBuffer = this.buf();
    b.cursorX = 0;
    b.pendingWrap = false;
    this.markRow(b.cursorY);
  }

  lineFeed(): void {
    const b: VtBuffer = this.buf();
    b.pendingWrap = false;
    if (b.cursorY >= b.scrollBottom) {
      this.scrollUp(1);
    } else {
      const oldY: number = b.cursorY;
      b.cursorY = b.cursorY + 1;
      this.markRow(oldY);
      this.markRow(b.cursorY);
    }
  }

  index(): void {
    this.lineFeed();
  }

  reverseIndex(): void {
    const b: VtBuffer = this.buf();
    b.pendingWrap = false;
    if (b.cursorY <= b.scrollTop) {
      this.scrollDown(1);
    } else {
      const oldY: number = b.cursorY;
      b.cursorY = b.cursorY - 1;
      this.markRow(oldY);
      this.markRow(b.cursorY);
    }
  }

  newLine(): void {
    this.carriageReturn();
    this.lineFeed();
  }

  backspace(): void {
    const b: VtBuffer = this.buf();
    b.pendingWrap = false;
    b.cursorX = b.cursorX > 0 ? b.cursorX - 1 : 0;
    this.markRow(b.cursorY);
  }

  tab(): void {
    const b: VtBuffer = this.buf();
    b.pendingWrap = false;
    let next: number = b.cursorX + 1;
    while (next < this.cols && next % 8 !== 0) {
      next = next + 1;
    }
    b.cursorX = this.clampX(next);
    this.markRow(b.cursorY);
  }

  // ---------- 写字符 ----------

  printChar(ch: string): void {
    const b: VtBuffer = this.buf();
    const code: number = ch.charCodeAt(0);
    if (isCombiningCode(code)) {
      if (b.cursorX > 0) {
        const prev: VtCell = b.cell(b.cursorX - 1, b.cursorY);
        if (!prev.skip) {
          prev.ch = prev.ch + ch;
          this.markRow(b.cursorY);
        }
      }
      return;
    }
    const wide: boolean = isWideCode(code);
    if (b.pendingWrap) {
      b.pendingWrap = false;
      b.cursorX = 0;
      this.lineFeed();
    }
    if (wide && this.cols > 1 && b.cursorX >= this.cols - 1) {
      if (!this.autoWrap) {
        return;
      }
      b.cursorX = 0;
      this.lineFeed();
    }
    const cell: VtCell = b.cell(b.cursorX, b.cursorY);
    cell.ch = ch;
    cell.pen.copyFrom(this.pen);
    cell.skip = false;
    if (b.cursorX + 1 < this.cols) {
      const nxt: VtCell = b.cell(b.cursorX + 1, b.cursorY);
      if (nxt.skip && !wide) {
        nxt.clear();
      }
    }
    this.markRow(b.cursorY);
    if (wide) {
      if (b.cursorX + 1 < this.cols) {
        const nxt: VtCell = b.cell(b.cursorX + 1, b.cursorY);
        nxt.ch = '';
        nxt.pen.copyFrom(this.pen);
        nxt.skip = true;
      }
      b.cursorX = b.cursorX + 2;
    } else {
      b.cursorX = b.cursorX + 1;
    }
    if (b.cursorX >= this.cols) {
      b.cursorX = this.cols - 1;
      b.pendingWrap = this.autoWrap;
    }
  }

  /** 本地信息行(连接提示等): 纯文本 + 换行, 走同一块屏幕。 */
  writePlain(text: string): void {
    const len: number = text.length;
    let i: number = 0;
    while (i < len) {
      const code: number = text.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < len) {
        const low: number = text.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          this.printChar(text.substring(i, i + 2));
          i = i + 2;
          continue;
        }
      }
      this.printChar(text.substring(i, i + 1));
      i = i + 1;
    }
    this.carriageReturn();
    this.lineFeed();
  }

  // ---------- 擦除 ----------

  private clearCellRange(y: number, x0: number, x1: number): void {
    if (y < 0 || y >= this.rows) {
      return;
    }
    const b: VtBuffer = this.buf();
    let a: number = x0 < 0 ? 0 : x0;
    let e: number = x1 >= this.cols ? this.cols - 1 : x1;
    for (let x = a; x <= e; x++) {
      b.cell(x, y).clear();
    }
    this.markRow(y);
  }

  private clearRow(y: number): void {
    this.clearCellRange(y, 0, this.cols - 1);
  }

  eraseLine(mode: number): void {
    const b: VtBuffer = this.buf();
    if (mode === 0) {
      this.clearCellRange(b.cursorY, b.cursorX, this.cols - 1);
    } else if (mode === 1) {
      this.clearCellRange(b.cursorY, 0, b.cursorX);
    } else {
      this.clearRow(b.cursorY);
    }
  }

  eraseDisplay(mode: number): void {
    const b: VtBuffer = this.buf();
    if (mode === 0) {
      this.clearCellRange(b.cursorY, b.cursorX, this.cols - 1);
      for (let y = b.cursorY + 1; y < this.rows; y++) {
        this.clearRow(y);
      }
    } else if (mode === 1) {
      for (let y = 0; y < b.cursorY; y++) {
        this.clearRow(y);
      }
      this.clearCellRange(b.cursorY, 0, b.cursorX);
    } else {
      for (let y = 0; y < this.rows; y++) {
        this.clearRow(y);
      }
      b.pendingWrap = false;
    }
  }

  eraseChars(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    this.clearCellRange(b.cursorY, b.cursorX, b.cursorX + n - 1);
  }

  insertChars(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    if (n > this.cols) {
      n = this.cols;
    }
    for (let x = this.cols - 1; x >= b.cursorX + n; x--) {
      b.cell(x, b.cursorY).copyFrom(b.cell(x - n, b.cursorY));
    }
    this.clearCellRange(b.cursorY, b.cursorX, b.cursorX + n - 1);
  }

  deleteChars(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    if (n > this.cols) {
      n = this.cols;
    }
    for (let x = b.cursorX; x + n < this.cols; x++) {
      b.cell(x, b.cursorY).copyFrom(b.cell(x + n, b.cursorY));
    }
    this.clearCellRange(b.cursorY, this.cols - n, this.cols - 1);
  }

  // ---------- 滚动 ----------

  private regionSize(): number {
    const b: VtBuffer = this.buf();
    return b.scrollBottom - b.scrollTop + 1;
  }

  scrollUp(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    const top: number = b.scrollTop;
    const bottom: number = b.scrollBottom;
    if (n >= this.regionSize()) {
      for (let y = top; y <= bottom; y++) {
        for (let x = 0; x < this.cols; x++) {
          b.cell(x, y).clear();
        }
      }
      this.markRange(top, bottom);
      return;
    }
    for (let y = top; y <= bottom - n; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).copyFrom(b.cell(x, y + n));
      }
    }
    for (let y = bottom - n + 1; y <= bottom; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).clear();
      }
    }
    this.markRange(top, bottom);
  }

  scrollDown(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    const top: number = b.scrollTop;
    const bottom: number = b.scrollBottom;
    if (n >= this.regionSize()) {
      for (let y = top; y <= bottom; y++) {
        for (let x = 0; x < this.cols; x++) {
          b.cell(x, y).clear();
        }
      }
      this.markRange(top, bottom);
      return;
    }
    for (let y = bottom; y >= top + n; y--) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).copyFrom(b.cell(x, y - n));
      }
    }
    for (let y = top; y <= top + n - 1; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).clear();
      }
    }
    this.markRange(top, bottom);
  }

  insertLines(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    const top: number = b.cursorY;
    const bottom: number = b.scrollBottom;
    if (top > bottom) {
      return;
    }
    const size: number = bottom - top + 1;
    if (n > size) {
      n = size;
    }
    for (let y = bottom; y >= top + n; y--) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).copyFrom(b.cell(x, y - n));
      }
    }
    for (let y = top; y <= top + n - 1; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).clear();
      }
    }
    this.markRange(top, bottom);
  }

  deleteLines(count: number): void {
    const b: VtBuffer = this.buf();
    let n: number = count < 1 ? 1 : count;
    const top: number = b.cursorY;
    const bottom: number = b.scrollBottom;
    if (top > bottom) {
      return;
    }
    const size: number = bottom - top + 1;
    if (n > size) {
      n = size;
    }
    for (let y = top; y <= bottom - n; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).copyFrom(b.cell(x, y + n));
      }
    }
    for (let y = bottom - n + 1; y <= bottom; y++) {
      for (let x = 0; x < this.cols; x++) {
        b.cell(x, y).clear();
      }
    }
    this.markRange(top, bottom);
  }

  setScrollRegion(top: number, bottom: number): void {
    const b: VtBuffer = this.buf();
    let t: number = top < 1 ? 1 : top;
    let bo: number = bottom > this.rows ? this.rows : bottom;
    if (bo <= t) {
      t = 1;
      bo = this.rows;
    }
    b.scrollTop = t - 1;
    b.scrollBottom = bo - 1;
    this.setCursor(0, 0);
  }

  // ---------- 备用屏幕缓冲 ----------

  /** 47/1047/1049: 主屏内容保留在 buffers[0], 切到 alt; clear=true 时清 alt 并归零滚动区。 */
  enterAltScreen(clearScreen: boolean): void {
    if (this.activeIndex === ALT_SCREEN) {
      if (clearScreen) {
        this.eraseDisplay(2);
        this.buf().scrollTop = 0;
        this.buf().scrollBottom = this.rows - 1;
        this.setCursor(0, 0);
      }
      return;
    }
    this.activeIndex = ALT_SCREEN;
    const b: VtBuffer = this.buf();
    b.scrollTop = 0;
    b.scrollBottom = this.rows - 1;
    if (clearScreen) {
      b.build(this.cols, this.rows);
    }
    this.resetRowRev();
    this.contentRev = this.contentRev + 1;
  }

  exitAltScreen(): void {
    if (this.activeIndex === MAIN_SCREEN) {
      return;
    }
    this.activeIndex = MAIN_SCREEN;
    const b: VtBuffer = this.buf();
    b.scrollTop = 0;
    b.scrollBottom = this.rows - 1;
    b.pendingWrap = false;
    this.resetRowRev();
    this.contentRev = this.contentRev + 1;
  }

  // ---------- SGR ----------

  applySgr(params: number[]): void {
    let i: number = 0;
    if (params.length === 0) {
      this.pen.reset();
      return;
    }
    while (i < params.length) {
      const p: number = params[i];
      if (p === 0) {
        this.pen.reset();
        i = i + 1;
        continue;
      }
      if (p === 1) {
        this.pen.bold = true;
      } else if (p === 2) {
        this.pen.dim = true;
      } else if (p === 22) {
        this.pen.bold = false;
        this.pen.dim = false;
      } else if (p === 3 || p === 23) {
        this.pen.italic = p === 3;
      } else if (p === 4 || p === 21) {
        this.pen.underline = true;
      } else if (p === 24) {
        this.pen.underline = false;
      } else if (p === 5 || p === 6) {
        this.pen.blink = true;
      } else if (p === 25) {
        this.pen.blink = false;
      } else if (p === 7) {
        this.pen.inverse = true;
      } else if (p === 27) {
        this.pen.inverse = false;
      } else if (p === 39) {
        this.pen.fg = COLOR_DEFAULT;
      } else if (p === 49) {
        this.pen.bg = COLOR_DEFAULT;
      } else if (p >= 30 && p <= 37) {
        this.pen.fg = paletteColor(p - 30);
      } else if (p >= 90 && p <= 97) {
        this.pen.fg = paletteColor(p - 90 + 8);
      } else if (p >= 40 && p <= 47) {
        this.pen.bg = paletteColor(p - 40);
      } else if (p >= 100 && p <= 107) {
        this.pen.bg = paletteColor(p - 100 + 8);
      } else if (p === 38 || p === 48) {
        const isFg: boolean = p === 38;
        const kind: number = i + 1 < params.length ? params[i + 1] : -1;
        if (kind === 5 && i + 2 < params.length) {
          const idx: number = params[i + 2];
          if (isFg) {
            this.pen.fg = paletteColor(idx);
          } else {
            this.pen.bg = paletteColor(idx);
          }
          i = i + 3;
          continue;
        }
        if (kind === 2 && i + 4 < params.length) {
          const r: number = params[i + 2] & 0xFF;
          const g: number = params[i + 3] & 0xFF;
          const b: number = params[i + 4] & 0xFF;
          const rgb: number = (r << 16) | (g << 8) | b;
          if (isFg) {
            this.pen.fg = rgb;
          } else {
            this.pen.bg = rgb;
          }
          i = i + 5;
          continue;
        }
        i = i + 1;
        continue;
      }
      i = i + 1;
    }
  }
}
