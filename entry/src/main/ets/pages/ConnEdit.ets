import { Context } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AUTH_KEY, AUTH_PASSWORD, ConnectionProfile, RouteParams } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';

@Entry
@Component
struct ConnEdit {
  @State editIndex: number = -1;
  @State pageTitle: Resource = $r('app.string.title_new');
  @State name: string = '';
  @State host: string = '';
  @State port: string = '22';
  @State username: string = '';
  @State authType: string = AUTH_PASSWORD;
  @State keyPath: string = '';
  @State password: string = '';

  aboutToAppear(): void {
    this.loadExisting();
  }

  private hostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private async loadExisting(): Promise<void> {
    const params: Object = router.getParams();
    let index: number = -1;
    if (params instanceof RouteParams) {
      index = params.index;
    }
    if (index < 0) {
      return;
    }
    this.editIndex = index;
    this.pageTitle = $r('app.string.title_edit');
    const ctx: Context | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    const profile: ConnectionProfile | null = await ProfileStore.getById(ctx, index);
    if (profile === null) {
      return;
    }
    this.name = profile.name;
    this.host = profile.host;
    this.port = `${profile.port}`;
    this.username = profile.username;
    this.authType = profile.authType;
    this.keyPath = profile.keyPath;
    this.password = profile.password;
  }

  private async save(): Promise<void> {
    const ctx: Context | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    const trimmedName: string = this.name.trim();
    const trimmedHost: string = this.host.trim();
    const trimmedUser: string = this.username.trim();
    const trimmedKey: string = this.keyPath.trim();
    if (trimmedName.length === 0 || trimmedHost.length === 0 || trimmedUser.length === 0) {
      promptAction.showToast({ message: $r('app.string.toast_required') });
      return;
    }
    const portNum: number = parseInt(this.port, 10);
    if (Number.isNaN(portNum) || portNum < 1 || portNum > 65535) {
      promptAction.showToast({ message: $r('app.string.toast_bad_port') });
      return;
    }
    if (this.authType === AUTH_KEY && trimmedKey.length === 0) {
      promptAction.showToast({ message: $r('app.string.toast_need_key_path') });
      return;
    }
    const profile: ConnectionProfile = new ConnectionProfile();
    profile.name = trimmedName;
    profile.host = trimmedHost;
    profile.port = portNum;
    profile.username = trimmedUser;
    profile.authType = this.authType === AUTH_KEY ? AUTH_KEY : AUTH_PASSWORD;
    profile.keyPath = trimmedKey;
    profile.password = profile.authType === AUTH_PASSWORD ? this.password : '';
    await ProfileStore.upsert(ctx, this.editIndex, profile);
    promptAction.showToast({ message: $r('app.string.toast_saved') });
    router.back();
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.btn_cancel'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.accent'))
          .onClick(() => {
            router.back();
          })
        Blank()
        Text(this.pageTitle)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text($r('app.string.btn_save'))
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .height($r('app.float.header_height'))
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      Scroll() {
        Column({ space: 16 }) {
          Column() {
            Row({ space: 12 }) {
              Text($r('app.string.label_name'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_secondary'))
                .width(88)
              TextInput({ text: this.name, placeholder: $r('app.string.placeholder_name') })
                .layoutWeight(1)
                .height($r('app.float.row_height'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.input_bg'))
                .borderWidth(0)
                .onChange((value: string) => {
                  this.name = value;
                })
            }
            .height($r('app.float.row_height'))

            Divider().strokeWidth(1).color($r('app.color.divider'))

            Row({ space: 12 }) {
              Text($r('app.string.label_host'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_secondary'))
                .width(88)
              TextInput({ text: this.host, placeholder: $r('app.string.placeholder_host') })
                .layoutWeight(1)
                .height($r('app.float.row_height'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.input_bg'))
                .borderWidth(0)
                .onChange((value: string) => {
                  this.host = value;
                })
              Text($r('app.string.label_port'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.port })
                .width($r('app.float.port_input_width'))
                .height($r('app.float.row_height'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.input_bg'))
                .borderWidth(0)
                .onChange((value: string) => {
                  this.port = value;
                })
            }
            .height($r('app.float.row_height'))

            Divider().strokeWidth(1).color($r('app.color.divider'))

            Row({ space: 12 }) {
              Text($r('app.string.label_user'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_secondary'))
                .width(88)
              TextInput({ text: this.username, placeholder: $r('app.string.placeholder_user') })
                .layoutWeight(1)
                .height($r('app.float.row_height'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.input_bg'))
                .borderWidth(0)
                .onChange((value: string) => {
                  this.username = value;
                })
            }
            .height($r('app.float.row_height'))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius($r('app.float.radius_card'))

          Column() {
            Row({ space: 12 }) {
              Text($r('app.string.label_auth'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_secondary'))
                .width(88)
              Blank()
              Radio({ value: 'password', group: 'tzAuth' })
                .checked(this.authType === AUTH_PASSWORD)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.authType = AUTH_PASSWORD;
                  }
                })
              Text($r('app.string.auth_password'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
                .margin({ right: 16 })
              Radio({ value: 'key', group: 'tzAuth' })
                .checked(this.authType === AUTH_KEY)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.authType = AUTH_KEY;
                  }
                })
              Text($r('app.string.auth_key'))
                .fontSize($r('app.float.font_footnote'))
                .fontColor($r('app.color.text_primary'))
            }
            .height($r('app.float.row_height'))

            if (this.authType === AUTH_PASSWORD) {
              Divider().strokeWidth(1).color($r('app.color.divider'))
              Row({ space: 12 }) {
                Text($r('app.string.label_password'))
                  .fontSize($r('app.float.font_footnote'))
                  .fontColor($r('app.color.text_secondary'))
                  .width(88)
                TextInput({ text: this.password, placeholder: $r('app.string.hint_password_optional') })
                  .type(InputType.Password)
                  .layoutWeight(1)
                  .height($r('app.float.row_height'))
                  .fontSize($r('app.float.font_footnote'))
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.input_bg'))
                  .borderWidth(0)
                  .onChange((value: string) => {
                    this.password = value;
                  })
              }
              .height($r('app.float.row_height'))
            } else {
              Divider().strokeWidth(1).color($r('app.color.divider'))
              Row({ space: 12 }) {
                Text($r('app.string.label_key_path'))
                  .fontSize($r('app.float.font_footnote'))
                  .fontColor($r('app.color.text_secondary'))
                  .width(88)
                TextInput({ text: this.keyPath, placeholder: $r('app.string.placeholder_key_path') })
                  .layoutWeight(1)
                  .height($r('app.float.row_height'))
                  .fontSize($r('app.float.font_footnote'))
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.input_bg'))
                  .borderWidth(0)
                  .onChange((value: string) => {
                    this.keyPath = value;
                  })
              }
              .height($r('app.float.row_height'))
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius($r('app.float.radius_card'))

          Button($r('app.string.btn_save'))
            .width('100%')
            .height($r('app.float.btn_height'))
            .fontSize($r('app.float.font_body'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_text_on'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.radius_control'))
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), top: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
