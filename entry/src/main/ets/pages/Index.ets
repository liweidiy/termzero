import { Context } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AUTH_KEY, ConnectionProfile, RouteParams } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';

@Entry
@Component
struct Index {
  @State profiles: ConnectionProfile[] = [];
  @State ready: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
  }

  private hostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private async reload(): Promise<void> {
    const ctx: Context | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    this.profiles = await ProfileStore.load(ctx);
    this.ready = true;
  }

  private openTerminal(index: number): void {
    router.pushUrl({ url: 'pages/Terminal', params: new RouteParams(index) });
  }

  private openEditor(index: number): void {
    router.pushUrl({ url: 'pages/ConnEdit', params: new RouteParams(index) });
  }

  private async deleteProfile(index: number): Promise<void> {
    if (index < 0 || index >= this.profiles.length) {
      return;
    }
    const target: ConnectionProfile = this.profiles[index];
    let choice: number = -1;
    try {
      const res: promptAction.ShowDialogSuccessResponse = await new Promise<promptAction.ShowDialogSuccessResponse>((resolve, reject) => {
        promptAction.showDialog({
          title: $r('app.string.dlg_delete_title'),
          message: target.name,
          buttons: [
            { text: $r('app.string.btn_cancel'), color: $r('app.color.accent') },
            { text: $r('app.string.btn_delete'), color: $r('app.color.destructive') }
          ]
        }, (err: BusinessError, data: promptAction.ShowDialogSuccessResponse) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      choice = res.index;
    } catch (e) {
      return;
    }
    if (choice !== 1) {
      return;
    }
    const ctx: Context | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    this.profiles = await ProfileStore.deleteAt(ctx, index);
    promptAction.showToast({ message: $r('app.string.toast_deleted') });
  }

  @Builder
  profileCard(item: ConnectionProfile, index: number) {
    Column() {
      Text(item.name)
        .fontSize($r('app.float.font_body'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${item.username}@${item.host}:${item.port}`)
        .fontSize($r('app.float.font_footnote'))
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.authType === AUTH_KEY ? $r('app.string.badge_key') : $r('app.string.badge_password'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.card_padding'))
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius($r('app.float.radius_card'))
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.app_title'))
          .fontSize($r('app.float.font_largeTitle'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button('+')
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_text_on'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            this.openEditor(-1);
          })
      }
      .width('100%')
      .height($r('app.float.header_height'))
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })

      if (this.ready && this.profiles.length === 0) {
        Column() {
          Text($r('app.string.empty_title'))
            .fontSize($r('app.float.font_title'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.empty_hint'))
            .fontSize($r('app.float.font_footnote'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.profiles, (item: ConnectionProfile, index: number) => {
            ListItem() {
              this.profileCard(item, index)
            }
            .onClick(() => {
              this.openTerminal(index);
            })
            .gesture(LongPressGesture().onAction(() => {
              this.deleteProfile(index);
            }))
          }, (item: ConnectionProfile, index: number) => `${index}-${item.host}-${item.name}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s'), top: 8, bottom: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
