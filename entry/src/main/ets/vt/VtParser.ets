/**
 * VT100 子集解析器 (Phase 1b): 字节流 -> VtScreen 状态变更。
 *
 * 覆盖: C0 控制、UTF-8 逐码点、CSI(A B C D E F G H ` d J K L M X @ P S T r s u m h l)、
 * SGR(含 38;5;n / 38;2;r;g;b)、SM/RM(含 ?47/?1047/?1049 备用屏)、
 * ESC 7/8、ESC c(RIS)、ESC D/M/E、ESC ( ) # 字符集(吞掉)、OSC 0/1/2(存 windowTitle)。
 * 未知 ESC/CSI 序列安全吞掉, 不抛异常。
 *
 * 未实现: CSI n(DSR 应答)、鼠标上报(1000/1006)、OSC 52 剪贴板、OSC 10/11 改色、
 * DECSCUSR、同步输出(2026)、WCFW 宽字符换行细节。
 */
import { VtScreen } from './VtScreen';

export enum VtParseState {
  Ground = 0,
  Escape = 1,
  Csi = 2,
  Osc = 3,
  Charset = 4
}

const OSC_MAX_LEN: number = 512;

export class VtParser {
  screen: VtScreen = new VtScreen();
  windowTitle: string = '';
  /** 存下来但不产生行为的 DEC 私有模式。 */
  private decModes: Map<number, boolean> = new Map<number, boolean>();
  private state: VtParseState = VtParseState.Ground;
  private params: string = '';
  private oscText: string = '';

  reset(): void {
    this.screen.reset();
    this.state = VtParseState.Ground;
    this.params = '';
    this.oscText = '';
    this.decModes.clear();
  }

  resize(cols: number, rows: number): boolean {
    return this.screen.resize(cols, rows);
  }

  /** 存下来但没产生行为的模式, 供页面/测试查询。 */
  decMode(mode: number): boolean {
    if (!this.decModes.has(mode)) {
      return false;
    }
    return this.decModes.get(mode) === true;
  }

  feed(data: string): void {
    const len: number = data.length;
    let i: number = 0;
    while (i < len) {
      const code: number = data.charCodeAt(i);
      if (this.state === VtParseState.Ground) {
        if (code === 0x1B) {
          this.state = VtParseState.Escape;
          i = i + 1;
          continue;
        }
        if (code === 0x9B) {
          this.state = VtParseState.Csi;
          this.params = '';
          i = i + 1;
          continue;
        }
        if (code === 0x9D) {
          this.state = VtParseState.Osc;
          this.oscText = '';
          i = i + 1;
          continue;
        }
        if ((code >= 0x20 && code <= 0x7E) || code >= 0xA0) {
          if (code >= 0xD800 && code <= 0xDBFF && i + 1 < len) {
            const low: number = data.charCodeAt(i + 1);
            if (low >= 0xDC00 && low <= 0xDFFF) {
              this.screen.printChar(data.substring(i, i + 2));
              i = i + 2;
              continue;
            }
          }
          this.screen.printChar(data.substring(i, i + 1));
          i = i + 1;
          continue;
        }
        this.c0Control(code);
        i = i + 1;
        continue;
      }

      if (this.state === VtParseState.Escape) {
        this.onEscape(code);
        i = i + 1;
        continue;
      }

      if (this.state === VtParseState.Charset) {
        // ESC ( B / ESC ) 0 / ESC # 3: 字符集指定, 吞掉参数不输出。
        this.state = VtParseState.Ground;
        i = i + 1;
        continue;
      }

      if (this.state === VtParseState.Csi) {
        if (code >= 0x40 && code <= 0x7E) {
          this.dispatchCsi(code);
          this.state = VtParseState.Ground;
          this.params = '';
          i = i + 1;
          continue;
        }
        if (code === 0x1B) {
          this.params = '';
          this.state = VtParseState.Escape;
          i = i + 1;
          continue;
        }
        if (code >= 0x20 && code <= 0x3F) {
          this.params = this.params + data.substring(i, i + 1);
        } else {
          this.params = '';
          this.state = VtParseState.Ground;
        }
        i = i + 1;
        continue;
      }

      if (this.state === VtParseState.Osc) {
        if (code === 0x07) {
          this.commitOsc();
          this.state = VtParseState.Ground;
          i = i + 1;
          continue;
        }
        if (code === 0x1B) {
          if (i + 1 < len && data.charCodeAt(i + 1) === 0x5C) {
            this.commitOsc();
            this.state = VtParseState.Ground;
            i = i + 2;
            continue;
          }
          this.oscText = '';
          this.state = VtParseState.Escape;
          i = i + 1;
          continue;
        }
        if (this.oscText.length < OSC_MAX_LEN) {
          this.oscText = this.oscText + data.substring(i, i + 1);
        }
        i = i + 1;
        continue;
      }

      this.state = VtParseState.Ground;
    }
  }

  private c0Control(code: number): void {
    if (code === 0x08) {
      this.screen.backspace();
    } else if (code === 0x09) {
      this.screen.tab();
    } else if (code === 0x0A || code === 0x0B || code === 0x0C) {
      this.screen.lineFeed();
    } else if (code === 0x0D) {
      this.screen.carriageReturn();
    } else if (code === 0x84) {
      this.screen.index();
    } else if (code === 0x85) {
      this.screen.newLine();
    } else if (code === 0x89) {
      this.screen.reverseIndex();
    }
    // 0x00 / 0x07 / 0x7F 以及其它 C0/C1: 吞掉
  }

  private onEscape(code: number): void {
    if (code === 0x5B) {
      this.state = VtParseState.Csi;
      this.params = '';
      return;
    }
    if (code === 0x5D) {
      this.state = VtParseState.Osc;
      this.oscText = '';
      return;
    }
    if (code === 0x28 || code === 0x29 || code === 0x23 || code === 0x2A || code === 0x3F) {
      this.state = VtParseState.Charset;
      return;
    }
    if (code === 0x37) {
      this.screen.saveCursor();
    } else if (code === 0x38) {
      this.screen.restoreCursor();
    } else if (code === 0x63) {
      this.reset();
    } else if (code === 0x44) {
      this.screen.index();
    } else if (code === 0x4D) {
      this.screen.reverseIndex();
    } else if (code === 0x45) {
      this.screen.newLine();
    } else if (code === 0x3D) {
      this.screen.applicationKeypad = true;
    } else if (code === 0x3E) {
      this.screen.applicationKeypad = false;
    }
    this.state = VtParseState.Ground;
  }

  private commitOsc(): void {
    const text: string = this.oscText;
    this.oscText = '';
    const idx: number = text.indexOf(';');
    if (idx <= 0) {
      return;
    }
    const kind: string = text.substring(0, idx);
    if (kind === '0' || kind === '1' || kind === '2') {
      this.windowTitle = text.substring(idx + 1);
    }
    // 其余 OSC(10/11 改色、52 剪贴板等): 吞掉
  }

  private parseParams(raw: string): number[] {
    const out: number[] = [];
    let cur: number = 0;
    let has: boolean = false;
    const len: number = raw.length;
    for (let i = 0; i < len; i++) {
      const c: number = raw.charCodeAt(i);
      if (c >= 0x30 && c <= 0x39) {
        cur = cur * 10 + (c - 0x30);
        has = true;
      } else if (c === 0x3B || c === 0x3A) {
        out.push(has ? cur : 0);
        cur = 0;
        has = false;
      }
      // '?' 与中间字节(0x20-0x2F)忽略, 由调用方另行判断私有模式
    }
    out.push(has ? cur : 0);
    return out;
  }

  private static num(params: number[], index: number): number {
    const v: number = index < params.length ? params[index] : 0;
    return v < 1 ? 1 : v;
  }

  private static opt(params: number[], index: number): number {
    return index < params.length ? params[index] : 0;
  }

  private dispatchCsi(final: number): void {
    const raw: string = this.params;
    const isPrivate: boolean = raw.length > 0 && raw.charAt(0) === '?';
    const params: number[] = this.parseParams(raw);
    const screen: VtScreen = this.screen;

    if (final === 0x6D) {
      screen.applySgr(params);
      return;
    }
    if (final === 0x68 || final === 0x6C) {
      this.setMode(final === 0x68, isPrivate, params);
      return;
    }
    if (final === 0x41) {
      screen.moveCursor(0, -VtParser.num(params, 0));
      return;
    }
    if (final === 0x42) {
      screen.moveCursor(0, VtParser.num(params, 0));
      return;
    }
    if (final === 0x43) {
      screen.moveCursor(VtParser.num(params, 0), 0);
      return;
    }
    if (final === 0x44) {
      screen.moveCursor(-VtParser.num(params, 0), 0);
      return;
    }
    if (final === 0x45) {
      screen.carriageReturn();
      screen.moveCursor(0, VtParser.num(params, 0));
      return;
    }
    if (final === 0x46) {
      screen.carriageReturn();
      screen.moveCursor(0, -VtParser.num(params, 0));
      return;
    }
    if (final === 0x47 || final === 0x60) {
      screen.setCursor(VtParser.num(params, 0) - 1, screen.cursorY());
      return;
    }
    if (final === 0x48 || final === 0x66) {
      screen.setCursor(VtParser.num(params, 1) - 1, VtParser.num(params, 0) - 1);
      return;
    }
    if (final === 0x64) {
      screen.setCursor(screen.cursorX(), VtParser.num(params, 0) - 1);
      return;
    }
    if (final === 0x4A) {
      screen.eraseDisplay(VtParser.opt(params, 0));
      return;
    }
    if (final === 0x4B) {
      screen.eraseLine(VtParser.opt(params, 0));
      return;
    }
    if (final === 0x4C) {
      screen.insertLines(VtParser.num(params, 0));
      return;
    }
    if (final === 0x4D) {
      screen.deleteLines(VtParser.num(params, 0));
      return;
    }
    if (final === 0x58) {
      screen.eraseChars(VtParser.num(params, 0));
      return;
    }
    if (final === 0x40) {
      screen.insertChars(VtParser.num(params, 0));
      return;
    }
    if (final === 0x50) {
      screen.deleteChars(VtParser.num(params, 0));
      return;
    }
    if (final === 0x53) {
      screen.scrollUp(VtParser.num(params, 0));
      return;
    }
    if (final === 0x54 || final === 0x75) {
      screen.scrollDown(VtParser.num(params, 0));
      return;
    }
    if (final === 0x73) {
      screen.saveCursor();
      return;
    }
    if (final === 0x72) {
      let top: number = VtParser.opt(params, 0);
      let bottom: number = VtParser.opt(params, 1);
      if (top < 1) {
        top = 1;
      }
      if (bottom < 1) {
        bottom = screen.rows;
      }
      screen.setScrollRegion(top, bottom);
      return;
    }
    // CSI n (DSR)、CSI t (window ops)、CSI SP ... : 吞掉, 不回响应
  }

  private setMode(on: boolean, isPrivate: boolean, params: number[]): void {
    const screen: VtScreen = this.screen;
    if (!isPrivate) {
      for (let i = 0; i < params.length; i++) {
        this.decModes.set(params[i], on);
      }
      return;
    }
    for (let i = 0; i < params.length; i++) {
      const mode: number = params[i];
      if (mode === 47) {
        if (on) {
          screen.enterAltScreen(false);
        } else {
          screen.exitAltScreen();
        }
        continue;
      }
      if (mode === 1047) {
        if (on) {
          screen.enterAltScreen(false);
        } else {
          screen.exitAltScreen();
        }
        continue;
      }
      if (mode === 1049) {
        if (on) {
          screen.enterAltScreen(true);
        } else {
          screen.exitAltScreen();
        }
        continue;
      }
      if (mode === 1) {
        screen.applicationCursorKeys = on;
        continue;
      }
      if (mode === 7) {
        screen.autoWrap = on;
        continue;
      }
      if (mode === 25) {
        screen.setCursorVisible(on);
        continue;
      }
      if (mode === 200) {
        screen.bracketedPaste = on;
        continue;
      }
      this.decModes.set(mode, on);
    }
  }
}
