/**
 * 终端页 (Phase 1b): 真 VT 屏幕模型 + Span 游程渲染。
 * 连接/断开/密码逻辑沿用 Phase 1a, 只把"剥 ANSI 按行追加"换成 VtParser + VtScreen。
 */
import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction, router } from '@kit.ArkUI';
import { SshClient, SshError } from 'ssh_lib';
import { AUTH_KEY, ConnectionProfile, RouteParams } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { VtParser } from '../vt/VtParser';
import { buildScreenRows, TermRow, TermRun } from '../vt/VtRender';

/** 13fp monospace: 行高固定 18vp, 单字宽约 7.8vp。 */
const TERM_FONT_SIZE: number = 13;
const TERM_LINE_HEIGHT: number = 18;
const TERM_CHAR_WIDTH: number = 7.8;
/** 终端面内边距: 左右各 8, 上下各 4。 */
const TERM_PAD_H: number = 16;
const TERM_PAD_V: number = 8;
const FALLBACK_COLS: number = 80;
const FALLBACK_ROWS: number = 24;
/** data feed 合帧节流。 */
const FLUSH_MS: number = 30;
/** 尺寸变化后延迟下发 resizePty。 */
const RESIZE_DEBOUNCE_MS: number = 150;

/** vim 刚需快捷键: 直接往 PTY 写字节, 不经过输入框。 */
class KeyBtn {
  label: string = '';
  payload: string = '';

  constructor(label: string, payload: string) {
    this.label = label;
    this.payload = payload;
  }
}

const KEY_BAR: KeyBtn[] = [
  new KeyBtn('Esc', '\u001B'),
  new KeyBtn('Tab', '\u0009'),
  new KeyBtn('^C', '\u0003'),
  new KeyBtn('/', '/'),
  new KeyBtn('|', '|'),
  new KeyBtn('~', '~'),
  new KeyBtn('←', '\u001B[D'),
  new KeyBtn('↑', '\u001B[A'),
  new KeyBtn('↓', '\u001B[B'),
  new KeyBtn('→', '\u001B[C')
];

@Entry
@Component
struct Terminal {
  @State profileName: string = '';
  @State hostLabel: string = '';
  @State windowTitle: string = '';
  @State profileIndex: number = -1;
  @State connected: boolean = false;
  @State busy: boolean = false;
  @State needPassword: boolean = false;
  @State termRows: TermRow[] = [];
  @State command: string = '';
  @State password: string = '';
  @State gridLabel: string = '';

  private profile: ConnectionProfile | null = null;
  private client: SshClient | null = null;
  private parser: VtParser = new VtParser();
  private rowCache: TermRow[] = [];
  private areaWidth: number = 0;
  private areaHeight: number = 0;
  private gridCols: number = FALLBACK_COLS;
  private gridRows: number = FALLBACK_ROWS;
  private flushPending: boolean = false;
  private resizePending: boolean = false;

  aboutToAppear(): void {
    this.loadProfile();
    this.refreshScreen();
  }

  aboutToDisappear(): void {
    this.disposeClient(false);
  }

  private hostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private statusText(): Resource {
    if (this.connected) {
      return $r('app.string.status_connected');
    }
    if (this.busy) {
      return $r('app.string.status_connecting');
    }
    return $r('app.string.status_disconnected');
  }

  private dotColor(): Resource {
    if (this.connected || this.busy) {
      return $r('app.color.accent');
    }
    return $r('app.color.text_tertiary');
  }

  private titleText(): string | Resource {
    if (this.windowTitle.length > 0) {
      return this.windowTitle;
    }
    if (this.profileName.length > 0) {
      return this.profileName;
    }
    return $r('app.string.no_profile');
  }

  private async loadProfile(): Promise<void> {
    const params: Object = router.getParams();
    let index: number = -1;
    if (params instanceof RouteParams) {
      index = params.index;
    }
    this.profileIndex = index;
    const ctx: Context | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    const profile: ConnectionProfile | null = await ProfileStore.getById(ctx, index);
    if (profile === null) {
      promptAction.showToast({ message: $r('app.string.toast_no_profile') });
      return;
    }
    this.profile = profile;
    this.profileName = profile.name;
    this.hostLabel = `${profile.username}@${profile.host}:${profile.port}`;
    this.appendInfo(`${profile.host}:${profile.port}  user=${profile.username}`);
    if (profile.authType === AUTH_KEY) {
      this.connect();
    } else if (profile.password.length > 0) {
      this.password = profile.password;
      this.connect();
    } else {
      this.needPassword = true;
    }
  }

  private async connect(): Promise<void> {
    const profile: ConnectionProfile | null = this.profile;
    if (profile === null || this.busy || this.connected) {
      return;
    }
    this.busy = true;
    const client: SshClient = new SshClient();
    client.on('data', (payload) => {
      const text: string = typeof payload === 'string' ? payload : '';
      if (text.length > 0) {
        this.parser.feed(text);
        this.scheduleFlush();
      }
    });
    client.on('error', (payload) => {
      if (payload instanceof Error) {
        const e: SshError = payload as SshError;
        this.appendInfo(`error ${e.code}: ${e.message}`);
      }
    });
    client.on('close', () => {
      this.handleClosed();
    });
    try {
      if (profile.authType === AUTH_KEY) {
        const keyContent: string = this.readKeyContent(profile.keyPath);
        await client.connectWithKey(profile.host, profile.port, profile.username, keyContent);
      } else {
        await client.connect(profile.host, profile.port, profile.username, this.password);
      }
      await client.startShell(this.gridCols, this.gridRows);
      this.client = client;
      this.connected = true;
      this.busy = false;
      this.needPassword = false;
      this.appendInfo(`connected ${this.gridCols}x${this.gridRows}  host-key SHA-256: ${client.getHostKeyFingerprint()}`);
      this.applyResizePty();
    } catch (e) {
      client.dispose();
      this.client = null;
      this.connected = false;
      this.busy = false;
      let detail: string = 'unknown error';
      if (e instanceof SshError) {
        const sshError: SshError = e as SshError;
        detail = `${sshError.code}: ${sshError.message}`;
      } else {
        const generic: Error = e as Error;
        detail = generic.message;
      }
      promptAction.showToast({ message: `connect failed: ${detail}` });
      this.appendInfo(`connect failed: ${detail}`);
    }
  }

  private disconnect(): void {
    if (this.client === null) {
      return;
    }
    this.disposeClient(true);
  }

  /** 引擎没有 stopShell/close: dispose() 内部关 shell 通道 -> 关 channel -> session disconnect -> 发 close 事件。 */
  private disposeClient(notify: boolean): void {
    const client: SshClient | null = this.client;
    if (client === null) {
      return;
    }
    this.client = null;
    this.connected = false;
    this.busy = false;
    client.dispose();
    if (notify) {
      this.appendInfo('disconnected');
    }
  }

  private handleClosed(): void {
    if (!this.connected) {
      return;
    }
    this.client = null;
    this.connected = false;
    this.appendInfo('closed by remote');
  }

  private async sendCommand(): Promise<void> {
    const client: SshClient | null = this.client;
    if (client === null || !this.connected) {
      return;
    }
    const text: string = this.command;
    this.command = '';
    await client.writeToShell(`${text}\n`);
  }

  /** 快捷键条: 原样把控制字节写进 PTY。 */
  private async sendRaw(text: string): Promise<void> {
    const client: SshClient | null = this.client;
    if (client === null || !this.connected) {
      return;
    }
    await client.writeToShell(text);
  }

  private readKeyContent(path: string): string {
    let target: string = path.trim();
    if (target.length === 0) {
      throw new Error('empty private key path');
    }
    if (!this.fileExists(target)) {
      const ctx: Context | undefined = this.hostContext();
      if (ctx !== undefined) {
        const candidate: string = `${ctx.filesDir}/${target}`;
        if (this.fileExists(candidate)) {
          target = candidate;
        }
      }
    }
    if (!this.fileExists(target)) {
      throw new Error(`private key not found: ${target}`);
    }
    return fs.readTextSync(target);
  }

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  /** 本地提示行(连接状态等)写进同一块 VT 屏幕, 不再单独维护行数组。 */
  private appendInfo(text: string): void {
    this.parser.screen.writePlain(text);
    this.refreshScreen();
  }

  // ---------- 渲染节流 ----------

  private scheduleFlush(): void {
    if (this.flushPending) {
      return;
    }
    this.flushPending = true;
    setTimeout((): void => {
      this.flushPending = false;
      this.refreshScreen();
    }, FLUSH_MS);
  }

  private refreshScreen(): void {
    const cursorOn: boolean = this.connected && this.parser.screen.cursorVisible;
    const rows: TermRow[] = buildScreenRows(this.parser.screen, this.rowCache, cursorOn);
    this.rowCache = rows;
    this.termRows = rows;
    const title: string = this.parser.windowTitle;
    if (title !== this.windowTitle) {
      this.windowTitle = title;
    }
    const label: string = `${this.parser.screen.cols}x${this.parser.screen.rows}`;
    if (label !== this.gridLabel) {
      this.gridLabel = label;
    }
  }

  // ---------- 尺寸联动 ----------

  private handleAreaChange(oldArea: Area, newArea: Area): void {
    const w: number = typeof newArea.width === 'number' ? newArea.width : this.areaWidth;
    const h: number = typeof newArea.height === 'number' ? newArea.height : this.areaHeight;
    if (w <= 0 || h <= 0) {
      return;
    }
    if (w === this.areaWidth && h === this.areaHeight) {
      return;
    }
    this.areaWidth = w;
    this.areaHeight = h;
    const cols: number = Math.max(20, Math.floor((w - TERM_PAD_H) / TERM_CHAR_WIDTH));
    const rows: number = Math.max(8, Math.floor((h - TERM_PAD_V) / TERM_LINE_HEIGHT));
    this.gridCols = cols;
    this.gridRows = rows;
    if (this.parser.resize(cols, rows)) {
      this.refreshScreen();
    }
    this.scheduleResizePty();
  }

  private scheduleResizePty(): void {
    if (this.resizePending) {
      return;
    }
    this.resizePending = true;
    setTimeout((): void => {
      this.resizePending = false;
      this.applyResizePty();
    }, RESIZE_DEBOUNCE_MS);
  }

  private async applyResizePty(): Promise<void> {
    const client: SshClient | null = this.client;
    if (client === null || !this.connected) {
      return;
    }
    try {
      await client.resizePty(this.gridCols, this.gridRows);
    } catch (e) {
      this.appendInfo('resize failed');
    }
  }

  @Builder
  termRunView(run: TermRun) {
    Span(run.text)
      .fontColor(run.fg)
      .backgroundColor(run.bg)
      .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
      .decoration({
        type: run.underline ? TextDecorationType.Underline : TextDecorationType.None,
        color: run.fg
      })
  }

  @Builder
  termRowView(row: TermRow) {
    Text() {
      ForEach(row.runs, (run: TermRun, index: number) => {
        this.termRunView(run)
      }, (run: TermRun, index: number) => `${index}:${run.fg}:${run.bg}:${run.bold ? 1 : 0}:${run.underline ? 1 : 0}:${run.text.length}`)
    }
    .width('100%')
    .height(TERM_LINE_HEIGHT)
    .lineHeight(TERM_LINE_HEIGHT)
    .fontSize(TERM_FONT_SIZE)
    .fontFamily('monospace')
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Clip })
    .textAlign(TextAlign.Start)
  }

  @Builder
  keyBtn(item: KeyBtn) {
    Text(item.label)
      .height(32)
      .padding({ left: 16, right: 16 })
      .fontSize($r('app.float.font_footnote'))
      .fontColor($r('app.color.keycap_fg'))
      .backgroundColor($r('app.color.keycap_bg'))
      .borderRadius(8)
      .onClick(() => {
        this.sendRaw(item.payload);
      })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text($r('app.string.btn_back'))
          .fontSize($r('app.float.font_footnote'))
          .fontColor($r('app.color.accent'))
          .onClick(() => {
            router.back();
          })
        Column() {
          Text(this.titleText())
            .fontSize($r('app.float.font_body'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.hostLabel}  ${this.gridLabel}`)
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          Circle({ width: 8, height: 8 })
            .fill(this.dotColor())
          Text(this.statusText())
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
        }

        if (this.connected) {
          Button($r('app.string.btn_disconnect'))
            .height(32)
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.accent_text_on'))
            .backgroundColor($r('app.color.destructive'))
            .borderRadius($r('app.float.radius_control'))
            .onClick(() => {
              this.disconnect();
            })
        } else {
          Button($r('app.string.btn_connect'))
            .height(32)
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.accent_text_on'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.radius_control'))
            .enabled(!this.busy)
            .onClick(() => {
              this.connect();
            })
        }
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
      .backgroundColor($r('app.color.bar_bg'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      Column() {
        ForEach(this.termRows, (row: TermRow) => {
          this.termRowView(row)
        }, (row: TermRow) => row.key)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.terminal_bg'))
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.handleAreaChange(oldArea, newArea);
      })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(KEY_BAR, (item: KeyBtn) => {
            this.keyBtn(item)
          }, (item: KeyBtn) => item.label)
        }
        .height(40)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(40)
      .backgroundColor($r('app.color.bar_bg'))
      .align(Alignment.Start)

      if (this.needPassword && !this.connected) {
        Row({ space: 8 }) {
          TextInput({ text: this.password, placeholder: $r('app.string.placeholder_password') })
            .type(InputType.Password)
            .layoutWeight(1)
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius($r('app.float.radius_control'))
            .borderWidth(1)
            .borderColor($r('app.color.divider'))
            .onChange((value: string) => {
              this.password = value;
            })
            .onSubmit(() => {
              this.connect();
            })
          Button($r('app.string.btn_connect'))
            .width($r('app.float.connect_btn_width'))
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.accent_text_on'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.radius_control'))
            .enabled(!this.busy)
            .onClick(() => {
              this.connect();
            })
        }
        .width('100%')
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), top: 8, bottom: 8 })
        .backgroundColor($r('app.color.bar_bg'))
      } else {
        Row({ space: 8 }) {
          TextInput({ text: this.command, placeholder: $r('app.string.placeholder_cmd') })
            .layoutWeight(1)
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius($r('app.float.radius_control'))
            .borderWidth(1)
            .borderColor($r('app.color.divider'))
            .enabled(this.connected)
            .onChange((value: string) => {
              this.command = value;
            })
            .onSubmit(() => {
              this.sendCommand();
            })
          Button($r('app.string.btn_send'))
            .width($r('app.float.send_btn_width'))
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.accent_text_on'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.radius_control'))
            .enabled(this.connected)
            .onClick(() => {
              this.sendCommand();
            })
        }
        .width('100%')
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), top: 8, bottom: 8 })
        .backgroundColor($r('app.color.bar_bg'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
